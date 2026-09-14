# syntax=docker/dockerfile:1
FROM python:3.12-slim AS runtime

# Security best practice: Create non-root user and group
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -s /bin/bash -m appuser

WORKDIR /app

# Install package dependencies
COPY pyproject.toml .
RUN pip install --no-cache-dir .

# Copy application source code
COPY src/ /app/src/

# Switch to non-root user
USER 10001:10001

# Entrypoint executes the ingestion module
ENTRYPOINT ["python", "-m", "src.ingest"]
