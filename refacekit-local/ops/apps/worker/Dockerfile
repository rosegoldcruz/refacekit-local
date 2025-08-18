FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create non-root user and export directory
RUN useradd --create-home --shell /bin/bash worker \
    && mkdir -p /data/exports \
    && chown -R worker:worker /app /data/exports
USER worker

# Run the worker
CMD ["python", "worker.py"]
