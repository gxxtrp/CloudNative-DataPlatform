# syntax=docker/dockerfile:1
FROM curlimages/curl:8.16.0 AS dependencies

ARG ICEBERG_VERSION=1.10.1
ARG GCS_CONNECTOR_VERSION=2.2.28

RUN curl --fail --location --silent --show-error \
      "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-3.5_2.12/${ICEBERG_VERSION}/iceberg-spark-runtime-3.5_2.12-${ICEBERG_VERSION}.jar" \
      --output /tmp/iceberg-spark-runtime.jar \
 && curl --fail --location --silent --show-error \
      "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-gcp-bundle/${ICEBERG_VERSION}/iceberg-gcp-bundle-${ICEBERG_VERSION}.jar" \
      --output /tmp/iceberg-gcp-bundle.jar \
 && curl --fail --location --silent --show-error \
      "https://repo1.maven.org/maven2/com/google/cloud/bigdataoss/gcs-connector/hadoop3-${GCS_CONNECTOR_VERSION}/gcs-connector-hadoop3-${GCS_CONNECTOR_VERSION}-shaded.jar" \
      --output /tmp/gcs-connector.jar

FROM apache/spark:3.5.1

USER 0
COPY --from=dependencies /tmp/*.jar /opt/spark/jars/
COPY publish.py /opt/spark/work-dir/publish.py
USER 185
