Write-Host "Setting up Monitoring & Logging..." -ForegroundColor Green

# Create monitoring directories
Write-Host "Creating monitoring directory structure..." -ForegroundColor Yellow

$directories = @(
    "monitoring",
    "monitoring/grafana",
    "monitoring/grafana/dashboards", 
    "monitoring/grafana/datasources",
    "monitoring/fluentd"
)

foreach ($dir in $directories) {
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "Created $dir" -ForegroundColor Green
    } else {
        Write-Host "$dir already exists" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "=== Directory Structure Created ===" -ForegroundColor Cyan
Write-Host "monitoring/" -ForegroundColor White
Write-Host "├── prometheus.yml" -ForegroundColor White
Write-Host "├── alert_rules.yml" -ForegroundColor White
Write-Host "├── grafana/" -ForegroundColor White
Write-Host "│   ├── datasources/" -ForegroundColor White
Write-Host "│   │   └── prometheus.yml" -ForegroundColor White
Write-Host "│   └── dashboards/" -ForegroundColor White
Write-Host "│       ├── dashboard.yml" -ForegroundColor White
Write-Host "│       └── distributed-database.json" -ForegroundColor White
Write-Host "└── fluentd/" -ForegroundColor White
Write-Host "    ├── Dockerfile" -ForegroundColor White
Write-Host "    └── fluent.conf" -ForegroundColor White

Write-Host ""
Write-Host "Monitoring setup completed!" -ForegroundColor Green