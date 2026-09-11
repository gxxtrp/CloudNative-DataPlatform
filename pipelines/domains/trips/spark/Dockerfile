# Trips Spark Job Image
FROM apache/spark-py:v3.5.0

USER root

# Install additional Python packages
COPY requirements.txt /opt/spark/work-dir/
RUN pip install --no-cache-dir -r /opt/spark/work-dir/requirements.txt

# Copy source code
COPY src/ /opt/spark/work-dir/src/

# Set working directory
WORKDIR /opt/spark/work-dir

USER spark
