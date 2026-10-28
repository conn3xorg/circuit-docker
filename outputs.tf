output "stack_dirs" {
  description = "Directory of each stack on the hosts, by stack name."
  value       = { for name, _ in var.stacks : name => "${local.stacks_dir}/${name}" }
}
