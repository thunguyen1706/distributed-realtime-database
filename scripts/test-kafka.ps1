#!/usr/bin/env pwsh

Write-Host "Testing Kafka setup..." -ForegroundColor Green

# Wait for Kafka to be ready
Write-Host "Waiting for Kafka to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

Write-Host ""
Write-Host "=== Listing Kafka topics ===" -ForegroundColor Cyan
try {
    $topics = docker exec kafka kafka-topics --list --bootstrap-server localhost:29092
    Write-Host "Available topics:" -ForegroundColor White
    $topics | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
} catch {
    Write-Host "Failed to list topics: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Describing posts topic ===" -ForegroundColor Cyan
try {
    $postsInfo = docker exec kafka kafka-topics --describe --topic posts --bootstrap-server localhost:29092
    Write-Host $postsInfo -ForegroundColor White
} catch {
    Write-Host "Failed to describe posts topic" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Describing comments topic ===" -ForegroundColor Cyan
try {
    $commentsInfo = docker exec kafka kafka-topics --describe --topic comments --bootstrap-server localhost:29092
    Write-Host $commentsInfo -ForegroundColor White
} catch {
    Write-Host "Failed to describe comments topic" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Describing likes topic ===" -ForegroundColor Cyan
try {
    $likesInfo = docker exec kafka kafka-topics --describe --topic likes --bootstrap-server localhost:29092
    Write-Host $likesInfo -ForegroundColor White
} catch {
    Write-Host "Failed to describe likes topic" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Testing producer/consumer ===" -ForegroundColor Cyan
Write-Host "Sending test message to posts topic..." -ForegroundColor Yellow

$testMessage = '{"user_id": "test-user", "content": "Hello Kafka from PowerShell!"}'
try {
    $testMessage | docker exec -i kafka kafka-console-producer --topic posts --bootstrap-server localhost:29092
    Write-Host "Test message sent successfully!" -ForegroundColor Green
} catch {
    Write-Host "Failed to send test message" -ForegroundColor Red
}

Write-Host ""
Write-Host "Consuming from posts topic (will timeout after 5 seconds)..." -ForegroundColor Yellow
try {
    # Use PowerShell job to timeout the consumer
    $job = Start-Job -ScriptBlock {
        docker exec kafka kafka-console-consumer --topic posts --from-beginning --bootstrap-server localhost:29092
    }
    
    Wait-Job $job -Timeout 5 | Out-Null
    $output = Receive-Job $job
    Stop-Job $job -PassThru | Remove-Job
    
    if ($output) {
        Write-Host "Received messages:" -ForegroundColor Green
        $output | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
    } else {
        Write-Host "No messages received (this might be normal)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Consumer test completed with timeout (expected)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Kafka test completed!" -ForegroundColor Green
Write-Host "Access Kafka UI at: http://localhost:8090" -ForegroundColor Cyan