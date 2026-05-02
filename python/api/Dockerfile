FROM python:3.12-slim-trixie AS build
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
WORKDIR /app

COPY pyproject.toml uv.lock README.md ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project --no-dev

COPY src/ src/
COPY alembic.ini ./
COPY alembic/ alembic/
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

FROM python:3.12-slim-trixie

WORKDIR /app
COPY --from=build /app /app
ENV PATH="/app/.venv/bin:$PATH"

ENTRYPOINT ["alembic", "upgrade", "head"]
