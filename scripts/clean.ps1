#!/usr/bin/env pwsh

Write-Host "Cleaning all services and data..." -ForegroundColor Yellow
Write-Host "This will remove all volumes and data!" -ForegroundColor Red

$confirmation = Read-Host "Are you sure? Type 'yes' to continue"
if ($confirmation -ne "yes") {
    Write-Host "Operation cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host "Stopping and removing containers and volumes..." -ForegroundColor Yellow
docker-compose down -v

Write-Host "Cleaning up Docker system..." -ForegroundColor Yellow
docker system prune -f

# Clean up local build artifacts
if (Test-Path "bin") {
    Write-Host "Removing local build artifacts..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force "bin"
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "Cleanup completed successfully!" -ForegroundColor Green
} else {
    Write-Host "Cleanup encountered some errors!" -ForegroundColor Red
    exit 1
}