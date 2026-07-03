## Between-chapter rewards — one source of truth for their catalog and effects, so
## the scene, the CLI, and the balance sim can't drift apart.
##
## `apply` mutates a plain state dict with keys {hp, max_hp, used, has_hint}; each
## caller builds that from its own state (member vars / run dict / locals) and reads
## it back, so the actual effect math lives in exactly one place.
class_name Boons
extends RefCounted

const ALL := [
	{"id": "tough", "label": "Toughness", "desc": "+6 Max HP"},
	{"id": "mend", "label": "Mend", "desc": "Heal to full"},
	{"id": "eraser", "label": "Eraser", "desc": "Forget all spent words (reuse them)"},
	{"id": "focus", "label": "Focus", "desc": "Gain a Hint button"},
]


static func ids() -> Array:
	var out: Array = []
	for b in ALL:
		out.append(b.id)
	return out


## "Toughness (+6 Max HP)" — for CLI listings.
static func describe(id: String) -> String:
	for b in ALL:
		if b.id == id:
			return "%s (%s)" % [b.label, b.desc]
	return id


## Apply boon `id` to a state dict {hp, max_hp, used, has_hint}, in place.
static func apply(id: String, s: Dictionary) -> void:
	match id:
		"tough":
			s["max_hp"] = int(s["max_hp"]) + 6
			s["hp"] = mini(int(s["max_hp"]), int(s["hp"]) + 6)
		"mend":
			s["hp"] = s["max_hp"]
		"eraser":
			s["used"] = []
		"focus":
			s["has_hint"] = true
