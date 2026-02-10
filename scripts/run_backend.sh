#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="local"
PORT="${PORT:-8787}"
CONFIGURE_APP=true
FLY_APP="${FLY_APP:-}"
CONFIG_TARGET="${CONFIG_TARGET:-auto}"
EFFECTIVE_CONFIG_TARGET=""

usage() {
  cat <<'EOF'
Usage:
  scripts/run_backend.sh [local|fly] [options]

Modes:
  local                      Run backend locally (default)
  fly                        Deploy backend to Fly.io

Options:
  --mode <local|fly>         Explicit mode selection
  --port <port>              Local backend port (default: 8787)
  --app <fly_app_name>       Fly app name (overrides fly.toml)
  --config <debug|release|all|auto>
                             Which app build config URL to update
                             (default: auto; local->debug, fly->release)
  --no-configure-app         Do not update SnapToFlash/Info.plist
  -h, --help                 Show this help

Examples:
  scripts/run_backend.sh local
  scripts/run_backend.sh fly
  scripts/run_backend.sh --mode fly --app snaptoflash-backend
  scripts/run_backend.sh local --config debug
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    local|fly)
      MODE="$1"
      shift
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --port)
      PORT="${2:-}"
      shift 2
      ;;
    --app)
      FLY_APP="${2:-}"
      shift 2
      ;;
    --config)
      CONFIG_TARGET="${2:-}"
      shift 2
      ;;
    --no-configure-app)
      CONFIGURE_APP=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$MODE" != "local" && "$MODE" != "fly" ]]; then
  echo "Invalid mode: $MODE" >&2
  usage
  exit 1
fi

if [[ "$CONFIG_TARGET" != "debug" && "$CONFIG_TARGET" != "release" && "$CONFIG_TARGET" != "all" && "$CONFIG_TARGET" != "auto" ]]; then
  echo "Invalid config target: $CONFIG_TARGET" >&2
  usage
  exit 1
fi

if [[ "$CONFIG_TARGET" == "auto" ]]; then
  if [[ "$MODE" == "local" ]]; then
    EFFECTIVE_CONFIG_TARGET="debug"
  else
    EFFECTIVE_CONFIG_TARGET="release"
  fi
else
  EFFECTIVE_CONFIG_TARGET="$CONFIG_TARGET"
fi

for ENV_PATH in "$ROOT/.env" "$(dirname "$ROOT")/.env"; do
  if [[ -f "$ENV_PATH" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$ENV_PATH"
    set +a
    break
  fi
done

: "${OPENAI_MODEL:=gpt-4o-mini}"

APP_PLIST="$ROOT/SnapToFlash/Info.plist"

set_backend_base_url() {
  local url="$1"
  if [[ "$CONFIGURE_APP" != "true" ]]; then
    return
  fi
  if [[ ! -f "$APP_PLIST" ]]; then
    echo "WARNING: Info.plist not found at $APP_PLIST; skipping app URL update." >&2
    return
  fi
  local keys=()
  case "$EFFECTIVE_CONFIG_TARGET" in
    debug)
      keys=("BackendBaseURLDebug")
      ;;
    release)
      keys=("BackendBaseURLRelease")
      ;;
    all)
      keys=("BackendBaseURLDebug" "BackendBaseURLRelease")
      ;;
  esac
  # Keep legacy key in sync for backwards compatibility.
  keys+=("BackendBaseURL")

  for key in "${keys[@]}"; do
    if /usr/libexec/PlistBuddy -c "Set :${key} $url" "$APP_PLIST" >/dev/null 2>&1; then
      :
    else
      /usr/libexec/PlistBuddy -c "Add :${key} string $url" "$APP_PLIST"
    fi
  done
  echo "Updated app backend URL ($EFFECTIVE_CONFIG_TARGET) -> $url"
}

resolve_fly_app_name() {
  if [[ -n "$FLY_APP" ]]; then
    echo "$FLY_APP"
    return
  fi

  if [[ -f "$ROOT/fly.toml" ]]; then
    local parsed
    parsed="$(awk -F"'" '/^app[[:space:]]*=/ {print $2; exit}' "$ROOT/fly.toml")"
    if [[ -z "$parsed" ]]; then
      parsed="$(awk -F'"' '/^app[[:space:]]*=/ {print $2; exit}' "$ROOT/fly.toml")"
    fi
    if [[ -n "$parsed" ]]; then
      echo "$parsed"
      return
    fi
  fi

  echo ""
}

run_local() {
  set_backend_base_url "http://127.0.0.1:${PORT}"

  if [[ ! -d "$ROOT/.venv" ]]; then
    python3 -m venv "$ROOT/.venv"
  fi

  # shellcheck disable=SC1091
  source "$ROOT/.venv/bin/activate"
  python -m pip install --upgrade pip
  pip install -r backend/requirements.txt

  if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    echo "WARNING: OPENAI_API_KEY not set; backend will return stub output."
  fi

  echo "Starting local backend on http://127.0.0.1:${PORT}"
  exec uvicorn backend.main:app --host 0.0.0.0 --port "$PORT"
}

deploy_fly() {
  if ! command -v flyctl >/dev/null 2>&1; then
    echo "ERROR: flyctl is not installed." >&2
    exit 1
  fi

  local app_name
  app_name="$(resolve_fly_app_name)"
  if [[ -z "$app_name" ]]; then
    echo "ERROR: Could not resolve Fly app name. Use --app <name>." >&2
    exit 1
  fi

  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    flyctl secrets set OPENAI_API_KEY="$OPENAI_API_KEY" OPENAI_MODEL="$OPENAI_MODEL" -a "$app_name"
    echo "Updated Fly secrets for app: $app_name"
  else
    echo "WARNING: OPENAI_API_KEY not set in environment; deploying without LLM key (stub output)." >&2
    flyctl secrets set OPENAI_MODEL="$OPENAI_MODEL" -a "$app_name"
  fi

  flyctl deploy -a "$app_name"
  set_backend_base_url "https://${app_name}.fly.dev"
  echo "Fly deployment complete: https://${app_name}.fly.dev"
}

if [[ "$MODE" == "local" ]]; then
  run_local
else
  deploy_fly
fi
