output "server_container" {
  description = "Name of the server container (used to fetch kubeconfig and import images)."
  value       = docker_container.server.name
}

output "node_containers" {
  description = "All node container names, server first."
  value       = concat([docker_container.server.name], docker_container.agent[*].name)
}

output "api_endpoint" {
  description = "Kubernetes API endpoint reachable from the host."
  value       = "https://127.0.0.1:${var.api_port}"
}

output "ingress_https" {
  description = "Ingress HTTPS endpoint reachable from the host."
  value       = "https://127.0.0.1:${var.https_port}"
}

output "join_token" {
  description = "Cluster join token."
  value       = random_password.token.result
  sensitive   = true
}
