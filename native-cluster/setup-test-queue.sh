#!/usr/bin/env bash
# setup-test-queue.sh — declare the Spring Boot app's messaging topology on the
# cluster: a durable topic exchange, a durable queue, and the binding between
# them. Uses the management HTTP API, so run it on any node once the management
# plugin is up (after 02-configure.sh) and the admin user exists (create-admin.sh).
#
#   ./setup-test-queue.sh                    # declare exchange + queue + binding
#   ./setup-test-queue.sh --publish          # also publish one test message
#   HOST=10.194.178.81 ./setup-test-queue.sh # target a specific node
#
# Declaring is idempotent (safe to re-run) and matches what the app declares on
# startup, so it never conflicts. The topology defaults below mirror
# app/src/main/resources/application.yml (app.rabbitmq.*) — override via env if
# you change them there.
source "$(dirname "$0")/lib.sh"

HOST="${HOST:-localhost}"
PORT="${PORT:-15672}"
USER="${RABBITMQ_ADMIN_USER}"
PASS="${RABBITMQ_ADMIN_PASS}"
VHOST="${VHOST:-/}"

EXCHANGE="${EXCHANGE:-sample.exchange}"
QUEUE="${QUEUE:-sample.queue}"
ROUTING_KEY="${ROUTING_KEY:-sample.key}"

# URL-encode the vhost ("/" -> "%2F"); the sample.* names need no encoding.
EVH="${VHOST//\//%2F}"
BASE="http://${HOST}:${PORT}/api"

# call METHOD PATH [JSON_BODY] DESCRIPTION — hits the management API and fails
# loudly on any HTTP >= 400. Returns the response body on stdout.
call() {
  local method="$1" path="$2" data="$3" desc="$4"
  local args=(-sS -u "${USER}:${PASS}" -H "content-type: application/json" -X "${method}" -w $'\n%{http_code}')
  [[ -n "${data}" ]] && args+=(--data "${data}")
  local out code body
  out="$(curl "${args[@]}" "${BASE}${path}")" || die "cannot reach the management API at ${BASE} — is the node up and the management plugin enabled?"
  code="${out##*$'\n'}"
  body="${out%$'\n'*}"
  if [[ "${code}" -ge 400 ]]; then
    die "${desc} failed (HTTP ${code}): ${body}"
  fi
  log "${desc} (HTTP ${code})"
  printf '%s' "${body}"
}

log "declaring topology on ${HOST} (vhost '${VHOST}') as '${USER}' ..."
call PUT  "/exchanges/${EVH}/${EXCHANGE}" '{"type":"topic","durable":true}'          "exchange '${EXCHANGE}'" >/dev/null
call PUT  "/queues/${EVH}/${QUEUE}"       '{"durable":true}'                          "queue '${QUEUE}'"       >/dev/null
call POST "/bindings/${EVH}/e/${EXCHANGE}/q/${QUEUE}" '{"routing_key":"'"${ROUTING_KEY}"'"}' "binding ${EXCHANGE} -> ${QUEUE} (${ROUTING_KEY})" >/dev/null

if [[ "${1:-}" == "--publish" ]]; then
  # Payload matches the app's SampleMessage record: {content, sentAtEpochMs}.
  inner='{"content":"hello from setup-test-queue","sentAtEpochMs":'"$(( $(date +%s) * 1000 ))"'}'
  b64="$(printf '%s' "${inner}" | base64 | tr -d '\n')"
  pub='{"properties":{"content_type":"application/json"},"routing_key":"'"${ROUTING_KEY}"'","payload":"'"${b64}"'","payload_encoding":"base64"}'
  result="$(call POST "/exchanges/${EVH}/${EXCHANGE}/publish" "${pub}" "publish test message")"
  case "${result}" in
    *'"routed":true'*)  log "test message routed to the queue." ;;
    *)                  warn "message was NOT routed — check the binding/routing key. Response: ${result}" ;;
  esac
fi

depth="$(call GET "/queues/${EVH}/${QUEUE}" "" "read queue state")"
count="$(printf '%s' "${depth}" | grep -o '"messages":[0-9]*' | head -1 | cut -d: -f2)"
log "queue '${QUEUE}' now has ${count:-?} message(s) ready."
log "done. The app consumes from '${QUEUE}' via its @RabbitListener; if it's running, published messages are consumed immediately."
