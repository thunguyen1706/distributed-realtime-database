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
	"strings"
	"syscall"
	"time"

	"github.com/IBM/sarama"
	"github.com/joho/godotenv"
	_ "github.com/lib/pq"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
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
	messagesProcessed = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "messages_processed_total",
			Help: "Total number of messages processed",
		},
		[]string{"topic", "status"},
	)
	
	databaseWrites = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "database_writes_total",
			Help: "Total number of database writes",
		},
		[]string{"shard", "table", "status"},
	)
	
	processingDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name: "message_processing_duration_seconds",
			Help: "Time spent processing messages",
		},
		[]string{"topic"},
	)
)

func init() {
	prometheus.MustRegister(messagesProcessed)
	prometheus.MustRegister(databaseWrites)
	prometheus.MustRegister(processingDuration)
}

type ConsumerService struct {
	consumer    sarama.ConsumerGroup
	shards      []ShardConfig
	dbPool      map[uint32]*sql.DB
	logger      *logrus.Logger
	ready       chan bool
	ctx         context.Context
	cancel      context.CancelFunc
}

func NewConsumerService() (*ConsumerService, error) {
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
	
	// Initialize Kafka consumer
	kafkaServers := strings.Split(getEnv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"), ",")
	config := sarama.NewConfig()
	config.Consumer.Group.Rebalance.Strategy = sarama.BalanceStrategyRoundRobin
	config.Consumer.Offsets.Initial = sarama.OffsetOldest
	config.Consumer.Group.Session.Timeout = 10 * time.Second
	config.Consumer.Group.Heartbeat.Interval = 3 * time.Second
	config.Version = sarama.V2_6_0_0
	
	consumer, err := sarama.NewConsumerGroup(kafkaServers, "db-writer-group", config)
	if err != nil {
		return nil, fmt.Errorf("failed to create consumer group: %w", err)
	}
	
	ctx, cancel := context.WithCancel(context.Background())
	
	return &ConsumerService{
		consumer: consumer,
		shards:   shards,
		dbPool:   dbPool,
		logger:   logger,
		ready:    make(chan bool),
		ctx:      ctx,
		cancel:   cancel,
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
	
	// Query shard configuration
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
	
	if len(shards) == 0 {
		return nil, fmt.Errorf("no shards found in configuration")
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
		
		// Test the connection
		if err := db.Ping(); err != nil {
			return nil, fmt.Errorf("failed to ping shard %d: %w", shard.ID, err)
		}
		
		// Configure connection pool
		db.SetMaxOpenConns(10)
		db.SetMaxIdleConns(5)
		db.SetConnMaxLifetime(time.Hour)
		
		dbPool[shard.ID] = db
		logger.WithField("shard_id", shard.ID).Info("Connected to database shard")
	}
	
	return dbPool, nil
}

func (c *ConsumerService) Close() {
	c.cancel()
	if c.consumer != nil {
		c.consumer.Close()
	}
	for _, db := range c.dbPool {
		db.Close()
	}
}

// Setup implements sarama.ConsumerGroupHandler
func (c *ConsumerService) Setup(sarama.ConsumerGroupSession) error {
	close(c.ready)
	return nil
}

// Cleanup implements sarama.ConsumerGroupHandler
func (c *ConsumerService) Cleanup(sarama.ConsumerGroupSession) error {
	return nil
}

// ConsumeClaim implements sarama.ConsumerGroupHandler
func (c *ConsumerService) ConsumeClaim(session sarama.ConsumerGroupSession, claim sarama.ConsumerGroupClaim) error {
	for {
		select {
		case message := <-claim.Messages():
			if message == nil {
				return nil
			}
			
			timer := prometheus.NewTimer(processingDuration.WithLabelValues(message.Topic))
			err := c.processMessage(message)
			timer.ObserveDuration()
			
			if err != nil {
				c.logger.WithError(err).WithFields(logrus.Fields{
					"topic":     message.Topic,
					"partition": message.Partition,
					"offset":    message.Offset,
				}).Error("Failed to process message")
				messagesProcessed.WithLabelValues(message.Topic, "error").Inc()
			} else {
				messagesProcessed.WithLabelValues(message.Topic, "success").Inc()
			}
			
			session.MarkMessage(message, "")
			
		case <-c.ctx.Done():
			return nil
		}
	}
}

func (c *ConsumerService) processMessage(message *sarama.ConsumerMessage) error {
	c.logger.WithFields(logrus.Fields{
		"topic":     message.Topic,
		"partition": message.Partition,
		"offset":    message.Offset,
		"key":       string(message.Key),
	}).Debug("Processing message")
	
	switch message.Topic {
	case "posts":
		return c.processPostEvent(message)
	case "comments":
		return c.processCommentEvent(message)
	case "likes":
		return c.processLikeEvent(message)
	default:
		c.logger.WithField("topic", message.Topic).Warn("Unknown topic")
		return nil
	}
}

func (c *ConsumerService) processPostEvent(message *sarama.ConsumerMessage) error {
	var event PostEvent
	if err := json.Unmarshal(message.Value, &event); err != nil {
		return fmt.Errorf("failed to unmarshal post event: %w", err)
	}
	
	// Determine shard
	shardID := c.getShardID(event.UserID)
	db := c.dbPool[shardID]
	
	// Insert into database
	query := `INSERT INTO posts (id, user_id, content, created_at, updated_at) 
			  VALUES ($1, $2, $3, $4, $4)
			  ON CONFLICT (id) DO NOTHING`
	
	_, err := db.Exec(query, event.ID, event.UserID, event.Content, event.Timestamp)
	if err != nil {
		databaseWrites.WithLabelValues(fmt.Sprintf("shard_%d", shardID), "posts", "error").Inc()
		return fmt.Errorf("failed to insert post into shard %d: %w", shardID, err)
	}
	
	databaseWrites.WithLabelValues(fmt.Sprintf("shard_%d", shardID), "posts", "success").Inc()
	c.logger.WithFields(logrus.Fields{
		"post_id":  event.ID,
		"user_id":  event.UserID,
		"shard_id": shardID,
	}).Info("Post inserted successfully")
	
	return nil
}

func (c *ConsumerService) processCommentEvent(message *sarama.ConsumerMessage) error {
	var event CommentEvent
	if err := json.Unmarshal(message.Value, &event); err != nil {
		return fmt.Errorf("failed to unmarshal comment event: %w", err)
	}
	
	// Determine shard based on user_id for consistency
	shardID := c.getShardID(event.UserID)
	db := c.dbPool[shardID]
	
	// Insert into database
	query := `INSERT INTO comments (id, post_id, user_id, content, created_at, updated_at) 
			  VALUES ($1, $2, $3, $4, $5, $5)
			  ON CONFLICT (id) DO NOTHING`
	
	_, err := db.Exec(query, event.ID, event.PostID, event.UserID, event.Content, event.Timestamp)
	if err != nil {
		databaseWrites.WithLabelValues(fmt.Sprintf("shard_%d", shardID), "comments", "error").Inc()
		return fmt.Errorf("failed to insert comment into shard %d: %w", shardID, err)
	}
	
	databaseWrites.WithLabelValues(fmt.Sprintf("shard_%d", shardID), "comments", "success").Inc()
	c.logger.WithFields(logrus.Fields{
		"comment_id": event.ID,
		"post_id":    event.PostID,
		"user_id":    event.UserID,
		"shard_id":   shardID,
	}).Info("Comment inserted successfully")
	
	return nil
}

func (c *ConsumerService) processLikeEvent(message *sarama.ConsumerMessage) error {
	var event LikeEvent
	if err := json.Unmarshal(message.Value, &event); err != nil {
		return fmt.Errorf("failed to unmarshal like event: %w", err)
	}
	
	// Determine shard based on user_id for consistency
	shardID := c.getShardID(event.UserID)
	db := c.dbPool[shardID]
	
	if event.Action == "like" {
		// Insert like
		query := `INSERT INTO likes (id, post_id, user_id, created_at) 
				  VALUES ($1, $2, $3, $4)
				  ON CONFLICT (post_id, user_id) DO NOTHING`
		
		_, err := db.Exec(query, event.ID, event.PostID, event.UserID, event.Timestamp)
		if err != nil {
			databaseWrites.WithLabelValues(fmt.Sprintf("shard_%d", shardID), "likes", "error").Inc()
			return fmt.Errorf("failed to insert like into shard %d: %w", shardID, err)
		}
		
		databaseWrites.WithLabelValues(fmt.Sprintf("shard_%d", shardID), "likes", "success").Inc()
		c.logger.WithFields(logrus.Fields{
			"like_id":  event.ID,
			"post_id":  event.PostID,
			"user_id":  event.UserID,
			"action":   event.Action,
			"shard_id": shardID,
		}).Info("Like inserted successfully")
		
	} else if event.Action == "unlike" {
		// Remove like
		query := `DELETE FROM likes WHERE post_id = $1 AND user_id = $2`
		
		result, err := db.Exec(query, event.PostID, event.UserID)
		if err != nil {
			databaseWrites.WithLabelValues(fmt.Sprintf("shard_%d", shardID), "likes", "error").Inc()
			return fmt.Errorf("failed to delete like from shard %d: %w", shardID, err)
		}
		
		rowsAffected, _ := result.RowsAffected()
		databaseWrites.WithLabelValues(fmt.Sprintf("shard_%d", shardID), "likes", "success").Inc()
		c.logger.WithFields(logrus.Fields{
			"post_id":       event.PostID,
			"user_id":       event.UserID,
			"action":        event.Action,
			"shard_id":      shardID,
			"rows_affected": rowsAffected,
		}).Info("Unlike processed successfully")
	}
	
	return nil
}

// Simple hash function to determine shard
func (c *ConsumerService) getShardID(userID string) uint32 {
	h := fnv.New32a()
	h.Write([]byte(userID))
	hash := h.Sum32()
	shardID := hash % uint32(len(c.shards))
	
	c.logger.WithFields(logrus.Fields{
		"user_id":  userID,
		"hash":     hash,
		"shard_id": shardID,
		"total_shards": len(c.shards),
	}).Debug("Calculated shard for user")
	
	return shardID
}

func (c *ConsumerService) healthHandler(w http.ResponseWriter, r *http.Request) {
	response := map[string]interface{}{
		"service":   "consumer",
		"status":    "healthy",
		"timestamp": time.Now().UTC(),
		"shards":    len(c.shards),
		"version":   "1.0.0",
	}
	
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func (c *ConsumerService) startHTTPServer() {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", c.healthHandler)
	mux.Handle("/metrics", promhttp.Handler())
	
	port := getEnv("CONSUMER_PORT", "8082")
	server := &http.Server{
		Addr:    ":" + port,
		Handler: mux,
	}
	
	go func() {
		c.logger.WithField("port", port).Info("Starting consumer HTTP server")
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			c.logger.WithError(err).Error("HTTP server failed")
		}
	}()
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func main() {
	service, err := NewConsumerService()
	if err != nil {
		logrus.WithError(err).Fatal("Failed to create consumer service")
	}
	defer service.Close()
	
	// Start HTTP server for health checks and metrics
	service.startHTTPServer()
	
	// Start consuming
	topics := []string{"posts", "comments", "likes"}
	
	go func() {
		for {
			// `Consume` should be called inside an infinite loop
			if err := service.consumer.Consume(service.ctx, topics, service); err != nil {
				service.logger.WithError(err).Error("Error from consumer")
			}
			
			// Check if context was cancelled, signaling that the consumer should stop
			if service.ctx.Err() != nil {
				return
			}
			service.ready = make(chan bool)
		}
	}()
	
	<-service.ready // Await till the consumer has been set up
	service.logger.Info("Consumer service started and ready")
	
	// Wait for interrupt signal
	sigterm := make(chan os.Signal, 1)
	signal.Notify(sigterm, syscall.SIGINT, syscall.SIGTERM)
	
	select {
	case <-service.ctx.Done():
		service.logger.Info("Terminating: context cancelled")
	case <-sigterm:
		service.logger.Info("Terminating: via signal")
	}
	
	service.cancel()
	service.logger.Info("Consumer service stopped")
}