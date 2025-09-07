#!/usr/bin/env pwsh

Write-Host "Stopping all services..." -ForegroundColor Yellow

docker-compose down

if ($LASTEXITCODE -eq 0) {
    Write-Host "All services stopped successfully!" -ForegroundColor Green
} else {
    Write-Host "Failed to stop some services!" -ForegroundColor Red
    exit 1
}