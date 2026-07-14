#!/usr/bin/env bash
# deploy-all.sh — OPTIONAL orchestrator. Run from a control machine (your
# laptop, or one of the nodes) that can SSH into all three nodes as a
# sudo-capable user. It copies this directory to each node and runs the install
# + configure steps in the right order (seed first), then creates the admin user
# and prints the cluster status.
#
#   SSH_USER=ubuntu ./deploy-all.sh
#   SSH_USER=ubuntu SSH_KEY=~/.ssh/id_ed25519 ./deploy-all.sh
#
# Requirements: passwordless (or agent-backed) SSH to each node, and passwordless
# sudo on each node. Nothing here needs root on the control machine.
source "$(dirname "$0")/lib.sh"   # for NODE_IPS / NODE_HOSTS / SEED_INDEX / logging

SSH_USER="${SSH_USER:-$(id -un)}"
REMOTE_DIR="/tmp/native-cluster"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new)
[[ -n "${SSH_KEY:-}" ]] && SSH_OPTS+=(-i "${SSH_KEY}")

ssh_node() { ssh "${SSH_OPTS[@]}" "${SSH_USER}@$1" "$2"; }
push_dir() {
  ssh_node "$1" "rm -rf ${REMOTE_DIR} && mkdir -p ${REMOTE_DIR}"
  scp "${SSH_OPTS[@]}" -q "${LIB_DIR}"/*.sh "${LIB_DIR}/cluster.env" "${SSH_USER}@$1:${REMOTE_DIR}/"
  # For offline-debs installs, also ship the pre-staged .deb bundle.
  if [[ "${INSTALL_SOURCE:-offline-debs}" == "offline-debs" ]]; then
    [[ -d "${LIB_DIR}/packages" ]] || die "INSTALL_SOURCE=offline-debs but ${LIB_DIR}/packages is missing. \
Run fetch-packages.sh on an internet-connected host first."
    ssh_node "$1" "mkdir -p ${REMOTE_DIR}/packages"
    scp "${SSH_OPTS[@]}" -q "${LIB_DIR}"/packages/*.deb "${SSH_USER}@$1:${REMOTE_DIR}/packages/"
  fi
}

# Order the nodes with the seed first.
order=("${SEED_INDEX}")
for i in "${!NODE_IPS[@]}"; do [[ "$i" -ne "${SEED_INDEX}" ]] && order+=("$i"); done

log "==> copying scripts to all nodes"
for i in "${order[@]}"; do
  log "  ${NODE_HOSTS[$i]} (${NODE_IPS[$i]})"
  push_dir "${NODE_IPS[$i]}"
done

log "==> installing packages on all nodes (parallel-friendly, run sequentially here)"
for i in "${order[@]}"; do
  log "  install on ${NODE_HOSTS[$i]}"
  ssh_node "${NODE_IPS[$i]}" "sudo bash ${REMOTE_DIR}/01-install.sh"
done

log "==> configuring nodes, seed first"
for i in "${order[@]}"; do
  log "  configure ${NODE_HOSTS[$i]}"
  ssh_node "${NODE_IPS[$i]}" "sudo bash ${REMOTE_DIR}/02-configure.sh"
done

log "==> creating admin user on the seed node"
ssh_node "${NODE_IPS[$SEED_INDEX]}" "sudo bash ${REMOTE_DIR}/create-admin.sh"

log "==> cluster status"
ssh_node "${NODE_IPS[$SEED_INDEX]}" "sudo bash ${REMOTE_DIR}/03-verify.sh"

log "done."
