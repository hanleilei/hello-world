"""
DynamoDB helpers for the hello-world Chalice app.

Table schema (single-table, PAY_PER_REQUEST):
    PK: id  (String, UUID)
    Attributes: name (String), description (String, optional)

Environment variables:
    TABLE_NAME         — DynamoDB table name (required)
    AWS_DEFAULT_REGION — AWS region (default: us-east-1)
    AWS_ENDPOINT_URL   — Override endpoint URL; set to LocalStack URL in
                         docker-compose / local dev. Unset in real AWS.
"""

import os
import uuid

import boto3
from botocore.exceptions import ClientError


def _get_table():
    kwargs: dict = {"region_name": os.environ.get("AWS_DEFAULT_REGION", "us-east-1")}
    endpoint_url = os.environ.get("AWS_ENDPOINT_URL")
    if endpoint_url:
        kwargs["endpoint_url"] = endpoint_url
    dynamodb = boto3.resource("dynamodb", **kwargs)
    return dynamodb.Table(os.environ.get("TABLE_NAME", "hello-world-items-dev"))


def ensure_table_if_local() -> None:
    """
    Auto-create the DynamoDB table when AWS_ENDPOINT_URL is set (i.e. LocalStack
    or local DynamoDB). This is a no-op in real AWS environments.
    """
    endpoint_url = os.environ.get("AWS_ENDPOINT_URL")
    if not endpoint_url:
        return

    table_name = os.environ.get("TABLE_NAME", "hello-world-items-dev")
    region = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
    dynamodb = boto3.resource("dynamodb", region_name=region, endpoint_url=endpoint_url)

    try:
        dynamodb.create_table(
            TableName=table_name,
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
    except ClientError as exc:
        # ResourceInUseException means the table already exists — that's fine.
        if exc.response["Error"]["Code"] != "ResourceInUseException":
            raise


def list_items() -> list:
    table = _get_table()
    result = table.scan()
    return result.get("Items", [])


def get_item(item_id: str) -> dict | None:
    table = _get_table()
    result = table.get_item(Key={"id": item_id})
    return result.get("Item")


def create_item(name: str, description: str | None = None) -> dict:
    table = _get_table()
    item: dict = {"id": str(uuid.uuid4()), "name": name}
    if description is not None:
        item["description"] = description
    table.put_item(Item=item)
    return item


def delete_item(item_id: str) -> bool:
    """Return True if the item existed and was deleted, False if not found."""
    if get_item(item_id) is None:
        return False
    _get_table().delete_item(Key={"id": item_id})
    return True
