variable "port" {
  type    = number
  default = 2222
}

module "docker" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  daemon_config = { log-driver = "json-file", log-opts = { max-size = "10m" } }
  stacks = {
    whoami = <<-EOT
      services:
        whoami:
          image: docker.io/traefik/whoami:v1.11
          ports:
            - "8080:80"
          restart: unless-stopped
    EOT
  }
}
