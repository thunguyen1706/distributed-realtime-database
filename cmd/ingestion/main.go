package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/IBM/sarama"
	"github.com/google/uuid"
	"github.com/gorilla/mux"
	"github.com/joho/godotenv"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/rs/cors"
	"github.com/sirupsen/logrus"
)

// Event types
type PostEvent struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	Content   string    `json:"content"`
	Timestamp time.Time `json:"timestamp"`
}

type CommentEvent struct {
	ID        string    `json:"id"`
	PostID    string    `json:"post_id"`
	UserID    string    `json:"user_id"`
	Content   string    `json:"content"`
	Timestamp time.Time `json:"timestamp"`
}

type LikeEvent struct {
	ID        string    `json:"id"`
	PostID    string    `json:"post_id"`
	UserID    string    `json:"user_id"`
	Action    string    `json:"action"` // "like" or "unlike"
	Timestamp time.Time `json:"timestamp"`
}

// Request types
type CreatePostRequest struct {
	UserID  string `json:"user_id"`
	Content string `json:"content"`
}

type CreateCommentRequest struct {
	PostID  string `json:"post_id"`
	UserID  string `json:"user_id"`
	Content string `json:"content"`
}

type LikeRequest struct {
	PostID string `json:"post_id"`
	UserID string `json:"user_id"`
	Action string `json:"action"` // "like" or "unlike"
}

