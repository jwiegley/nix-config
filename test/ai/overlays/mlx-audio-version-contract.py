import sys
from importlib import metadata

from mlx_audio.version import __version__ as module_version

expected = sys.argv[1]
installed = metadata.version("mlx-audio")
if expected != installed or expected != module_version:
    raise SystemExit(
        "mlx-audio version mismatch: "
        f"catalog {expected}, metadata {installed}, module {module_version}"
    )
