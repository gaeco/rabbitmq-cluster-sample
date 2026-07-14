#!/usr/bin/env bash
# Show cluster membership and running nodes.
set -euo pipefail

cd "$(dirname "$0")/.."

podman exec rabbit1 rabbitmqctl cluster_status