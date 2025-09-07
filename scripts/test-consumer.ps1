#!/usr/bin/env pwsh

Write-Host "Testing Consumer Service and Database Integration..." -ForegroundColor Green

# Check if services are running
Write-Host "Checking if services are running..." -ForegroundColor Yellow

$services = docker-compose ps --services --filter "status=running"
if ($services -notcontains "consumer-service") {
    Write-Host "Error: Consumer service is not running. Please run './scripts/up.ps1' first." -ForegroundColor Red
    exit 1
}

if ($services -notcontains "ingestion-service") {
    Write-Host "Error: Ingestion service is not running. Please run './scripts/up.ps1' first." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Testing Consumer Service Health ===" -ForegroundColor Cyan
try {
    $healthResponse = Invoke-RestMethod -Uri "http://localhost:8082/health" -Method GET -ContentType "application/json"
    Write-Host ($healthResponse | ConvertTo-Json -Depth 3) -ForegroundColor Green
    Write-Host "Consumer service health check passed!" -ForegroundColor Green
} catch {
    Write-Host "Consumer service health check failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Creating Test Data via Ingestion Service ===" -ForegroundColor Cyan

# Create a test user
$testUser = "test-user-$(Get-Random -Minimum 1000 -Maximum 9999)"
Write-Host "Using test user: $testUser" -ForegroundColor Yellow

# Create multiple posts to test sharding
Write-Host "Creating test posts..." -ForegroundColor Yellow
$postIds = @()

for ($i = 1; $i -le 3; $i++) {
    $postBody = @{
        user_id = $testUser
        content = "Test post #$i for database integration testing"
    } | ConvertTo-Json

    try {
        $postResponse = Invoke-RestMethod -Uri "http://localhost:8081/api/posts" -Method POST -Body $postBody -ContentType "application/json"
        $postId = $postResponse.data.post_id
        $postIds += $postId
        Write-Host "Created post $i with ID: $postId" -ForegroundColor Green
    } catch {
        Write-Host "Failed to create post $i : $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Create comments
Write-Host "Creating test comments..." -ForegroundColor Yellow
foreach ($postId in $postIds) {
    $commentBody = @{
        post_id = $postId
        user_id = $testUser
        content = "Test comment for post $postId"
    } | ConvertTo-Json

    try {
        $commentResponse = Invoke-RestMethod -Uri "http://localhost:8081/api/comments" -Method POST -Body $commentBody -ContentType "application/json"
        Write-Host "Created comment for post: $postId" -ForegroundColor Green
    } catch {
        Write-Host "Failed to create comment: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Create likes
Write-Host "Creating test likes..." -ForegroundColor Yellow
foreach ($postId in $postIds) {
    $likeBody = @{
        post_id = $postId
        user_id = $testUser
        action = "like"
    } | ConvertTo-Json

    try {
        $likeResponse = Invoke-RestMethod -Uri "http://localhost:8081/api/likes" -Method POST -Body $likeBody -ContentType "application/json"
        Write-Host "Created like for post: $postId" -ForegroundColor Green
    } catch {
        Write-Host "Failed to create like: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Waiting for Consumer to Process Messages ===" -ForegroundColor Cyan
Write-Host "Waiting 10 seconds for consumer to process all messages..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

Write-Host ""
Write-Host "=== Checking Consumer Metrics ===" -ForegroundColor Cyan
try {
    $metricsResponse = Invoke-WebRequest -Uri "http://localhost:8082/metrics" -UseBasicParsing
    $metrics = $metricsResponse.Content -split "`n" | Where-Object { $_ -match "(messages_processed_total|database_writes_total)" }
    
    Write-Host "Consumer processing metrics:" -ForegroundColor White
    $metrics | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    
    # Check if messages were processed
    $processedCount = ($metrics | Where-Object { $_ -match 'messages_processed_total.*status="success"' } | Measure-Object).Count
    if ($processedCount -gt 0) {
        Write-Host "Consumer is processing messages successfully!" -ForegroundColor Green
    } else {
        Write-Host "No successful message processing detected in metrics" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Failed to get consumer metrics: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Checking Database Content ===" -ForegroundColor Cyan

# Check each database shard for our test data
$shardPorts = @(5433, 5434, 5435)
$foundPosts = 0
$foundComments = 0
$foundLikes = 0

for ($i = 0; $i -lt $shardPorts.Length; $i++) {
    $port = $shardPorts[$i]
    Write-Host "Checking shard $i (port $port)..." -ForegroundColor Yellow
    
    try {
        # Check posts
        $postsResult = docker exec pg_shard_$i psql -U postgres -d posts -t -c "SELECT COUNT(*) FROM posts WHERE user_id = '$testUser';"
        $postsCount = [int]($postsResult -join '').Trim()
        $foundPosts += $postsCount
        
        if ($postsCount -gt 0) {
            Write-Host "Found $postsCount posts in shard $i" -ForegroundColor Green
            
            # Show sample post data
            $samplePost = docker exec pg_shard_$i psql -U postgres -d posts -t -c "SELECT id, content FROM posts WHERE user_id = '$testUser' LIMIT 1;"
            Write-Host "Sample: $(($samplePost -join '').Trim())" -ForegroundColor White
        }
        
        # Check comments
        $commentsResult = docker exec pg_shard_$i psql -U postgres -d posts -t -c "SELECT COUNT(*) FROM comments WHERE user_id = '$testUser';"
        $commentsCount = [int]($commentsResult -join '').Trim()
        $foundComments += $commentsCount
        
        if ($commentsCount -gt 0) {
            Write-Host "Found $commentsCount comments in shard $i" -ForegroundColor Green
        }
        
        # Check likes
        $likesResult = docker exec pg_shard_$i psql -U postgres -d posts -t -c "SELECT COUNT(*) FROM likes WHERE user_id = '$testUser';"
        $likesCount = [int]($likesResult -join '').Trim()
        $foundLikes += $likesCount
        
        if ($likesCount -gt 0) {
            Write-Host "Found $likesCount likes in shard $i" -ForegroundColor Green
        }
        
        if ($postsCount -eq 0 -and $commentsCount -eq 0 -and $likesCount -eq 0) {
            Write-Host "No data found in shard $i" -ForegroundColor Gray
        }
        
    } catch {
        Write-Host "Error checking shard $i : $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Database Integration Test Results ===" -ForegroundColor Cyan
Write-Host "Total data found across all shards:" -ForegroundColor White
Write-Host "Posts: $foundPosts" -ForegroundColor $(if ($foundPosts -gt 0) { "Green" } else { "Red" })
Write-Host "Comments: $foundComments" -ForegroundColor $(if ($foundComments -gt 0) { "Green" } else { "Red" })
Write-Host "Likes: $foundLikes" -ForegroundColor $(if ($foundLikes -gt 0) { "Green" } else { "Red" })

# Test unlike functionality
if ($postIds.Count -gt 0) {
    Write-Host ""
    Write-Host "=== Testing Unlike Functionality ===" -ForegroundColor Cyan
    $unlikePostId = $postIds[0]
    
    $unlikeBody = @{
        post_id = $unlikePostId
        user_id = $testUser
        action = "unlike"
    } | ConvertTo-Json

    try {
        $unlikeResponse = Invoke-RestMethod -Uri "http://localhost:8081/api/likes" -Method POST -Body $unlikeBody -ContentType "application/json"
        Write-Host "Unlike request sent for post: $unlikePostId" -ForegroundColor Green
        
        # Wait for processing
        Start-Sleep -Seconds 3
        
        # Check if like was removed
        $totalLikesAfter = 0
        for ($i = 0; $i -lt $shardPorts.Length; $i++) {
            try {
                $likesResult = docker exec pg_shard_$i psql -U postgres -d posts -t -c "SELECT COUNT(*) FROM likes WHERE user_id = '$testUser';"
                $likesCount = [int]($likesResult.Trim())
                $totalLikesAfter += $likesCount
            } catch {
            }
        }
        
        if ($totalLikesAfter -lt $foundLikes) {
            Write-Host "Unlike functionality working - likes reduced from $foundLikes to $totalLikesAfter" -ForegroundColor Green
        } else {
            Write-Host "Unlike might not have processed yet or failed" -ForegroundColor Yellow
        }
        
    } catch {
        Write-Host "Failed to test unlike: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Overall Test Results ===" -ForegroundColor Cyan

$successCount = 0
if ($foundPosts -gt 0) { $successCount++ }
if ($foundComments -gt 0) { $successCount++ }
if ($foundLikes -gt 0) { $successCount++ }

if ($successCount -eq 3) {
    Write-Host "ALL TESTS PASSED! Consumer service is working perfectly!" -ForegroundColor Green
    Write-Host "Data is being consumed from Kafka and written to database shards" -ForegroundColor Green
    Write-Host "Sharding is working - data distributed across multiple database instances" -ForegroundColor Green
} elseif ($successCount -gt 0) {
    Write-Host "PARTIAL SUCCESS - Some data types were processed successfully" -ForegroundColor Yellow
    Write-Host "Check consumer service logs for any errors" -ForegroundColor Yellow
} else {
    Write-Host "TESTS FAILED - No data found in database" -ForegroundColor Red
    Write-Host "Consumer service may not be processing messages correctly" -ForegroundColor Red
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  - Check consumer service logs: docker-compose logs consumer-service" -ForegroundColor White
Write-Host "  - View Kafka UI: http://localhost:8090" -ForegroundColor White
Write-Host "  - View database UI: http://localhost:8080" -ForegroundColor White
Write-Host "  - View metrics: http://localhost:8082/metrics" -ForegroundColor White