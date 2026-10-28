variable "aws_region" {
  description = "AWS region for the lab"
  type        = string
  default     = "ap-south-1"
}
variable "project_name" {
  type    = string
  default = "mongo-ssm-demo"
}
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "instance_type" {
  description = "Small instance for demo only"
  type        = string
  default     = "t3.micro"
}
variable "root_volume_size" {
  description = "Encrypted root/data disk size in GiB; minimum practical Ubuntu demo size"
  type        = number
  default     = 8
}
variable "mongo_count" {
  description = "Keep at 3 for a conventional three-member replica set"
  type        = number
  default     = 3
  validation {
    condition     = var.mongo_count == 3
    error_message = "This demo configuration expects exactly three MongoDB nodes."
  }
}
