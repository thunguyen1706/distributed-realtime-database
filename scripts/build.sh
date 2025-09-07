#!/usr/bin/env pwsh

Write-Host "Building Go services..." -ForegroundColor Green

# Create bin directory if it doesn't exist
if (!(Test-Path "bin")) {
    New-Item -ItemType Directory -Path "bin" | Out-Null
}

# Build ingestion service
Write-Host "Building ingestion service..." -ForegroundColor Yellow
$env:CGO_ENABLED = "1"
go build -o bin/ingestion.exe ./cmd/ingestion

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to build ingestion service!" -ForegroundColor Red
    exit 1
}

# Build test client
Write-Host "Building test client..." -ForegroundColor Yellow
go build -o bin/test-client.exe ./cmd/test-client

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to build test client!" -ForegroundColor Red
    exit 1
}

Write-Host "Build completed successfully!" -ForegroundColor Green
Write-Host "Binaries available in .\bin\" -ForegroundColor Cyan
Write-Host "  - .\bin\ingestion.exe" -ForegroundColor White
Write-Host "  - .\bin\test-client.exe" -ForegroundColor White