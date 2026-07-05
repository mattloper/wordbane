## Between-chapter rewards — one source of truth for their catalog and effects, so
## the scene, the CLI, and the balance sim can't drift apart.
##
## `apply` mutates a plain state dict with keys {hp, max_hp, hints}; each caller
## builds that from its own state and reads it back, so the effect math lives in
## exactly one place.
class_name Boons
extends RefCounted

const HINTS_PER_FOCUS := 3  # hint charges gained per Focus pick (consumable, no refill)

const ALL := [
	{"id": "tough", "label": "Toughness", "desc": "+6 Max HP"},
	{"id": "mend", "label": "Mend", "desc": "Heal to full"},
	{"id": "focus", "label": "Focus", "desc": "+%d Hints" % HINTS_PER_FOCUS},
]


static func ids() -> Array:
	var out: Array = []
	for b in ALL:
		out.append(b.id)
	return out


## The full {id, label, desc} for one boon id (or {} if unknown).
static func entry(id: String) -> Dictionary:
	for b in ALL:
		if b.id == id:
			return b
	return {}


## Up to 3 random boon ids to offer between chapters. All boons repeat (Focus stocks
## more hints, Toughness stacks HP, Mend re-heals), so nothing is filtered out.
static func offer() -> Array:
	var pool := ids()
	pool.shuffle()
	return pool.slice(0, 3)


## "Toughness (+6 Max HP)" — for CLI listings.
static func describe(id: String) -> String:
	for b in ALL:
		if b.id == id:
			return "%s (%s)" % [b.label, b.desc]
	return id


## Apply boon `id` to a state dict {hp, max_hp, hints}, in place.
static func apply(id: String, s: Dictionary) -> void:
	match id:
		"tough":
			s["max_hp"] = int(s["max_hp"]) + 6
			s["hp"] = mini(int(s["max_hp"]), int(s["hp"]) + 6)
		"mend":
			s["hp"] = s["max_hp"]
		"focus":
			s["hints"] = int(s.get("hints", 0)) + HINTS_PER_FOCUS
