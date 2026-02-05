FROM python:3.12-slim-bookworm

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    bison \
    ca-certificates \
    cmake \
    curl \
    flex \
    git \
    ninja-build \
    pkg-config \
    xz-utils \
    bzip2 \
  && rm -rf /var/lib/apt/lists/*

# Isolate build tooling.
RUN python3 -m venv /opt/pyodide-venv
ENV PATH=/opt/pyodide-venv/bin:$PATH

# Pin wheel to keep the toolchain stable; match the Pyodide 0.29.3 toolchain.
RUN pip install --no-cache-dir "wheel==0.41.3" "pyodide-build==0.29.3"

WORKDIR /work
