## Generates an escalating run of enemies from the word-bank pools.
##
## A run is a gauntlet: each victory advances you to a tougher enemy (more weapons,
## meaner adjectives). The generator only builds enemies; run state (HP, depth)
## lives in the scene driving the battles.
class_name Gauntlet
extends RefCounted

const MAX_ITEMS := 4
const MIN_DANGER_MULT := 1.5  # only "dangerous" adjectives arm weapons

var _pools: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func setup(bank: Dictionary) -> void:
	_pools = bank.get("pools", {})
	_rng.randomize()


func _neg(kind: String) -> Array:
	return _pools.get(kind, {}).get(GameLogic.NEGATIVE, [])


func _pick(arr: Array) -> Dictionary:
	return arr[_rng.randi_range(0, arr.size() - 1)]


## Dangerous adjectives (high multiplier), so each weapon is a real threat.
func _danger_adjectives() -> Array:
	var out: Array = []
	for a in _neg(GameLogic.KIND_ADJ):
		if float(a.get("mult", 1.0)) >= MIN_DANGER_MULT:
			out.append(a)
	return out if not out.is_empty() else _neg(GameLogic.KIND_ADJ)


## Build the enemy for a given (1-based) round: more weapons as you go deeper.
func generate(round: int) -> Dictionary:
	var num_items: int = clampi(2 + int((round - 1) / 2.0), 2, MAX_ITEMS)
	var adjs := _danger_adjectives()
	var creature := _pick(_neg(GameLogic.KIND_CREATURE))
	var owner_adj := _pick(adjs)

	var tokens: Array = []
	tokens.append(_fixed("A"))
	tokens.append(_adj(owner_adj, "owner"))
	tokens.append({"text": creature.get("text", "foe"), "kind": GameLogic.KIND_CREATURE,
		"sentiment": GameLogic.NEGATIVE, "is_owner": true})
	tokens.append(_fixed("wields"))

	# Distinct items per enemy (no "wields a hex and a hex").
	var items := _neg(GameLogic.KIND_ITEM).duplicate()
	items.shuffle()
	for i in range(num_items):
		if i > 0:
			tokens.append(_fixed("and"))
		tokens.append(_fixed("a"))
		tokens.append(_adj(_pick(adjs), "item:%d" % i))
		var item: Dictionary = items[i % items.size()]
		tokens.append({"text": item.get("text", "blade"), "kind": GameLogic.KIND_ITEM,
			"sentiment": GameLogic.NEGATIVE, "item_type": item.get("item_type", "hp_attack"),
			"base": int(item.get("base", 2)), "item_index": i})

	return {
		"name": String(creature.get("text", "foe")).capitalize(),
		"role": "enemy",
		"tokens": tokens,
		"item_order": range(num_items),
		"round": round,
	}


func _fixed(text: String) -> Dictionary:
	return {"text": text, "kind": GameLogic.KIND_FIXED}


func _adj(entry: Dictionary, attaches: String) -> Dictionary:
	return {"text": entry.get("text", "grim"), "kind": GameLogic.KIND_ADJ,
		"sentiment": GameLogic.NEGATIVE, "mult": float(entry.get("mult", 1.5)),
		"attaches": attaches}
