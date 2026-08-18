# syntax=docker/dockerfile:1
FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim@sha256:531f855bda2c73cd6ef67d56b733b357cea384185b3022bd09f05e002cd144ca AS base

ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV UV_COMPILE_BYTECODE=1
ENV HF_HOME=/app/.cache/huggingface
ENV TORCH_HOME=/app/.cache/torch
WORKDIR /app

FROM base AS build
RUN apt-get update && apt-get install -y --no-install-recommends gcc g++ python3-dev \
    && rm -rf /var/lib/apt/lists/*
COPY pyproject.toml uv.lock ./
RUN mkdir -p src && uv sync --locked --no-dev
COPY src ./src
RUN uv run --locked --module livekit.agents download-files

FROM base AS runtime
ARG UID=10001
RUN adduser --disabled-password --gecos "" --home /app --shell /sbin/nologin --uid ${UID} appuser
COPY --from=build --chown=appuser:appuser /app /app
RUN chown appuser:appuser /app
ENV HOME=/app
USER appuser
CMD ["/app/.venv/bin/python", "src/agent.py", "start"]
