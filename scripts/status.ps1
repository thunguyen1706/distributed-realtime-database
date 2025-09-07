#!/usr/bin/env pwsh

Write-Host "Checking service status..." -ForegroundColor Green
Write-Host ""

# Show service status
docker-compose ps

Write-Host ""
Write-Host "Service URLs:" -ForegroundColor Cyan
Write-Host "  - Health Check: " -NoNewline -ForegroundColor White
try {
    $healthResponse = Invoke-WebRequest -Uri "http://localhost:8081/health" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
    if ($healthResponse.StatusCode -eq 200) {
        Write-Host "http://localhost:8081/health (OK)" -ForegroundColor Green
    } else {
        Write-Host "http://localhost:8081/health (Status: $($healthResponse.StatusCode))" -ForegroundColor Red
    }
} catch {
    Write-Host "http://localhost:8081/health (Not responding)" -ForegroundColor Red
}

Write-Host "  - Kafka UI: " -NoNewline -ForegroundColor White
try {
    $kafkaResponse = Invoke-WebRequest -Uri "http://localhost:8090" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
    if ($kafkaResponse.StatusCode -eq 200) {
        Write-Host "http://localhost:8090 (OK)" -ForegroundColor Green
    } else {
        Write-Host "http://localhost:8090 (Status: $($kafkaResponse.StatusCode))" -ForegroundColor Red
    }
} catch {
    Write-Host "http://localhost:8090 (Not responding)" -ForegroundColor Red
}

Write-Host "  - Adminer DB UI: " -NoNewline -ForegroundColor White
try {
    $adminerResponse = Invoke-WebRequest -Uri "http://localhost:8080" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
    if ($adminerResponse.StatusCode -eq 200) {
        Write-Host "http://localhost:8080 (OK)" -ForegroundColor Green
    } else {
        Write-Host "http://localhost:8080 (Status: $($adminerResponse.StatusCode))" -ForegroundColor Red
    }
} catch {
    Write-Host "http://localhost:8080 (Not responding)" -ForegroundColor Red
}