## Loads data/rules.json — the single source of truth for tuning + catalogs,
## so the Godot game and any future port read identical numbers. Other core classes
## (Lexicon, Gauntlet, Boons) back their tuning with these, keeping their public
## names (e.g. Gauntlet.START_HP) unchanged.
class_name Rules
extends RefCounted

const PATH := "res://../data/rules.json"

static var DATA: Dictionary = _load()


static func _load() -> Dictionary:
	var data := JsonFile.load_dict(PATH)
	if data.is_empty():
		push_error("rules.json not found/empty: %s" % PATH)
	return data


static func section(name: String) -> Dictionary:
	return DATA.get(name, {})

## A value nested under a section, e.g. num("gauntlet", "start_hp", 30).
static func num(section_name: String, key: String, default: float) -> float:
	return float((section(section_name)).get(key, default))
