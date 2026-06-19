variable "aws_region" {
  type    = string
  default = "ap-south-1" # Change to your preferred region
}

variable "instance_type" {
  type    = string
  default = "t2.micro" # Strictly Free Tier
}

variable "key_name" {
  type        = string
  description = "Name of your existing AWS SSH Key Pair to log into the instance"
}