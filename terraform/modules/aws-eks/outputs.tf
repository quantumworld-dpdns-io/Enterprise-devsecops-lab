output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca" {
  description = "Base64 cluster CA certificate."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (nodes, internal load balancers)."
  value       = aws_subnet.private[*].id
}

output "secrets_kms_key_arn" {
  description = "KMS key encrypting Kubernetes Secrets."
  value       = aws_kms_key.eks_secrets.arn
}

output "app_role_arn" {
  description = "IAM role bound to the demo workload through Pod Identity."
  value       = aws_iam_role.app.arn
}

output "kubeconfig_command" {
  description = "Command to fetch a kubeconfig (uses your current AWS identity)."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${data.aws_region.current.region}"
}
