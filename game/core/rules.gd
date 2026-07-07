## Loads game/data/rules.json — the single source of truth for tuning + catalogs,
## so the Godot game and any future port read identical numbers. Other core classes
## (Lexicon, Gauntlet, Boons) back their tuning with these, keeping their public
## names (e.g. Gauntlet.START_HP) unchanged.
class_name Rules
extends RefCounted

const PATH := "res://data/rules.json"

static var DATA: Dictionary = _load()


static func _load() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		push_error("rules.json not found: %s" % PATH)
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func section(name: String) -> Dictionary:
	return DATA.get(name, {})

## A value nested under a section, e.g. num("gauntlet", "start_hp", 30).
static func num(section_name: String, key: String, default: float) -> float:
	return float((section(section_name)).get(key, default))
