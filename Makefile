.PHONY: up down logs test-kafka test-ingestion test-consumer build clean status help deps

# Start all services
up:
	docker-compose up -d --build
	@echo "Services are starting up..."
	@echo "Waiting for services to be ready..."
	@sleep 60
	@echo "Services should be ready now!"
	@echo "Access points:"
	@echo "  - Adminer (DB UI): http://localhost:8080"
	@echo "  - Kafka UI: http://localhost:8090"
	@echo "  - Ingestion Service: http://localhost:8081"
	@echo "  - Consumer Service: http://localhost:8082"
	@echo "  - Health Checks: http://localhost:8081/health, http://localhost:8082/health"
	@echo "  - Metrics: http://localhost:8081/metrics, http://localhost:8082/metrics"

# Stop all services
down:
	docker-compose down

# Stop and remove volumes (clean slate)
clean:
	docker-compose down -v
	docker system prune -f
	rm -rf bin/

# Show logs
logs:
	docker-compose logs -f

# Show specific service logs
logs-ingestion:
	docker-compose logs -f ingestion-service

logs-consumer:
	docker-compose logs -f consumer-service

logs-kafka:
	docker-compose logs -f kafka

# Show service status
status:
	docker-compose ps

# Install Go dependencies
deps:
	go mod tidy
	go mod download

# Build Go binaries locally
build:
	chmod +x ./scripts/build.sh
	./scripts/build.sh

# Test Kafka setup
test-kafka:
	chmod +x ./test-kafka.sh
	./test-kafka.sh

# Test consumer service
test-consumer:
	chmod +x ./scripts/test-consumer.ps1
	./scripts/test-consumer.ps1

# Test full pipeline (ingestion + consumer)
test-pipeline:
	@echo "Testing complete pipeline..."
	chmod +x ./scripts/test-ingestion.ps1
	./scripts/test-ingestion.ps1
	@echo "Waiting for consumer to process..."
	@sleep 5
	chmod +x ./scripts/test-consumer.ps1
	./scripts/test-consumer.ps1

# Run test client (requires services to be up)
test-client:
	@echo "Running test client..."
	go run ./cmd/test-client

# Restart specific services
restart-ingestion:
	docker-compose restart ingestion-service

restart-consumer:
	docker-compose restart consumer-service

restart-kafka:
	docker-compose restart kafka

# Show available commands
help:
	@echo "Available commands:"
	@echo "  make up             - Start all services"
	@echo "  make down           - Stop all services"
	@echo "  make clean          - Stop services and remove volumes"
	@echo "  make build          - Build Go binaries locally"
	@echo "  make deps           - Install Go dependencies"
	@echo "  make logs           - Show all service logs"
	@echo "  make logs-ingestion - Show ingestion service logs"
	@echo "  make logs-consumer  - Show consumer service logs"
	@echo "  make logs-kafka     - Show Kafka logs"
	@echo "  make status         - Show service status"
	@echo "  make test-kafka     - Test Kafka setup"
	@echo "  make test-ingestion - Test ingestion service"
	@echo "  make test-consumer  - Test consumer service"
	@echo "  make test-pipeline  - Test complete pipeline"
	@echo "  make test-client    - Run Go test client"
	@echo "  make restart-ingestion - Restart ingestion service"
	@echo "  make restart-consumer  - Restart consumer service"
	@echo "  make restart-kafka  - Restart Kafka"
	@echo "  make help           - Show this help"