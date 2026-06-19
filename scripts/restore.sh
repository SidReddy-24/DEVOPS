#!/bin/bash
# Restore Script for EHR MySQL Database
set -e

BACKUP_DIR="/Users/siddharthreddy/Desktop/devops/backups"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "❌ Error: Backup directory $BACKUP_DIR does not exist!"
    exit 1
fi

# Find the latest backup file
LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/ehr_backup_*.sql 2>/dev/null | head -n 1 || echo "")

if [ -z "$LATEST_BACKUP" ]; then
    echo "⚠️ Local backup file not found. Checking AWS S3 bucket: s3://sidreddy24-ehr-db-backups..."
    if command -v aws &> /dev/null; then
        aws s3 sync s3://sidreddy24-ehr-db-backups/ "$BACKUP_DIR/"
        LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/ehr_backup_*.sql 2>/dev/null | head -n 1 || echo "")
    fi
fi

if [ -z "$LATEST_BACKUP" ]; then
    echo "❌ Error: No SQL backup files found locally or in S3!"
    exit 1
fi

echo "⏳ Finding MySQL pod in namespace: healthcare..."
MYSQL_POD=$(kubectl get pods -n healthcare -l app=mysql --insecure-skip-tls-verify -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$MYSQL_POD" ]; then
    # Fallback to local docker execution if not running in cluster
    echo "⚠️  MySQL Kubernetes pod not found. Attempting restore via local Docker container..."
    DOCKER_CONTAINER=$(docker ps -q -f name=mysql)
    if [ -z "$DOCKER_CONTAINER" ]; then
        echo "❌ Error: No running MySQL pod or container detected!"
        exit 1
    fi
    echo "🔄 Restoring latest backup ($LATEST_BACKUP) to local Docker container..."
    docker exec -i "$DOCKER_CONTAINER" mysql -u root -prootpassword healthcare < "$LATEST_BACKUP"
else
    echo "🔄 Restoring latest backup ($LATEST_BACKUP) to Kubernetes pod: $MYSQL_POD..."
    kubectl exec -i "$MYSQL_POD" -n healthcare --insecure-skip-tls-verify -- mysql -u root -prootpassword healthcare < "$LATEST_BACKUP"
fi

echo "✅ Database restore completed successfully!"
