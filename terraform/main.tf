resource "aws_instance" "devops_server" {
  ami           = "ami-007020fd9c84e18c7" # Ubuntu 22.04 LTS Free-Tier AMI
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.healthcare_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.s3_backup_profile.name

  root_block_device {
    volume_size = 30 # Maximum allowed storage on AWS Free Tier
    volume_type = "gp3"
  }

  tags = {
    Name = "Healthcare-DevOps-Server"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y curl apt-transport-https ca-certificates gnupg lsb-release

              # Install Docker
              mkdir -p /etc/apt/keyrings
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
              echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
              apt-get update -y
              apt-get install -y docker-ce docker-ce-cli containerd.io
              systemctl enable docker
              systemctl start docker

              # Install K3s (Lightweight Kubernetes)
              curl -sfL https://get.k3s.io | sh -
              
              # Run Jenkins Container
              docker run -d -p 8080:8080 -p 50000:50000 --name jenkins --restart always -v jenkins_home:/var/jenkins_home jenkins/jenkins:lts
              EOF
}

# Create S3 Bucket for Backup storage (Disaster Recovery compliance)
resource "aws_s3_bucket" "backup_bucket" {
  bucket        = "sidreddy24-ehr-db-backups"
  force_destroy = true
}

# IAM Role allowing EC2 to read/write to the Backup S3 bucket
resource "aws_iam_role" "s3_backup_role" {
  name = "healthcare-s3-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
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
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.backup_bucket.arn,
          "${aws_s3_bucket.backup_bucket.arn}/*"
        ]
      }
    ]
  })
}

# IAM Instance Profile to attach to the EC2 Instance
resource "aws_iam_instance_profile" "s3_backup_profile" {
  name = "healthcare-s3-backup-profile"
  role = aws_iam_role.s3_backup_role.name
}

output "server_public_ip" {
  value       = aws_instance.devops_server.public_ip
  description = "Public IP of your DevOps server"
}