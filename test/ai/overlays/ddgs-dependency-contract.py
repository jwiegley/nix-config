import importlib
import sys
from importlib import metadata

import ddgs
import httpx
from ddgs.ddgs import DDGS
from packaging.requirements import Requirement
from packaging.utils import canonicalize_name

HTTPX_EXTRA_IMPORTS = {
    "brotli": "brotli",
    "http2": "h2",
    "socks": "socksio",
}


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
if not active:
    raise SystemExit("DDGS installed METADATA has no runtime requirements")

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

httpx_requirements = [
    requirement
    for requirement in active
    if canonicalize_name(requirement.name) == "httpx"
]
if len(httpx_requirements) != 1:
    raise SystemExit(f"expected one DDGS HTTPX requirement, got {httpx_requirements}")
httpx_extras = httpx_requirements[0].extras
if httpx_extras != HTTPX_EXTRA_IMPORTS.keys():
    raise SystemExit(
        f"DDGS HTTPX extras mismatch: expected {sorted(HTTPX_EXTRA_IMPORTS)}, got {sorted(httpx_extras)}"
    )
for extra in sorted(httpx_extras):
    importlib.import_module(HTTPX_EXTRA_IMPORTS[extra])

http2_client = httpx.Client(http2=True)
http2_client.close()
socks_client = httpx.Client(proxy="socks5://127.0.0.1:1")
socks_client.close()

provider = DDGS()
if not callable(provider.text):
    raise SystemExit("DDGS text search API is unavailable")
