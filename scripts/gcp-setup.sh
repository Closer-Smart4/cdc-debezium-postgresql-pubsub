#!/bin/sh
# Create the Google Cloud resources for this PoC.
#
# Five topics, one per inventory table. Four of them have a single pull
# subscription. db-inventory.inventory.customers has two subscriptions:
# one writes the raw message into BigQuery, and one pushes it to the notify
# function. The function logs the change and keeps customers_current aligned
# with the PostgreSQL customers table.
#
# Requires a logged-in gcloud user who can create resources in the project.
# The JSON key written for Debezium is gitignored.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
ENV_FILE="${ROOT}/postgresql-debezium/gcp.env"
PROJECT=""
LOCATION=""
REGION=""

usage() {
  echo "Usage: scripts/gcp-setup.sh" >&2
  echo "Reads GCP_PROJECT_ID, BQ_LOCATION, and FUNCTION_REGION from ${ENV_FILE}." >&2
  echo "Optional overrides: --project PROJECT_ID --location EU --region europe-west1" >&2
  exit 2
}

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  PROJECT=${GCP_PROJECT_ID:-}
  LOCATION=${BQ_LOCATION:-}
  REGION=${FUNCTION_REGION:-}
fi
if [ "$PROJECT" = "your-gcp-project-id" ]; then
  PROJECT=""
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      PROJECT=${2:?}
      shift 2
      ;;
    --location)
      LOCATION=${2:?}
      shift 2
      ;;
    --region)
      REGION=${2:?}
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

if [ -z "$PROJECT" ]; then
  echo "Set GCP_PROJECT_ID in ${ENV_FILE}. Copy postgresql-debezium/gcp.env.example if you do not have that file yet." >&2
  usage
fi
LOCATION=${LOCATION:-EU}
REGION=${REGION:-europe-west1}

if ! command -v gcloud >/dev/null 2>&1 || ! command -v bq >/dev/null 2>&1; then
  echo "Install the Google Cloud SDK (gcloud and bq) and run gcloud auth login" >&2
  exit 1
fi

TOPICS="
db-inventory.inventory.customers
db-inventory.inventory.geom
db-inventory.inventory.orders
db-inventory.inventory.products
db-inventory.inventory.products_on_hand
"
CUSTOMERS_TOPIC="db-inventory.inventory.customers"
BQ_SUBSCRIPTION="db-inventory.inventory.customers-bq"
NOTIFY_SUBSCRIPTION="db-inventory.inventory.customers-notify"
DATASET="debezium_cdc"
TABLE="customers_changes"
MIRROR_TABLE="customers_current"
PUBLISHER_SA="debezium-publisher"
PUSH_SA="pubsub-push"
FUNCTION="notify-customer-change"
KEY_FILE="${ROOT}/postgresql-debezium/keys/gcp-sa.json"

echo "Enabling APIs on ${PROJECT}"
gcloud services enable \
  pubsub.googleapis.com \
  bigquery.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  --project="$PROJECT"

ensure_topic() {
  name=$1
  if gcloud pubsub topics describe "$name" --project="$PROJECT" >/dev/null 2>&1; then
    echo "Topic ${name} already exists"
  else
    echo "Creating topic ${name}"
    gcloud pubsub topics create "$name" --project="$PROJECT"
  fi
}

ensure_pull() {
  name=$1
  if gcloud pubsub subscriptions describe "$name" --project="$PROJECT" >/dev/null 2>&1; then
    echo "Pull subscription ${name} already exists"
  else
    echo "Creating pull subscription ${name}"
    gcloud pubsub subscriptions create "$name" \
      --project="$PROJECT" \
      --topic="$name" \
      --message-retention-duration=7d \
      --expiration-period=never
  fi
}

for name in $TOPICS; do
  ensure_topic "$name"
  if [ "$name" != "$CUSTOMERS_TOPIC" ]; then
    ensure_pull "$name"
  fi
done

wait_for_service_account() {
  email=$1
  echo "Waiting until ${email} is visible to IAM"
  i=0
  while [ "$i" -lt 30 ]; do
    if gcloud iam service-accounts describe "$email" --project="$PROJECT" >/dev/null 2>&1; then
      return 0
    fi
    i=$((i + 1))
    sleep 2
  done
  echo "Service account ${email} was not visible yet. Run this script again." >&2
  exit 1
}

echo "Preparing publisher service account"
PUBLISHER_EMAIL="${PUBLISHER_SA}@${PROJECT}.iam.gserviceaccount.com"
if ! gcloud iam service-accounts describe "$PUBLISHER_EMAIL" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$PUBLISHER_SA" \
    --project="$PROJECT" \
    --display-name="Debezium publisher"
fi
wait_for_service_account "$PUBLISHER_EMAIL"
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${PUBLISHER_EMAIL}" \
  --role="roles/pubsub.publisher" \
  --quiet >/dev/null
CREDENTIALS_FILE=""
if [ -s "$KEY_FILE" ]; then
  CREDENTIALS_FILE="$KEY_FILE"
  echo "Key already present at ${KEY_FILE}"
