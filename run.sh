#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults (env-overridable). ENDPOINT is the model endpoint both agents talk to.
MODEL="${MODEL:-gpt-oss:20b}"
BACKEND="${BACKEND:-http}"
ENDPOINT="${ENDPOINT:-http://127.0.0.1:11433/v1}"
DEFAULT_CLI="apfel --code -s {system} {instruction}"
CLI_COMMAND="${CLI_COMMAND:-$DEFAULT_CLI}"
SERVE="${SERVE:-0}"
AGENT="${AGENT:-simple}"
DATASET="${DATASET:-terminal-bench/terminal-bench-2}"

usage() {
  cat <<'EOF'
Usage: ./run.sh [OPTIONS]

Run a Harbor task. Two agent modes:

  SimpleAgent (default): single-shot bash command. Use with --task.
  terminus-2:           iterative plan/commands loop for terminal-bench tasks.
                         Use -d/--dataset to pick the dataset.

Backend / infra:
  -s, --serve      Bring up local infra first (ollama + proxy) then run
  -c, --cli        (simple mode only) pipe to a local CLI instead of HTTP

Config:
  -k, --agent NAME     simple | terminus | terminus-1 | terminus-2 (default simple)
  -e, --endpoint URL   Model HTTP endpoint (default: http://127.0.0.1:11433/v1)
  -m, --model NAME     Model name (default: gpt-oss:20b)
  -t, --task PATH      Task path (simple mode only; default hello-world)
  -d, --dataset NAME   Dataset (terminus mode only; default terminal-bench/terminal-bench-2)
      --cli-command C  CLI command template with {system}/{instruction} (simple mode)
  -h, --help           Show this help

Env overrides: MODEL, BACKEND, ENDPOINT, CLI_COMMAND, SERVE, AGENT, DATASET
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--serve) SERVE=1; shift ;;
    -c|--cli) BACKEND=cli; shift ;;
    -k|--agent)
      case "$2" in
        simple|simple-agent|custom) AGENT=simple ;;
        terminus|terminus-1|terminus-2) AGENT="$2" ;;
        *) echo "Unknown agent: $2" >&2; usage; exit 1 ;;
      esac
      shift 2 ;;
    -e|--endpoint) ENDPOINT="$2"; shift 2 ;;
    -m|--model) MODEL="$2"; shift 2 ;;
    -t|--task) TASK="$2"; shift 2 ;;
    -d|--dataset) DATASET="$2"; shift 2 ;;
    --cli-command) CLI_COMMAND="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [ "$SERVE" = "1" ]; then
  "$ROOT/serve.sh"
fi

if [ "$AGENT" = "simple" ]; then
  TASK="${TASK:-$ROOT/hello-world}"
  agent_args=(
    "--path" "$TASK"
    "--agent" "agent:SimpleAgent"
    "--ak" "model=$MODEL"
    "--ak" "backend=$BACKEND"
  )
  if [ "$BACKEND" = "cli" ]; then
    agent_args+=("--ak" "cli_command=$CLI_COMMAND")
  else
    agent_args+=("--ak" "base_url=$ENDPOINT")
  fi
  echo ">> agent=simple backend=$BACKEND model=$MODEL endpoint=$ENDPOINT task=$TASK"
  PYTHONPATH="$ROOT" harbor run "${agent_args[@]}" --jobs-dir "$ROOT/jobs"
else
  echo ">> agent=$AGENT model=$MODEL endpoint=$ENDPOINT dataset=$DATASET"
  harbor run \
    -d "$DATASET" \
    -a "$AGENT" \
    -m "$MODEL" \
    --ak "api_base=$ENDPOINT" \
    --ak "temperature=0" \
    --ak 'llm_call_kwargs={"extra_body":{"options":{"num_predict":4096,"think":"low"}}}' \
    --ak 'model_info={"max_input_tokens":32768,"max_output_tokens":4096}' \
    -n 1 -l 1 -y
fi