output "aws_region" {
  value = var.aws_region
}
output "mongo_instances" {
  value = [
    for i, instance in aws_instance.mongo : {
      name       = "mongo${i + 1}"
      instance_id = instance.id
      private_ip = instance.private_ip
    }
  ]
}
output "mongo_private_ips" {
  value = [for instance in aws_instance.mongo : instance.private_ip]
}
output "mongo_instance_ids" {
  value = [for instance in aws_instance.mongo : instance.id]
}
output "ssm_transfer_bucket" {
  value = aws_s3_bucket.ansible_transfer.bucket
}
output "vpc_id" {
  value = aws_vpc.main.id
}
