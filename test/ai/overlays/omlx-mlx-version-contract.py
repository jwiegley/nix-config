import sys
from importlib import metadata

import mlx.core as mx
from packaging.requirements import Requirement
from packaging.utils import canonicalize_name

expected = sys.argv[1]
requirements = [
    requirement
    for raw in metadata.requires("omlx") or []
    if canonicalize_name((requirement := Requirement(raw)).name) == "mlx"
]
active_requirements = [
    requirement
    for requirement in requirements
    if requirement.marker is None or requirement.marker.evaluate()
]

if (
    len(requirements) != 1
    or len(active_requirements) != 1
    or active_requirements[0].extras
    or str(active_requirements[0].specifier) != f"=={expected}"
):
    raise SystemExit(f"oMLX must require exactly mlx=={expected}, got {requirements}")
installed = metadata.version("mlx")
if installed != expected or mx.__version__ != expected:
    raise SystemExit(
        f"MLX version mismatch: expected {expected}, metadata {installed}, module {mx.__version__}"
    )

total = mx.sum(mx.array([1, 2, 3], dtype=mx.int32))
mx.eval(total)
if total.item() != 6:
    raise SystemExit("MLX runtime operation returned the wrong result")
