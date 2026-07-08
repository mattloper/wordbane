"""Per-model-family generation presets, so choosing a model picks its config
instead of a pile of command-line flags.

`presets.json` is keyed by family, each with a `match` list of substrings tested
against the model filename. Sampler/seed-mode are stored as readable names and
mapped to the FlatBuffer enum ints here.
"""
from __future__ import annotations

import json
import os
import sys

_GEN = os.path.join(os.path.dirname(__file__), "_generated")
if _GEN not in sys.path:
    sys.path.insert(0, _GEN)

from SamplerType import SamplerType  # noqa: E402
from SeedMode import SeedMode        # noqa: E402

_PATH = os.path.join(os.path.dirname(__file__), "presets.json")

# Fields we coerce when they arrive as strings (from `--set k=v` or JSON edits).
_INT_FIELDS = {"width", "height", "steps"}
_FLOAT_FIELDS = {"shift", "guidance_scale", "guidance_embed"}
_BOOL_FIELDS = {"resolution_dependent_shift"}


def _enum_map(cls) -> dict:
    return {k: v for k, v in vars(cls).items() if not k.startswith("_") and isinstance(v, int)}


SAMPLERS = _enum_map(SamplerType)
SEED_MODES = _enum_map(SeedMode)


def load() -> dict:
    with open(_PATH) as f:
        return json.load(f)


def coerce(key: str, value):
    """Coerce a (possibly string) override value to the field's type."""
    if not isinstance(value, str):
        return value
    if key in _INT_FIELDS:
        return int(value)
    if key in _FLOAT_FIELDS:
        return float(value)
    if key in _BOOL_FIELDS:
        return value.strip().lower() in ("1", "true", "yes", "on")
    return value  # sampler / seed_mode stay as names; resolved below


def resolve(model: str, overrides: dict | None = None) -> dict:
    """Return the ready-to-build config for `model`: the matching family preset,
    with `overrides` applied and sampler/seed-mode names turned into enum ints."""
    presets = load()
    match = next(
        (p for p in presets.values() if any(m in model for m in p.get("match", []))),
        None,
    )
    if match is None:
        raise ValueError(
            f"no preset matches model {model!r}. Add a family to presets.json "
            f"(known: {', '.join(presets)})."
        )
    cfg = {k: v for k, v in match.items() if k not in ("match", "note")}
    for k, v in (overrides or {}).items():
        cfg[k] = coerce(k, v)
    cfg["sampler"] = SAMPLERS[cfg["sampler"]] if isinstance(cfg["sampler"], str) else cfg["sampler"]
    cfg["seed_mode"] = SEED_MODES[cfg["seed_mode"]] if isinstance(cfg["seed_mode"], str) else cfg["seed_mode"]
    return cfg
