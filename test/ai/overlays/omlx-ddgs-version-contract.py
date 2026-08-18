import sys
from importlib import metadata

import ddgs
from ddgs import DDGS
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
    or active_requirements[0].extras
    or str(active_requirements[0].specifier) != f"=={expected}"
):
    raise SystemExit(f"oMLX must require exactly ddgs=={expected}, got {requirements}")

installed = metadata.version("ddgs")
if installed != expected or ddgs.__version__ != expected:
    raise SystemExit(
        f"DDGS version mismatch: expected {expected}, metadata {installed}, module {ddgs.__version__}"
    )
client = DDGS()
if type(client).__module__ != "ddgs.ddgs":
    raise SystemExit(f"unexpected DDGS provider: {type(client).__module__}")
if not callable(client.text):
    raise SystemExit("DDGS text search API is unavailable")
