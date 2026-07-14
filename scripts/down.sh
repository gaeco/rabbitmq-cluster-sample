#!/usr/bin/env bash
# Stop the cluster. Pass --volumes (or -v) to also delete the data volumes.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--volumes" || "${1:-}" == "-v" ]]; then
  echo "Stopping cluster and removing data volumes..."
  podman compose down --volumes
else
  echo "Stopping cluster (data volumes preserved)..."
  podman compose down
fi