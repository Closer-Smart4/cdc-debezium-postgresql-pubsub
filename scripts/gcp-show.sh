#!/bin/sh
# Show the latest customer rows in BigQuery and the notify function log.
# Uses postgresql-debezium/gcp.env.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
ENV_FILE="${ROOT}/postgresql-debezium/gcp.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing ${ENV_FILE}. Copy postgresql-debezium/gcp.env.example and set GCP_PROJECT_ID." >&2
  exit 1
fi

GCP_PROJECT_ID=""
BQ_LOCATION="EU"
FUNCTION_REGION="europe-west1"
# shellcheck disable=SC1090
. "$ENV_FILE"

if [ -z "$GCP_PROJECT_ID" ] || [ "$GCP_PROJECT_ID" = "your-gcp-project-id" ]; then
  echo "Set GCP_PROJECT_ID in ${ENV_FILE}" >&2
  exit 1
fi

echo "Latest rows in ${GCP_PROJECT_ID}.debezium_cdc.customers"
bq --project_id="$GCP_PROJECT_ID" query \
  --use_legacy_sql=false \
  --location="$BQ_LOCATION" \
  --format=pretty \
  "SELECT publish_time, op, id, first_name, last_name, email
   FROM \`${GCP_PROJECT_ID}.debezium_cdc.customers\`
   ORDER BY publish_time DESC
   LIMIT 20"

echo "Recent notify-customer-change logs"
gcloud functions logs read notify-customer-change \
  --project="$GCP_PROJECT_ID" \
  --gen2 \
  --region="$FUNCTION_REGION" \
  --limit=20
