#!/bin/bash
# Backup Script for EHR MySQL Database
# This script can be scheduled via cron to run periodic backups.
set -e

BACKUP_DIR="/Users/siddharthreddy/Desktop/devops/backups"
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/ehr_backup_$TIMESTAMP.sql"

echo "⏳ Finding MySQL pod in namespace: healthcare..."
MYSQL_POD=$(kubectl get pods -n healthcare -l app=mysql --insecure-skip-tls-verify -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$MYSQL_POD" ]; then
    # Fallback to local docker execution if not running in cluster
    echo "⚠️  MySQL Kubernetes pod not found. Attempting backup via local Docker container..."
    DOCKER_CONTAINER=$(docker ps -q -f name=mysql)
    if [ -z "$DOCKER_CONTAINER" ]; then
        echo "❌ Error: No running MySQL pod or container detected!"
        exit 1
    fi
    docker exec "$DOCKER_CONTAINER" mysqldump -u root -prootpassword healthcare > "$BACKUP_FILE"
else
    echo "📦 Starting database backup from Kubernetes pod: $MYSQL_POD..."
    kubectl exec -i "$MYSQL_POD" -n healthcare --insecure-skip-tls-verify -- mysqldump -u root -prootpassword healthcare > "$BACKUP_FILE"
fi

echo "✅ Backup successfully saved to: $BACKUP_FILE"

# Upload to AWS S3 (for Disaster Recovery compliance)
S3_BUCKET="s3://sidreddy24-ehr-db-backups"
echo "☁️ Uploading backup to AWS S3: $S3_BUCKET..."
if command -v aws &> /dev/null; then
    aws s3 cp "$BACKUP_FILE" "$S3_BUCKET/$(basename "$BACKUP_FILE")" && echo "✅ Uploaded to S3 successfully." || echo "⚠️ S3 upload failed (check AWS CLI config/permissions)."
else
    echo "⚠️ AWS CLI not installed on this node. Simulated upload to S3: $S3_BUCKET/$(basename "$BACKUP_FILE")"
fi
