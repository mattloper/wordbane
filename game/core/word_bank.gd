## Shared word-bank loading + item-power resolution for Wordplay.
##
## Token kinds (from the Python parser):
##   fixed     : {text}                                          — scenery
##   adjective : {text, sentiment, mult, attaches}               — a multiplier
##   creature  : {text, sentiment, is_owner}                     — the owner
##   item      : {text, sentiment, item_type, base, item_index}  — a weapon
class_name WordBank
extends RefCounted

const NEGATIVE := "negative"  # enemies are built from the "negative" vocabulary pools

const KIND_FIXED := "fixed"
const KIND_ADJ := "adjective"
const KIND_CREATURE := "creature"
const KIND_ITEM := "item"

const HP_ATTACK := "hp_attack"


static func load_bank(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("word bank not found: %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("word bank is not a JSON object")
		return {}
	return parsed


static func item_token(tokens: Array, item_index: int) -> Dictionary:
	for t in tokens:
		if t.get("kind", "") == KIND_ITEM and int(t.get("item_index", -1)) == item_index:
			return t
	return {}

## The adjective tokens modifying a given item.
static func item_adjectives(tokens: Array, item_index: int) -> Array:
	var key := "item:%d" % item_index
	var adjs: Array = []
	for t in tokens:
		if t.get("kind", "") == KIND_ADJ and t.get("attaches", "") == key:
			adjs.append(t)
	return adjs

## Combined multiplier from every adjective modifying this item.
static func item_multiplier(tokens: Array, item_index: int) -> float:
	var mult := 1.0
	for t in item_adjectives(tokens, item_index):
		mult *= float(t.get("mult", 1.0))
	return mult

## Resolve an item to {type, base, mult, amount, noun}. amount = base * mult,
## rounded, min 1 — a weapon's per-turn bite in the letter-pool game.
static func item_power(tokens: Array, item_index: int) -> Dictionary:
	var noun := item_token(tokens, item_index)
	if noun.is_empty():
		return {}
	var base := int(noun.get("base", 1))
	var mult := item_multiplier(tokens, item_index)
	return {
		"type": noun.get("item_type", HP_ATTACK),
		"base": base,
		"mult": mult,
		"amount": maxi(1, int(round(float(base) * mult))),
		"noun": noun.get("text", ""),
	}
