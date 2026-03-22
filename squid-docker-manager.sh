#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/squid-proxy}"
CONF_DIR="$APP_DIR/conf"
DATA_DIR="$APP_DIR/data"
LOG_DIR="$APP_DIR/log"
PASSWD_FILE="$CONF_DIR/passwd"
SQUID_CONF="$CONF_DIR/squid.conf"

CONTAINER_NAME="${CONTAINER_NAME:-squid-proxy}"
IMAGE="${IMAGE:-ubuntu/squid:latest}"
PROXY_PORT="${PROXY_PORT:-3128}"
ALLOWED_NET="${ALLOWED_NET:-0.0.0.0/0}"

SCRIPT_NAME="$(basename "$0")"

print_usage() {
  cat <<EOF
Usage:
  sudo $SCRIPT_NAME init
  sudo $SCRIPT_NAME configure [allowed_subnet]
  sudo $SCRIPT_NAME add-user <username> [password]
  sudo $SCRIPT_NAME del-user <username>
  sudo $SCRIPT_NAME list-users
  sudo $SCRIPT_NAME start
  sudo $SCRIPT_NAME stop
  sudo $SCRIPT_NAME restart
  sudo $SCRIPT_NAME status
  sudo $SCRIPT_NAME logs
  sudo $SCRIPT_NAME test <username> <password> <target_url>
  sudo $SCRIPT_NAME show-config
  sudo $SCRIPT_NAME show-proxy-url <username> <password> <host_or_ip>
  sudo $SCRIPT_NAME destroy

Environment overrides:
  APP_DIR=/opt/squid-proxy
  CONTAINER_NAME=squid-proxy
  IMAGE=ubuntu/squid:latest
  PROXY_PORT=3128
  ALLOWED_NET=10.0.0.0/24

Examples:
  sudo $SCRIPT_NAME init
  sudo $SCRIPT_NAME configure 10.0.0.0/24
  sudo $SCRIPT_NAME add-user alice
  sudo $SCRIPT_NAME start
  sudo $SCRIPT_NAME test alice 'secret123' http://example.com
  sudo $SCRIPT_NAME show-proxy-url alice 'secret123' 203.0.113.10
EOF
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run as root or with sudo."
    exit 1
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd"
    exit 1
  fi
}

init_dirs() {
  need_root
  mkdir -p "$CONF_DIR" "$DATA_DIR" "$LOG_DIR"
  chmod 700 "$CONF_DIR"
  touch "$PASSWD_FILE"
  chmod 640 "$PASSWD_FILE"
  echo "Initialized directories under $APP_DIR"
}

write_config() {
  need_root

  mkdir -p "$CONF_DIR" "$DATA_DIR" "$LOG_DIR"

  cat > "$SQUID_CONF" <<EOF
http_port ${PROXY_PORT}

visible_hostname squid-docker-proxy

# Authentication
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm Squid Proxy
auth_param basic credentialsttl 2 hours
acl authenticated proxy_auth REQUIRED

# Source restrictions
acl localhost src 127.0.0.1/32 ::1
acl allowed_net src ${ALLOWED_NET}

# Safe ports
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 21
acl Safe_ports port 443
acl Safe_ports port 70
acl Safe_ports port 210
acl Safe_ports port 1025-65535
acl Safe_ports port 280
acl Safe_ports port 488
acl Safe_ports port 591
acl Safe_ports port 777
acl CONNECT method CONNECT

# Security
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports

# Require auth and subnet restriction
http_access allow localhost
http_access allow authenticated allowed_net
http_access deny all

# Logging
access_log stdio:/var/log/squid/access.log
cache_log /var/log/squid/cache.log

# Cache/storage
coredump_dir /var/spool/squid
cache_mem 128 MB
maximum_object_size_in_memory 512 KB
EOF

  chmod 644 "$SQUID_CONF"
  echo "Wrote config to $SQUID_CONF"
  echo "Allowed subnet: $ALLOWED_NET"
}

start_container() {
  need_root
  require_cmd docker

  [[ -f "$SQUID_CONF" ]] || { echo "Missing $SQUID_CONF. Run: $SCRIPT_NAME init && $SCRIPT_NAME configure"; exit 1; }
  [[ -f "$PASSWD_FILE" ]] || { echo "Missing $PASSWD_FILE. Run: $SCRIPT_NAME add-user <username>"; exit 1; }

  docker pull "$IMAGE"

  if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  fi

  docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p "${PROXY_PORT}:${PROXY_PORT}" \
    -v "${SQUID_CONF}:/etc/squid/squid.conf:ro" \
    -v "${PASSWD_FILE}:/etc/squid/passwd:ro" \
    -v "${DATA_DIR}:/var/spool/squid" \
    -v "${LOG_DIR}:/var/log/squid" \
    "$IMAGE" >/dev/null

  echo "Container started: $CONTAINER_NAME"
  echo "Listening on port: $PROXY_PORT"
}

stop_container() {
  need_root
  require_cmd docker
  if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    docker stop "$CONTAINER_NAME" >/dev/null
    echo "Container stopped."
  else
    echo "Container not found."
  fi
}

