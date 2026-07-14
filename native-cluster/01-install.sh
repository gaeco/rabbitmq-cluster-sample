#!/usr/bin/env bash
# 01-install.sh — install Erlang + RabbitMQ on an AIR-GAPPED node. Run on EVERY
# node (as root / with sudo).
#
#   sudo ./01-install.sh
#
# The nodes have no internet access, so this script never contacts the RabbitMQ
# signing-key servers or ppa*.rabbitmq.com. It installs either from a pre-staged
# local .deb bundle (INSTALL_SOURCE=offline-debs, the default) or from the
# internal apt mirror (INSTALL_SOURCE=apt-repo). See cluster.env.
#
# To build the offline bundle, run fetch-packages.sh on an internet-connected
# Ubuntu 24.04 (noble) amd64 host, then copy this whole directory to the nodes.
source "$(dirname "$0")/lib.sh"
require_root
export DEBIAN_FRONTEND=noninteractive

PKG_DIR="${OFFLINE_DEB_DIR:-${LIB_DIR}/packages}"

# The Erlang packages RabbitMQ needs (used for the apt-repo path).
ERLANG_PKGS=(erlang-base
  erlang-asn1 erlang-crypto erlang-eldap erlang-ftp erlang-inets
  erlang-mnesia erlang-os-mon erlang-parsetools erlang-public-key
  erlang-runtime-tools erlang-snmp erlang-ssl
  erlang-syntax-tools erlang-tftp erlang-tools erlang-xmerl)

install_from_debs() {
  shopt -s nullglob
  local debs=("${PKG_DIR}"/*.deb)
  [[ ${#debs[@]} -gt 0 ]] || die "no .deb files in ${PKG_DIR}.
Build the bundle on an internet-connected Ubuntu ${UBUNTU_CODENAME} amd64 host with
./fetch-packages.sh, then copy this directory (including packages/) to the node."
  log "installing ${#debs[@]} local .deb packages from ${PKG_DIR} (offline) ..."
  # apt resolves dependencies among the bundled .debs and pulls only base OS
  # packages (libc, etc.) from the internal mirror — no external repos involved.
  apt-get install -y --allow-downgrades "${debs[@]}"
}

install_from_apt_repo() {
  log "installing from the internal apt mirror ..."
  apt-get update -y
  log "installing Erlang ..."
  apt-get install -y "${ERLANG_PKGS[@]}"

  if [[ -n "${RABBITMQ_VERSION:-}" ]]; then
    local pkg_version
    pkg_version="$(apt-cache madison rabbitmq-server | awk -v v="${RABBITMQ_VERSION}" 'index($3, v)==1 {print $3; exit}')"
    [[ -n "${pkg_version}" ]] || die "RabbitMQ ${RABBITMQ_VERSION} not found on the internal mirror. Available:
$(apt-cache madison rabbitmq-server | awk '{print "  " $3}')"
    log "installing rabbitmq-server ${pkg_version} (pinned to ${RABBITMQ_VERSION}) ..."
    apt-get install -y --allow-downgrades "rabbitmq-server=${pkg_version}"
  else
    log "installing rabbitmq-server (latest available) ..."
    apt-get install -y rabbitmq-server
  fi
}

case "${INSTALL_SOURCE:-offline-debs}" in
  offline-debs) install_from_debs ;;
  apt-repo)     install_from_apt_repo ;;
  *)            die "unknown INSTALL_SOURCE='${INSTALL_SOURCE}' (use offline-debs or apt-repo)." ;;
esac

# Confirm the pinned version landed (warn, don't fail — the bundle may legitimately differ).
installed="$(dpkg-query -W -f='${Version}' rabbitmq-server 2>/dev/null || true)"
[[ -n "${installed}" ]] || die "rabbitmq-server is not installed after the install step."
if [[ -n "${RABBITMQ_VERSION:-}" && "${installed}" != "${RABBITMQ_VERSION}"* ]]; then
  warn "installed rabbitmq-server is ${installed}, expected ${RABBITMQ_VERSION}*."
fi

# Keep unattended upgrades from moving off the installed version.
apt-mark hold rabbitmq-server erlang-base >/dev/null 2>&1 || true

# Leave it enabled (starts on boot); 02-configure.sh restarts it with the
# shared cookie and cluster config.
systemctl enable rabbitmq-server

log "install complete. RabbitMQ: ${installed}, Erlang: $(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell 2>/dev/null || echo '?')"
log "next: run 02-configure.sh on this node."
