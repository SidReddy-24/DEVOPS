#!/bin/bash
# =====================================================================
# Monitoring Stack Setup Script for EHR DevOps Platform
# Deploys: Prometheus + Grafana + Elasticsearch + Logstash + Kibana
# Run this script ONCE on the EC2 instance after Terraform provisioning.
# =====================================================================
set -e

echo ""
echo "======================================================"
echo "  EHR Platform Monitoring Stack Setup"
echo "======================================================"
echo ""

# -----------------------------------------------
# Step 1: Create Docker network for monitoring
# -----------------------------------------------
echo "🔧 Creating Docker monitoring network..."
docker network create monitoring-net 2>/dev/null || echo "  monitoring-net already exists, skipping."

# -----------------------------------------------
# Step 2: Deploy Prometheus (Port 9090)
# -----------------------------------------------
echo ""
echo "📡 Starting Prometheus (port 9090)..."

mkdir -p /opt/prometheus

# Write prometheus.yml config
cat > /opt/prometheus/prometheus.yml <<-PROMEOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'ehr-app'
    metrics_path: '/metrics'
    static_configs:
      - targets: ['ehr-app-service.healthcare.svc.cluster.local:80']
PROMEOF

docker stop prometheus 2>/dev/null || true
docker rm   prometheus 2>/dev/null || true

docker run -d \
  --name prometheus \
  --network monitoring-net \
  --restart always \
  -p 9090:9090 \
  -v /opt/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus

echo "  ✅ Prometheus running at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9090"

# -----------------------------------------------
# Step 3: Deploy Grafana (Port 3000)
# -----------------------------------------------
echo ""
echo "📊 Starting Grafana (port 3000)..."

docker stop grafana 2>/dev/null || true
docker rm   grafana 2>/dev/null || true

docker run -d \
  --name grafana \
  --network monitoring-net \
  --restart always \
  -p 3000:3000 \
  -e GF_SECURITY_ADMIN_USER=admin \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  -e GF_SERVER_ROOT_URL=http://0.0.0.0:3000 \
  grafana/grafana

echo "  ✅ Grafana running at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):3000"
echo "  📋 Login: admin / admin"

# -----------------------------------------------
# Step 4: Deploy Elasticsearch (Port 9200)
# -----------------------------------------------
echo ""
echo "🔍 Starting Elasticsearch (port 9200)..."

docker stop elasticsearch 2>/dev/null || true
docker rm   elasticsearch 2>/dev/null || true

docker run -d \
  --name elasticsearch \
  --network monitoring-net \
  --restart always \
  -p 9200:9200 \
  -e discovery.type=single-node \
  -e xpack.security.enabled=false \
  -e "ES_JAVA_OPTS=-Xms256m -Xmx256m" \
  docker.elastic.co/elasticsearch/elasticsearch:8.13.0

echo "  ✅ Elasticsearch running on port 9200"

# -----------------------------------------------
# Step 5: Deploy Kibana (Port 5601)
# -----------------------------------------------
echo ""
echo "📋 Starting Kibana (port 5601)..."

docker stop kibana 2>/dev/null || true
docker rm   kibana 2>/dev/null || true

docker run -d \
  --name kibana \
  --network monitoring-net \
  --restart always \
  -p 5601:5601 \
  -e ELASTICSEARCH_HOSTS=http://elasticsearch:9200 \
  docker.elastic.co/kibana/kibana:8.13.0

echo "  ✅ Kibana running at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):5601"

# -----------------------------------------------
# Step 6: Deploy Logstash (ships container logs to Elasticsearch)
# -----------------------------------------------
echo ""
echo "📦 Starting Logstash..."

mkdir -p /opt/logstash/pipeline

cat > /opt/logstash/pipeline/logstash.conf <<-LSEOF
input {
  file {
    path => "/var/log/containers/ehr-app-*.log"
    type => "kubernetes-ehr"
    start_position => "beginning"
    codec => json
  }
}
filter {
  if [type] == "kubernetes-ehr" {
    json {
      source => "message"
      target => "app_log"
      skip_on_invalid_json => true
    }
    mutate {
      add_field => { "environment" => "production" }
      add_field => { "application" => "ehr-app" }
    }
    if [message] =~ "GET /health" {
      drop { }
    }
  }
}
output {
  elasticsearch {
    hosts => ["http://elasticsearch:9200"]
    index => "ehr-healthcare-logs-%{+YYYY.MM.dd}"
  }
  stdout { codec => rubydebug }
}
LSEOF

docker stop logstash 2>/dev/null || true
docker rm   logstash 2>/dev/null || true

docker run -d \
  --name logstash \
  --network monitoring-net \
  --restart always \
  -v /opt/logstash/pipeline:/usr/share/logstash/pipeline \
  -v /var/log/containers:/var/log/containers:ro \
  -e "LS_JAVA_OPTS=-Xms256m -Xmx256m" \
  docker.elastic.co/logstash/logstash:8.13.0

echo "  ✅ Logstash running and watching container logs"

# -----------------------------------------------
# Summary
# -----------------------------------------------
EC2_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo ""
echo "======================================================"
echo "  ✅ MONITORING STACK SETUP COMPLETE"
echo "======================================================"
echo ""
echo "  🔗 ACCESS DASHBOARDS (using EC2 public IP):"
echo ""
echo "  📡 Prometheus:     http://${EC2_IP}:9090"
echo "  📊 Grafana:        http://${EC2_IP}:3000   (admin / admin)"
echo "  🔍 Kibana (ELK):   http://${EC2_IP}:5601"
echo ""
echo "======================================================"
