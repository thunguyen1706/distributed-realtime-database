#!/usr/bin/env pwsh

$BASE_URL = "http://localhost:8081"

Write-Host "Testing Ingestion Service..." -ForegroundColor Green

# Check if services are running
Write-Host "Checking if services are running..." -ForegroundColor Yellow

$services = docker-compose ps --services --filter "status=running"
if ($services -notcontains "ingestion-service") {
    Write-Host "Error: Ingestion service is not running. Please run './scripts/up.ps1' first." -ForegroundColor Red
    exit 1
}

if ($services -notcontains "kafka") {
    Write-Host "Error: Kafka is not running. Please run './scripts/up.ps1' first." -ForegroundColor Red
    exit 1
}

Write-Host "Waiting for services to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

Write-Host ""
Write-Host "=== Testing Health Endpoint ===" -ForegroundColor Cyan
try {
    $healthResponse = Invoke-RestMethod -Uri "$BASE_URL/health" -Method GET -ContentType "application/json"
    Write-Host ($healthResponse | ConvertTo-Json -Depth 3) -ForegroundColor Green
    Write-Host "Health check passed!" -ForegroundColor Green
} catch {
    Write-Host "Health check failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Testing Post Creation ===" -ForegroundColor Cyan
$postBody = @{
    user_id = "test-user-1"
    content = "This is a test post from the ingestion service!"
} | ConvertTo-Json

try {
    $postResponse = Invoke-RestMethod -Uri "$BASE_URL/api/posts" -Method POST -Body $postBody -ContentType "application/json"
    Write-Host ($postResponse | ConvertTo-Json -Depth 3) -ForegroundColor Green
    $postId = $postResponse.data.post_id
    Write-Host "Post created with ID: $postId" -ForegroundColor Green
} catch {
    Write-Host "Post creation failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Testing Comment Creation ===" -ForegroundColor Cyan
$commentBody = @{
    post_id = $postId
    user_id = "test-user-2"
    content = "Great post! This is a comment."
} | ConvertTo-Json

try {
    $commentResponse = Invoke-RestMethod -Uri "$BASE_URL/api/comments" -Method POST -Body $commentBody -ContentType "application/json"
    Write-Host ($commentResponse | ConvertTo-Json -Depth 3) -ForegroundColor Green
    Write-Host "Comment created successfully!" -ForegroundColor Green
} catch {
    Write-Host "Comment creation failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Testing Like Action ===" -ForegroundColor Cyan
$likeBody = @{
    post_id = $postId
    user_id = "test-user-2"
    action = "like"
} | ConvertTo-Json

try {
    $likeResponse = Invoke-RestMethod -Uri "$BASE_URL/api/likes" -Method POST -Body $likeBody -ContentType "application/json"
    Write-Host ($likeResponse | ConvertTo-Json -Depth 3) -ForegroundColor Green
    Write-Host "Like action completed!" -ForegroundColor Green
} catch {
    Write-Host "Like action failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Testing Unlike Action ===" -ForegroundColor Cyan
$unlikeBody = @{
    post_id = $postId
    user_id = "test-user-2"
    action = "unlike"
} | ConvertTo-Json

try {
    $unlikeResponse = Invoke-RestMethod -Uri "$BASE_URL/api/likes" -Method POST -Body $unlikeBody -ContentType "application/json"
    Write-Host ($unlikeResponse | ConvertTo-Json -Depth 3) -ForegroundColor Green
    Write-Host "Unlike action completed!" -ForegroundColor Green
} catch {
    Write-Host "Unlike action failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Testing Validation Errors ===" -ForegroundColor Cyan

# Test empty content
Write-Host "Testing empty content..." -ForegroundColor Yellow
$emptyBody = @{
    user_id = ""
    content = ""
} | ConvertTo-Json

try {
    Invoke-RestMethod -Uri "$BASE_URL/api/posts" -Method POST -Body $emptyBody -ContentType "application/json" -ErrorAction Stop
    Write-Host "Expected validation error for empty content" -ForegroundColor Red
} catch {
    if ($_.Exception.Response.StatusCode -eq 400) {
        Write-Host "Empty content validation test passed" -ForegroundColor Green
    } else {
        Write-Host "Unexpected error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Test long content
Write-Host "Testing long content..." -ForegroundColor Yellow
$longContent = "a" * 300  # Over 280 char limit
$longBody = @{
    user_id = "test-user"
    content = $longContent
} | ConvertTo-Json

try {
    Invoke-RestMethod -Uri "$BASE_URL/api/posts" -Method POST -Body $longBody -ContentType "application/json" -ErrorAction Stop
    Write-Host "Expected validation error for long content" -ForegroundColor Red
} catch {
    if ($_.Exception.Response.StatusCode -eq 400) {
        Write-Host "Long content validation test passed" -ForegroundColor Green
    } else {
        Write-Host "Unexpected error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Testing Metrics Endpoint ===" -ForegroundColor Cyan
try {
    $metricsResponse = Invoke-WebRequest -Uri "$BASE_URL/metrics" -UseBasicParsing
    $metrics = $metricsResponse.Content -split "`n" | Where-Object { $_ -match "(http_requests_total|events_published_total)" } | Select-Object -First 5
    $metrics | ForEach-Object { Write-Host $_ -ForegroundColor White }
    Write-Host "Metrics endpoint working!" -ForegroundColor Green
} catch {
    Write-Host "Metrics endpoint failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Checking Kafka Topics ===" -ForegroundColor Cyan
try {
    $topics = docker exec kafka kafka-topics --list --bootstrap-server localhost:29092
    Write-Host "Available topics:" -ForegroundColor White
    $topics | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
} catch {
    Write-Host "Failed to list Kafka topics" -ForegroundColor Red
}

Write-Host ""
Write-Host "Ingestion service tests completed!" -ForegroundColor Green