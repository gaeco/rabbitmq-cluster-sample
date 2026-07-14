#!/usr/bin/env bash
# 02-configure.sh — configure this node so the three brokers can form a cluster.
# Run on EVERY node (as root / with sudo), seed node (rabbit1) first.
#
#   sudo ./02-configure.sh
#
# It makes all three node names resolvable (/etc/hosts), pins this node's
# RabbitMQ node name (leaving the OS hostname unchanged), relocates the data
# directory, installs the shared Erlang cookie, writes rabbitmq.conf
# (static/classic_config peer discovery, same as the Podman setup) + enables the
# management plugin, and restarts the broker. (No local firewall is configured on
# these nodes, so no ports are opened here.)
source "$(dirname "$0")/lib.sh"
require_root
detect_self

RMQ_HOME="${RABBITMQ_HOME:-/var/lib/rabbitmq}"

log "this is node #${SELF_INDEX}: ${SELF_HOST} (${SELF_IP})"

# NOTE: the OS hostname is left untouched. Instead we pin RABBITMQ_NODENAME
# below (in rabbitmq-env.conf) so this node is rabbit@${SELF_HOST} regardless of
# the machine's hostname, and /etc/hosts makes those names resolvable.

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

# --- relocate RabbitMQ's home / data directory ----------------------------
# Move the cookie, mnesia data and logs to RMQ_HOME. We set the rabbitmq user's
# home (so CLI tools find the cookie), point the data/log dirs via
# rabbitmq-env.conf, and override the systemd unit's HOME/WorkingDirectory (and
# ReadWritePaths, in case the packaged unit sandboxes the filesystem).
log "relocating RabbitMQ home/data to ${RMQ_HOME} ..."
install -d -o rabbitmq -g rabbitmq -m 0750 "${RMQ_HOME}"
usermod -d "${RMQ_HOME}" rabbitmq

install -d -m 0755 /etc/rabbitmq
{
  echo "# Managed by native-cluster/02-configure.sh — do not edit by hand."
  echo "HOME=${RMQ_HOME}"
  echo "RABBITMQ_MNESIA_BASE=${RMQ_HOME}/mnesia"
  echo "RABBITMQ_LOG_BASE=${RMQ_HOME}/log"
  # Pin the node name so it doesn't depend on the OS hostname. Uses a short name
  # (rabbit@rabbit1), resolved to this node's IP via the /etc/hosts block above.
  echo "RABBITMQ_NODENAME=rabbit@${SELF_HOST}"
} > /etc/rabbitmq/rabbitmq-env.conf
chmod 644 /etc/rabbitmq/rabbitmq-env.conf

install -d -m 0755 /etc/systemd/system/rabbitmq-server.service.d
{
  echo "# Managed by native-cluster/02-configure.sh"
  echo "[Service]"
  echo "Environment=HOME=${RMQ_HOME}"
  echo "WorkingDirectory=${RMQ_HOME}"
  echo "ReadWritePaths=${RMQ_HOME}"
} > /etc/systemd/system/rabbitmq-server.service.d/override.conf
systemctl daemon-reload

# --- shared Erlang cookie -------------------------------------------------
if [[ "${ERLANG_COOKIE}" == *CHANGE_ME* ]]; then
  warn "ERLANG_COOKIE in cluster.env still has a placeholder value — set a real secret!"
fi
log "installing shared Erlang cookie ..."
COOKIE_FILE="${RMQ_HOME}/.erlang.cookie"
printf '%s' "${ERLANG_COOKIE}" > "${COOKIE_FILE}"
chown rabbitmq:rabbitmq "${COOKIE_FILE}"
chmod 400 "${COOKIE_FILE}"

# A stale node dir from the package's first boot (rabbit@<old-hostname>) is
# harmless, but clear it so this node starts clean under its new name.
rm -rf "${RMQ_HOME}/mnesia" 2>/dev/null || true

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

# --- ports ----------------------------------------------------------------
# No local firewall is configured on these nodes, so nothing to open here.
# Ensure the network path between nodes allows: 4369 (epmd), 25672 (inter-node),
# 5672 (AMQP), 15672 (management UI).

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
