output "name" {
  description = "The repository's name."
  value       = github_repository.this.name
}

output "repo_id" {
  description = "The repository's numeric id, as an immutable OIDC subject names it."
  value       = github_repository.this.repo_id
}
