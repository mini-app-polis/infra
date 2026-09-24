output "doppler_sync_role_arn" {
  description = "Paste into each Doppler config's AWS Parameter Store integration."
  value       = aws_iam_role.doppler_sync.arn
}
