# harbor-custom-agent

A custom Harbor `BaseAgent` (`agent.py:SimpleAgent`) that asks a local model for
a bash command to run against a task. It can reach the model via an
OpenAI-compatible HTTP endpoint (`backend=http`) or by piping to a local CLI
(`backend=cli`, e.g. `apfel`).

## Endpoint

The HTTP endpoint is fully configurable via `-e/--endpoint` or `ENDPOINT` in
`./run.sh`, defaulting to the local proxy at `http://127.0.0.1:11433/v1`. Point
it at any OpenAI-compatible LLM endpoint.

## Local infra

`serve.sh` brings up ollama (`:11434`) plus an OpenAI-compatible litellm proxy
(`:11433`) with agent-friendly server tuning. Run both together:

```
./run.sh --serve
```

## Running

```
./run.sh                        # SimpleAgent, hello-world via local proxy
./run.sh -e http://HOST:PORT/v1 -m my-model
./run.sh -c                     # SimpleAgent via a local CLI backend instead
./run.sh -k terminus-2          # iterative terminus agent on terminal-bench
./run.sh -k terminus-2 -d some/dataset -e http://HOST:PORT/v1
./run.sh --serve                # bring up infra, then run whichever mode
```

## Pending model tuning (HOLD - per chris, do NOT apply yet)

Ollama defaults truncate/reduce determinism for agentic use. Would be set
per-request via `options` or a Modelfile once approved:

- `num_predict` (default 128) truncates JSON mid-object -> invalid output.
- `temperature` (default 0.8) too high; want ~0.2.

How to apply later: create a tuned model
(`PARAMETER num_predict 4096` / `PARAMETER temperature 0.2`), then point
`--model` at it.