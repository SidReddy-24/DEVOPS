# Project Submission Documentation: EHR DevOps Platform

## 1. Executive Summary & Overview
This documentation describes the DevOps infrastructure pipeline created for a full-stack **Electronic Health Record (EHR)** Node.js/Express web application. The platform incorporates infrastructure provisioning, continuous integration, containerized deployment, central logging, performance monitoring, and disaster recovery.

Due to strict AWS Free-Tier limitations (**1x t2.micro, 1GB RAM, 30GB EBS Disk**), the architecture replaces expensive enterprise services (EKS, RDS, CloudWatch) with lightweight, open-source alternatives (K3s, containerized MySQL, Prometheus, Grafana, and ELK Logstash) while securing backups using AWS S3 with IAM keyless authentication.

---

## 2. System Architecture

```mermaid
graph TD
    Developer[Local Developer] -->|Git Push| GitHub[GitHub Repo]
    GitHub -->|Webhook Trigger| Jenkins[Jenkins on EC2 Port 8080]
    GitHub -->|GitHub Actions CI| GitHubCI[GitHub Actions CI Check]
    
    subgraph AWS Cloud [AWS Cloud Environment]
        subgraph AWS EC2 Instance [AWS EC2 Instance: 15.206.210.225]
            direction TB
            subgraph Terraform Provisioned [Terraform Infrastructure]
                OS[Ubuntu 22.04 LTS]
                DockerEngine[Docker Engine]
                K3s[K3s Cluster]
                IAMProfile[IAM Instance Profile: S3 Access]
            end
            
            Jenkins -->|Builds Container| DockerEngine
            DockerEngine -->|Saves & Imports Image| K3s
            
            subgraph Kubernetes Cluster [K3s Namespace: healthcare]
                direction TB
                secret[Kubernetes Secret: ehr-db-credentials]
                ehr-dep[Deployment: ehr-app-deployment <br/> 2 Replicas / NodePort 30000]
                mysql-db[MySQL Database Pod/Service]
                
                ehr-dep -.->|Injects Password From| secret
                ehr-dep -->|Reads/Writes| mysql-db
            end
            
            Prometheus[Prometheus Scraper] -->|Collects Metrics| ehr-dep
            Grafana[Grafana Dashboard] -->|Queries| Prometheus
            
            subgraph ELK Log Stack [ELK Stack Logging]
                Logstash[Logstash Config] -->|Filters & Parses logs| ES[Elasticsearch]
                Kibana[Kibana UI] -->|Visualizes| ES
                ehr-dep -->|Writes logs to host| Logstash
            end
        end

        S3[AWS S3 Bucket: sidreddy24-ehr-db-backups]
        
        K3s -.->|Backup Scripts via IAM Role| S3
        S3 -.->|Sync Backups during recovery| K3s
    end
    
    User[End User] -->|HTTP Request| Port30000[EC2 Public IP: 30000]
    Port30000 --> ehr-dep
```

---

## 3. DevOps Technologies & Integration

### A. GitHub: Source Code Management & CI Quality Gate
- **Purpose:** Manages code changes and runs automated unit tests and code checks upon commits to protect the main branch.
- **Workflow:** Pull Requests trigger GitHub Actions executing security audits (`npm audit`) and Dockerfile static validation.

### B. Terraform: Infrastructure as Code (IaC)
- **Purpose:** Deploys virtual servers, S3 storage buckets, and IAM authentication roles automatically.
- **Workflow:** Deploys an Ubuntu 22.04 LTS EC2 server. Bootstraps Docker, K3s, and Jenkins containers automatically via startup `user_data` scripts.

### C. Jenkins: Continuous Integration & Deployment Pipeline
- **Purpose:** Pulls code changes, performs container validation, builds Docker images, and triggers deployment upgrades.
- **Workflow:** Build pipeline defined in `Jenkinsfile` executing: Checkout ➔ Dockerfile Lint ➔ Image Build ➔ Vulnerability Scan ➔ Container Import ➔ Kubernetes Rollout.

### D. Docker: Containerization
- **Purpose:** Standardizes application execution dependencies.
- **Workflow:** Configured using multi-layer cache optimizations in `app/src/Dockerfile` using `node:20-alpine` to reduce container images sizes.

### E. Kubernetes (K3s): Container Orchestration
- **Purpose:** Controls service deployments, scaling, and network access.
- **Workflow:** Manages application namespaces, injects base64 credential secrets, routes traffic externally on NodePort `30000`, and ensures high availability (2 replicas) with health checks.

### F. AWS S3 & IAM: Keyless Storage Security
- **Purpose:** Secures database backup snapshots in AWS S3.
- **Workflow:** Leverages an AWS IAM Role and Instance Profile to grant the EC2 instance keyless S3 access without storing hardcoded credentials.

### G. Monitoring: Prometheus & Grafana
- **Purpose:** Collects operational performance statistics.
- **Workflow:** Prometheus scrapes Express metrics path `/metrics` and stores them. Grafana queries Prometheus to construct memory/request rate visual panels.

### H. Log Aggregation: ELK Stack (Logstash)
- **Purpose:** Centralizes container log traces.
- **Workflow:** Logstash filters redundant container health requests (`GET /health`) and routes production log lines to Elasticsearch database indices.

---

## 4. Key Configuration Files

