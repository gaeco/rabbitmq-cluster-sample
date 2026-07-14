#!/usr/bin/env bash
# Tail logs. Pass a node name (rabbit1|rabbit2|rabbit3) to follow one node,
# otherwise follow all of them.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -n "${1:-}" ]]; then
  podman logs -f "$1"
else
  podman compose logs -f
fi