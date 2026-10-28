# Facts give each host's distribution, which picks Docker's repository.
data "conn3x_host" "facts" {
  for_each = var.hosts

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }
}

locals {
  # Docker publishes one repository per distribution. Rocky Linux and
  # AlmaLinux use the RHEL one. apt needs the release's codename.
  repo     = { rocky = "rhel", almalinux = "rhel", rhel = "rhel", centos = "rhel", fedora = "fedora", ubuntu = "ubuntu", debian = "debian" }
  codename = { "22.04" = "jammy", "24.04" = "noble", "26.04" = "resolute", "12" = "bookworm", "13" = "trixie" }

  hosts = {
    for name, f in data.conn3x_host.facts : name => {
      url    = f.os_family == "redhat" ? "https://download.docker.com/linux/${local.repo[f.os_id]}/$releasever/$basearch/stable" : "https://download.docker.com/linux/${local.repo[f.os_id]}"
      key    = file("${path.module}/files/docker-${f.os_family == "redhat" ? "rpm" : "deb"}.asc")
      suites = f.os_family == "redhat" ? null : [local.codename[f.os_version]]
    }
  }

  # Each stack's file and its last applied checksum live here.
  stacks_dir = "/opt/stacks"
}

circuit "docker" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "repo" {
    repository {
      name       = "docker-ce"
      url        = local.hosts[each.key].url
      key        = local.hosts[each.key].key
      suites     = local.hosts[each.key].suites
      components = ["stable"]
    }
  }

  step "packages" {
    for_each = toset(["docker-ce", "docker-ce-cli", "containerd.io", "docker-buildx-plugin", "docker-compose-plugin"])
    package {
      name = item.value
    }
  }

  step "config_dir" {
    directory {
      path = "/etc/docker"
    }
  }

  step "daemon_config" {
    file {
      path    = "/etc/docker/daemon.json"
      content = "${jsonencode(var.daemon_config)}\n"
    }
    notify = [handler.restart]
  }

  step "running" {
    service {
      name    = "docker"
      state   = "started"
      enabled = true
    }
  }

  step "users" {
    for_each = toset(var.docker_users)
    command {
      command = "usermod -aG docker ${item.value}"
      unless  = "id -nG ${item.value} | tr ' ' '\\n' | grep -qx docker"
    }
  }

  step "stack_dir" {
    for_each = var.stacks
    directory {
      path = "${local.stacks_dir}/${item.key}"
    }
  }

  step "stack_file" {
    for_each = var.stacks
    file {
      path    = "${local.stacks_dir}/${item.key}/compose.yaml"
      content = item.value
    }
  }

  # Runs docker compose up when the file changed since the last run, or when
  # one of the stack's services isn't running.
  step "stack_up" {
    for_each = var.stacks
    command {
      command = "cd ${local.stacks_dir}/${item.key} && docker compose up -d --remove-orphans --wait && sha256sum compose.yaml > .applied"
      unless  = "cd ${local.stacks_dir}/${item.key} && sha256sum -c --status .applied && [ \"$(docker compose config --services | sort)\" = \"$(docker compose ps --services --status running | sort)\" ]"
    }
  }

  handler "restart" {
    service {
      name = "docker"
    }
  }
}
