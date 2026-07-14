# lib.sh — shared helpers. Source this at the top of every node script:
#   source "$(dirname "$0")/lib.sh"
#
# It loads cluster.env, provides logging/root checks, works out which of the
# three configured nodes we are running on, and wraps rabbitmqctl so it always
# runs with the rabbitmq user's Erlang cookie.

set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cluster.env
source "${LIB_DIR}/cluster.env"

log()  { printf '\033[1;32m[%s]\033[0m %s\n' "$(hostname -s 2>/dev/null || echo node)" "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "run as root (use sudo)."
}

# List this machine's global IPv4 addresses.
local_ipv4s() {
  ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1
}

# Work out which configured node we are: sets SELF_INDEX, SELF_HOST, SELF_IP.
# Override by exporting SELF_INDEX before calling (0-based).
detect_self() {
  if [[ -n "${SELF_INDEX:-}" ]]; then
    :
  else
    local ip
    for ip in $(local_ipv4s); do
      for i in "${!NODE_IPS[@]}"; do
        if [[ "$ip" == "${NODE_IPS[$i]}" ]]; then
          SELF_INDEX="$i"
          break 2
        fi
      done
    done
  fi

  [[ -n "${SELF_INDEX:-}" ]] || die "this host's IP is not in NODE_IPS (cluster.env). \
Set SELF_INDEX=<0-based index> to override."

  SELF_HOST="${NODE_HOSTS[$SELF_INDEX]}"
  SELF_IP="${NODE_IPS[$SELF_INDEX]}"
  SEED_HOST="${NODE_HOSTS[$SEED_INDEX]}"
  export SELF_INDEX SELF_HOST SELF_IP SEED_HOST
}

# rabbitmqctl / rabbitmq-plugins that always find the shared cookie.
rmqctl()    { sudo -u rabbitmq env HOME=/var/lib/rabbitmq rabbitmqctl "$@"; }
rmqplugin() { sudo -u rabbitmq env HOME=/var/lib/rabbitmq rabbitmq-plugins "$@"; }

# Block until the local broker is running and responsive.
wait_for_broker() {
  local tries="${1:-60}"
  log "waiting for the broker to come up ..."
  for ((n = 1; n <= tries; n++)); do
    if rmqctl await_startup >/dev/null 2>&1; then
      log "broker is up."
      return 0
    fi
    sleep 2
  done
  die "broker did not become ready in time."
}
