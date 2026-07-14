#!/usr/bin/env bash
# create-admin.sh — create the cluster-wide administrator user. Run ONCE, on the
# seed node, after the cluster has formed (users replicate to all members).
#
#   sudo ./create-admin.sh
#
# The built-in "guest" user only works over loopback, so this account is what
# you use to log into the management UI / connect AMQP from other machines.
source "$(dirname "$0")/lib.sh"
require_root
detect_self

if [[ "${SELF_INDEX}" -ne "${SEED_INDEX}" ]]; then
  warn "not the seed node (${NODE_HOSTS[$SEED_INDEX]}); run this there. Continuing anyway."
fi
if [[ "${RABBITMQ_ADMIN_PASS}" == *change-me* ]]; then
  warn "RABBITMQ_ADMIN_PASS in cluster.env is still a placeholder — change it!"
fi

log "creating administrator '${RABBITMQ_ADMIN_USER}' ..."
if rmqctl -q list_users | awk '{print $1}' | grep -qx "${RABBITMQ_ADMIN_USER}"; then
  log "user already exists — resetting its password."
  rmqctl change_password "${RABBITMQ_ADMIN_USER}" "${RABBITMQ_ADMIN_PASS}"
else
  rmqctl add_user "${RABBITMQ_ADMIN_USER}" "${RABBITMQ_ADMIN_PASS}"
fi
rmqctl set_user_tags "${RABBITMQ_ADMIN_USER}" administrator
rmqctl set_permissions -p / "${RABBITMQ_ADMIN_USER}" ".*" ".*" ".*"

log "done. Log in at http://<any-node-ip>:15672 as '${RABBITMQ_ADMIN_USER}'."
