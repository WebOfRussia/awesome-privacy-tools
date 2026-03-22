#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-/opt/socks5}"
CONF_DIR="$BASE_DIR/conf"
MAIN_CONF="$CONF_DIR/main.yml"
AUTH_FILE="$CONF_DIR/auth.txt"

CONTAINER_NAME="${CONTAINER_NAME:-socks5}"
IMAGE="${IMAGE:-hev-socks5-server:latest}"
PORT="${PORT:-1080}"

usage() {
  cat <<EOF
Usage:
  sudo $0 init
  sudo $0 start
  sudo $0 stop
  sudo $0 restart
  sudo $0 status
  sudo $0 logs
  sudo $0 list-users
  sudo $0 add-user <username> <password> [mark]
  sudo $0 del-user <username>
  sudo $0 test <username> <password> <url>

Examples:
  sudo $0 init
  sudo $0 add-user alice secret123
  sudo $0 start
  sudo $0 test alice secret123 http://example.com
EOF
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run with sudo."
    exit 1
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1"
    exit 1
  }
}

init_files() {
  need_root
  mkdir -p "$CONF_DIR"

  if [[ ! -f "$MAIN_CONF" ]]; then
    cat > "$MAIN_CONF" <<EOF
main:
  workers: 4
  port: ${PORT}
  listen-address: '::'
  listen-ipv6-only: false

auth:
  file: /etc/hev-socks5-server/auth.txt

misc:
  log-file: stderr
  log-level: warn
EOF
  fi

  touch "$AUTH_FILE"
  chmod 600 "$AUTH_FILE"

  echo "Initialized:"
  echo "  $MAIN_CONF"
  echo "  $AUTH_FILE"
}

start_container() {
  need_root
  require_cmd docker

  [[ -f "$MAIN_CONF" ]] || { echo "Missing $MAIN_CONF"; exit 1; }
  [[ -f "$AUTH_FILE" ]] || { echo "Missing $AUTH_FILE"; exit 1; }

  # docker pull "$IMAGE" >/dev/null

  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

  docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p "${PORT}:1080" \
    -v "${MAIN_CONF}:/etc/hev-socks5-server/main.yml:ro" \
    -v "${AUTH_FILE}:/etc/hev-socks5-server/auth.txt" \
    "$IMAGE" \
    /etc/hev-socks5-server/main.yml >/dev/null

  echo "Started $CONTAINER_NAME on port $PORT"
}

stop_container() {
  need_root
  require_cmd docker
  docker stop "$CONTAINER_NAME"
}

restart_container() {
  need_root
  require_cmd docker
  docker restart "$CONTAINER_NAME"
}

status_container() {
  require_cmd docker
  docker ps -a --filter "name=^${CONTAINER_NAME}$"
}

logs_container() {
  require_cmd docker
  docker logs -f "$CONTAINER_NAME"
}

list_users() {
  [[ -f "$AUTH_FILE" ]] || { echo "Missing $AUTH_FILE"; exit 1; }
  awk '{print $1}' "$AUTH_FILE"
}

reload_auth() {
  if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    docker kill -s SIGUSR1 "$CONTAINER_NAME" >/dev/null
  fi
}

add_user() {
  need_root

  local user="${1:-}"
  local pass="${2:-}"
  local mark="${3:-0x1}"

  [[ -n "$user" && -n "$pass" ]] || {
    echo "Usage: $0 add-user <username> <password> [mark]"
    exit 1
  }

  touch "$AUTH_FILE"
  chmod 600 "$AUTH_FILE"

  if grep -qE "^${user}[[:space:]]" "$AUTH_FILE"; then
    awk -v u="$user" -v p="$pass" -v m="$mark" '
      $1 == u {$2=p; $3=m; print; next}
      {print}
    ' "$AUTH_FILE" > "${AUTH_FILE}.tmp"
    mv "${AUTH_FILE}.tmp" "$AUTH_FILE"
    echo "Updated user: $user"
  else
    printf '%s %s %s\n' "$user" "$pass" "$mark" >> "$AUTH_FILE"
    echo "Added user: $user"
  fi

  reload_auth
}

del_user() {
  need_root
  local user="${1:-}"

  [[ -n "$user" ]] || {
    echo "Usage: $0 del-user <username>"
    exit 1
  }

  [[ -f "$AUTH_FILE" ]] || { echo "Missing $AUTH_FILE"; exit 1; }

  grep -vE "^${user}[[:space:]]" "$AUTH_FILE" > "${AUTH_FILE}.tmp"
  mv "${AUTH_FILE}.tmp" "$AUTH_FILE"
  chmod 600 "$AUTH_FILE"

  echo "Deleted user: $user"
  reload_auth
}

test_proxy() {
  require_cmd curl

  local user="${1:-}"
  local pass="${2:-}"
  local url="${3:-}"

  [[ -n "$user" && -n "$pass" && -n "$url" ]] || {
    echo "Usage: $0 test <username> <password> <url>"
    exit 1
  }

  curl --socks5 "${user}:${pass}@127.0.0.1:${PORT}" "$url"
}

case "${1:-}" in
  init) shift; init_files ;;
  start) shift; start_container ;;
  stop) shift; stop_container ;;
  restart) shift; restart_container ;;
  status) shift; status_container ;;
  logs) shift; logs_container ;;
  list-users) shift; list_users ;;
  add-user) shift; add_user "${1:-}" "${2:-}" "${3:-}" ;;
  del-user) shift; del_user "${1:-}" ;;
  test) shift; test_proxy "${1:-}" "${2:-}" "${3:-}" ;;
  ""|-h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
