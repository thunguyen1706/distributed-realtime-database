# Distributed Database System with Kafka

A complete distributed database system with PostgreSQL shards, Kafka event streaming, and comprehensive monitoring.

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Ingestion     │    │      Kafka      │    │    Consumer     │
│   Service       │───▶│   (Event Bus)   │───▶│    Service      │
│   (Port 8081)   │    │   (Port 9092)   │    │   (Port 8082)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Query Service │    │   Kafka UI      │    │  PostgreSQL     │
│   (Port 8083)   │    │  (Port 8090)    │    │   Shards        │
└─────────────────┘    └─────────────────┘    │ (5433,5434,5435)│
         │                                     └─────────────────┘
         ▼
┌─────────────────┐
│   PostgreSQL    │
│   Master        │
│  (Port 5440)    │
└─────────────────┘
```

## 🚀 Quick Start

### Prerequisites
- Docker Desktop installed and running
- PowerShell (Windows) or Bash (Linux/Mac)

### Setup
1. **Copy environment file:**
   ```powershell
   copy env.example .env
   ```

2. **Start all services:**
   ```powershell
   .\scripts.ps1 up
   ```

3. **Check system status:**
   ```powershell
   .\scripts.ps1 status
   ```

## 📊 Services & Access Points

### Core Services
- **Ingestion Service**: http://localhost:8081 - API for creating posts, comments, likes
- **Consumer Service**: http://localhost:8082 - Processes Kafka messages to database
- **Query Service**: http://localhost:8083 - API for reading data across shards
- **Kafka UI**: http://localhost:8090 - Kafka management interface

### Databases
- **PostgreSQL Shard 0**: localhost:5433
- **PostgreSQL Shard 1**: localhost:5434  
- **PostgreSQL Shard 2**: localhost:5435
- **PostgreSQL Master**: localhost:5440 (metadata)
- **Adminer (DB UI)**: http://localhost:8080

### Monitoring & Logging
- **Prometheus**: http://localhost:9090 - Metrics collection
- **Grafana**: http://localhost:3000 (admin/admin123) - Dashboards
- **Elasticsearch**: http://localhost:9200 - Log storage
- **Kibana**: http://localhost:5601 - Log visualization

## 🛠️ Management Commands

### Using PowerShell Scripts
```powershell
# Start all services
.\scripts.ps1 up

# Check comprehensive status
.\scripts.ps1 status

# Test individual services
.\scripts.ps1 test-kafka
.\scripts.ps1 test-ingestion
.\scripts.ps1 test-consumer
.\scripts.ps1 test-query

# View logs
.\scripts.ps1 logs
.\scripts.ps1 logs-kafka

# Stop services
.\scripts.ps1 down

# Complete cleanup
.\scripts.ps1 clean
```

### Using Docker Compose Directly
```bash
# Start services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

## 🔧 API Usage

### Ingestion API (Write Operations)
```bash
# Create a post
curl -X POST http://localhost:8081/api/posts \
  -H "Content-Type: application/json" \
  -d '{"user_id": "john", "content": "Hello World!"}'

# Add a comment
curl -X POST http://localhost:8081/api/comments \
  -H "Content-Type: application/json" \
  -d '{"post_id": "post-id", "user_id": "jane", "content": "Great post!"}'

# Like a post
curl -X POST http://localhost:8081/api/likes \
  -H "Content-Type: application/json" \
  -d '{"post_id": "post-id", "user_id": "bob"}'
```

### Query API (Read Operations)
```bash
# Get recent posts
curl http://localhost:8083/api/posts?limit=10

# Get posts by user
curl http://localhost:8083/api/users/john/posts

# Get user statistics
curl http://localhost:8083/api/users/john/stats

# Get post details with comments and likes
curl http://localhost:8083/api/posts/post-id
```

## 🗄️ Database Schema

### Shard Databases (posts)
```sql
-- Posts table
CREATE TABLE posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Comments table
CREATE TABLE comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL,
    user_id VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Likes table
CREATE TABLE likes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL,
    user_id VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Master Database (metadata)
```sql
-- Shard metadata
CREATE TABLE shard_metadata (
    id SERIAL PRIMARY KEY,
    shard_name VARCHAR(50) NOT NULL,
    host VARCHAR(255) NOT NULL,
    port INTEGER NOT NULL,
    database_name VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

## 📈 Monitoring & Metrics

### Key Metrics
- **Request rates** per service
- **Database write rates** by shard
- **Message processing rates** in Kafka
- **Response times** and error rates
- **System resource usage**

### Sample Prometheus Queries
```promql
# Request rate per service
rate(http_requests_total[1m])

# Database write rate by shard
rate(database_writes_total[1m])

# 95th percentile response time
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

## 🔒 Environment Variables

All configuration is managed through the `.env` file:

```bash
# Database Credentials
PG_SHARD_USER=postgres
PG_SHARD_PASS=your_password
PG_SHARD_DB=posts

PG_MASTER_USER=postgres
PG_MASTER_PASS=your_password
PG_MASTER_DB=metadata

# Kafka Configuration
KAFKA_BROKER_ID=1
KAFKA_ZOOKEEPER_CONNECT=zookeeper:2181
KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://kafka:29092,PLAINTEXT_HOST://localhost:9092
```

## 🧪 Testing

### Run All Tests
```powershell
.\scripts.ps1 test-kafka
.\scripts.ps1 test-ingestion
.\scripts.ps1 test-consumer
.\scripts.ps1 test-query
```

### Manual Testing
```powershell
# Test the complete flow
.\scripts.ps1 test-client
```

## 🚨 Troubleshooting

### Common Issues

1. **Docker not responding**
   - Start Docker Desktop
   - Wait for it to fully initialize

2. **Container name conflicts**
   ```powershell
   .\scripts.ps1 clean
   .\scripts.ps1 up
   ```

3. **Services not starting**
   - Check logs: `.\scripts.ps1 logs`
   - Verify Docker resources

4. **Database connection issues**
   - Check if PostgreSQL containers are running
   - Verify credentials in `.env` file

### Health Checks
```powershell
# Check all service health
.\scripts.ps1 status

# Check specific service logs
.\scripts.ps1 logs-kafka
```

## 📚 Architecture Benefits

- **Scalability**: Horizontal scaling with multiple shards
- **Reliability**: Event-driven architecture with Kafka
- **Observability**: Comprehensive monitoring and logging
- **Performance**: Distributed reads and writes
- **Flexibility**: Microservices architecture

## 🔄 Data Flow

1. **Write Path**: Client → Ingestion Service → Kafka → Consumer Service → Database Shards
2. **Read Path**: Client → Query Service → Database Shards → Aggregated Results
3. **Monitoring**: All services → Prometheus → Grafana Dashboards
4. **Logging**: All services → Elasticsearch → Kibana
