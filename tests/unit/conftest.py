"""
Unit test fixtures.

Strategy: mock AWS with moto (no real AWS calls), and use chalice.test.Client
to invoke Chalice handlers directly (no HTTP server needed).
"""

import os

import boto3
import pytest
from moto import mock_aws

# Set env vars BEFORE importing the app so module-level code picks them up.
os.environ.setdefault("TABLE_NAME", "hello-world-items-dev")
os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")
os.environ.setdefault("AWS_ACCESS_KEY_ID", "testing")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "testing")
# Ensure we never accidentally hit LocalStack during unit tests.
os.environ.pop("AWS_ENDPOINT_URL", None)

from chalice.test import Client  # noqa: E402

from app import app  # noqa: E402


@pytest.fixture
def mock_table():
    """Start moto, create the test DynamoDB table, yield, then stop moto."""
    with mock_aws():
        dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
        dynamodb.create_table(
            TableName=os.environ["TABLE_NAME"],
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        yield


@pytest.fixture
def test_client(mock_table):
    """Chalice test client with DynamoDB already mocked and table created."""
    with Client(app) as client:
        yield client
