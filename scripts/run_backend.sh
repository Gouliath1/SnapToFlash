#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root (one level up from this script)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Load .env if present (first from app root, then from parent)
for ENV_PATH in "$ROOT/.env" "$(dirname "$ROOT")/.env"; do
  if [[ -f "$ENV_PATH" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$ENV_PATH"
    set +a
    break
  fi
done

# Default model if not provided
: "${OPENAI_MODEL:=gpt-4o-mini}"

PORT="${PORT:-8787}"

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "ERROR: OPENAI_API_KEY not set. Copy .env.example to .env and fill it in." >&2
  exit 1
fi

# Create venv if missing
if [[ ! -d "$ROOT/.venv" ]]; then
  python3 -m venv "$ROOT/.venv"
fi

# Activate venv
# shellcheck disable=SC1091
source "$ROOT/.venv/bin/activate"

python -m pip install --upgrade pip
pip install -r backend/requirements.txt

exec uvicorn backend.main:app --host 0.0.0.0 --port "$PORT"