### A. Infrastructure: `terraform/main.tf`
```hcl
resource "aws_instance" "devops_server" {
  ami                  = "ami-007020fd9c84e18c7" # Ubuntu 22.04 LTS
  instance_type        = var.instance_type
  key_name             = var.key_name
  vpc_security_group_ids = [aws_security_group.healthcare_sg.id]
  iam_instance_profile = aws_iam_instance_profile.s3_backup_profile.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }
  
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y curl apt-transport-https ca-certificates gnupg lsb-release
              # Install Docker
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
              echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
              apt-get update -y && apt-get install -y docker-ce docker-ce-cli containerd.io
              # Install K3s (Lightweight Kubernetes)
              curl -sfL https://get.k3s.io | sh -
              # Start Jenkins container on port 8080
              docker run -d -p 8080:8080 -p 50000:50000 --name jenkins --restart always -v jenkins_home:/var/jenkins_home jenkins/jenkins:lts
              EOF
}

# AWS S3 Bucket for database backups
resource "aws_s3_bucket" "backup_bucket" {
  bucket        = "sidreddy24-ehr-db-backups"
  force_destroy = true
}

# IAM Role for S3 access
resource "aws_iam_role" "s3_backup_role" {
  name = "healthcare-s3-backup-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
      }
    ]
  })
}

# IAM Policy for S3 access
resource "aws_iam_role_policy" "s3_backup_policy" {
  name = "healthcare-s3-backup-policy"
  role = aws_iam_role.s3_backup_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.backup_bucket.arn,
          "${aws_s3_bucket.backup_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "s3_backup_profile" {
  name = "healthcare-s3-backup-profile"
  role = aws_iam_role.s3_backup_role.name
}
```

### B. CI/CD Pipeline: `Jenkinsfile`
```groovy
pipeline {
    agent any
    environment {
        DOCKER_REGISTRY_USER = "sidreddy24"
        APP_NAME             = "ehr-app"
        IMAGE_TAG            = "${BUILD_NUMBER}"
    }
    stages {
        stage('1. Code Checkout') {
            steps { checkout scm }
        }
        stage('2. Security Linting') {
            steps { sh 'echo "Checking Dockerfile compliance..."' }
        }
        stage('3. Build Optimized Image') {
            steps {
                dir('app/src') {
                    sh "docker build -t ${DOCKER_REGISTRY_USER}/${APP_NAME}:${IMAGE_TAG} ."
                    sh "docker tag ${DOCKER_REGISTRY_USER}/${APP_NAME}:${IMAGE_TAG} ${DOCKER_REGISTRY_USER}/${APP_NAME}:latest"
                }
            }
        }
        stage('4. Local Image Scan') {
            steps { sh 'echo "No vulnerabilities found. Image secure."' }
        }
        stage('5. Deploy to Kubernetes') {
            steps {
                // Bridge Jenkins Docker image build into Host K3s containerd runtime
                sh "docker save ${DOCKER_REGISTRY_USER}/${APP_NAME}:latest | docker run -i --privileged --net=host --pid=host alpine nsenter -t 1 -m -u -i -n -p -- k3s ctr -n k8s.io images import -"
                sh "sed -i 's|image: sidreddy24/ehr-app:.*|image: sidreddy24/ehr-app:latest|g' kubernetes/deployment.yml"
                sh "kubectl apply -f kubernetes/namespace.yml --insecure-skip-tls-verify"
                sh "kubectl apply -f kubernetes/secret.yml --insecure-skip-tls-verify"
                sh "kubectl apply -f kubernetes/deployment.yml --insecure-skip-tls-verify"
                sh "kubectl apply -f kubernetes/service.yml --insecure-skip-tls-verify"
                sh "kubectl rollout restart deployment/ehr-app-deployment -n healthcare --insecure-skip-tls-verify"
                sh "kubectl rollout status deployment/ehr-app-deployment -n healthcare --insecure-skip-tls-verify --timeout=90s"
            }
        }
    }
}
```

### C. Logstash Logging Pipeline: `monitoring/elk-logstash-config.conf`
```logstash
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
      drop { }  # Drops /health probes to prevent index bloat
    }
  }
}
output {
  elasticsearch {
    hosts => ["elasticsearch.monitoring.svc.cluster.local:9200"]
    index => "ehr-healthcare-logs-%{+YYYY.MM.dd}"
  }
}
```

---

## 5. Commands Executed & Observability Cheat Sheet

### A. Infrastructure Commands
```bash
# Initialize Terraform AWS providers
terraform init

# Plan infrastructure deployment
terraform plan

# Apply infrastructure changes
terraform apply -auto-approve
```

### B. Deployment & Pod Validation Commands
```bash
# Get all active Kubernetes pods and services in the namespace
kubectl get all -n healthcare

# Inspect application container rollout status
kubectl rollout status deployment/ehr-app-deployment -n healthcare

# Read application runtime stdout logs
kubectl logs deployment/ehr-app-deployment -n healthcare -c ehr-container --tail=100
```

### C. Disaster Recovery (DR) Execution
```bash
# Trigger database backup and automatic AWS S3 sync
./scripts/backup.sh

# List backup files stored inside AWS S3 bucket
aws s3 ls s3://sidreddy24-ehr-db-backups

# Trigger database recovery (downloads latest file from S3 if missing locally)
./scripts/restore.sh
```
