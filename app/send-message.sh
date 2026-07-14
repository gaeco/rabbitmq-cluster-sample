#!/usr/bin/env bash
# Publish a message to the running app's POST /messages endpoint.
#
# Usage:
#   ./send-message.sh                 # sends the default content
#   ./send-message.sh "hello there"   # sends custom content
#   ./send-message.sh "msg" 5         # sends "msg #1".."msg #5"
#   HOST=localhost PORT=8080 ./send-message.sh   # override target
set -euo pipefail

HOST="${HOST:-localhost}"
PORT="${PORT:-8080}"
CONTENT="${1:-hello from curl}"
COUNT="${2:-1}"
URL="http://${HOST}:${PORT}/messages"

for i in $(seq 1 "$COUNT"); do
  if [[ "$COUNT" -gt 1 ]]; then
    body="${CONTENT} #${i}"
  else
    body="${CONTENT}"
  fi
  echo "POST ${URL}  content='${body}'"
  curl -sS -X POST "${URL}" \
    --data-urlencode "content=${body}" \
    -w '  -> HTTP %{http_code}\n'
  echo
done
