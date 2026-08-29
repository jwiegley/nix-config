#!/usr/bin/env python3
"""Prove Droid SDK starts its child from only the explicitly supplied environment."""

import asyncio
import json
import os
import stat
import sys
import tempfile
from pathlib import Path

from droid_sdk.transport import ProcessTransport


async def main() -> None:
    with tempfile.TemporaryDirectory(prefix="droid-sdk-env-") as temporary:
        root = Path(temporary)
        output = root / "environment.json"
        child = root / "child.py"
        child.write_text(
            f"#!{sys.executable}\n"
            "import json, os, time\n"
            "from pathlib import Path\n"
            "Path(os.environ['PROBE_OUTPUT']).write_text(json.dumps(dict(os.environ)))\n"
            "time.sleep(30)\n"
        )
        child.chmod(child.stat().st_mode | stat.S_IXUSR)

        os.environ.update(
            {
                "HOME": "/ambient-home",
                "OPENAI_API_KEY": "openai-canary",
                "SSH_AUTH_SOCK": "/ambient-agent",
            }
        )
        transport = ProcessTransport(
            exec_path=str(child),
            exec_args=[],
            env={
                "FACTORY_API_KEY": "factory-canary",
                "HOME": "/managed-home",
                "PROBE_OUTPUT": str(output),
            },
        )
        await transport.connect()
        try:
            for _ in range(100):
                if output.exists():
                    break
                await asyncio.sleep(0.01)
            else:
                raise AssertionError("Droid SDK environment probe did not start")
        finally:
            await transport.close()

        child_environment = json.loads(output.read_text())
        assert child_environment["FACTORY_API_KEY"] == "factory-canary"
        assert child_environment["HOME"] == "/managed-home"
        assert "OPENAI_API_KEY" not in child_environment
        assert "SSH_AUTH_SOCK" not in child_environment


asyncio.run(main())
