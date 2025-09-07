#!/usr/bin/env pwsh

Write-Host "Starting all services..." -ForegroundColor Green

# Start all services with build
docker-compose up -d --build

if ($LASTEXITCODE -eq 0) {
    Write-Host "Services are starting up..." -ForegroundColor Yellow
    Write-Host "Waiting for services to be ready..." -ForegroundColor Yellow
    
    # Wait for services to start (increased for all services)
    Start-Sleep -Seconds 75
    
    Write-Host "Services should be ready now!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Access points:" -ForegroundColor Cyan
    Write-Host "  - Adminer (DB UI): http://localhost:8080" -ForegroundColor White
    Write-Host "  - Kafka UI: http://localhost:8090" -ForegroundColor White
    Write-Host "  - Ingestion Service (Write): http://localhost:8081" -ForegroundColor White
    Write-Host "  - Consumer Service: http://localhost:8082" -ForegroundColor White
    Write-Host "  - Query Service (Read): http://localhost:8083" -ForegroundColor White
    Write-Host ""
    Write-Host "Health Checks:" -ForegroundColor Cyan
    Write-Host "  - Ingestion: http://localhost:8081/health" -ForegroundColor White
    Write-Host "  - Consumer: http://localhost:8082/health" -ForegroundColor White
    Write-Host "  - Query: http://localhost:8083/health" -ForegroundColor White
    Write-Host ""
    Write-Host "Metrics:" -ForegroundColor Cyan
    Write-Host "  - Ingestion: http://localhost:8081/metrics" -ForegroundColor White
    Write-Host "  - Consumer: http://localhost:8082/metrics" -ForegroundColor White
    Write-Host "  - Query: http://localhost:8083/metrics" -ForegroundColor White
} else {
    Write-Host "Failed to start services!" -ForegroundColor Red
    exit 1
}