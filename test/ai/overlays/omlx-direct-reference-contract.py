import sys
from importlib import import_module, metadata
from pathlib import Path

from mlx_embeddings import generate as generate_embeddings
from mlx_embeddings import load as load_embeddings
from mlx_embeddings.utils import prepare_inputs
from mlx_vlm.tokenizer_utils import load_tokenizer
from mlx_vlm.utils import (
    StoppingCriteria,
    get_model_path,
    load,
    load_model,
    load_processor,
)
from mlx_vlm.utils import prepare_inputs as prepare_vlm_inputs
from omlx.patches.mlx_vlm_qwen4_exp_compat import (
    apply_mlx_vlm_qwen4_exp_compat_patch,
    is_applied,
)
from packaging.requirements import Requirement
from packaging.utils import canonicalize_name

expected_versions = {
    "mlx-embeddings": sys.argv[1],
    "mlx-vlm": sys.argv[2],
}
requirements = [Requirement(raw) for raw in metadata.requires("omlx") or []]

for distribution, expected in expected_versions.items():
    matches = [
        requirement
        for requirement in requirements
        if canonicalize_name(requirement.name) == distribution
    ]
    if (
        len(matches) != 1
        or matches[0].marker is not None
        or matches[0].extras
        or matches[0].url is not None
        or str(matches[0].specifier)
    ):
        raise SystemExit(
            f"oMLX must require exactly one unversioned {distribution}, got {matches}"
        )

    installed = metadata.version(distribution)
    if installed != expected:
        raise SystemExit(
            f"{distribution} version mismatch: selected {expected}, installed {installed}"
        )

required_apis = {
    "mlx_embeddings.load": load_embeddings,
    "mlx_embeddings.generate": generate_embeddings,
    "mlx_embeddings.utils.prepare_inputs": prepare_inputs,
    "mlx_vlm.tokenizer_utils.load_tokenizer": load_tokenizer,
    "mlx_vlm.utils.StoppingCriteria": StoppingCriteria,
    "mlx_vlm.utils.get_model_path": get_model_path,
    "mlx_vlm.utils.load": load,
    "mlx_vlm.utils.load_model": load_model,
    "mlx_vlm.utils.load_processor": load_processor,
    "mlx_vlm.utils.prepare_inputs": prepare_vlm_inputs,
}
missing = [name for name, value in required_apis.items() if not callable(value)]
if missing:
    raise SystemExit(f"oMLX dependency APIs are not callable: {missing}")

if not apply_mlx_vlm_qwen4_exp_compat_patch() and not is_applied():
    raise SystemExit("oMLX Qwen4 compatibility patch did not apply")
compat_module = import_module("omlx.patches.mlx_vlm_qwen4_exp_compat")
qwen4_language = import_module("mlx_vlm.models.qwen4_exp.language")
vendor_root = Path(compat_module.__file__).resolve().parent / "vendor"
if not Path(qwen4_language.__file__).resolve().is_relative_to(vendor_root):
    raise SystemExit("oMLX Qwen4 model did not resolve from its vendored compatibility tree")
embedding = qwen4_language.ShardedEmbedding(8, 4, 2)
if "weight_scale" not in embedding.parameters():
    raise SystemExit("oMLX Qwen4 embedding omitted its strict-load weight_scale parameter")
