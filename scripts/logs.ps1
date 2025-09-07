#!/usr/bin/env pwsh

param(
    [string]$Service = ""
)

if ($Service) {
    Write-Host "Showing logs for service: $Service" -ForegroundColor Green
    docker-compose logs -f $Service
} else {
    Write-Host "Showing logs for all services..." -ForegroundColor Green
    Write-Host "Use Ctrl+C to stop following logs" -ForegroundColor Yellow
    Write-Host ""
    docker-compose logs -f
}