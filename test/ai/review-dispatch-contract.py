#!/usr/bin/env python3
"""Exercise the no-history and exact-model dispatch contract helpers."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile


def run(*arguments: str, ok: bool) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(arguments, check=False, capture_output=True, text=True)
    if (result.returncode == 0) != ok:
        raise AssertionError(
            f"unexpected exit {result.returncode}: {' '.join(arguments)}\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
    return result


def response(
    path: Path,
    model: str,
    *,
    content: str = "probe",
    status: str = "success",
    metadata: bool = True,
) -> None:
    tool_output = {"status": status, "content": content}
    if metadata:
        tool_output["metadata"] = {"model_used": model, "provider_used": "fixture"}
    path.write_text(
        json.dumps({"content": [{"type": "text", "text": json.dumps(tool_output)}]}),
        encoding="utf-8",
    )


def main() -> None:
    history = Path(sys.argv[1])
    models = Path(sys.argv[2])
    assert history.is_file() and history.stat().st_mode & 0o111
    assert models.is_file() and models.stat().st_mode & 0o111

    sentinel = "PARENT_HISTORY_SENTINEL=0123456789abcdef"
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        absent = root / "absent.txt"
        inherited = root / "inherited.txt"
        noisy = root / "noisy.txt"
        pal_absent = root / "pal-absent.json"
        pal_error = root / "pal-error.json"
        absent.write_text("PARENT_HISTORY_ABSENT\n", encoding="utf-8")
        inherited.write_text(f"{sentinel}\n", encoding="utf-8")
        noisy.write_text("PARENT_HISTORY_ABSENT\nextra\n", encoding="utf-8")
        response(pal_absent, "model-a", content="PARENT_HISTORY_ABSENT")
        response(
            pal_error,
            "model-a",
            content="PARENT_HISTORY_ABSENT",
            status="error",
        )

        run(sys.executable, str(history), sentinel, str(absent), ok=True)
        run(sys.executable, str(history), sentinel, str(pal_absent), ok=True)
        run(sys.executable, str(history), sentinel, str(pal_error), ok=False)
        run(sys.executable, str(history), sentinel, str(inherited), ok=False)
        run(sys.executable, str(history), sentinel, str(noisy), ok=False)
        run(sys.executable, str(history), "short", str(absent), ok=False)

        first = root / "first.json"
        second = root / "second.json"
        third = root / "third.json"
        mismatch = root / "mismatch.json"
        duplicate = root / "duplicate.json"
        error = root / "error.json"
        unidentified = root / "unidentified.json"
        response(first, "model-a")
        response(second, "model-b", status="continuation_available")
        response(third, "model-c")
        response(mismatch, "model-c")
        response(duplicate, "model-a")
        response(error, "model-d", status="error")
        response(unidentified, "model-e", metadata=False)

        result = run(
            sys.executable,
            str(models),
            "--expect",
            "model-a",
            "--expect",
            "model-b",
            "--distinct",
            f"model-a={first}",
            f"model-b={second}",
            ok=True,
        )
        manifest = json.loads(result.stdout)
        assert [item["returned_model"] for item in manifest["dispatches"]] == [
            "model-a",
            "model-b",
        ]
        assert manifest["expected_models"] == ["model-a", "model-b"]

        run(
            sys.executable,
            str(models),
            "--expect",
            "model-a",
            f"model-a={mismatch}",
            ok=False,
        )
        run(
            sys.executable,
            str(models),
            "--expect",
            "model-a",
            "--expect",
            "model-a",
            "--distinct",
            f"model-a={first}",
            f"model-a={duplicate}",
            ok=False,
        )
        run(
            sys.executable,
            str(models),
            "--expect",
            "model-a",
            "--distinct",
            f"model-a={first}",
            ok=False,
        )
        run(
            sys.executable,
            str(models),
            "--expect",
            "model-a",
            "--expect",
            "model-b",
            "--expect",
            "model-c",
            f"model-a={first}",
            f"model-b={second}",
            ok=False,
        )
        run(
            sys.executable,
            str(models),
            "--expect",
            "model-a",
            "--expect",
            "model-b",
            f"model-a={first}",
            f"model-b={second}",
            f"model-c={third}",
            ok=False,
        )
        run(sys.executable, str(models), f"model-a={first}", ok=False)
        run(
            sys.executable,
            str(models),
            "--expect",
            "model-d",
            f"model-d={error}",
            ok=False,
        )
        run(
            sys.executable,
            str(models),
            "--expect",
            "model-e",
            f"model-e={unidentified}",
            ok=False,
        )


if __name__ == "__main__":
    main()
