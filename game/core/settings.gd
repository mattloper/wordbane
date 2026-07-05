## Persisted player settings + records, in one place so every screen reads/writes
## the same keys (art style, portrait model, best run). Backed by a user:// config.
class_name Settings
extends RefCounted

const PATH := "user://wordplay.cfg"

const DEFAULT_STYLE := "storybook"
const DEFAULT_MODEL := "flux_2_klein_9b_q8p.ckpt"

# Art styles for the Options dropdown; `key` must match wordplay_art.portrait.STYLES.
const STYLES := [
	{"key": "storybook", "label": "Storybook"},
	{"key": "flat-sticker", "label": "Flat sticker"},
	{"key": "enamel-pin", "label": "Enamel pin"},
	{"key": "pixel-art", "label": "Pixel art"},
	{"key": "woodcut-ink", "label": "Woodcut"},
]
# Portrait models; `file` is the Draw Things filename (resolves to a preset).
const MODELS := [
	{"label": "Klein 4b — fastest", "file": "flux_2_klein_4b_q8p.ckpt"},
	{"label": "Klein 9b — balanced", "file": "flux_2_klein_9b_q8p.ckpt"},
	{"label": "Dev — slow, best", "file": "flux_2_dev_q8p.ckpt"},
]


static func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # missing file is fine — we return an empty config
	return cfg


static func get_style() -> String:
	return str(_load().get_value("art", "style", DEFAULT_STYLE))

static func set_style(style: String) -> void:
	var cfg := _load()
	cfg.set_value("art", "style", style)
	cfg.save(PATH)


static func get_model() -> String:
	return str(_load().get_value("art", "model", DEFAULT_MODEL))

static func set_model(model: String) -> void:
	var cfg := _load()
	cfg.set_value("art", "model", model)
	cfg.save(PATH)


## Best run so far, as {depth, score} (0/0 if none yet).
static func get_best() -> Dictionary:
	var cfg := _load()
	return {"depth": int(cfg.get_value("record", "depth", 0)),
		"score": int(cfg.get_value("record", "score", 0))}

## Record a finished run; returns true if it's a new best (by score).
static func record_run(depth: int, score: int) -> bool:
	var cfg := _load()
	if score <= int(cfg.get_value("record", "score", 0)):
		return false
	cfg.set_value("record", "depth", depth)
	cfg.set_value("record", "score", score)
	cfg.save(PATH)
	return true
