#!/usr/bin/env bash
# 02-configure.sh — configure this node so the three brokers can form a cluster.
# Run on EVERY node (as root / with sudo), seed node (rabbit1) first.
#
#   sudo ./02-configure.sh
#
# It sets the hostname, makes all three node names resolvable, installs the
# shared Erlang cookie, writes rabbitmq.conf (static/classic_config peer
# discovery, same as the Podman setup) + enables the management plugin, opens
# the firewall ports, and restarts the broker.
source "$(dirname "$0")/lib.sh"
require_root
detect_self

log "this is node #${SELF_INDEX}: ${SELF_HOST} (${SELF_IP})"

# --- hostname -------------------------------------------------------------
# RabbitMQ's node name is rabbit@<short-hostname>, so the hostname must match
# NODE_HOSTS for classic_config peer discovery to line up.
log "setting hostname to ${SELF_HOST} ..."
hostnamectl set-hostname "${SELF_HOST}"

# --- /etc/hosts -----------------------------------------------------------
# Every node must resolve every node name to its real (non-loopback) IP so the
# Erlang distribution can reach peers across machines.
log "updating /etc/hosts with the cluster members ..."
MARK_BEGIN="# >>> rabbitmq-cluster >>>"
MARK_END="# <<< rabbitmq-cluster <<<"
# Drop any previous block, then append a fresh one.
sed -i "/${MARK_BEGIN}/,/${MARK_END}/d" /etc/hosts
{
  echo "${MARK_BEGIN}"
  for i in "${!NODE_IPS[@]}"; do
    echo "${NODE_IPS[$i]} ${NODE_HOSTS[$i]}"
  done
  echo "${MARK_END}"
} >> /etc/hosts

# --- stop broker before touching the cookie / node identity ---------------
log "stopping rabbitmq-server ..."
systemctl stop rabbitmq-server || true

# --- shared Erlang cookie -------------------------------------------------
if [[ "${ERLANG_COOKIE}" == *CHANGE_ME* ]]; then
  warn "ERLANG_COOKIE in cluster.env still has a placeholder value — set a real secret!"
fi
log "installing shared Erlang cookie ..."
COOKIE_FILE=/var/lib/rabbitmq/.erlang.cookie
install -d -o rabbitmq -g rabbitmq -m 0755 /var/lib/rabbitmq
printf '%s' "${ERLANG_COOKIE}" > "${COOKIE_FILE}"
chown rabbitmq:rabbitmq "${COOKIE_FILE}"
chmod 400 "${COOKIE_FILE}"

# A stale node dir from the package's first boot (rabbit@<old-hostname>) is
# harmless, but clear it so this node starts clean under its new name.
rm -rf /var/lib/rabbitmq/mnesia 2>/dev/null || true

# --- rabbitmq.conf --------------------------------------------------------
log "writing /etc/rabbitmq/rabbitmq.conf ..."
install -d -m 0755 /etc/rabbitmq
{
  echo "# Managed by native-cluster/02-configure.sh — do not edit by hand."
  echo "listeners.tcp.default = 5672"
  echo "management.tcp.port = 15672"
  echo
  echo "# Static (classic_config) peer discovery: every node knows the full member"
  echo "# list and forms/joins the cluster automatically on boot."
  echo "cluster_formation.peer_discovery_backend = classic_config"
  for i in "${!NODE_HOSTS[@]}"; do
    echo "cluster_formation.classic_config.nodes.$((i + 1)) = rabbit@${NODE_HOSTS[$i]}"
  done
  echo
  echo "# Keep retrying while peers boot."
  echo "cluster_formation.discovery_retry_limit = 60"
  echo "cluster_formation.discovery_retry_interval = 1000"
  echo
  echo "cluster_partition_handling = pause_minority"
} > /etc/rabbitmq/rabbitmq.conf
chmod 644 /etc/rabbitmq/rabbitmq.conf

# --- plugins --------------------------------------------------------------
log "enabling the management plugin ..."
echo "[rabbitmq_management]." > /etc/rabbitmq/enabled_plugins
chmod 644 /etc/rabbitmq/enabled_plugins

# --- firewall (only if ufw is active) -------------------------------------
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  log "opening cluster ports in ufw ..."
  ufw allow 4369/tcp   >/dev/null   # epmd (Erlang port mapper)
  ufw allow 25672/tcp  >/dev/null   # inter-node / CLI Erlang distribution
  ufw allow 5672/tcp   >/dev/null   # AMQP
  ufw allow 15672/tcp  >/dev/null   # management UI
else
  warn "ufw not active — make sure these TCP ports are reachable between nodes: \
4369 (epmd), 25672 (inter-node), 5672 (AMQP), 15672 (management UI)."
fi

# --- start ----------------------------------------------------------------
log "starting rabbitmq-server ..."
systemctl start rabbitmq-server
wait_for_broker

log "node ${SELF_HOST} configured."
if [[ "${SELF_INDEX}" -eq "${SEED_INDEX}" ]]; then
  log "this is the seed node. Configure the other nodes next; they will join automatically."
else
  log "this node will discover and join rabbit@${SEED_HOST}. Verify with 03-verify.sh."
fi
