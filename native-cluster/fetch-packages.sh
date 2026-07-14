#!/usr/bin/env bash
# fetch-packages.sh — build the offline .deb bundle for the air-gapped nodes.
#
# Run this ONCE on an INTERNET-CONNECTED Ubuntu 24.04 (noble) amd64 host (a
# staging box or VM that matches the target nodes). It downloads RabbitMQ +
# Erlang and their dependencies into ./packages/ WITHOUT installing them. Then
# copy this whole native-cluster/ directory (now including packages/) onto each
# air-gapped node, where 01-install.sh installs from it with no internet.
#
#   sudo ./fetch-packages.sh
#
# NOTE: the staging host must match the nodes' Ubuntu release and architecture,
# or the downloaded .debs won't install there.
source "$(dirname "$0")/lib.sh"
require_root
export DEBIAN_FRONTEND=noninteractive

command -v curl >/dev/null || die "curl is required on the staging host."
DPKG_ARCH="$(dpkg --print-architecture)"
log "staging host: Ubuntu ${UBUNTU_CODENAME} target, arch ${DPKG_ARCH}."

PKG_DIR="${LIB_DIR}/packages"
mkdir -p "${PKG_DIR}"

KEYRING_DIR=/usr/share/keyrings
log "installing prerequisites + signing keys (staging host only) ..."
apt-get update -y
apt-get install -y curl gnupg apt-transport-https
curl -1sLf "https://keys.openpgp.org/vks/v1/by-fingerprint/0A9AF2115F4687BD29803A206B73A36E6026DFCA" \
  | gpg --dearmor | tee "${KEYRING_DIR}/com.rabbitmq.team.gpg" >/dev/null
curl -1sLf "https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-erlang.E495BB49CC4BBE5B.key" \
  | gpg --dearmor | tee "${KEYRING_DIR}/rabbitmq.E495BB49CC4BBE5B.gpg" >/dev/null
curl -1sLf "https://github.com/rabbitmq/signing-keys/releases/download/3.0/cloudsmith.rabbitmq-server.9F4587F226208342.key" \
  | gpg --dearmor | tee "${KEYRING_DIR}/rabbitmq.9F4587F226208342.gpg" >/dev/null

log "adding RabbitMQ apt repositories for ${UBUNTU_CODENAME} ..."
tee /etc/apt/sources.list.d/rabbitmq.list >/dev/null <<EOF
deb [signed-by=${KEYRING_DIR}/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa1.rabbitmq.com/rabbitmq/rabbitmq-erlang/deb/ubuntu ${UBUNTU_CODENAME} main
deb [signed-by=${KEYRING_DIR}/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa2.rabbitmq.com/rabbitmq/rabbitmq-erlang/deb/ubuntu ${UBUNTU_CODENAME} main
deb [signed-by=${KEYRING_DIR}/rabbitmq.9F4587F226208342.gpg] https://ppa1.rabbitmq.com/rabbitmq/rabbitmq-server/deb/ubuntu ${UBUNTU_CODENAME} main
deb [signed-by=${KEYRING_DIR}/rabbitmq.9F4587F226208342.gpg] https://ppa2.rabbitmq.com/rabbitmq/rabbitmq-server/deb/ubuntu ${UBUNTU_CODENAME} main
EOF
apt-get update -y

# Resolve the pinned RabbitMQ version to its exact package string.
if [[ -n "${RABBITMQ_VERSION:-}" ]]; then
  PKG_VERSION="$(apt-cache madison rabbitmq-server | awk -v v="${RABBITMQ_VERSION}" 'index($3, v)==1 {print $3; exit}')"
  [[ -n "${PKG_VERSION}" ]] || die "RabbitMQ ${RABBITMQ_VERSION} not found in the repo. Available:
$(apt-cache madison rabbitmq-server | awk '{print "  " $3}')"
  RMQ_TARGET="rabbitmq-server=${PKG_VERSION}"
else
  RMQ_TARGET="rabbitmq-server"
fi
log "bundling ${RMQ_TARGET} + Erlang + dependencies ..."

# Download the packages AND their dependency closure without installing.
# --download-only + a full dependency resolution puts everything in the apt
# cache; we clean first so we can copy exactly what this pulls.
apt-get clean
apt-get install -y --download-only --allow-downgrades \
  "${RMQ_TARGET}" \
  erlang-base \
  erlang-asn1 erlang-crypto erlang-eldap erlang-ftp erlang-inets \
  erlang-mnesia erlang-os-mon erlang-parsetools erlang-public-key \
  erlang-runtime-tools erlang-snmp erlang-ssl \
  erlang-syntax-tools erlang-tftp erlang-tools erlang-xmerl

count=0
for deb in /var/cache/apt/archives/*.deb; do
  [[ -e "$deb" ]] || continue
  cp -f "$deb" "${PKG_DIR}/"
  count=$((count + 1))
done
[[ "${count}" -gt 0 ]] || die "no .deb files ended up in the apt cache — nothing to bundle."

log "bundled ${count} .deb files into ${PKG_DIR}"
log "total size: $(du -sh "${PKG_DIR}" | cut -f1)"
log "next: copy the whole native-cluster/ directory to each air-gapped node and run 01-install.sh."
