# ─── Build / test stage ───────────────────────────────────────────────────────
# Contains all dev + runtime deps; used by docker-compose.test.yml test-runner.
FROM python:3.12-slim AS builder

WORKDIR /build

COPY requirements.txt requirements-dev.txt ./
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt -r requirements-dev.txt

COPY src/ ./src/
COPY tests/ ./tests/

# ─── Runtime stage ─────────────────────────────────────────────────────────────
# Minimal image; serves the app locally via `chalice local`.
FROM python:3.12-slim AS runtime

RUN useradd --no-create-home --shell /bin/false appuser

WORKDIR /app

# Install only runtime + chalice (needed for `chalice local`).
COPY requirements.txt requirements-dev.txt ./
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt -r requirements-dev.txt

# Copy application code.
COPY src/ ./src/

USER appuser

EXPOSE 8000

# `chalice local` acts as a lightweight Lambda + API-GW emulator.
CMD ["chalice", "--project-dir", "/app/src", "local", "--host", "0.0.0.0", "--port", "8000"]
