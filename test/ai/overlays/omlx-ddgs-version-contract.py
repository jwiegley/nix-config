import re
import sys
from ast import literal_eval
from importlib import metadata
from inspect import signature
from pathlib import Path

import ddgs
import omlx
from ddgs import DDGS
from ddgs.engines import ENGINES
from omlx.websearch import DDGS_TEXT_BACKENDS, HTTP_TIMEOUT_SECONDS
from packaging.requirements import Requirement
from packaging.utils import canonicalize_name

expected = sys.argv[1]
requirements = [
    requirement
    for raw in metadata.requires("omlx") or []
    if canonicalize_name((requirement := Requirement(raw)).name) == "ddgs"
]
active_requirements = [
    requirement
    for requirement in requirements
    if requirement.marker is None or requirement.marker.evaluate()
]
if (
    len(requirements) != 1
    or len(active_requirements) != 1
    or active_requirements[0].marker is not None
    or active_requirements[0].extras
    or str(active_requirements[0].specifier) != f"=={expected}"
):
    raise SystemExit(f"oMLX must require exactly ddgs=={expected}, got {requirements}")

installed = metadata.version("ddgs")
if installed != expected or ddgs.__version__ != expected:
    raise SystemExit(
        f"DDGS version mismatch: expected {expected}, metadata {installed}, module {ddgs.__version__}"
    )
with DDGS(timeout=int(HTTP_TIMEOUT_SECONDS)) as client:
    if not callable(client.text):
        raise SystemExit("DDGS text search API is unavailable")
    try:
        signature(client.text).bind("probe", max_results=1, backend="auto")
    except TypeError as exc:
        raise SystemExit(f"DDGS text search call shape is incompatible: {exc}") from exc

runtime_backends = tuple(DDGS_TEXT_BACKENDS)
if (
    not runtime_backends
    or any(not isinstance(backend, str) or not backend for backend in runtime_backends)
    or len(set(runtime_backends)) != len(runtime_backends)
):
    raise SystemExit(
        f"oMLX must advertise nonempty unique DDGS text backends, got {runtime_backends}"
    )
missing_backends = sorted(set(runtime_backends) - set(ENGINES["text"]))
if missing_backends:
    raise SystemExit(
        f"oMLX advertises unavailable DDGS text backends: {missing_backends}"
    )

dashboard = Path(omlx.__file__).parent / "admin/static/js/dashboard.js"
matches = re.findall(r"ddgsBackendList:\s*\[([^]]*)\]", dashboard.read_text())
try:
    parsed_backends = literal_eval(f"[{matches[0]}]") if len(matches) == 1 else None
except (SyntaxError, ValueError):
    parsed_backends = None
if not isinstance(parsed_backends, list) or any(
    not isinstance(backend, str) for backend in parsed_backends
):
    raise SystemExit("oMLX DDGS backend UI must contain one literal string array")
ui_backends = tuple(parsed_backends)
if ui_backends != runtime_backends:
    raise SystemExit(
        f"oMLX DDGS backend UI mismatch: runtime {runtime_backends}, UI {ui_backends}"
    )
