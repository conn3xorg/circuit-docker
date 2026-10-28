variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file or jump_hosts."
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}


variable "daemon_config" {
  type        = any
  default     = {}
  description = "Settings for /etc/docker/daemon.json, such as { log-driver = \"json-file\", log-opts = { max-size = \"10m\" } }."
}

variable "docker_users" {
  type        = list(string)
  default     = []
  description = "Existing users to add to the docker group, so they can run docker without sudo."
}

variable "stacks" {
  type        = map(string)
  default     = {}
  description = "Compose files to run, by stack name. Each goes to /opt/stacks/NAME/compose.yaml and runs with docker compose up."
}
