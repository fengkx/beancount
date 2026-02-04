FROM ubuntu:22.04

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
    python3 \
    python3-pip \
    python3-venv \
    xz-utils \
    bzip2 \
  && rm -rf /var/lib/apt/lists/*

# Install emsdk (required by pyodide-build).
RUN git clone --depth 1 --branch 3.1.46 https://github.com/emscripten-core/emsdk.git /opt/emsdk
RUN /opt/emsdk/emsdk install 3.1.46
RUN /opt/emsdk/emsdk activate 3.1.46

ENV EMSDK=/opt/emsdk
ENV PATH=/opt/emsdk:/opt/emsdk/upstream/emscripten:/opt/emsdk/node/16.20.0_64bit/bin:$PATH

# Isolate build tooling.
RUN python3 -m venv /opt/pyodide-venv
ENV PATH=/opt/pyodide-venv/bin:$PATH

# Pin wheel to a version compatible with pyodide-cli in pyodide-build 0.25.1.
RUN pip install --no-cache-dir "wheel==0.41.3" "pyodide-build==0.25.1"

WORKDIR /work
