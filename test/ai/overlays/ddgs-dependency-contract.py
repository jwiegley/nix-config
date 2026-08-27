import importlib
import sys
from importlib import metadata
from inspect import signature

import ddgs
import primp
from ddgs.ddgs import DDGS
from ddgs.http_client import HttpClient
from packaging.requirements import Requirement
from packaging.utils import canonicalize_name

EXPECTED_RUNTIME_REQUIREMENTS = {"click", "lxml", "primp"}


expected = sys.argv[1]
installed = metadata.version("ddgs")
if expected != installed or expected != ddgs.__version__:
    raise SystemExit(
        f"DDGS version mismatch: catalog {expected}, metadata {installed}, module {ddgs.__version__}"
    )

requirements = [Requirement(raw) for raw in metadata.requires("ddgs") or []]
active = [
    requirement
    for requirement in requirements
    if requirement.marker is None or requirement.marker.evaluate()
]
actual_requirements = {
    canonicalize_name(requirement.name) for requirement in active
}
if actual_requirements != EXPECTED_RUNTIME_REQUIREMENTS:
    raise SystemExit(
        "DDGS runtime requirements mismatch: "
        f"expected {sorted(EXPECTED_RUNTIME_REQUIREMENTS)}, got {sorted(actual_requirements)}"
    )

for requirement in active:
    selected = metadata.version(requirement.name)
    if requirement.specifier and not requirement.specifier.contains(
        selected, prereleases=True
    ):
        raise SystemExit(
            f"{requirement} is not satisfied by installed {requirement.name} {selected}"
        )
    name = canonicalize_name(requirement.name)
    importlib.import_module(name.replace("-", "_"))

transport = HttpClient(proxy="socks5://127.0.0.1:1", timeout=1)
if not isinstance(transport.client, primp.Client):
    raise SystemExit("DDGS HttpClient does not use the installed primp transport")
if not all(callable(getattr(transport, method, None)) for method in ("get", "post", "request")):
    raise SystemExit("DDGS primp transport API is incomplete")

provider = DDGS(proxy="socks5://127.0.0.1:1", timeout=1)
if not callable(provider.text):
    raise SystemExit("DDGS text search API is unavailable")
try:
    signature(provider.text).bind("probe", max_results=1, backend="auto")
except TypeError as exc:
    raise SystemExit(f"DDGS text search call shape is incompatible: {exc}") from exc
