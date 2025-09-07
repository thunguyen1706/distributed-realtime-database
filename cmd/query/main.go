package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"hash/fnv"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/gorilla/mux"
	"github.com/joho/godotenv"
	_ "github.com/lib/pq"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/rs/cors"
	"github.com/sirupsen/logrus"
)

// Data types
type Post struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	Content   string    `json:"content"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type Comment struct {
	ID        string    `json:"id"`
	PostID    string    `json:"post_id"`
	UserID    string    `json:"user_id"`
	Content   string    `json:"content"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type Like struct {
	ID        string    `json:"id"`
	PostID    string    `json:"post_id"`
	UserID    string    `json:"user_id"`
	CreatedAt time.Time `json:"created_at"`
}

type PostWithStats struct {
	Post
	CommentCount int `json:"comment_count"`
	LikeCount    int `json:"like_count"`
}

type UserStats struct {
	UserID       string `json:"user_id"`
	PostCount    int    `json:"post_count"`
	CommentCount int    `json:"comment_count"`
	LikeCount    int    `json:"like_count"`
}

// Response types
type APIResponse struct {
	Success bool        `json:"success"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
	Error   string      `json:"error,omitempty"`
	Count   *int        `json:"count,omitempty"`
}

// Shard configuration
type ShardConfig struct {
	ID               uint32
	Host             string
	Port             int
	Database         string
	Username         string
	Password         string
	ConnectionString string
}

// Metrics
var (
	queriesTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "queries_total",
			Help: "Total number of queries executed",
		},
		[]string{"method", "endpoint", "status"},
	)
	
	queryDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name: "query_duration_seconds",
			Help: "Time spent executing queries",
		},
		[]string{"method", "endpoint"},
	)
	
	shardQueries = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "shard_queries_total",
			Help: "Total number of queries per shard",
		},
		[]string{"shard", "status"},
	)
)

func init() {
	prometheus.MustRegister(queriesTotal)
	prometheus.MustRegister(queryDuration)
	prometheus.MustRegister(shardQueries)
}

type QueryService struct {
	shards   []ShardConfig
	dbPool   map[uint32]*sql.DB
	logger   *logrus.Logger
}

func NewQueryService() (*QueryService, error) {
	logger := logrus.New()
	logger.SetFormatter(&logrus.JSONFormatter{})
	
	// Load environment variables
	if err := godotenv.Load(); err != nil {
		logger.Warn("No .env file found")
	}
	
	// Load shard configuration
	shards, err := loadShardConfig(logger)
	if err != nil {
		return nil, fmt.Errorf("failed to load shard config: %w", err)
	}
	
	// Initialize database connections
	dbPool, err := initDBConnections(shards, logger)
	if err != nil {
		return nil, fmt.Errorf("failed to initialize DB connections: %w", err)
	}
	
	return &QueryService{
		shards: shards,
		dbPool: dbPool,
		logger: logger,
	}, nil
}

func loadShardConfig(logger *logrus.Logger) ([]ShardConfig, error) {
	// Connect to master database to get shard configuration
	masterDB, err := sql.Open("postgres", fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		getEnv("PG_MASTER_HOST", "localhost"),
		getEnv("PG_MASTER_PORT", "5440"),
		getEnv("PG_MASTER_USER", "postgres"),
		getEnv("PG_MASTER_PASS", "Genius171317@"),
		getEnv("PG_MASTER_DB", "master"),
	))
	if err != nil {
		return nil, fmt.Errorf("failed to connect to master DB: %w", err)
	}
	defer masterDB.Close()
	
	rows, err := masterDB.Query("SELECT shard_id, host, port, db_name, username, password FROM shards ORDER BY shard_id")
	if err != nil {
		return nil, fmt.Errorf("failed to query shards: %w", err)
	}
	defer rows.Close()
	
	var shards []ShardConfig
	for rows.Next() {
		var shard ShardConfig
		err := rows.Scan(&shard.ID, &shard.Host, &shard.Port, &shard.Database, &shard.Username, &shard.Password)
		if err != nil {
			return nil, fmt.Errorf("failed to scan shard row: %w", err)
		}
		
		shard.ConnectionString = fmt.Sprintf(
			"host=%s port=%d user=%s password=%s dbname=%s sslmode=disable",
			shard.Host, shard.Port, shard.Username, shard.Password, shard.Database,
		)
		
		shards = append(shards, shard)
		logger.WithFields(logrus.Fields{
			"shard_id": shard.ID,
			"host":     shard.Host,
			"port":     shard.Port,
		}).Info("Loaded shard configuration")
	}
	
	return shards, nil
}

func initDBConnections(shards []ShardConfig, logger *logrus.Logger) (map[uint32]*sql.DB, error) {
	dbPool := make(map[uint32]*sql.DB)
	
	for _, shard := range shards {
		db, err := sql.Open("postgres", shard.ConnectionString)
		if err != nil {
			return nil, fmt.Errorf("failed to open connection to shard %d: %w", shard.ID, err)
		}
		
		if err := db.Ping(); err != nil {
			return nil, fmt.Errorf("failed to ping shard %d: %w", shard.ID, err)
		}
		
		db.SetMaxOpenConns(10)
		db.SetMaxIdleConns(5)
		db.SetConnMaxLifetime(time.Hour)
		
		dbPool[shard.ID] = db
		logger.WithField("shard_id", shard.ID).Info("Connected to database shard")
	}
	
	return dbPool, nil
}

func (q *QueryService) Close() {
	for _, db := range q.dbPool {
		db.Close()
	}
}

// Hash function to determine shard
func (q *QueryService) getShardID(userID string) uint32 {
	h := fnv.New32a()
	h.Write([]byte(userID))
	return h.Sum32() % uint32(len(q.shards))
}

// GET /api/users/{user_id}/posts - Get posts by user
func (q *QueryService) getUserPosts(w http.ResponseWriter, r *http.Request) {
	timer := prometheus.NewTimer(queryDuration.WithLabelValues("GET", "/api/users/{user_id}/posts"))
	defer timer.ObserveDuration()
	
	vars := mux.Vars(r)
	userID := vars["user_id"]
	
	if userID == "" {
		queriesTotal.WithLabelValues("GET", "/api/users/{user_id}/posts", "400").Inc()
		q.respondWithError(w, http.StatusBadRequest, "user_id is required")
		return
	}
	
	// Get limit and offset from query parameters
	limitStr := r.URL.Query().Get("limit")
	offsetStr := r.URL.Query().Get("offset")
	
	limit := 10 
	if limitStr != "" {
		if l, err := strconv.Atoi(limitStr); err == nil && l > 0 {
			limit = l
		}
	}
	
	offset := 0 
	if offsetStr != "" {
		if o, err := strconv.Atoi(offsetStr); err == nil && o >= 0 {
			offset = o
		}
	}
	
	// Determine which shard contains this user's data
	shardID := q.getShardID(userID)
	db := q.dbPool[shardID]
	
	query := `SELECT id, user_id, content, created_at, updated_at 
			  FROM posts 
			  WHERE user_id = $1 
			  ORDER BY created_at DESC 
			  LIMIT $2 OFFSET $3`
	
	rows, err := db.Query(query, userID, limit, offset)
	if err != nil {
		queriesTotal.WithLabelValues("GET", "/api/users/{user_id}/posts", "500").Inc()
		shardQueries.WithLabelValues(fmt.Sprintf("shard_%d", shardID), "error").Inc()
		q.logger.WithError(err).Error("Failed to query user posts")
		q.respondWithError(w, http.StatusInternalServerError, "Failed to retrieve posts")
		return
	}
	defer rows.Close()
	
	var posts []Post
	for rows.Next() {
		var post Post
		err := rows.Scan(&post.ID, &post.UserID, &post.Content, &post.CreatedAt, &post.UpdatedAt)
		if err != nil {
			q.logger.WithError(err).Error("Failed to scan post row")
			continue
		}
		posts = append(posts, post)
	}
	
	shardQueries.WithLabelValues(fmt.Sprintf("shard_%d", shardID), "success").Inc()
	queriesTotal.WithLabelValues("GET", "/api/users/{user_id}/posts", "200").Inc()
	
	count := len(posts)
	q.respondWithJSON(w, http.StatusOK, APIResponse{
		Success: true,
		Message: fmt.Sprintf("Retrieved %d posts for user %s", count, userID),
		Data:    posts,
		Count:   &count,
	})
}

// GET /api/posts/{post_id} - Get post by ID with comments and likes
func (q *QueryService) getPost(w http.ResponseWriter, r *http.Request) {
	timer := prometheus.NewTimer(queryDuration.WithLabelValues("GET", "/api/posts/{post_id}"))
	defer timer.ObserveDuration()
	
	vars := mux.Vars(r)
	postID := vars["post_id"]
	
	if postID == "" {
		queriesTotal.WithLabelValues("GET", "/api/posts/{post_id}", "400").Inc()
		q.respondWithError(w, http.StatusBadRequest, "post_id is required")
		return
	}
	
	var post *Post
	
	for _, db := range q.dbPool {
		query := `SELECT id, user_id, content, created_at, updated_at FROM posts WHERE id = $1`
		row := db.QueryRow(query, postID)
		
		var p Post
		err := row.Scan(&p.ID, &p.UserID, &p.Content, &p.CreatedAt, &p.UpdatedAt)
		if err == nil {
			post = &p
			break
		}
	}
	
	if post == nil {
		queriesTotal.WithLabelValues("GET", "/api/posts/{post_id}", "404").Inc()
		q.respondWithError(w, http.StatusNotFound, "Post not found")
		return
	}
	
	// Get comments for this post 
	var comments []Comment
	for shardID, db := range q.dbPool {
		query := `SELECT id, post_id, user_id, content, created_at, updated_at 
				  FROM comments WHERE post_id = $1 ORDER BY created_at ASC`
		rows, err := db.Query(query, postID)
		if err != nil {
			shardQueries.WithLabelValues(fmt.Sprintf("shard_%d", shardID), "error").Inc()
			continue
		}
		
		for rows.Next() {
			var comment Comment
			err := rows.Scan(&comment.ID, &comment.PostID, &comment.UserID, &comment.Content, &comment.CreatedAt, &comment.UpdatedAt)
			if err == nil {
				comments = append(comments, comment)
			}
		}
		rows.Close()
		shardQueries.WithLabelValues(fmt.Sprintf("shard_%d", shardID), "success").Inc()
	}
	
	// Get likes for this post 
	var likes []Like
	for shardID, db := range q.dbPool {
		query := `SELECT id, post_id, user_id, created_at FROM likes WHERE post_id = $1`
		rows, err := db.Query(query, postID)
		if err != nil {
			shardQueries.WithLabelValues(fmt.Sprintf("shard_%d", shardID), "error").Inc()
			continue
		}
		
		for rows.Next() {
			var like Like
			err := rows.Scan(&like.ID, &like.PostID, &like.UserID, &like.CreatedAt)
			if err == nil {
				likes = append(likes, like)
			}
		}
		rows.Close()
		shardQueries.WithLabelValues(fmt.Sprintf("shard_%d", shardID), "success").Inc()
	}
	
	queriesTotal.WithLabelValues("GET", "/api/posts/{post_id}", "200").Inc()
	
	result := map[string]interface{}{
		"post":     post,
		"comments": comments,
		"likes":    likes,
		"stats": map[string]int{
			"comment_count": len(comments),
			"like_count":    len(likes),
		},
	}
	
	q.respondWithJSON(w, http.StatusOK, APIResponse{
		Success: true,
		Message: "Post retrieved successfully",
		Data:    result,
	})
}

// GET /api/users/{user_id}/stats - Get user statistics
func (q *QueryService) getUserStats(w http.ResponseWriter, r *http.Request) {
	timer := prometheus.NewTimer(queryDuration.WithLabelValues("GET", "/api/users/{user_id}/stats"))
	defer timer.ObserveDuration()
	
	vars := mux.Vars(r)
	userID := vars["user_id"]
	
	if userID == "" {
		queriesTotal.WithLabelValues("GET", "/api/users/{user_id}/stats", "400").Inc()
		q.respondWithError(w, http.StatusBadRequest, "user_id is required")
		return
	}
	
	// Get stats from the user's shard
	shardID := q.getShardID(userID)
	db := q.dbPool[shardID]
	
	var stats UserStats
	stats.UserID = userID
	
	// Get post count
	err := db.QueryRow("SELECT COUNT(*) FROM posts WHERE user_id = $1", userID).Scan(&stats.PostCount)
	if err != nil {
		q.logger.WithError(err).Error("Failed to get post count")
	}
	
	// Get comment count
	err = db.QueryRow("SELECT COUNT(*) FROM comments WHERE user_id = $1", userID).Scan(&stats.CommentCount)
	if err != nil {
		q.logger.WithError(err).Error("Failed to get comment count")
	}
	
	// Get like count
	err = db.QueryRow("SELECT COUNT(*) FROM likes WHERE user_id = $1", userID).Scan(&stats.LikeCount)
	if err != nil {
		q.logger.WithError(err).Error("Failed to get like count")
	}
	
	shardQueries.WithLabelValues(fmt.Sprintf("shard_%d", shardID), "success").Inc()
	queriesTotal.WithLabelValues("GET", "/api/users/{user_id}/stats", "200").Inc()
	
	q.respondWithJSON(w, http.StatusOK, APIResponse{
		Success: true,
		Message: "User statistics retrieved successfully",
		Data:    stats,
	})
}

// GET /api/posts - Get recent posts across all shards
func (q *QueryService) getRecentPosts(w http.ResponseWriter, r *http.Request) {
	timer := prometheus.NewTimer(queryDuration.WithLabelValues("GET", "/api/posts"))
	defer timer.ObserveDuration()
	
	limitStr := r.URL.Query().Get("limit")
	limit := 20 // default
	if limitStr != "" {
		if l, err := strconv.Atoi(limitStr); err == nil && l > 0 {
			limit = l
		}
	}
	
	// Query all shards and merge results
	var allPosts []Post
	
	for shardID, db := range q.dbPool {
		query := `SELECT id, user_id, content, created_at, updated_at 
				  FROM posts 
				  ORDER BY created_at DESC 
				  LIMIT $1`
		
		rows, err := db.Query(query, limit)
		if err != nil {
			shardQueries.WithLabelValues(fmt.Sprintf("shard_%d", shardID), "error").Inc()
			q.logger.WithError(err).WithField("shard_id", shardID).Error("Failed to query posts")
			continue
		}
		
		for rows.Next() {
			var post Post
			err := rows.Scan(&post.ID, &post.UserID, &post.Content, &post.CreatedAt, &post.UpdatedAt)
			if err == nil {
				allPosts = append(allPosts, post)
			}
		}
		rows.Close()
		shardQueries.WithLabelValues(fmt.Sprintf("shard_%d", shardID), "success").Inc()
	}
	
	// Sort by created_at descending and limit
	// Simple bubble sort for small datasets
	for i := 0; i < len(allPosts)-1; i++ {
		for j := 0; j < len(allPosts)-i-1; j++ {
			if allPosts[j].CreatedAt.Before(allPosts[j+1].CreatedAt) {
				allPosts[j], allPosts[j+1] = allPosts[j+1], allPosts[j]
			}
		}
	}
	
	// Apply limit
	if len(allPosts) > limit {
		allPosts = allPosts[:limit]
	}
	
	queriesTotal.WithLabelValues("GET", "/api/posts", "200").Inc()
	count := len(allPosts)
	
	q.respondWithJSON(w, http.StatusOK, APIResponse{
		Success: true,
		Message: fmt.Sprintf("Retrieved %d recent posts", count),
		Data:    allPosts,
		Count:   &count,
	})
}

// GET /health
func (q *QueryService) handleHealth(w http.ResponseWriter, r *http.Request) {
	// Check database connections
	healthyShards := 0
	for shardID, db := range q.dbPool {
		if err := db.Ping(); err == nil {
			healthyShards++
		} else {
			q.logger.WithError(err).WithField("shard_id", shardID).Warn("Unhealthy shard")
		}
	}
	
	status := "healthy"
	if healthyShards < len(q.dbPool) {
		status = "degraded"
	}
	
	response := map[string]interface{}{
		"service":        "query",
		"status":         status,
		"timestamp":      time.Now().UTC(),
		"total_shards":   len(q.dbPool),
		"healthy_shards": healthyShards,
		"version":        "1.0.0",
	}
	
	statusCode := http.StatusOK
	if status == "degraded" {
		statusCode = http.StatusServiceUnavailable
	}
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	json.NewEncoder(w).Encode(response)
}

func (q *QueryService) respondWithJSON(w http.ResponseWriter, code int, payload interface{}) {
	response, _ := json.Marshal(payload)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	w.Write(response)
}

func (q *QueryService) respondWithError(w http.ResponseWriter, code int, message string) {
	q.respondWithJSON(w, code, APIResponse{
		Success: false,
		Error:   message,
	})
}

func (q *QueryService) setupRoutes() *mux.Router {
	r := mux.NewRouter()
	
	// API routes
	api := r.PathPrefix("/api").Subrouter()
	api.HandleFunc("/users/{user_id}/posts", q.getUserPosts).Methods("GET")
	api.HandleFunc("/users/{user_id}/stats", q.getUserStats).Methods("GET")
	api.HandleFunc("/posts/{post_id}", q.getPost).Methods("GET")
	api.HandleFunc("/posts", q.getRecentPosts).Methods("GET")
	
	// Health and metrics
	r.HandleFunc("/health", q.handleHealth).Methods("GET")
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
	service, err := NewQueryService()
	if err != nil {
		logrus.WithError(err).Fatal("Failed to create query service")
	}
	defer service.Close()
	
	router := service.setupRoutes()
	
	// CORS middleware
	c := cors.New(cors.Options{
		AllowedOrigins: []string{"*"}, 
		AllowedMethods: []string{"GET", "OPTIONS"},
		AllowedHeaders: []string{"*"},
	})
	
	handler := c.Handler(router)
	
	port := getEnv("QUERY_PORT", "8083")
	server := &http.Server{
		Addr:    ":" + port,
		Handler: handler,
	}
	
	go func() {
		service.logger.WithField("port", port).Info("Starting query service")
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			service.logger.WithError(err).Fatal("Server failed to start")
		}
	}()
	
	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	
	service.logger.Info("Shutting down query service...")
	
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	
	if err := server.Shutdown(ctx); err != nil {
		service.logger.WithError(err).Fatal("Server forced to shutdown")
	}
	
	service.logger.Info("Query service stopped")
}