// Response types
type APIResponse struct {
	Success bool        `json:"success"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
	Error   string      `json:"error,omitempty"`
}

// Metrics
var (
	requestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of HTTP requests",
		},
		[]string{"method", "endpoint", "status"},
	)
	
	eventsPublished = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "events_published_total",
			Help: "Total number of events published to Kafka",
		},
		[]string{"topic", "status"},
	)
	
	requestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name: "http_request_duration_seconds",
			Help: "HTTP request duration in seconds",
		},
		[]string{"method", "endpoint"},
	)
)

func init() {
	prometheus.MustRegister(requestsTotal)
	prometheus.MustRegister(eventsPublished)
	prometheus.MustRegister(requestDuration)
}

type IngestionService struct {
	producer sarama.SyncProducer
	logger   *logrus.Logger
}

func NewIngestionService() (*IngestionService, error) {
	logger := logrus.New()
	logger.SetFormatter(&logrus.JSONFormatter{})
	
	// Load environment variables
	if err := godotenv.Load(); err != nil {
		logger.Warn("No .env file found")
	}
	
	kafkaServers := strings.Split(getEnv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"), ",")
	
	// Configure Sarama
	config := sarama.NewConfig()
	config.Producer.RequiredAcks = sarama.WaitForAll // Wait for all in-sync replicas to ack
	config.Producer.Retry.Max = 3                    // Retry up to 3 times to produce the message
	config.Producer.Return.Successes = true
	config.Producer.Return.Errors = true
	config.Version = sarama.V2_6_0_0 
	
	producer, err := sarama.NewSyncProducer(kafkaServers, config)
	if err != nil {
		return nil, fmt.Errorf("failed to create Kafka producer: %w", err)
	}
	
	return &IngestionService{
		producer: producer,
		logger:   logger,
	}, nil
}

func (s *IngestionService) Close() {
	if s.producer != nil {
		s.producer.Close()
	}
}

func (s *IngestionService) publishEvent(topic string, key string, event interface{}) error {
	value, err := json.Marshal(event)
	if err != nil {
		eventsPublished.WithLabelValues(topic, "error").Inc()
		return fmt.Errorf("failed to marshal event: %w", err)
	}
	
	msg := &sarama.ProducerMessage{
		Topic: topic,
		Key:   sarama.StringEncoder(key),
		Value: sarama.StringEncoder(value),
	}
	
	partition, offset, err := s.producer.SendMessage(msg)
	if err != nil {
		eventsPublished.WithLabelValues(topic, "error").Inc()
		return fmt.Errorf("failed to send message: %w", err)
	}
	
	eventsPublished.WithLabelValues(topic, "success").Inc()
	s.logger.WithFields(logrus.Fields{
		"topic":     topic,
		"key":       key,
		"partition": partition,
		"offset":    offset,
	}).Info("Event published successfully")
	
	return nil
}

func (s *IngestionService) handleCreatePost(w http.ResponseWriter, r *http.Request) {
	timer := prometheus.NewTimer(requestDuration.WithLabelValues("POST", "/api/posts"))
	defer timer.ObserveDuration()
	
	var req CreatePostRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		requestsTotal.WithLabelValues("POST", "/api/posts", "400").Inc()
		s.respondWithError(w, http.StatusBadRequest, "Invalid request body")
		return
	}
	
	// Validation
	if req.UserID == "" || req.Content == "" {
		requestsTotal.WithLabelValues("POST", "/api/posts", "400").Inc()
		s.respondWithError(w, http.StatusBadRequest, "user_id and content are required")
		return
	}
	
	if len(req.Content) > 280 {
		requestsTotal.WithLabelValues("POST", "/api/posts", "400").Inc()
		s.respondWithError(w, http.StatusBadRequest, "content must be 280 characters or less")
		return
	}
	
	// Create event
	event := PostEvent{
		ID:        uuid.New().String(),
		UserID:    req.UserID,
		Content:   req.Content,
		Timestamp: time.Now().UTC(),
	}
	
	// Publish to Kafka
	if err := s.publishEvent("posts", req.UserID, event); err != nil {
		requestsTotal.WithLabelValues("POST", "/api/posts", "500").Inc()
		s.logger.WithError(err).Error("Failed to publish post event")
		s.respondWithError(w, http.StatusInternalServerError, "Failed to process post")
		return
	}
	
	requestsTotal.WithLabelValues("POST", "/api/posts", "202").Inc()
	s.respondWithJSON(w, http.StatusAccepted, APIResponse{
		Success: true,
		Message: "Post accepted for processing",
		Data: map[string]string{
			"post_id": event.ID,
		},
	})
}

func (s *IngestionService) handleCreateComment(w http.ResponseWriter, r *http.Request) {
	timer := prometheus.NewTimer(requestDuration.WithLabelValues("POST", "/api/comments"))
	defer timer.ObserveDuration()
	
	var req CreateCommentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		requestsTotal.WithLabelValues("POST", "/api/comments", "400").Inc()
		s.respondWithError(w, http.StatusBadRequest, "Invalid request body")
		return
	}
	
	// Validation
	if req.PostID == "" || req.UserID == "" || req.Content == "" {
		requestsTotal.WithLabelValues("POST", "/api/comments", "400").Inc()
		s.respondWithError(w, http.StatusBadRequest, "post_id, user_id and content are required")
		return
	}
	
	if len(req.Content) > 280 {
		requestsTotal.WithLabelValues("POST", "/api/comments", "400").Inc()
		s.respondWithError(w, http.StatusBadRequest, "content must be 280 characters or less")
		return
	}
	
	// Create event
	event := CommentEvent{
		ID:        uuid.New().String(),
		PostID:    req.PostID,
		UserID:    req.UserID,
		Content:   req.Content,
		Timestamp: time.Now().UTC(),
	}
	
	// Publish to Kafka (key by post_id to ensure ordering per post)
	if err := s.publishEvent("comments", req.PostID, event); err != nil {
		requestsTotal.WithLabelValues("POST", "/api/comments", "500").Inc()
		s.logger.WithError(err).Error("Failed to publish comment event")
		s.respondWithError(w, http.StatusInternalServerError, "Failed to process comment")
		return
	}
	
	requestsTotal.WithLabelValues("POST", "/api/comments", "202").Inc()
	s.respondWithJSON(w, http.StatusAccepted, APIResponse{
		Success: true,
		Message: "Comment accepted for processing",
		Data: map[string]string{
			"comment_id": event.ID,
		},
	})
}

func (s *IngestionService) handleLike(w http.ResponseWriter, r *http.Request) {
	timer := prometheus.NewTimer(requestDuration.WithLabelValues("POST", "/api/likes"))
	defer timer.ObserveDuration()
	
	var req LikeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		requestsTotal.WithLabelValues("POST", "/api/likes", "400").Inc()
		s.respondWithError(w, http.StatusBadRequest, "Invalid request body")
		return
	}
	
	// Validation
	if req.PostID == "" || req.UserID == "" {
		requestsTotal.WithLabelValues("POST", "/api/likes", "400").Inc()
		s.respondWithError(w, http.StatusBadRequest, "post_id and user_id are required")
		return
	}
	
	if req.Action != "like" && req.Action != "unlike" {
		requestsTotal.WithLabelValues("POST", "/api/likes", "400").Inc()
		s.respondWithError(w, http.StatusBadRequest, "action must be 'like' or 'unlike'")
		return
	}
	
	// Create event
	event := LikeEvent{
		ID:        uuid.New().String(),
		PostID:    req.PostID,
		UserID:    req.UserID,
		Action:    req.Action,
		Timestamp: time.Now().UTC(),
	}
	
	// Publish to Kafka (key by post_id to ensure ordering per post)
	if err := s.publishEvent("likes", req.PostID, event); err != nil {
		requestsTotal.WithLabelValues("POST", "/api/likes", "500").Inc()
		s.logger.WithError(err).Error("Failed to publish like event")
		s.respondWithError(w, http.StatusInternalServerError, "Failed to process like")
		return
	}
	
	requestsTotal.WithLabelValues("POST", "/api/likes", "202").Inc()
	s.respondWithJSON(w, http.StatusAccepted, APIResponse{
		Success: true,
		Message: fmt.Sprintf("%s accepted for processing", strings.Title(req.Action)),
		Data: map[string]string{
			"like_id": event.ID,
		},
	})
}

func (s *IngestionService) handleHealth(w http.ResponseWriter, r *http.Request) {
	s.respondWithJSON(w, http.StatusOK, APIResponse{
		Success: true,
		Message: "Ingestion service is healthy",
		Data: map[string]interface{}{
			"timestamp": time.Now().UTC(),
			"service":   "ingestion",
			"version":   "1.0.0",
		},
	})
}

func (s *IngestionService) respondWithJSON(w http.ResponseWriter, code int, payload interface{}) {
	response, _ := json.Marshal(payload)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	w.Write(response)
}

func (s *IngestionService) respondWithError(w http.ResponseWriter, code int, message string) {
	s.respondWithJSON(w, code, APIResponse{
		Success: false,
		Error:   message,
	})
}

func (s *IngestionService) setupRoutes() *mux.Router {
	r := mux.NewRouter()
	
	// API routes
	api := r.PathPrefix("/api").Subrouter()
	api.HandleFunc("/posts", s.handleCreatePost).Methods("POST")
	api.HandleFunc("/comments", s.handleCreateComment).Methods("POST")
	api.HandleFunc("/likes", s.handleLike).Methods("POST")
	
	// Health and metrics
	r.HandleFunc("/health", s.handleHealth).Methods("GET")
	r.Handle("/metrics", promhttp.Handler()).Methods("GET")
	
	return r
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func main() {
	service, err := NewIngestionService()
	if err != nil {
		logrus.WithError(err).Fatal("Failed to create ingestion service")
	}
	defer service.Close()
	
	router := service.setupRoutes()
	
	// CORS middleware
	c := cors.New(cors.Options{
		AllowedOrigins: []string{"*"}, // In production, specify actual origins
		AllowedMethods: []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders: []string{"*"},
	})
	
	handler := c.Handler(router)
	
	port := getEnv("APP_PORT", "8081")
	server := &http.Server{
		Addr:    ":" + port,
		Handler: handler,
	}
	
	// Graceful shutdown
	go func() {
		service.logger.WithField("port", port).Info("Starting ingestion service")
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			service.logger.WithError(err).Fatal("Server failed to start")
		}
	}()
	
	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	
	service.logger.Info("Shutting down ingestion service...")
	
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	
	if err := server.Shutdown(ctx); err != nil {
		service.logger.WithError(err).Fatal("Server forced to shutdown")
	}
	
	service.logger.Info("Ingestion service stopped")
}