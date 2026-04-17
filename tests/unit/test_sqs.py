"""
Unit tests for the SQS handler (handle_processor_queue).
"""

import json


def test_sqs_create_item(test_client):
    """A valid create_item message should insert the item into DynamoDB."""
    event = test_client.events.generate_sqs_event(
        queue_name="processor",
        message_bodies=[json.dumps({"action": "create_item", "name": "sqs-widget"})],
    )
    # Should not raise
    test_client.lambda_.invoke("handle_processor_queue", event)

    # Item should now be visible via the HTTP route
    items = test_client.http.get("/items").json_body
    assert any(i["name"] == "sqs-widget" for i in items)


def test_sqs_with_description(test_client):
    event = test_client.events.generate_sqs_event(
        queue_name="processor",
        message_bodies=[
            json.dumps({"action": "create_item", "name": "x", "description": "desc"})
        ],
    )
    test_client.lambda_.invoke("handle_processor_queue", event)
    items = test_client.http.get("/items").json_body
    match = next((i for i in items if i["name"] == "x"), None)
    assert match is not None
    assert match["description"] == "desc"


def test_sqs_unknown_action_is_skipped(test_client):
    """Unknown actions must not raise — they are silently skipped."""
    event = test_client.events.generate_sqs_event(
        queue_name="processor",
        message_bodies=[json.dumps({"action": "noop"})],
    )
    test_client.lambda_.invoke("handle_processor_queue", event)
    assert test_client.http.get("/items").json_body == []


def test_sqs_multiple_records(test_client):
    """All valid records in a batch should be processed."""
    event = test_client.events.generate_sqs_event(
        queue_name="processor",
        message_bodies=[
            json.dumps({"action": "create_item", "name": "item-1"}),
            json.dumps({"action": "create_item", "name": "item-2"}),
        ],
    )
    test_client.lambda_.invoke("handle_processor_queue", event)
    names = {i["name"] for i in test_client.http.get("/items").json_body}
    assert names == {"item-1", "item-2"}


def test_sqs_malformed_body_does_not_crash(test_client):
    """A malformed JSON body must not crash the handler (error is logged, skipped)."""
    event = test_client.events.generate_sqs_event(
        queue_name="processor",
        message_bodies=["not-valid-json"],
    )
    test_client.lambda_.invoke("handle_processor_queue", event)
