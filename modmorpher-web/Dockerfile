FROM python:3.12-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends openjdk-21-jre-headless git \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN git clone --depth 1 https://github.com/Indozilla1234/Modmorpher /opt/Modmorpher
COPY app.py .
COPY templates templates

ENV MODMORPHER_DIR=/opt/Modmorpher PORT=8000
EXPOSE 8000
# One worker: job state lives in memory, and conversions are queued inside it.
CMD gunicorn --workers 1 --threads 8 --timeout 0 --bind 0.0.0.0:${PORT} app:app
