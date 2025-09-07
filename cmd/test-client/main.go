package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"github.com/google/uuid"
	"github.com/sirupsen/logrus"
)

type APIResponse struct {
	Success bool        `json:"success"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
	Error   string      `json:"error,omitempty"`
}

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
	Action string `json:"action"`
}

func main() {
	logger := logrus.New()
	baseURL := "http://localhost:8081"
	
	if len(os.Args) > 1 {
		baseURL = os.Args[1]
	}
	
	logger.WithField("base_url", baseURL).Info("Testing ingestion service")
	
	// Test health endpoint
	if err := testHealth(baseURL, logger); err != nil {
		logger.WithError(err).Fatal("Health check failed")
	}
	
	// Generate test user IDs
	user1 := uuid.New().String()
	user2 := uuid.New().String()
	
	logger.WithFields(logrus.Fields{
		"user1": user1,
		"user2": user2,
	}).Info("Generated test users")
	
	// Test creating posts
	post1ID, err := testCreatePost(baseURL, user1, "Hello, this is my first post! #testing", logger)
	if err != nil {
		logger.WithError(err).Fatal("Failed to create post 1")
	}
	
	post2ID, err := testCreatePost(baseURL, user2, "Another test post from user 2", logger)
	if err != nil {
		logger.WithError(err).Fatal("Failed to create post 2")
	}
	
	// Test creating comments
	if err := testCreateComment(baseURL, post1ID, user2, "Great post!", logger); err != nil {
		logger.WithError(err).Fatal("Failed to create comment")
	}
	
	if err := testCreateComment(baseURL, post2ID, user1, "Nice work!", logger); err != nil {
		logger.WithError(err).Fatal("Failed to create comment 2")
	}
	
	// Test likes
	if err := testLike(baseURL, post1ID, user2, "like", logger); err != nil {
		logger.WithError(err).Fatal("Failed to like post")
	}
	
	if err := testLike(baseURL, post2ID, user1, "like", logger); err != nil {
		logger.WithError(err).Fatal("Failed to like post 2")
	}
	
	// Test unlike
	if err := testLike(baseURL, post1ID, user2, "unlike", logger); err != nil {
		logger.WithError(err).Fatal("Failed to unlike post")
	}
	
	// Test validation errors
	testValidationErrors(baseURL, logger)
	
	logger.Info("All tests completed successfully!")
}

func testHealth(baseURL string, logger *logrus.Logger) error {
	logger.Info("Testing health endpoint...")
	
	resp, err := http.Get(baseURL + "/health")
	if err != nil {
		return fmt.Errorf("health request failed: %w", err)
	}
	defer resp.Body.Close()
	
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("health check failed with status: %d", resp.StatusCode)
	}
	
	var apiResp APIResponse
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return fmt.Errorf("failed to decode health response: %w", err)
	}
	
	logger.WithField("response", apiResp).Info("Health check passed")
	return nil
}

func testCreatePost(baseURL, userID, content string, logger *logrus.Logger) (string, error) {
	logger.WithFields(logrus.Fields{
		"user_id": userID,
		"content": content[:20] + "...",
	}).Info("Testing post creation...")
	
	req := CreatePostRequest{
		UserID:  userID,
		Content: content,
	}
	
	resp, err := makeRequest("POST", baseURL+"/api/posts", req)
	if err != nil {
		return "", fmt.Errorf("create post request failed: %w", err)
	}
	defer resp.Body.Close()
	
	if resp.StatusCode != http.StatusAccepted {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("create post failed with status %d: %s", resp.StatusCode, string(body))
	}
	
	var apiResp APIResponse
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return "", fmt.Errorf("failed to decode post response: %w", err)
	}
	
	data, ok := apiResp.Data.(map[string]interface{})
	if !ok {
		return "", fmt.Errorf("unexpected response data format")
	}
	
	postID, ok := data["post_id"].(string)
	if !ok {
		return "", fmt.Errorf("post_id not found in response")
	}
	
	logger.WithField("post_id", postID).Info("Post created successfully")
	return postID, nil
}

func testCreateComment(baseURL, postID, userID, content string, logger *logrus.Logger) error {
	logger.WithFields(logrus.Fields{
		"post_id": postID,
		"user_id": userID,
		"content": content,
	}).Info("Testing comment creation...")
	
	req := CreateCommentRequest{
		PostID:  postID,
		UserID:  userID,
		Content: content,
	}
	
	resp, err := makeRequest("POST", baseURL+"/api/comments", req)
	if err != nil {
		return fmt.Errorf("create comment request failed: %w", err)
	}
	defer resp.Body.Close()
	
	if resp.StatusCode != http.StatusAccepted {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("create comment failed with status %d: %s", resp.StatusCode, string(body))
	}
	
	var apiResp APIResponse
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return fmt.Errorf("failed to decode comment response: %w", err)
	}
	
	logger.WithField("response", apiResp).Info("Comment created successfully")
	return nil
}

func testLike(baseURL, postID, userID, action string, logger *logrus.Logger) error {
	logger.WithFields(logrus.Fields{
		"post_id": postID,
		"user_id": userID,
		"action":  action,
	}).Info("Testing like action...")
	
	req := LikeRequest{
		PostID: postID,
		UserID: userID,
		Action: action,
	}
	
	resp, err := makeRequest("POST", baseURL+"/api/likes", req)
	if err != nil {
		return fmt.Errorf("like request failed: %w", err)
	}
	defer resp.Body.Close()
	
	if resp.StatusCode != http.StatusAccepted {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("like failed with status %d: %s", resp.StatusCode, string(body))
	}
	
	var apiResp APIResponse
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return fmt.Errorf("failed to decode like response: %w", err)
	}
	
	logger.WithField("response", apiResp).Info("Like action completed successfully")
	return nil
}

func testValidationErrors(baseURL string, logger *logrus.Logger) {
	logger.Info("Testing validation errors...")
	
	// Test empty post
	emptyPost := CreatePostRequest{
		UserID:  "",
		Content: "",
	}
	
	resp, err := makeRequest("POST", baseURL+"/api/posts", emptyPost)
	if err == nil {
		defer resp.Body.Close()
		if resp.StatusCode == http.StatusBadRequest {
			logger.Info("Empty post validation test passed")
		} else {
			logger.Warn("Expected validation error for empty post")
		}
	}
	
	// Test long content
	longContent := CreatePostRequest{
		UserID:  uuid.New().String(),
		Content: string(make([]byte, 300)), // Over 280 char limit
	}
	
	resp, err = makeRequest("POST", baseURL+"/api/posts", longContent)
	if err == nil {
		defer resp.Body.Close()
		if resp.StatusCode == http.StatusBadRequest {
			logger.Info("Long content validation test passed")
		} else {
			logger.Warn("Expected validation error for long content")
		}
	}
	
	// Test invalid like action
	invalidLike := LikeRequest{
		PostID: uuid.New().String(),
		UserID: uuid.New().String(),
		Action: "invalid_action",
	}
	
	resp, err = makeRequest("POST", baseURL+"/api/likes", invalidLike)
	if err == nil {
		defer resp.Body.Close()
		if resp.StatusCode == http.StatusBadRequest {
			logger.Info("Invalid like action validation test passed")
		} else {
			logger.Warn("Expected validation error for invalid like action")
		}
	}
}

func makeRequest(method, url string, payload interface{}) (*http.Response, error) {
	jsonData, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}
	
	client := &http.Client{
		Timeout: 10 * time.Second,
	}
	
	req, err := http.NewRequest(method, url, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, err
	}
	
	req.Header.Set("Content-Type", "application/json")
	
	return client.Do(req)
}