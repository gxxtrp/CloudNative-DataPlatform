# DBT Docker Image for Argo Workflows
FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install DBT with BigQuery adapter
RUN pip install --no-cache-dir \
    dbt-core==1.7.* \
    dbt-bigquery==1.7.*

# Create dbt user
RUN useradd -m -s /bin/bash dbt
USER dbt
WORKDIR /home/dbt

# Copy dbt project
COPY --chown=dbt:dbt . /home/dbt/dbt_project/

WORKDIR /home/dbt/dbt_project

# Install dbt packages
RUN dbt deps

# Default command
ENTRYPOINT ["dbt"]
CMD ["--help"]