else
  mkdir -p "$(dirname "$KEY_FILE")"
  key_err=$(mktemp)
  if gcloud iam service-accounts keys create "$KEY_FILE" \
    --project="$PROJECT" \
    --iam-account="$PUBLISHER_EMAIL" 2>"$key_err"
  then
    chmod 600 "$KEY_FILE"
    CREDENTIALS_FILE="$KEY_FILE"
    echo "Wrote ${KEY_FILE}"
  elif grep -q "iam.disableServiceAccountKeyCreation" "$key_err"; then
    rm -f "$KEY_FILE"
    echo "This project does not allow service account keys."
    echo "Debezium will publish with your user account instead."
    account=$(gcloud config get-value account)
    gcloud projects add-iam-policy-binding "$PROJECT" \
      --member="user:${account}" \
      --role="roles/pubsub.publisher" \
      --quiet >/dev/null
    adc="${HOME}/.config/gcloud/application_default_credentials.json"
    if [ ! -f "$adc" ]; then
      rm -f "$key_err"
      echo "Run: gcloud beta auth login --update-adc" >&2
      echo "Allow Cloud Platform access on the consent screen, then run scripts/gcp-setup.sh again." >&2
      exit 1
    fi
    gcloud auth application-default set-quota-project "$PROJECT"
    CREDENTIALS_FILE="$adc"
  else
    cat "$key_err" >&2
    rm -f "$key_err"
    exit 1
  fi
  rm -f "$key_err"
fi

echo "Preparing BigQuery dataset ${DATASET} in ${LOCATION}"
if ! bq --project_id="$PROJECT" show --dataset "${PROJECT}:${DATASET}" >/dev/null 2>&1; then
  bq --project_id="$PROJECT" --location="$LOCATION" mk --dataset "${PROJECT}:${DATASET}"
