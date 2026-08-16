#!/usr/bin/env bash
set -euo pipefail

# Bring up local inference infra for the custom agent:
#   ollama (:11434) + OpenAI-compatible litellm proxy (:11433).
# Point run.sh's ENDPOINT at the proxy when using this.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OLLAMA_PORT="${OLLAMA_PORT:-11434}"
PROXY_PORT="${PROXY_PORT:-11433}"
MODEL="${MODEL:-gpt-oss:20b}"

rm -f "$ROOT/proxy.log"

# Free ports and stop any running ollama (also catches the macOS "Ollama" GUI).
for port in "$OLLAMA_PORT" "$PROXY_PORT"; do
  if pids=$(lsof -ti tcp:"$port" 2>/dev/null); then
    echo "killing processes on :$port -> $pids"
    echo "$pids" | xargs kill -9 2>/dev/null || true
  fi
done
pkill -9 -if "ollama" 2>/dev/null || true
# Give sockets/model locks a moment to release
sleep 2

# Ollama server-side tuning (see README for pending model-level params).
export OLLAMA_HOST="127.0.0.1:$OLLAMA_PORT"
export OLLAMA_CONTEXT_LENGTH=32768   # large context for agent prompts + history
export OLLAMA_KEEP_ALIVE=1h          # keep the model resident across turns
export OLLAMA_NUM_PARALLEL=2         # a little concurrency
export OLLAMA_MAX_LOADED_MODELS=1    # only keep $MODEL loaded (memory)

nohup ollama serve > "$ROOT/ollama.log" 2>&1 &

# Wait for ollama to accept requests
for i in $(seq 1 30); do
  if curl -sf "http://127.0.0.1:$OLLAMA_PORT" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Proxy (litellm -> ollama): :$PROXY_PORT -> :$OLLAMA_PORT
apic proxy -p "$PROXY_PORT" -P "$OLLAMA_PORT" > "$ROOT/proxy.log" &

echo ">> infra up: ollama=:$OLLAMA_PORT proxy=:$PROXY_PORT model=$MODEL"
echo ">> set ENDPOINT=http://<this-host>:$PROXY_PORT/v1 to use it"