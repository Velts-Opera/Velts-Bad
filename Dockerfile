# syntax=docker/dockerfile:1
ARG PYTHON_VERSION=3.13
FROM ghcr.io/astral-sh/uv:python${PYTHON_VERSION}-bookworm-slim AS base

ENV PYTHONUNBUFFERED=1
ENV UV_COMPILE_BYTECODE=1
WORKDIR /app

FROM base AS build
RUN apt-get update && apt-get install -y --no-install-recommends gcc g++ python3-dev \
    && rm -rf /var/lib/apt/lists/*
COPY pyproject.toml ./
RUN mkdir -p src && uv sync --no-dev
COPY src ./src
RUN uv run --module livekit.agents download-files

FROM base AS runtime
ARG UID=10001
RUN adduser --disabled-password --gecos "" --home /app --shell /sbin/nologin --uid ${UID} appuser
COPY --from=build --chown=appuser:appuser /app /app
USER appuser
CMD ["uv", "run", "src/agent.py", "start"]
