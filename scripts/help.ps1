#!/usr/bin/env pwsh

Write-Host ""
Write-Host "Distributed Database - Available PowerShell Commands" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Service Management:" -ForegroundColor Yellow
Write-Host "  .\scripts\up.ps1              - Start all services" -ForegroundColor White
Write-Host "  .\scripts\down.ps1            - Stop all services" -ForegroundColor White
Write-Host "  .\scripts\clean.ps1           - Stop services and remove all data" -ForegroundColor White
Write-Host "  .\scripts\status.ps1          - Check service status and health" -ForegroundColor White
Write-Host ""

Write-Host "Monitoring & Logs:" -ForegroundColor Yellow  
Write-Host "  .\scripts\logs.ps1            - Show logs for all services" -ForegroundColor White
Write-Host "  .\scripts\logs.ps1 kafka     - Show logs for specific service" -ForegroundColor White
Write-Host "  .\scripts\logs.ps1 ingestion-service" -ForegroundColor White
Write-Host "  .\scripts\logs.ps1 consumer-service" -ForegroundColor White
Write-Host ""

Write-Host "Testing:" -ForegroundColor Yellow
Write-Host "  .\scripts\test-kafka.ps1      - Test Kafka connectivity" -ForegroundColor White
Write-Host "  .\scripts\test-ingestion.ps1  - Test ingestion service APIs" -ForegroundColor White
Write-Host "  .\scripts\test-consumer.ps1   - Test consumer service & database" -ForegroundColor White
Write-Host ""

Write-Host "Development:" -ForegroundColor Yellow
Write-Host "  .\scripts\build.ps1           - Build Go services locally" -ForegroundColor White
Write-Host "  go run .\cmd\test-client      - Run Go test client" -ForegroundColor White
Write-Host ""

Write-Host "Access Points:" -ForegroundColor Yellow
Write-Host "  http://localhost:8080         - Adminer (Database UI)" -ForegroundColor White
Write-Host "  http://localhost:8090         - Kafka UI" -ForegroundColor White
Write-Host "  http://localhost:8081         - Ingestion Service API" -ForegroundColor White
Write-Host "  http://localhost:8082         - Consumer Service API" -ForegroundColor White
Write-Host "  http://localhost:8081/health  - Ingestion Health Check" -ForegroundColor White
Write-Host "  http://localhost:8082/health  - Consumer Health Check" -ForegroundColor White
Write-Host "  http://localhost:8081/metrics - Ingestion Metrics" -ForegroundColor White
Write-Host "  http://localhost:8082/metrics - Consumer Metrics" -ForegroundColor White
Write-Host ""

Write-Host "Quick Start:" -ForegroundColor Green
Write-Host "  1. .\scripts\up#!/usr/bin/env pwsh

Write-Host ""
Write-Host "Distributed Database - Available PowerShell Commands" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Service Management:" -ForegroundColor Yellow
Write-Host "  .\scripts\up.ps1              - Start all services" -ForegroundColor White
Write-Host "  .\scripts\down.ps1            - Stop all services" -ForegroundColor White
Write-Host "  .\scripts\clean.ps1           - Stop services and remove all data" -ForegroundColor White
Write-Host "  .\scripts\status.ps1          - Check service status and health" -ForegroundColor White
Write-Host ""

Write-Host "Monitoring & Logs:" -ForegroundColor Yellow  
Write-Host "  .\scripts\logs.ps1            - Show logs for all services" -ForegroundColor White
Write-Host "  .\scripts\logs.ps1 kafka     - Show logs for specific service" -ForegroundColor White
Write-Host "  .\scripts\logs.ps1 ingestion-service" -ForegroundColor White
Write-Host "  .\scripts\logs.ps1 consumer-service" -ForegroundColor White
Write-Host "  .\scripts\logs.ps1 query-service" -ForegroundColor White
Write-Host ""

Write-Host "Testing:" -ForegroundColor Yellow
Write-Host "  .\scripts\test-kafka.ps1      - Test Kafka connectivity" -ForegroundColor White
Write-Host "  .\scripts\test-ingestion.ps1  - Test write APIs (ingestion service)" -ForegroundColor White
Write-Host "  .\scripts\test-consumer.ps1   - Test consumer service & database" -ForegroundColor White
Write-Host "  .\scripts\test-query.ps1      - Test read APIs (query service)" -ForegroundColor White
Write-Host "  .\scripts\test-sharding.ps1   - Test data distribution across shards" -ForegroundColor White
Write-Host ""

Write-Host "Development:" -ForegroundColor Yellow
Write-Host "  .\scripts\build.ps1           - Build Go services locally" -ForegroundColor White
Write-Host "  go run .\cmd\test-client      - Run Go test client" -ForegroundColor White
Write-Host ""

Write-Host "Access Points:" -ForegroundColor Yellow
Write-Host "  http://localhost:8080         - Adminer (Database UI)" -ForegroundColor White
Write-Host "  http://localhost:8090         - Kafka UI" -ForegroundColor White
Write-Host "  http://localhost:8081         - Ingestion Service (Write APIs)" -ForegroundColor White
Write-Host "  http://localhost:8082         - Consumer Service" -ForegroundColor White
Write-Host "  http://localhost:8083         - Query Service (Read APIs)" -ForegroundColor White
Write-Host ""

Write-Host "Health Checks:" -ForegroundColor Yellow
Write-Host "  http://localhost:8081/health  - Ingestion Service Health" -ForegroundColor White
Write-Host "  http://localhost:8082/health  - Consumer Service Health" -ForegroundColor White
Write-Host "  http://localhost:8083/health  - Query Service Health" -ForegroundColor White
Write-Host ""

Write-Host "Metrics:" -ForegroundColor Yellow
Write-Host "  http://localhost:8081/metrics - Ingestion Metrics" -ForegroundColor White
Write-Host "  http://localhost:8082/metrics - Consumer Metrics" -ForegroundColor White
Write-Host "  http://localhost:8083/metrics - Query Metrics" -ForegroundColor White
Write-Host ""

Write-Host "Quick Start:" -ForegroundColor Green
Write-Host "  1. .\scripts\up.ps1           # Start everything" -ForegroundColor White
Write-Host "  2. .\scripts\status.ps1       # Check if running" -ForegroundColor White  
Write-Host "  3. .\scripts\test-ingestion.ps1  # Test write operations" -ForegroundColor White
Write-Host "  4. .\scripts\test-consumer.ps1   # Test data processing" -ForegroundColor White
Write-Host "  5. .\scripts\test-query.ps1      # Test read operations" -ForegroundColor White
Write-Host ""

Write-Host "API Examples:" -ForegroundColor Green
Write-Host "  # Create a post (Write)" -ForegroundColor Gray
Write-Host "  curl -X POST http://localhost:8081/api/posts \\" -ForegroundColor White
Write-Host "    -H 'Content-Type: application/json' \\" -ForegroundColor White
Write-Host "    -d '{\"user_id\":\"alice\",\"content\":\"Hello World!\"}'" -ForegroundColor White
Write-Host ""
Write-Host "  # Get recent posts (Read)" -ForegroundColor Gray
Write-Host "  curl http://localhost:8083/api/posts?limit=5" -ForegroundColor White
Write-Host ""
Write-Host "  # Get user posts (Read)" -ForegroundColor Gray
Write-Host "  curl http://localhost:8083/api/users/alice/posts" -ForegroundColor White
Write-Host ""

Write-Host "Need help? Run .\scripts\help.ps1" -ForegroundColor Cyan
Write-Host ""