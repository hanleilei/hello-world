"""
hello-world — Chalice application.

Routes:
    GET  /health           — liveness probe
    GET  /                 — service info
    GET  /items            — list all items
    POST /items            — create an item  (201)
    GET  /items/{item_id}  — get one item
    DELETE /items/{item_id}— delete an item  (204)

SQS handler:
    handle_processor_queue — processes messages from the 'processor' queue.
    Expected message body:
        {"action": "create_item", "name": "...", "description": "..."}
"""

import json
import logging
import os
import time

from chalice import BadRequestError, Chalice, NotFoundError, Response

from chalicelib import db

logger = logging.getLogger(__name__)

app = Chalice(app_name="hello-world")
app.log.setLevel(logging.INFO)

_START_TIME = time.time()

# Auto-create DynamoDB table when running against LocalStack (docker-compose / local dev).
db.ensure_table_if_local()


# ─── HTTP routes ──────────────────────────────────────────────────────────────


@app.route("/health")
def health():
    return {"status": "ok", "uptime_seconds": round(time.time() - _START_TIME, 1)}


@app.route("/")
def index():
    return {
        "message": "hello-world",
        "env": os.environ.get("ENV", "dev"),
        "version": "1.2.0",
    }


@app.route("/items", methods=["GET"])
def list_items():
    return db.list_items()


@app.route("/items", methods=["POST"])
def create_item():
    body = app.current_request.json_body or {}
    name = body.get("name", "").strip()
    if not name:
        raise BadRequestError("'name' is required and must not be empty")
    item = db.create_item(name=name, description=body.get("description"))
    return Response(body=item, status_code=201)


@app.route("/items/{item_id}", methods=["GET"])
def get_item(item_id):
    item = db.get_item(item_id)
    if item is None:
        raise NotFoundError(f"Item '{item_id}' not found")
    return item


@app.route("/items/{item_id}", methods=["DELETE"])
def delete_item(item_id):
    if not db.delete_item(item_id):
        raise NotFoundError(f"Item '{item_id}' not found")
    return Response(body=None, status_code=204)


# ─── SQS handler ──────────────────────────────────────────────────────────────


@app.on_sqs_message(queue="processor")
def handle_processor_queue(event):
    """
    Process SQS messages from the 'processor' queue.
    Errors are caught per-record and logged so that one bad message does not
    prevent the rest of the batch from being processed.
    """
    for record in event:
        try:
            body = json.loads(record.body)
            action = body.get("action")

            if action == "create_item":
                item = db.create_item(
                    name=body["name"],
                    description=body.get("description"),
                )
                logger.info("Created item id=%s from SQS", item["id"])
            else:
                logger.warning("Unknown action '%s' — skipping", action)

        except (KeyError, json.JSONDecodeError) as exc:
            logger.error("Failed to process SQS record: %s", exc)
