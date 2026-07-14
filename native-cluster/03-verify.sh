#!/usr/bin/env bash
# 03-verify.sh — show cluster status from this node. Run anywhere (as root).
#
#   sudo ./03-verify.sh
#
# Confirms all three rabbit@rabbitN nodes are running and clustered.
source "$(dirname "$0")/lib.sh"
require_root
detect_self

log "cluster status as seen from ${SELF_HOST}:"
echo
rmqctl cluster_status
echo

running="$(rmqctl -q cluster_status 2>/dev/null | tr ',' '\n' | grep -c 'rabbit@rabbit' || true)"
expected="${#NODE_HOSTS[@]}"
log "expected ${expected} member references; found ${running} in output above."
log "if a node is missing, check: same ERLANG_COOKIE, /etc/hosts resolves all \
rabbitN, and ports 4369/25672 are open between machines."
