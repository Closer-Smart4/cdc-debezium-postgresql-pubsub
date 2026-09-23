#!/bin/sh
# Point the active gcloud configuration at postgresql-debezium/gcp.env.

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

if ! command -v gcloud >/dev/null 2>&1; then
  echo "Install the Google Cloud CLI and run gcloud auth login" >&2
  exit 1
fi

gcloud config set project "$GCP_PROJECT_ID"
gcloud config set run/region "$FUNCTION_REGION"
gcloud config set functions/region "$FUNCTION_REGION"

echo "gcloud project is ${GCP_PROJECT_ID}"
echo "function region is ${FUNCTION_REGION}"
echo "BigQuery location is ${BQ_LOCATION}"
