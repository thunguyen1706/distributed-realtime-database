Write-Host "Testing Sharding Distribution..." -ForegroundColor Green

# Create different users
$users = @("alice", "bob", "charlie", "diana", "eve", "frank", "grace", "henry", "ivy", "jack")

Write-Host "Creating posts for different users..." -ForegroundColor Yellow

foreach ($user in $users) {
    $body = @{
        user_id = $user
        content = "Test post from $user"
    } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod -Uri "http://localhost:8081/api/posts" -Method POST -Body $body -ContentType "application/json"
        Write-Host "Created post for $user" -ForegroundColor Green
    } catch {
        Write-Host "Failed to create post for $user" -ForegroundColor Red
    }
}

Write-Host "Waiting 10 seconds for processing..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

Write-Host "Checking data distribution:" -ForegroundColor Cyan

# Check shard 0
Write-Host "Shard 0:" -ForegroundColor Yellow
$shard0 = docker exec pg_shard_0 psql -U postgres -d posts -t -c "SELECT COUNT(*) FROM posts;"
Write-Host "  Posts: $($shard0.Trim())" -ForegroundColor White
if ($shard0.Trim() -gt 0) {
    $users0 = docker exec pg_shard_0 psql -U postgres -d posts -t -c "SELECT DISTINCT user_id FROM posts;"
    Write-Host "  Users: $($users0.Trim())" -ForegroundColor Cyan
}

# Check shard 1
Write-Host "Shard 1:" -ForegroundColor Yellow
$shard1 = docker exec pg_shard_1 psql -U postgres -d posts -t -c "SELECT COUNT(*) FROM posts;"
Write-Host "  Posts: $($shard1.Trim())" -ForegroundColor White
if ($shard1.Trim() -gt 0) {
    $users1 = docker exec pg_shard_1 psql -U postgres -d posts -t -c "SELECT DISTINCT user_id FROM posts;"
    Write-Host "  Users: $($users1.Trim())" -ForegroundColor Cyan
}

# Check shard 2
Write-Host "Shard 2:" -ForegroundColor Yellow
$shard2 = docker exec pg_shard_2 psql -U postgres -d posts -t -c "SELECT COUNT(*) FROM posts;"
Write-Host "  Posts: $($shard2.Trim())" -ForegroundColor White
if ($shard2.Trim() -gt 0) {
    $users2 = docker exec pg_shard_2 psql -U postgres -d posts -t -c "SELECT DISTINCT user_id FROM posts;"
    Write-Host "  Users: $($users2.Trim())" -ForegroundColor Cyan
}

$total = [int]$shard0.Trim() + [int]$shard1.Trim() + [int]$shard2.Trim()
Write-Host "Total posts: $total" -ForegroundColor White

$nonEmpty = 0
if ([int]$shard0.Trim() -gt 0) { $nonEmpty++ }
if ([int]$shard1.Trim() -gt 0) { $nonEmpty++ }
if ([int]$shard2.Trim() -gt 0) { $nonEmpty++ }

Write-Host "Shards with data: $nonEmpty out of 3" -ForegroundColor White

if ($nonEmpty -eq 3) {
    Write-Host "SUCCESS: Data distributed across all shards!" -ForegroundColor Green
} elseif ($nonEmpty -eq 2) {
    Write-Host "GOOD: Data in 2 shards (normal for hashing)" -ForegroundColor Yellow
} else {
    Write-Host "WARNING: Data only in $nonEmpty shard(s)" -ForegroundColor Red
}