#!/usr/bin/env bash
# Start the 3-node RabbitMQ cluster and wait for it to form.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Starting RabbitMQ cluster..."
podman compose up -d

echo "Waiting for rabbit1 to become healthy..."
for i in $(seq 1 30); do
  if podman exec rabbit1 rabbitmq-diagnostics -q ping >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo "Cluster status:"
podman exec rabbit1 rabbitmqctl cluster_status

cat <<'EOF'

Cluster is up. Management UIs (user/pass: guest/guest):
  rabbit1 -> http://localhost:15672
  rabbit2 -> http://localhost:15673
  rabbit3 -> http://localhost:15674

AMQP endpoints: localhost:5672, localhost:5673, localhost:5674
EOF