fi
bq --project_id="$PROJECT" query --use_legacy_sql=false --location="$LOCATION" "
CREATE TABLE IF NOT EXISTS \`${PROJECT}.${DATASET}.${TABLE}\` (
  data JSON,
  subscription_name STRING,
  message_id STRING,
  publish_time TIMESTAMP,
  attributes JSON
);
CREATE OR REPLACE VIEW \`${PROJECT}.${DATASET}.customers\` AS
SELECT
  publish_time,
  JSON_VALUE(data, '$.payload.op') AS op,
  JSON_VALUE(data, '$.payload.after.id') AS id,
  JSON_VALUE(data, '$.payload.after.first_name') AS first_name,
  JSON_VALUE(data, '$.payload.after.last_name') AS last_name,
  JSON_VALUE(data, '$.payload.after.email') AS email
FROM \`${PROJECT}.${DATASET}.${TABLE}\`;
CREATE TABLE IF NOT EXISTS \`${PROJECT}.${DATASET}.${MIRROR_TABLE}\` (
  id INT64 NOT NULL,
  first_name STRING NOT NULL,
  last_name STRING NOT NULL,
  email STRING NOT NULL
);
MERGE \`${PROJECT}.${DATASET}.${MIRROR_TABLE}\` T
USING (
  SELECT id, first_name, last_name, email
  FROM (
    SELECT
      JSON_VALUE(data, '$.payload.op') AS op,
      SAFE_CAST(JSON_VALUE(data, '$.payload.after.id') AS INT64) AS id,
      IFNULL(JSON_VALUE(data, '$.payload.after.first_name'), '') AS first_name,
      IFNULL(JSON_VALUE(data, '$.payload.after.last_name'), '') AS last_name,
      IFNULL(JSON_VALUE(data, '$.payload.after.email'), '') AS email,
      ROW_NUMBER() OVER (
        PARTITION BY JSON_VALUE(data, '$.payload.after.id')
        ORDER BY publish_time DESC
      ) AS rn
    FROM \`${PROJECT}.${DATASET}.${TABLE}\`
    WHERE JSON_VALUE(data, '$.payload.op') != 'd'
  )
  WHERE rn = 1 AND id IS NOT NULL
) S
ON T.id = S.id
WHEN MATCHED THEN
  UPDATE SET first_name = S.first_name, last_name = S.last_name, email = S.email
WHEN NOT MATCHED THEN
  INSERT (id, first_name, last_name, email)
  VALUES (S.id, S.first_name, S.last_name, S.email);
DELETE FROM \`${PROJECT}.${DATASET}.${MIRROR_TABLE}\`
WHERE CAST(id AS STRING) IN (
  SELECT id
  FROM (
    SELECT
      JSON_VALUE(data, '$.payload.op') AS op,
      COALESCE(
        JSON_VALUE(data, '$.payload.before.id'),
        JSON_VALUE(data, '$.payload.after.id')
      ) AS id,
      ROW_NUMBER() OVER (
        PARTITION BY COALESCE(
          JSON_VALUE(data, '$.payload.before.id'),
          JSON_VALUE(data, '$.payload.after.id')
        )
        ORDER BY publish_time DESC
      ) AS rn
    FROM \`${PROJECT}.${DATASET}.${TABLE}\`
  )
  WHERE rn = 1 AND op = 'd'
);
"

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')
PUBSUB_AGENT_EMAIL="service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"
PUBSUB_AGENT="serviceAccount:${PUBSUB_AGENT_EMAIL}"
echo "Ensuring the Pub/Sub service agent exists"
gcloud beta services identity create \
  --service=pubsub.googleapis.com \
  --project="$PROJECT" >/dev/null
echo "Granting the Pub/Sub service agent access to ${DATASET}"
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="$PUBSUB_AGENT" \
  --role="roles/bigquery.dataEditor" \
  --quiet >/dev/null
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="$PUBSUB_AGENT" \
  --role="roles/bigquery.metadataViewer" \
  --quiet >/dev/null

if gcloud pubsub subscriptions describe "$BQ_SUBSCRIPTION" --project="$PROJECT" >/dev/null 2>&1; then
  echo "BigQuery subscription ${BQ_SUBSCRIPTION} already exists"
else
  echo "Creating BigQuery subscription ${BQ_SUBSCRIPTION}"
  gcloud pubsub subscriptions create "$BQ_SUBSCRIPTION" \
    --project="$PROJECT" \
    --topic="$CUSTOMERS_TOPIC" \
    --bigquery-table="${PROJECT}:${DATASET}.${TABLE}" \
    --write-metadata
fi

COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
echo "Granting Cloud Build access to ${COMPUTE_SA}"
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/cloudbuild.builds.builder" \
  --quiet >/dev/null
echo "Granting ${COMPUTE_SA} access to write ${MIRROR_TABLE}"
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/bigquery.dataEditor" \
  --quiet >/dev/null
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/bigquery.jobUser" \
  --quiet >/dev/null

echo "Deploying ${FUNCTION}"
gcloud functions deploy "$FUNCTION" \
  --project="$PROJECT" \
  --gen2 \
  --runtime=python312 \
  --region="$REGION" \
  --source="${ROOT}/scripts/notify" \
  --entry-point=notify_customer_change \
  --trigger-http \
  --no-allow-unauthenticated \
  --set-env-vars="GCP_PROJECT=${PROJECT},BQ_DATASET=${DATASET},BQ_TABLE=${MIRROR_TABLE},BQ_LOCATION=${LOCATION}" \
  --quiet

PUSH_EMAIL="${PUSH_SA}@${PROJECT}.iam.gserviceaccount.com"
if ! gcloud iam service-accounts describe "$PUSH_EMAIL" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$PUSH_SA" \
    --project="$PROJECT" \
    --display-name="Pub/Sub push to notify"
fi
wait_for_service_account "$PUSH_EMAIL"
gcloud run services add-iam-policy-binding "$FUNCTION" \
  --project="$PROJECT" \
  --region="$REGION" \
  --member="serviceAccount:${PUSH_EMAIL}" \
  --role="roles/run.invoker" \
  --quiet >/dev/null
gcloud iam service-accounts add-iam-policy-binding "$PUSH_EMAIL" \
  --project="$PROJECT" \
  --member="$PUBSUB_AGENT" \
  --role="roles/iam.serviceAccountTokenCreator" \
  --quiet >/dev/null

FUNCTION_URL=$(gcloud functions describe "$FUNCTION" \
  --project="$PROJECT" \
  --gen2 \
  --region="$REGION" \
  --format='value(serviceConfig.uri)')

if gcloud pubsub subscriptions describe "$NOTIFY_SUBSCRIPTION" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Notify subscription ${NOTIFY_SUBSCRIPTION} already exists"
else
  echo "Creating push subscription ${NOTIFY_SUBSCRIPTION}"
  gcloud pubsub subscriptions create "$NOTIFY_SUBSCRIPTION" \
    --project="$PROJECT" \
    --topic="$CUSTOMERS_TOPIC" \
    --push-endpoint="$FUNCTION_URL" \
    --push-auth-service-account="${PUSH_SA}@${PROJECT}.iam.gserviceaccount.com"
fi

if [ -f "$ENV_FILE" ]; then
  grep -v -e '^GCP_PROJECT_ID=' -e '^BQ_LOCATION=' -e '^FUNCTION_REGION=' -e '^GCP_CREDENTIALS_FILE=' "$ENV_FILE" > "${ENV_FILE}.tmp" || true
else
  : > "${ENV_FILE}.tmp"
fi
printf 'GCP_PROJECT_ID=%s\nBQ_LOCATION=%s\nFUNCTION_REGION=%s\nGCP_CREDENTIALS_FILE=%s\n' "$PROJECT" "$LOCATION" "$REGION" "$CREDENTIALS_FILE" >> "${ENV_FILE}.tmp"
mv "${ENV_FILE}.tmp" "$ENV_FILE"
echo "Wrote ${ENV_FILE}"

echo "Customers topic ${CUSTOMERS_TOPIC} has two subscriptions:"
echo "  ${BQ_SUBSCRIPTION} -> ${PROJECT}.${DATASET}.${TABLE}"
echo "  ${NOTIFY_SUBSCRIPTION} -> ${FUNCTION} -> ${PROJECT}.${DATASET}.${MIRROR_TABLE}"
echo "The other four topics each have one pull subscription of the same name."
