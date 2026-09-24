"""Log a customer change and keep a BigQuery copy of the PostgreSQL row."""

from __future__ import annotations

import base64
import json
import logging
import os
from typing import Any

import functions_framework
from flask import Request
from google.cloud import bigquery

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

_client: bigquery.Client | None = None


def _row(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    return {}


def _customer_id(value: Any) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    return value


def customer_line(payload: dict[str, Any]) -> str:
    """Format the Debezium payload as one log line."""
    row = _row(payload.get("after")) or _row(payload.get("before"))
    return (
        f"op={payload.get('op')} "
        f"id={row.get('id')} "
        f"{row.get('first_name')} {row.get('last_name')} "
        f"{row.get('email')}"
    )


def _project() -> str:
    project = os.environ.get("GCP_PROJECT") or os.environ.get("GOOGLE_CLOUD_PROJECT")
    if not project:
        raise RuntimeError("GCP_PROJECT is not set")
    return project


def _bq() -> bigquery.Client:
    global _client
    if _client is None:
        _client = bigquery.Client(
            project=_project(),
            location=os.environ.get("BQ_LOCATION", "europe-west1"),
        )
    return _client


def _table() -> str:
    dataset = os.environ.get("BQ_DATASET", "debezium_cdc")
    table = os.environ.get("BQ_TABLE", "customers_current")
    return f"{_project()}.{dataset}.{table}"


def apply_customer(payload: dict[str, Any]) -> None:
    """Upsert or delete the customer so the table matches PostgreSQL."""
    op = payload.get("op")
    after = _row(payload.get("after"))
    before = _row(payload.get("before"))
    if op == "d":
        customer_id = _customer_id(before.get("id"))
        if customer_id is None:
            logger.warning("Delete event has no customer id")
            return
        _bq().query(
            f"DELETE FROM `{_table()}` WHERE id = @id",
            job_config=bigquery.QueryJobConfig(
                query_parameters=[
                    bigquery.ScalarQueryParameter("id", "INT64", customer_id),
                ]
            ),
        ).result()
        return
    customer_id = _customer_id(after.get("id"))
    if customer_id is None:
        logger.warning("Change event has no customer id")
        return
    _bq().query(
        f"""
        MERGE `{_table()}` T
        USING (
          SELECT @id AS id, @first_name AS first_name,
                 @last_name AS last_name, @email AS email
        ) S
        ON T.id = S.id
        WHEN MATCHED THEN
          UPDATE SET first_name = S.first_name, last_name = S.last_name, email = S.email
        WHEN NOT MATCHED THEN
          INSERT (id, first_name, last_name, email)
          VALUES (S.id, S.first_name, S.last_name, S.email)
        """,
        job_config=bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("id", "INT64", customer_id),
                bigquery.ScalarQueryParameter(
                    "first_name", "STRING", str(after.get("first_name") or "")
                ),
                bigquery.ScalarQueryParameter(
                    "last_name", "STRING", str(after.get("last_name") or "")
                ),
                bigquery.ScalarQueryParameter(
                    "email", "STRING", str(after.get("email") or "")
                ),
            ]
        ),
    ).result()


@functions_framework.http
def notify_customer_change(request: Request) -> tuple[str, int]:
    """Handle one Pub/Sub push delivery of a customers change."""
    body = request.get_json(silent=True) or {}
    message = body.get("message") if isinstance(body, dict) else None
    data = message.get("data") if isinstance(message, dict) else None
    if not isinstance(data, str):
        logger.warning("Pub/Sub push message has no data")
        return ("no data", 400)
    event = json.loads(base64.b64decode(data))
    payload = event.get("payload") if isinstance(event, dict) else None
    if not isinstance(payload, dict):
        logger.warning("Debezium message has no payload")
        return ("no payload", 400)
    apply_customer(payload)
    line = customer_line(payload)
    logger.info(line)
    print(line, flush=True)
    return ("ok", 200)
