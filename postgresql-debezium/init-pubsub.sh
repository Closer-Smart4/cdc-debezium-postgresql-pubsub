#!/bin/sh
# Create the topics and pull subscriptions Debezium publishes to.
# The Pub/Sub emulator does not create them on first publish.
set -eu

HOST="${PUBSUB_HOST:-pubsub-emulator:8085}"
PROJECT="${PUBSUB_PROJECT:-local-debezium}"

TOPICS="
db-inventory.inventory.customers
db-inventory.inventory.geom
db-inventory.inventory.orders
db-inventory.inventory.products
db-inventory.inventory.products_on_hand
"

echo "Waiting for the Pub/Sub emulator at ${HOST}"
i=0
until curl -sf "http://${HOST}/v1/projects/${PROJECT}/topics" >/dev/null
do
  i=$((i + 1))
  if [ "$i" -gt 90 ]; then
    echo "Pub/Sub emulator did not become ready" >&2
    exit 1
  fi
  sleep 1
done

for name in $TOPICS; do
  echo "Creating topic and subscription ${name}"
  curl -sf -X PUT "http://${HOST}/v1/projects/${PROJECT}/topics/${name}" \
    -H "Content-Type: application/json" \
    -d "{}"
  curl -sf -X PUT "http://${HOST}/v1/projects/${PROJECT}/subscriptions/${name}" \
    -H "Content-Type: application/json" \
    -d "{\"topic\":\"projects/${PROJECT}/topics/${name}\",\"messageRetentionDuration\":\"604800s\",\"ackDeadlineSeconds\":20}"
done

echo "Pub/Sub topics are ready"
