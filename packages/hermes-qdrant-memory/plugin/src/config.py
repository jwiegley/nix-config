import copy
import logging
from pathlib import Path
from typing import Any, Dict

import yaml

logger = logging.getLogger(__name__)

_DEFAULT_CONFIG_PATH = Path(__file__).parent / "default_config.yaml"


def _load_defaults() -> Dict[str, Any]:
    raw = yaml.safe_load(_DEFAULT_CONFIG_PATH.read_text(encoding="utf-8")) or {}
    return (raw.get("plugins", {}) or {}).get("qdrant", {}) or {}


DEFAULTS: Dict[str, Any] = _load_defaults()


def _deep_merge(base: Dict[str, Any], overlay: Dict[str, Any]) -> Dict[str, Any]:
    result = copy.deepcopy(base)
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def load_config() -> Dict[str, Any]:
    """Return defaults merged with user overrides from ~/.hermes/config.yaml."""
    try:
        from hermes_cli.config import cfg_get
        from hermes_constants import get_hermes_home
    except ImportError:
        return copy.deepcopy(DEFAULTS)

    config_path = get_hermes_home() / "config.yaml"
    if not config_path.exists():
        return copy.deepcopy(DEFAULTS)

    try:
        with open(config_path, encoding="utf-8-sig") as f:
            raw = yaml.safe_load(f) or {}
        if not isinstance(raw, dict):
            raise TypeError("Hermes config root is not a mapping")
        user_cfg = cfg_get(raw, "plugins", "qdrant", default={}) or {}
        if not isinstance(user_cfg, dict):
            raise TypeError("plugins.qdrant is not a mapping")
        return _deep_merge(DEFAULTS, user_cfg)
    except Exception as exc:
        raise RuntimeError("failed to load the managed Qdrant plugin configuration") from exc


def save_plugin_config(values: Dict[str, Any], hermes_home: str) -> None:
    config_path = Path(hermes_home) / "config.yaml"

    existing: Dict[str, Any] = {}
    if config_path.exists():
        with open(config_path, encoding="utf-8-sig") as f:
            existing = yaml.safe_load(f) or {}
    if not isinstance(existing, dict):
        existing = {}

    # Persist only user overrides, merged onto any existing ones. Defaults stay
    # in default_config.yaml so a later default change still reaches the user.
    plugins = existing.setdefault("plugins", {})
    current = plugins.get("qdrant") or {}
    plugins["qdrant"] = _deep_merge(current, values or {})

    config_path.parent.mkdir(parents=True, exist_ok=True)
    with open(config_path, "w", encoding="utf-8") as f:
        yaml.safe_dump(existing, f, default_flow_style=False, sort_keys=False)
