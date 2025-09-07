Write-Host "Testing Monitoring & Logging Stack..." -ForegroundColor Green

Write-Host ""
Write-Host "=== Checking Monitoring Services ===" -ForegroundColor Cyan

# Check Prometheus
Write-Host "Testing Prometheus..." -ForegroundColor Yellow
try {
    $prometheusHealth = Invoke-WebRequest -Uri "http://localhost:9090/-/healthy" -UseBasicParsing -TimeoutSec 5
    if ($prometheusHealth.StatusCode -eq 200) {
        Write-Host "Prometheus is healthy" -ForegroundColor Green
        
        # Check targets
        $targets = Invoke-RestMethod -Uri "http://localhost:9090/api/v1/targets" -TimeoutSec 5
        $activeTargets = ($targets.data.activeTargets | Where-Object { $_.health -eq "up" }).Count
        $totalTargets = $targets.data.activeTargets.Count
        Write-Host "   Active targets: $activeTargets / $totalTargets" -ForegroundColor White
        
        if ($activeTargets -lt $totalTargets) {
            Write-Host "Some targets are down" -ForegroundColor Yellow
            $downTargets = $targets.data.activeTargets | Where-Object { $_.health -ne "up" }
            foreach ($target in $downTargets) {
                Write-Host "     - $($target.labels.job): $($target.health)" -ForegroundColor Red
            }
        }
    }
} catch {
    Write-Host "Prometheus is not accessible: $($_.Exception.Message)" -ForegroundColor Red
}

# Check Grafana
Write-Host "Testing Grafana..." -ForegroundColor Yellow
try {
    $grafanaHealth = Invoke-WebRequest -Uri "http://localhost:3000/api/health" -UseBasicParsing -TimeoutSec 5
    if ($grafanaHealth.StatusCode -eq 200) {
        Write-Host "Grafana is healthy" -ForegroundColor Green
        Write-Host "Access: http://localhost:3000 (admin/admin123)" -ForegroundColor White
    }
} catch {
    Write-Host "Grafana is not accessible: $($_.Exception.Message)" -ForegroundColor Red
}

# Check Elasticsearch
Write-Host "Testing Elasticsearch..." -ForegroundColor Yellow
try {
    $elasticsearchHealth = Invoke-RestMethod -Uri "http://localhost:9200/_cluster/health" -TimeoutSec 5
    if ($elasticsearchHealth.status) {
        Write-Host "Elasticsearch is healthy (Status: $($elasticsearchHealth.status))" -ForegroundColor Green
        Write-Host "Indices: $($elasticsearchHealth.number_of_data_nodes) data nodes" -ForegroundColor White
    }
} catch {
    Write-Host "Elasticsearch is not accessible: $($_.Exception.Message)" -ForegroundColor Red
}

# Check Kibana
Write-Host "Testing Kibana..." -ForegroundColor Yellow
try {
    $kibanaHealth = Invoke-WebRequest -Uri "http://localhost:5601/api/status" -UseBasicParsing -TimeoutSec 5
    if ($kibanaHealth.StatusCode -eq 200) {
        Write-Host "Kibana is healthy" -ForegroundColor Green
        Write-Host "Access: http://localhost:5601" -ForegroundColor White
    }
} catch {
    Write-Host "Kibana is not accessible: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Testing Metrics Collection ===" -ForegroundColor Cyan

# Test metrics from each service
$services = @(
    @{Name="Ingestion"; Port=8081; Color="Green"},
    @{Name="Consumer"; Port=8082; Color="Yellow"}, 
    @{Name="Query"; Port=8083; Color="Cyan"}
)

foreach ($service in $services) {
    Write-Host "Testing $($service.Name) Service metrics..." -ForegroundColor $service.Color
    try {
        $metrics = Invoke-WebRequest -Uri "http://localhost:$($service.Port)/metrics" -UseBasicParsing -TimeoutSec 5
        if ($metrics.StatusCode -eq 200) {
            $metricLines = $metrics.Content -split "`n" | Where-Object { $_ -match "^[a-zA-Z].*total" -and $_ -notmatch "^#" }
            Write-Host "$($metricLines.Count) metrics available" -ForegroundColor Green
            
            # Show some sample metrics
            $metricLines | Select-Object -First 3 | ForEach-Object {
                Write-Host "     $($_.Trim())" -ForegroundColor Gray
            }
        }
    } catch {
        Write-Host "Metrics not accessible" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Sample Queries for Prometheus ===" -ForegroundColor Cyan
Write-Host "Try these queries in Prometheus (http://localhost:9090):" -ForegroundColor White
Write-Host ""
Write-Host "# Request rate per service" -ForegroundColor Gray
Write-Host "rate(http_requests_total[1m])" -ForegroundColor White
Write-Host ""
Write-Host "# Database write rate by shard" -ForegroundColor Gray
Write-Host "rate(database_writes_total[1m])" -ForegroundColor White
Write-Host ""
Write-Host "# Message processing rate" -ForegroundColor Gray
Write-Host "rate(messages_processed_total[1m])" -ForegroundColor White
Write-Host ""
Write-Host "# 95th percentile response time" -ForegroundColor Gray
Write-Host "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))" -ForegroundColor White

Write-Host ""
Write-Host "=== Access Points Summary ===" -ForegroundColor Cyan
Write-Host "Monitoring Dashboard:" -ForegroundColor White
Write-Host "Prometheus: http://localhost:9090" -ForegroundColor Yellow
Write-Host "Grafana: http://localhost:3000 (admin/admin123)" -ForegroundColor Yellow
Write-Host ""
Write-Host "Logging Dashboard:" -ForegroundColor White
Write-Host "Elasticsearch: http://localhost:9200" -ForegroundColor Yellow
Write-Host "Kibana: http://localhost:5601" -ForegroundColor Yellow
Write-Host ""
Write-Host "Service Metrics:" -ForegroundColor White
Write-Host "Ingestion: http://localhost:8081/metrics" -ForegroundColor Yellow
Write-Host "Consumer: http://localhost:8082/metrics" -ForegroundColor Yellow
Write-Host "Query: http://localhost:8083/metrics" -ForegroundColor Yellow

Write-Host ""
Write-Host "Monitoring & Logging stack is ready!" -ForegroundColor Green