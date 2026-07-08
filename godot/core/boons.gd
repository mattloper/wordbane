## Between-chapter rewards — one source of truth for their catalog and effects, so
## the scene, the CLI, and the balance sim can't drift apart.
##
## `offer()` returns resolved INSTANCES ({id, label, desc, arg}) — `arg` carries any
## per-offer parameter, e.g. the random letter of a "Double" boon. `apply(instance,
## state)` mutates a plain state dict {hp, max_hp, hints, letter_mult} in place, so
## the effect math lives in exactly one place.
class_name Boons
extends RefCounted

# Catalog + params from rules.json (Rules), so the game and any port stay in sync.
static var HINTS_PER_FOCUS: int = int(Rules.num("boons", "hints_per_focus", 3))
# Letters a "Double" boon can land on — biased to common, usable ones so the boon is
# worth taking (doubling a letter you never spell would be a dead pick).
static var DOUBLE_LETTERS: String = str(Rules.section("boons").get("double_letters", "eariotnslc"))
static var ALL: Array = Rules.section("boons").get("catalog", [])


static func ids() -> Array:
	var out: Array = []
	for b in ALL:
		out.append(b.id)
	return out


## Build one offerable instance of boon `id`, resolving any per-offer parameter
## (e.g. the random letter of a Double) via the injected `rng`.
static func instance(id: String, rng: Rng) -> Dictionary:
	if id == "double":
		var letter := DOUBLE_LETTERS[rng.range_int(0, DOUBLE_LETTERS.length() - 1)]
		return {"id": "double", "arg": letter, "label": "Double " + letter.to_upper(),
			"desc": "2x score for '%s' (rest of run)" % letter.to_upper()}
	for b in ALL:
		if b.id == id:
			return {"id": b.id, "arg": "", "label": b.label, "desc": b.desc}
	return {}


## Up to 3 resolved boon instances to offer between chapters. All boons repeat, so
## nothing is filtered (Focus stocks hints, Toughness stacks HP, Double stacks too).
static func offer(rng: Rng) -> Array:
	var pool := ids()
	rng.shuffle(pool)
	var out: Array = []
	for id in pool.slice(0, 3):
		out.append(instance(id, rng))
	return out


## "Double E (2x score...)" — for CLI listings.
static func describe(boon: Dictionary) -> String:
	return "%s (%s)" % [boon.label, boon.desc]


## Apply a boon instance to a state dict {hp, max_hp, hints, letter_mult}, in place.
static func apply(boon: Dictionary, s: Dictionary) -> void:
	match boon.id:
		"tough":
			s["max_hp"] = int(s["max_hp"]) + 6
			s["hp"] = mini(int(s["max_hp"]), int(s["hp"]) + 6)
		"mend":
			s["hp"] = s["max_hp"]
		"focus":
			s["hints"] = int(s.get("hints", 0)) + HINTS_PER_FOCUS
		"double":
			var mult: Dictionary = s.get("letter_mult", {})
			mult[boon.arg] = int(mult.get(boon.arg, 1)) * 2
			s["letter_mult"] = mult