restart_container() {
  need_root
  require_cmd docker
  if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    docker restart "$CONTAINER_NAME" >/dev/null
    echo "Container restarted."
  else
    echo "Container not found. Starting a new one."
    start_container
  fi
}

status_container() {
  require_cmd docker
  if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    docker ps -a --filter "name=^${CONTAINER_NAME}$"
  else
    echo "Container not found."
  fi
}

logs_container() {
  require_cmd docker
  docker logs -f "$CONTAINER_NAME"
}

add_user() {
  need_root
  require_cmd htpasswd

  local username="${1:-}"
  local password="${2:-}"

  [[ -n "$username" ]] || { echo "Usage: $SCRIPT_NAME add-user <username> [password]"; exit 1; }

  mkdir -p "$CONF_DIR"
  touch "$PASSWD_FILE"
  chmod 640 "$PASSWD_FILE"

  if grep -qE "^${username}:" "$PASSWD_FILE" 2>/dev/null; then
    if [[ -n "$password" ]]; then
      htpasswd -b "$PASSWD_FILE" "$username" "$password"
    else
      htpasswd "$PASSWD_FILE" "$username"
    fi
    echo "Updated user: $username"
  else
    if [[ ! -s "$PASSWD_FILE" ]]; then
      if [[ -n "$password" ]]; then
        htpasswd -cb "$PASSWD_FILE" "$username" "$password"
      else
        htpasswd -c "$PASSWD_FILE" "$username"
      fi
    else
      if [[ -n "$password" ]]; then
        htpasswd -b "$PASSWD_FILE" "$username" "$password"
      else
        htpasswd "$PASSWD_FILE" "$username"
      fi
    fi
    echo "Added user: $username"
  fi

  if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    docker restart "$CONTAINER_NAME" >/dev/null
    echo "Container restarted to pick up auth changes."
  fi
}

del_user() {
  need_root

  local username="${1:-}"
  [[ -n "$username" ]] || { echo "Usage: $SCRIPT_NAME del-user <username>"; exit 1; }

  [[ -f "$PASSWD_FILE" ]] || { echo "No passwd file found."; exit 1; }
  grep -qE "^${username}:" "$PASSWD_FILE" || { echo "User not found: $username"; exit 1; }

  cp "$PASSWD_FILE" "${PASSWD_FILE}.bak"
  grep -vE "^${username}:" "$PASSWD_FILE" > "${PASSWD_FILE}.tmp"
  mv "${PASSWD_FILE}.tmp" "$PASSWD_FILE"
  chmod 640 "$PASSWD_FILE"

  echo "Deleted user: $username"

  if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    docker restart "$CONTAINER_NAME" >/dev/null
    echo "Container restarted to pick up auth changes."
  fi
}

list_users() {
  [[ -f "$PASSWD_FILE" ]] || { echo "No passwd file found."; exit 1; }
  cut -d: -f1 "$PASSWD_FILE"
}

test_proxy() {
  require_cmd curl

  local username="${1:-}"
  local password="${2:-}"
  local target_url="${3:-}"

  [[ -n "$username" && -n "$password" && -n "$target_url" ]] || {
    echo "Usage: $SCRIPT_NAME test <username> <password> <target_url>"
    exit 1
  }

  curl -I -x "http://${username}:${password}@127.0.0.1:${PROXY_PORT}" "$target_url"
}

show_config() {
  [[ -f "$SQUID_CONF" ]] || { echo "No config found."; exit 1; }
  cat "$SQUID_CONF"
}

show_proxy_url() {
  local username="${1:-}"
  local password="${2:-}"
  local host="${3:-}"

  [[ -n "$username" && -n "$password" && -n "$host" ]] || {
    echo "Usage: $SCRIPT_NAME show-proxy-url <username> <password> <host_or_ip>"
    exit 1
  }

  echo "http://${username}:${password}@${host}:${PROXY_PORT}"
}

destroy_all() {
  need_root
  require_cmd docker

  if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    docker rm -f "$CONTAINER_NAME" >/dev/null
    echo "Removed container: $CONTAINER_NAME"
  else
    echo "Container not found."
  fi
}

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    init)
      init_dirs
      ;;
    configure)
      if [[ $# -ge 1 ]]; then
        ALLOWED_NET="$1"
      fi
      write_config
      ;;
    add-user)
      add_user "${1:-}" "${2:-}"
      ;;
    del-user)
      del_user "${1:-}"
      ;;
    list-users)
      list_users
      ;;
    start)
      start_container
      ;;
    stop)
      stop_container
      ;;
    restart)
      restart_container
      ;;
    status)
      status_container
      ;;
    logs)
      logs_container
      ;;
    test)
      test_proxy "${1:-}" "${2:-}" "${3:-}"
      ;;
    show-config)
      show_config
      ;;
    show-proxy-url)
      show_proxy_url "${1:-}" "${2:-}" "${3:-}"
      ;;
    destroy)
      destroy_all
      ;;
    ""|-h|--help|help)
      print_usage
      ;;
    *)
      echo "Unknown command: $cmd"
      echo
      print_usage
      exit 1
      ;;
  esac
}

main "$@"
