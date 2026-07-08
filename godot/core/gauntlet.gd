## Generates an escalating run of enemies from the word-bank pools.
##
## A run is a gauntlet: each victory advances you to a tougher enemy (more weapons,
## meaner adjectives). The generator only builds enemies; run state (HP, depth)
## lives in the scene driving the battles.
class_name Gauntlet
extends RefCounted

# Run tuning — backed by rules.json (Rules) so the scene, CLI, solver, and any port
# read identical numbers. Names unchanged, so callers still use Gauntlet.START_HP etc.
static var START_HP: int = int(Rules.num("gauntlet", "start_hp", 36))
static var MAX_ITEMS: int = int(Rules.num("gauntlet", "max_items", 2))          # weapons per enemy
static var MIN_DANGER_MULT: float = Rules.num("gauntlet", "min_danger_mult", 1.5)  # min adj mult to arm
static var SCORE_PER_DAMAGE: int = int(Rules.num("gauntlet", "score_per_damage", 3))
static var CHAPTER_BONUS: int = int(Rules.num("gauntlet", "chapter_bonus", 25))  # x chapter number
static var HP_PER_CHAPTER: int = int(Rules.num("gauntlet", "hp_per_chapter", 1))  # enemy HP growth/depth

var _pools: Dictionary = {}
var rng := Rng.new()  # injected/seeded by the caller for reproducible runs
var _usable_items: Array = []  # weapon pool (set in setup)


func setup(bank: Dictionary) -> void:
	_pools = bank.get("pools", {})
	_usable_items = _neg(WordBank.KIND_ITEM)


func _neg(kind: String) -> Array:
	return _pools.get(kind, {}).get(WordBank.NEGATIVE, [])


func _pick(arr: Array) -> Dictionary:
	return rng.pick(arr)


## Dangerous adjectives (high multiplier), so each weapon is a real threat.
func _danger_adjectives() -> Array:
	var out: Array = []
	for a in _neg(WordBank.KIND_ADJ):
		if float(a.get("mult", 1.0)) >= MIN_DANGER_MULT:
			out.append(a)
	return out if not out.is_empty() else _neg(WordBank.KIND_ADJ)


## Build the enemy for a given (1-based) round: one weapon for the first two
## chapters (a gentle intro), two thereafter. Difficulty then comes from bite +
## HP scaling with depth (see below), not from piling on weapons.
func generate(round: int) -> Dictionary:
	var num_items: int = clampi(1 + int((round - 1) / 2.0), 1, MAX_ITEMS)
	var adjs := _danger_adjectives()
	var creature := _pick(_neg(WordBank.KIND_CREATURE))
	var owner_adj := _pick(adjs)

	var tokens: Array = []
	tokens.append(_fixed("A"))
	tokens.append(_adj(owner_adj, "owner"))
	tokens.append({"text": creature.get("text", "foe"), "kind": WordBank.KIND_CREATURE,
		"sentiment": WordBank.NEGATIVE, "is_owner": true})
	tokens.append(_fixed("wields"))

	# Distinct, fairly-solvable items per enemy (no "wields a hex and a hex").
	var items := _usable_items.duplicate()
	rng.shuffle(items)
	for i in range(num_items):
		if i > 0:
			tokens.append(_fixed("and"))
		tokens.append(_fixed("a"))
		tokens.append(_adj(_pick(adjs), "item:%d" % i))
		var item: Dictionary = items[i % items.size()]
		# Weapons hit harder the deeper you go (+1 base every 2 chapters). Since a
		# strong player bursts enemies down in a turn or two, the per-turn bite is the
		# real ceiling — it must climb fast enough to out-pace healing eventually.
		var scaled_base: int = int(item.get("base", 2)) + int((round - 1) / 2.0)
		tokens.append({"text": item.get("text", "blade"), "kind": WordBank.KIND_ITEM,
			"sentiment": WordBank.NEGATIVE, "item_type": item.get("item_type", "hp_attack"),
			"base": scaled_base, "item_index": i})

	var enemy := {
		"name": String(creature.get("text", "foe")).capitalize(),
		"role": "enemy",
		"tokens": tokens,
		"item_order": range(num_items),
		"round": round,
	}
	# Seed the letter pool / HP / bite now, so they survive the CLI's JSON save.
	PoolBattle.seed_enemy(enemy)
	# With weapon count fixed, letters alone no longer make deeper enemies tankier —
	# so scale HP with depth too. Fights get longer AND hits harder as you descend.
	var hp_bonus: int = int((round - 1) * HP_PER_CHAPTER)
	enemy["max_hp"] = int(enemy["max_hp"]) + hp_bonus
	enemy["hp"] = enemy["max_hp"]
	return enemy


func _fixed(text: String) -> Dictionary:
	return {"text": text, "kind": WordBank.KIND_FIXED}


func _adj(entry: Dictionary, attaches: String) -> Dictionary:
	return {"text": entry.get("text", "grim"), "kind": WordBank.KIND_ADJ,
		"sentiment": WordBank.NEGATIVE, "mult": float(entry.get("mult", 1.5)),
		"attaches": attaches}
