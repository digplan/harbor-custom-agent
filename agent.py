"""A minimal Harbor external agent that asks a local model for the command to run.

The model can be reached either over an OpenAI-compatible HTTP endpoint
(``backend="http"``) or by piping to a local CLI program such as ``apfel``
(``backend="cli"``). Both are configurable via ``--ak``.
"""

import json
import logging
import re
import shlex
import subprocess
import urllib.request

from harbor.agents.base import BaseAgent
from harbor.environments.base import BaseEnvironment
from harbor.models.agent.context import AgentContext

DEFAULT_MODEL = "qwen3-8b:q4_k"
DEFAULT_BASE_URL = "http://localhost:12778/v1"
DEFAULT_CLI_COMMAND = "apfel --code -s {system} {instruction}"

SYSTEM_PROMPT = (
    "You are a coding agent inside a Docker container. Given a task instruction, "
    "reply with EXACTLY ONE bash command (and nothing else, no fenced code blocks, "
    "no explanations) that accomplishes it. The command must create or modify a file "
    "in /app so it can be verified."
)

_ANSI_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def _strip_ansi(text: str) -> str:
    return _ANSI_RE.sub("", text)


class SimpleAgent(BaseAgent):
    def __init__(
        self,
        logs_dir,
        model: str = DEFAULT_MODEL,
        backend: str = "http",
        base_url: str = DEFAULT_BASE_URL,
        cli_command: str = DEFAULT_CLI_COMMAND,
        **kwargs,
    ):
        super().__init__(logs_dir=logs_dir, **kwargs)
        self.model = model
        self.backend = backend
        self.base_url = base_url
        self.cli_command = cli_command

    @staticmethod
    def name() -> str:
        return "simple-agent"

    def version(self) -> str | None:
        return "0.1.0"

    async def setup(self, environment: BaseEnvironment) -> None:
        pass

    def _ask_http(self, instruction: str) -> str:
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": instruction},
            ],
            "stream": False,
        }
        req = urllib.request.Request(
            f"{self.base_url}/chat/completions",
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=300) as resp:
            body = json.loads(resp.read().decode())
        return body["choices"][0]["message"]["content"].strip()

    def _ask_cli(self, instruction: str) -> str:
        command = self.cli_command.format(
            system=shlex.quote(SYSTEM_PROMPT),
            instruction=shlex.quote(instruction),
        )
        proc = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True,
            timeout=300,
            encoding="utf-8",
            errors="replace",
        )
        if proc.returncode != 0 and not proc.stdout:
            raise RuntimeError(f"{self.cli_command} failed: {proc.stderr}")
        return _strip_ansi((proc.stdout or proc.stderr).strip())

    def _ask_model(self, instruction: str) -> str:
        if self.backend == "cli":
            return self._ask_cli(instruction)
        if self.backend == "http":
            return self._ask_http(instruction)
        raise ValueError(f"Unknown backend: {self.backend}")

    async def run(
        self,
        instruction: str,
        environment: BaseEnvironment,
        context: AgentContext,
    ) -> None:
        raw = self._ask_model(instruction)
        command = re.sub(r"^```(?:bash|sh)?\s*|\s*```$", "", raw).strip()
        logging.getLogger(__name__).info(
            "Model %s (backend=%s) proposed command: %s", self.model, self.backend, command
        )

        result = await environment.exec(command)
        context.metadata = {
            "model": self.model,
            "backend": self.backend,
            "command": command,
            "exit_code": result.return_code,
        }