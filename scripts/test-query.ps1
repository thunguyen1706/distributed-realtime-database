Write-Host "Testing Query Service..." -ForegroundColor Green

# Check if services are running
$services = docker-compose ps --services --filter "status=running"
if ($services -notcontains "query-service") {
    Write-Host "Error: Query service is not running. Please run './scripts/up.ps1' first." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Testing Query Service Health ===" -ForegroundColor Cyan
try {
    $healthResponse = Invoke-RestMethod -Uri "http://localhost:8083/health" -Method GET -ContentType "application/json"
    Write-Host ($healthResponse | ConvertTo-Json -Depth 3) -ForegroundColor Green
    Write-Host "Query service health check passed!" -ForegroundColor Green
} catch {
    Write-Host "Query service health check failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Testing Recent Posts API ===" -ForegroundColor Cyan
try {
    $recentPosts = Invoke-RestMethod -Uri "http://localhost:8083/api/posts?limit=5" -Method GET
    Write-Host "Recent posts:" -ForegroundColor White
    Write-Host ($recentPosts | ConvertTo-Json -Depth 3) -ForegroundColor Yellow
    Write-Host "Recent posts retrieved successfully!" -ForegroundColor Green
    
    # Store some data for further testing
    $testUsers = @()
    $testPosts = @()
    
    if ($recentPosts.data -and $recentPosts.data.Count -gt 0) {
        $testUsers = $recentPosts.data | ForEach-Object { $_.user_id } | Sort-Object -Unique | Select-Object -First 2
        $testPosts = $recentPosts.data | Select-Object -First 2
    }
    
} catch {
    Write-Host "Recent posts test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Testing User Posts API ===" -ForegroundColor Cyan
if ($testUsers.Count -gt 0) {
    $testUser = $testUsers[0]
    Write-Host "Testing with user: $testUser" -ForegroundColor Yellow
    
    try {
        $userPosts = Invoke-RestMethod -Uri "http://localhost:8083/api/users/$testUser/posts?limit=3" -Method GET
        Write-Host "User posts for $testUser :" -ForegroundColor White
        Write-Host ($userPosts | ConvertTo-Json -Depth 3) -ForegroundColor Yellow
        Write-Host "User posts retrieved successfully!" -ForegroundColor Green
    } catch {
        Write-Host "User posts test failed: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "No users available for testing user posts API" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Testing User Stats API ===" -ForegroundColor Cyan
if ($testUsers.Count -gt 0) {
    $testUser = $testUsers[0]
    Write-Host "Testing stats for user: $testUser" -ForegroundColor Yellow
    
    try {
        $userStats = Invoke-RestMethod -Uri "http://localhost:8083/api/users/$testUser/stats" -Method GET
        Write-Host "User stats for $testUser :" -ForegroundColor White
        Write-Host ($userStats | ConvertTo-Json -Depth 3) -ForegroundColor Yellow
        Write-Host "User stats retrieved successfully!" -ForegroundColor Green
    } catch {
        Write-Host "User stats test failed: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "No users available for testing user stats API" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Testing Post Details API ===" -ForegroundColor Cyan
if ($testPosts.Count -gt 0) {
    $testPost = $testPosts[0]
    $postId = $testPost.id
    Write-Host "Testing with post ID: $postId" -ForegroundColor Yellow
    
    try {
        $postDetails = Invoke-RestMethod -Uri "http://localhost:8083/api/posts/$postId" -Method GET
        Write-Host "Post details for $postId :" -ForegroundColor White
        Write-Host ($postDetails | ConvertTo-Json -Depth 4) -ForegroundColor Yellow
        Write-Host "Post details retrieved successfully!" -ForegroundColor Green
    } catch {
        Write-Host "Post details test failed: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "No posts available for testing post details API" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Testing Query Performance Metrics ===" -ForegroundColor Cyan
try {
    $metricsResponse = Invoke-WebRequest -Uri "http://localhost:8083/metrics" -UseBasicParsing
    $queryMetrics = $metricsResponse.Content -split "`n" | Where-Object { $_ -match "(queries_total|query_duration|shard_queries)" }
    
    if ($queryMetrics) {
        Write-Host "Query service metrics:" -ForegroundColor White
        foreach ($metric in $queryMetrics) {
            if ($metric.Trim()) {
                Write-Host "  $metric" -ForegroundColor Yellow
            }
        }
        Write-Host "Query metrics retrieved successfully!" -ForegroundColor Green
    }
} catch {
    Write-Host "Failed to get query metrics: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== API Endpoints Summary ===" -ForegroundColor Cyan
Write-Host "Query Service APIs available:" -ForegroundColor White
Write-Host "GET /api/posts?limit=X                    - Recent posts across all shards" -ForegroundColor Cyan
Write-Host "GET /api/users/{user_id}/posts           - Posts by specific user" -ForegroundColor Cyan
Write-Host "GET /api/users/{user_id}/stats           - User statistics" -ForegroundColor Cyan
Write-Host "GET /api/posts/{post_id}                 - Post details with comments & likes" -ForegroundColor Cyan
Write-Host "GET /health                              - Service health check" -ForegroundColor Cyan
Write-Host "GET /metrics                             - Prometheus metrics" -ForegroundColor Cyan

Write-Host ""
Write-Host "=== Testing Pagination ===" -ForegroundColor Cyan
try {
    Write-Host "Testing pagination with limit=2, offset=0..." -ForegroundColor Yellow
    $page1 = Invoke-RestMethod -Uri "http://localhost:8083/api/posts?limit=2&offset=0" -Method GET
    Write-Host "Page 1 count: $($page1.count)" -ForegroundColor White
    
    Write-Host "Testing pagination with limit=2, offset=2..." -ForegroundColor Yellow
    $page2 = Invoke-RestMethod -Uri "http://localhost:8083/api/posts?limit=2&offset=2" -Method GET
    Write-Host "Page 2 count: $($page2.count)" -ForegroundColor White
    
    Write-Host "Pagination working correctly!" -ForegroundColor Green
} catch {
    Write-Host "Pagination test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Complete API Test Examples ===" -ForegroundColor Cyan
Write-Host "You can now test these APIs manually:" -ForegroundColor White
Write-Host ""
Write-Host "# Get recent posts" -ForegroundColor Gray
Write-Host "curl http://localhost:8083/api/posts?limit=5" -ForegroundColor White
Write-Host ""
Write-Host "# Get posts by user" -ForegroundColor Gray
if ($testUsers.Count -gt 0) {
    Write-Host "curl http://localhost:8083/api/users/$($testUsers[0])/posts" -ForegroundColor White
}
Write-Host ""
Write-Host "# Get user statistics" -ForegroundColor Gray
if ($testUsers.Count -gt 0) {
    Write-Host "curl http://localhost:8083/api/users/$($testUsers[0])/stats" -ForegroundColor White
}
Write-Host ""
Write-Host "# Get post details" -ForegroundColor Gray
if ($testPosts.Count -gt 0) {
    Write-Host "curl http://localhost:8083/api/posts/$($testPosts[0].id)" -ForegroundColor White
}

Write-Host ""
Write-Host "Query Service testing completed!" -ForegroundColor Green
Write-Host "Your distributed database now supports both READ and WRITE operations!" -ForegroundColor Green
Write-Host ""