import sys
from importlib import metadata

from packaging.markers import default_environment
from packaging.requirements import Requirement
from packaging.utils import canonicalize_name

if len(sys.argv[1:]) % 2:
    raise SystemExit("expected distribution/version argument pairs")

expected = {
    canonicalize_name(name): version
    for name, version in zip(sys.argv[1::2], sys.argv[2::2])
}
requirements = [Requirement(raw) for raw in metadata.requires("omlx") or []]
environment = default_environment() | {"extra": ""}

for requirement in requirements:
    if requirement.marker is not None and not requirement.marker.evaluate(environment):
        continue
    if requirement.url is not None:
        raise SystemExit(
            f"oMLX direct reference survived Nix source validation: {requirement}"
        )
    installed = metadata.version(requirement.name)
    if requirement.specifier and installed not in requirement.specifier:
        raise SystemExit(
            f"oMLX requirement {requirement} is not satisfied by {installed}"
        )

for distribution, selected in expected.items():
    installed = metadata.version(distribution)
    if installed != selected:
        raise SystemExit(
            f"oMLX dependency mismatch for {distribution}: selected {selected}, "
            f"installed {installed}"
        )
