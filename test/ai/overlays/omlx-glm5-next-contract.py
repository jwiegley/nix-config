from types import SimpleNamespace
from unittest import mock

import mlx.core as mx

from omlx.patches.glm_moe_dsa.deepseek_v32 import Model as DSV32Model
from omlx.patches.mlx_vlm_glm5_next_compat import (
    apply_mlx_vlm_glm5_next_compat_patch,
    is_applied,
)

if not apply_mlx_vlm_glm5_next_compat_patch() and not is_applied():
    raise SystemExit("oMLX GLM-5.3 compatibility patch did not apply")

from mlx_vlm.models.glm5_next.glm5_next import Model
from mlx_vlm.models.glm5_next.language import LanguageModel
from mlx_vlm.prompt_utils import MODEL_CONFIG
from mlx_vlm.utils import _quantization_for_module_path

if "glm5_next" not in MODEL_CONFIG:
    raise SystemExit("glm5_next prompt format is not registered")

model_proxy = SimpleNamespace(
    quantization_path_aliases=lambda path: Model.quantization_path_aliases(None, path)
 )
quantization = {"group_size": 64, "bits": 4, "mode": "affine"}

for projection in ("f_a_proj", "f_b_proj"):
    model_path = (
        f"language_model.model.layers.0.self_attn.forget_gate.{projection}"
    )
    checkpoint_path = f"language_model.model.layers.0.self_attn.{projection}"
    aliases = Model.quantization_path_aliases(SimpleNamespace(), model_path)
    if checkpoint_path not in aliases:
        raise SystemExit(
            f"GLM-5.3 quantization alias missing: {model_path} -> {checkpoint_path}"
        )
    quantization[checkpoint_path] = {
        "group_size": 64,
        "bits": 8,
        "mode": "affine",
    }
    selected = _quantization_for_module_path(
        quantization, model_path, model_proxy
    )
    if selected != quantization[checkpoint_path]:
        raise SystemExit(
            f"GLM-5.3 quantization recipe alias was not selected for {model_path}"
        )

weights = {
    f"model.layers.0.self_attn.{projection}.{suffix}": mx.array([1.0])
    for projection in ("f_a_proj", "f_b_proj")
    for suffix in ("weight", "scales", "biases")
}
with mock.patch.object(DSV32Model, "sanitize", lambda _self, values: values):
    sanitized = LanguageModel.sanitize(SimpleNamespace(), weights)
for projection in ("f_a_proj", "f_b_proj"):
    for suffix in ("weight", "scales", "biases"):
        expected = f"model.layers.0.self_attn.forget_gate.{projection}.{suffix}"
        if expected not in sanitized:
            raise SystemExit(f"GLM-5.3 quantized parameter was not remapped: {expected}")

text_only = SimpleNamespace(
    language_model=SimpleNamespace(sanitize=lambda values: values),
    vision_model=None,
)
sanitized = Model.sanitize(
    text_only,
    {
        "model.visual.blocks.0.attn.qkv.weight": mx.array([1.0]),
        "vision_tower.blocks.0.attn.qkv.weight": mx.array([1.0]),
    },
)
if sanitized:
    raise SystemExit(
        f"GLM-5.3 text-only load retained orphaned vision parameters: {sorted(sanitized)}"
    )
