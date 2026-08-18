import importlib
import sys
from importlib import metadata

from mlx_vlm.version import __version__ as module_version
from packaging.requirements import Requirement
from packaging.utils import canonicalize_name

IMPORT_NAMES = {
    "mlx-audio": "mlx_audio",
    "opencv-python": "cv2",
    "pillow": "PIL",
    "python-multipart": "multipart",
}


expected = sys.argv[1]
installed = metadata.version("mlx-vlm")
if expected != installed or expected != module_version:
    raise SystemExit(
        "mlx-vlm version mismatch: "
        f"catalog {expected}, metadata {installed}, module {module_version}"
    )

requirements = [Requirement(raw) for raw in metadata.requires("mlx-vlm") or []]
active = [
    requirement
    for requirement in requirements
    if requirement.marker is None or requirement.marker.evaluate()
]
if not active:
    raise SystemExit("mlx-vlm installed METADATA has no runtime requirements")

for requirement in active:
    selected = metadata.version(requirement.name)
    if requirement.specifier and not requirement.specifier.contains(
        selected, prereleases=True
    ):
        raise SystemExit(
            f"{requirement} is not satisfied by installed {requirement.name} {selected}"
        )
    name = canonicalize_name(requirement.name)
    importlib.import_module(IMPORT_NAMES.get(name, name.replace("-", "_")))
