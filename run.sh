#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults (env-overridable)
MODEL="${MODEL:-qwen3-8b:q4_k}"
BACKEND="${BACKEND:-http}"
BASE_URL="${BASE_URL:-http://localhost:11434/v1}"
DEFAULT_CLI="apfel --code -s {system} {instruction}"
CLI_COMMAND="${CLI_COMMAND:-$DEFAULT_CLI}"

usage() {
  cat <<'EOF'
Usage: ./run.sh [OPTIONS]

Run the hello-world Harbor task with the custom agent.

Backend selection:
  -c, --cli           Pipe to a local CLI command instead of an HTTP server
                      (default CLI: apfel)

Config:
  -m, --model NAME    Model name (default: qwen3-8b:q4_k)
      --base-url URL  HTTP base URL (default: http://localhost:11434/v1)
      --cli-command C  CLI command template with {system}/{instruction}
                       (default: apfel --code -s {system} {instruction})
  -h, --help          Show this help

Env overrides: MODEL, BACKEND, BASE_URL, CLI_COMMAND
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--cli) BACKEND=cli; shift ;;
    -m|--model) MODEL="$2"; shift 2 ;;
    --base-url) BASE_URL="$2"; shift 2 ;;
    --cli-command) CLI_COMMAND="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

agent_args=(
  "--path" "$ROOT/hello-world"
  "--agent" "agent:SimpleAgent"
  "--ak" "model=$MODEL"
  "--ak" "backend=$BACKEND"
)
if [ "$BACKEND" = "cli" ]; then
  agent_args+=("--ak" "cli_command=$CLI_COMMAND")
else
  agent_args+=("--ak" "base_url=$BASE_URL")
fi

echo ">> backend=$BACKEND model=$MODEL"
PYTHONPATH="$ROOT" harbor run "${agent_args[@]}" \
  --jobs-dir "$ROOT/jobs"