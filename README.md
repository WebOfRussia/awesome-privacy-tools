# awesome-privacy-tools

A collection of shell scripts for self-hosting network privacy infrastructure on Linux using Docker.

## Tools

| Script | Protocol | Image |
|--------|----------|-------|
| [`socks5-manager.sh`](#socks5-managersh) | SOCKS5 | `hev-socks5-server` |
| [`squid-docker-manager.sh`](#squid-docker-managersh) | HTTP/HTTPS | `ubuntu/squid` |

---

## Requirements

- Linux host (tested on Ubuntu 22.04+)
- Docker
- `curl` (for connection tests)
- `htpasswd` (squid only — from `apache2-utils`)
- `sudo` / root access

---

## socks5-manager.sh

Manages a Dockerized [hev-socks5-server](https://github.com/heiher/hev-socks5-server) instance with per-user authentication and hot-reload support.

### Quick start

```bash
sudo ./socks5-manager.sh init
sudo ./socks5-manager.sh add-user alice secret123
sudo ./socks5-manager.sh start
sudo ./socks5-manager.sh test alice secret123 http://example.com
```

### Commands

```
init                              Create config files under /opt/socks5/
start                             Start the container
stop                              Stop the container
restart                           Restart the container
status                            Show container status
logs                              Tail container logs
list-users                        Print all usernames
add-user <user> <pass> [mark]     Add or update a user (live reload)
del-user <user>                   Remove a user (live reload)
test <user> <pass> <url>          Test connectivity through the proxy
```

### Environment overrides

| Variable | Default | Description |
|----------|---------|-------------|
| `BASE_DIR` | `/opt/socks5` | Base directory for config files |
| `CONTAINER_NAME` | `socks5` | Docker container name |
| `IMAGE` | `hev-socks5-server:latest` | Docker image |
| `PORT` | `1080` | Host port to expose |

### Notes

- Users are stored in `/opt/socks5/conf/auth.txt` (mode `600`).
- Adding or removing a user sends `SIGUSR1` to the running container for a live credential reload — no restart needed.
- The `mark` field (default `0x1`) maps to hev-socks5-server's user permission flags.

---

## squid-docker-manager.sh

Manages a Dockerized [Squid](http://www.squid-cache.org/) HTTP/HTTPS proxy with basic authentication, subnet ACLs, and a safe-port allowlist.

### Quick start

```bash
sudo apt-get install -y apache2-utils   # provides htpasswd

sudo ./squid-docker-manager.sh init
sudo ./squid-docker-manager.sh configure 0.0.0.0/0   # or a tighter subnet
sudo ./squid-docker-manager.sh add-user alice secret123
sudo ./squid-docker-manager.sh start
sudo ./squid-docker-manager.sh test alice secret123 http://example.com
```

### Commands

```
init                                   Create directories under /opt/squid-proxy/
configure [subnet]                     Write squid.conf (default subnet: 0.0.0.0/0)
add-user <user> [pass]                 Add or update a user (prompts if no pass given)
del-user <user>                        Remove a user
list-users                             Print all usernames
start                                  Pull image and start the container
stop                                   Stop the container
restart                                Restart the container
status                                 Show container status
logs                                   Tail container logs
test <user> <pass> <url>               Test connectivity through the proxy
show-config                            Print the active squid.conf
show-proxy-url <user> <pass> <host>    Print a ready-to-use proxy URL
destroy                                Remove the container (data/config kept)
```

### Environment overrides

| Variable | Default | Description |
|----------|---------|-------------|
| `APP_DIR` | `/opt/squid-proxy` | Base directory |
| `CONTAINER_NAME` | `squid-proxy` | Docker container name |
| `IMAGE` | `ubuntu/squid:latest` | Docker image |
| `PROXY_PORT` | `3128` | Host port to expose |
| `ALLOWED_NET` | `0.0.0.0/0` | Source subnet ACL |

### Notes

- Passwords are stored in bcrypt via `htpasswd`.
- Modifying users restarts the container automatically to pick up auth changes.
- The generated config enforces: authentication required, safe-ports allowlist, and `CONNECT` restricted to port 443.
- Logs and spool are bind-mounted to `$APP_DIR/log` and `$APP_DIR/data` so they survive container restarts.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

See [SECURITY.md](SECURITY.md).

## License

[Apache 2.0](LICENSE)
