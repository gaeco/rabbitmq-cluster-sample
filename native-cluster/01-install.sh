#!/usr/bin/env bash
# 01-install.sh — install Erlang + RabbitMQ from the apt mirror. Run on EVERY
# node (as root / with sudo).
#
#   sudo ./01-install.sh
#
# Ubuntu 24.04 ships rabbitmq-server (3.12.x) in its 'universe' repository, so
# this is a plain apt install — no external repos, keys, or offline bundle. It
# works air-gapped as long as the internal apt mirror carries the Ubuntu
# archive (rabbitmq-server + erlang). Erlang is pulled in automatically as a
# dependency.
source "$(dirname "$0")/lib.sh"
require_root
export DEBIAN_FRONTEND=noninteractive

log "installing rabbitmq-server from the apt mirror ..."
apt-get update -y
apt-get install -y rabbitmq-server

installed="$(dpkg-query -W -f='${Version}' rabbitmq-server 2>/dev/null || true)"
[[ -n "${installed}" ]] || die "rabbitmq-server is not installed after the install step."

# Leave it enabled (starts on boot); 02-configure.sh restarts it with the
# shared cookie and cluster config.
systemctl enable rabbitmq-server

log "install complete. RabbitMQ: ${installed}, Erlang: $(erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell 2>/dev/null || echo '?')"
log "next: run 02-configure.sh on this node."
