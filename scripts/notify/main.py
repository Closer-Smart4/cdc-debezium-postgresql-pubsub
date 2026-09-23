"""Log a customer change pushed from Pub/Sub."""

from __future__ import annotations

import base64
import json
import logging
from typing import Any

import functions_framework
from flask import Request

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _row(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    return {}


def customer_line(payload: dict[str, Any]) -> str:
    """Format the Debezium payload as one log line."""
    row = _row(payload.get("after")) or _row(payload.get("before"))
    return (
        f"op={payload.get('op')} "
        f"id={row.get('id')} "
        f"{row.get('first_name')} {row.get('last_name')} "
        f"{row.get('email')}"
    )


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
    line = customer_line(payload)
    logger.info(line)
    print(line, flush=True)
    return ("ok", 200)
