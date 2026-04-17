import os

import pytest

# APP_BASE_URL is injected by docker-compose.test.yml into the test-runner container.
BASE_URL = os.environ.get("APP_BASE_URL", "http://localhost:8000").rstrip("/")


@pytest.fixture(scope="session")
def base_url() -> str:
    return BASE_URL
