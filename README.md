# circuit-docker

A Conn3x circuit that installs Docker Engine from Docker's own repository, keeps it running, and runs your Compose stacks. It's the piece most homelab setups start with: get Docker on the box, then bring up Jellyfin, the *arr apps, a VPN container or a monitoring stack from a `compose.yaml`.

Each stack's file lives in your configuration, so a change to it shows up in `conn3x plan` as a diff, and the apply runs `docker compose up` only when the file changed or a service stopped.

## Usage

```hcl
module "docker" {
  source = "github.com/conn3xorg/circuit-docker?ref=v0.1.0"

  hosts                = { media = "192.168.1.20" }
  ssh_private_key_file = "~/.ssh/id_ed25519"

  docker_users = ["james"]
  stacks = {
    media = file("${path.module}/stacks/media.yaml")
  }
}
```

With `stacks/media.yaml` next to it:

```yaml
services:
  jellyfin:
    image: lscr.io/linuxserver/jellyfin:12.4ubu2604-ls57
    ports: ["8096:8096"]
    volumes:
      - /srv/jellyfin/config:/config
      - /srv/media:/data/media
    restart: unless-stopped
  sonarr:
    image: lscr.io/linuxserver/sonarr:4.0.20.3014-ls1
    ports: ["8989:8989"]
    volumes:
      - /srv/sonarr/config:/config
      - /srv/media:/data/media
    restart: unless-stopped
```

Then run `conn3x init` and `conn3x apply`. A second `conn3x plan` says `No changes.`

For hosts created in the same plan, pass host objects with the host key you generated, so Conn3x checks it without a known_hosts entry:

```hcl
hosts = {
  for name, d in digitalocean_droplet.app : name => {
    address  = d.ipv4_address
    host_key = tls_private_key.host[name].public_key_openssh
  }
}
```

To try it on a throwaway container first, see [examples/local](examples/local).

## What it does

On each host, in order:

1. Adds Docker's repository and signing key: `download.docker.com/linux/rhel` on Rocky Linux, AlmaLinux and RHEL, and the `fedora`, `ubuntu` or `debian` one elsewhere. The keys are in [files](files), copied from Docker's site.
2. Installs `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin` and `docker-compose-plugin`.
3. Writes `/etc/docker/daemon.json` from `daemon_config`, and restarts Docker when it changes.
4. Starts Docker now and at boot.
5. Adds each of `docker_users` to the `docker` group. The users must already exist; the [users circuit](https://github.com/conn3xorg/circuit-users) can create them.
6. For each stack, writes `/opt/stacks/NAME/compose.yaml` and runs `docker compose up -d --remove-orphans --wait` in that directory.

A stack runs again when its file changed since the last successful run, or when one of its services isn't running. `--wait` makes the apply fail if a service doesn't start, or doesn't turn healthy when it has a health check. Every service in a stack should keep running: one that runs once and exits looks stopped, so the stack would run again on every apply.

Before the circuit runs, the `conn3x_host` data source reads each host's distribution over SSH. On Debian and Ubuntu it picks the apt suite from the release: Ubuntu 22.04, 24.04 and 26.04, and Debian 12 and 13. Another release fails the plan.

The circuit doesn't open firewall ports for your stacks. Docker publishes ports through its own iptables rules, which bypass `ufw`.

### Removing a stack

Deleting a stack from `stacks` leaves it running. Run `docker compose down` in its directory first, then delete it.

## Inputs

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `hosts` | any | Required | Hosts to configure, by name. Each value is an address, such as `"203.0.113.10"`, or a host object such as `{ address = "203.0.113.10", host_key = "ssh-ed25519 AAAA..." }`. A host object can also set `user`, `port`, `private_key_file` and `jump_hosts`. The two forms can be mixed. |
| `ssh_user` | string | `"root"` | User to log in as. |
| `ssh_port` | number | `22` | SSH port. |
| `ssh_private_key_file` | string | `null` | Path to a private key. When null, Conn3x uses the SSH agent. |
| `ssh_known_hosts_file` | string | `null` | known_hosts file to check host keys against. When null, `~/.ssh/known_hosts`. Not used for a host object with `host_key`. |
| `ssh_become` | bool | `false` | Run commands as root through sudo. Set it when `ssh_user` isn't root. |
| `daemon_config` | any | `{}` | Settings for `/etc/docker/daemon.json`, such as `{ log-driver = "json-file", log-opts = { max-size = "10m" } }`. |
| `docker_users` | list(string) | `[]` | Existing users to add to the `docker` group. |
| `stacks` | map(string) | `{}` | Compose files to run, by stack name. |

## Outputs

| Name | Description |
| --- | --- |
| `stack_dirs` | Each stack's directory on the hosts, such as `{ media = "/opt/stacks/media" }`. |

## Requirements

Requires Conn3x v0.6.4 or later and systemd on each host, with outbound HTTPS to download.docker.com and to the registries your stacks pull from.

## Tested on

Rocky Linux 10, Fedora 45, Ubuntu 24.04 and Debian 13. CI applies [examples/local](examples/local) to each on amd64, checks that the second plan has no changes, and checks the example stack is running.

## License

MPL-2.0. See [LICENSE](LICENSE). Docker Engine itself is Apache-2.0.
