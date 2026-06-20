## Pure, UI-free combat logic for Wordplay.
##
## A "fighter" is a Dictionary built from a parsed character:
##   {
##     name, role,
##     tokens: Array,        # the sentence (see token shapes below)
##     item_order: Array,    # item_index values, the cycle order
##     max_hp: int, hp: int,
##     cycle_index: int,     # which item the fighter uses next (enemy telegraph)
##     wards: int,           # queued randomization blocks
##   }
##
## Token kinds (from the Python parser):
##   fixed     : {text}                                   — scenery, not editable
##   adjective : {text, sentiment, mult, attaches}        — a multiplier
##   creature  : {text, sentiment, is_owner}              — the owner; deals no damage
##   item      : {text, sentiment, item_type, base, item_index} — what attacks/defends
class_name GameLogic
extends RefCounted

const POSITIVE := "positive"
const NEGATIVE := "negative"
const NEUTRAL := "neutral"
const SENTIMENTS := [POSITIVE, NEGATIVE, NEUTRAL]

const KIND_FIXED := "fixed"
const KIND_ADJ := "adjective"
const KIND_CREATURE := "creature"
const KIND_ITEM := "item"
const EDITABLE_KINDS := [KIND_ADJ, KIND_CREATURE, KIND_ITEM]

const HP_ATTACK := "hp_attack"
const WORD_ATTACK := "word_attack"
const HP_DEFENSE := "hp_defense"
const WORD_DEFENSE := "word_defense"
const OFFENSIVE_TYPES := [HP_ATTACK, WORD_ATTACK]


# --- loading / setup ---------------------------------------------------------

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


## The part of speech a replacement word must have to fill a token's role,
## so the sentence stays grammatical. "" for non-word tokens.
static func pos_for_kind(kind: String) -> String:
	match kind:
		KIND_ITEM, KIND_CREATURE: return "noun"
		KIND_ADJ: return "adjective"
		_: return ""


static func clone_tokens(tokens: Array) -> Array:
	var out: Array = []
	for t in tokens:
		out.append((t as Dictionary).duplicate(true))
	return out


static func pick_character(characters: Array, role: String, rng: RandomNumberGenerator) -> Dictionary:
	var matches: Array = []
	for c in characters:
		if (c as Dictionary).get("role", "") == role:
			matches.append(c)
	if matches.is_empty():
		return {}
	return matches[rng.randi_range(0, matches.size() - 1)]


static func make_fighter(template: Dictionary) -> Dictionary:
	var max_hp: int = int(template.get("max_hp", 0))
	return {
		"name": template.get("name", "?"),
		"role": template.get("role", ""),
		"tokens": clone_tokens(template.get("tokens", [])),
		"item_order": (template.get("item_order", []) as Array).duplicate(),
		"max_hp": max_hp,
		"hp": max_hp,
		"cycle_index": 0,
		"wards": 0,
	}


# --- queries -----------------------------------------------------------------

static func count_negative(tokens: Array) -> int:
	var n := 0
	for t in tokens:
		if t.get("kind", "") in EDITABLE_KINDS and t.get("sentiment", "") == NEGATIVE:
			n += 1
	return n

## Pacified = no negative words remain (one of the two ways to win).
static func is_pacified(tokens: Array) -> bool:
	return count_negative(tokens) == 0

static func editable_indices(tokens: Array) -> Array:
	var idx: Array = []
	for i in range(tokens.size()):
		if (tokens[i] as Dictionary).get("kind", "") in EDITABLE_KINDS:
			idx.append(i)
	return idx

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
## rounded, min 1 — this is the general-attack damage / heal / scramble count.
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

## "sharp knife" — adjective(s) + the item noun, for display.
static func item_label(tokens: Array, item_index: int) -> String:
	var words: Array = []
	for t in item_adjectives(tokens, item_index):
		words.append(t.get("text", ""))
	words.append(item_token(tokens, item_index).get("text", "?"))
	return " ".join(words)


# --- mutation ----------------------------------------------------------------

## Re-roll one editable token in place: same KIND, random sentiment, fresh word.
## Keeps structural fields (item_index / attaches) so items stay wired up.
static func reroll_token(token: Dictionary, pools: Dictionary, rng: RandomNumberGenerator) -> String:
	var kind: String = token.get("kind", "")
	if not (kind in EDITABLE_KINDS):
		return ""
	if not pools.has(kind):
		return ""
	var sentiment: String = SENTIMENTS[rng.randi_range(0, SENTIMENTS.size() - 1)]
	var choices: Array = pools[kind].get(sentiment, [])
	if choices.is_empty():
		return ""
	var current: String = token.get("text", "")
	var entry: Dictionary = choices[rng.randi_range(0, choices.size() - 1)]
	for _attempt in range(8):
		if entry.get("text", "") != current:
			break
		entry = choices[rng.randi_range(0, choices.size() - 1)]
	token["text"] = entry.get("text", current)
	token["sentiment"] = sentiment
	if kind == KIND_ITEM:
		token["item_type"] = entry.get("item_type", HP_ATTACK)
		token["base"] = entry.get("base", 1)
	elif kind == KIND_ADJ:
		token["mult"] = entry.get("mult", 1.0)
	return token["text"]


## Scramble up to `count` random editable words (used for auto-targeted attacks,
## e.g. the enemy AI). Returns {scrambled: [token_index...], blocked: int}.
static func scramble_words(target: Dictionary, count: int, pools: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array = editable_indices(target.tokens)
	var scrambled: Array = []
	var blocked := 0
	var done := 0
	while done < count and not pool.is_empty():
		var token_index: int = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		var r := scramble_one(target, token_index, pools, rng)
		if r.get("blocked", false):
			blocked += 1
		elif r.get("ok", false):
			scrambled.append(token_index)
		done += 1
	return {"scrambled": scrambled, "blocked": blocked}


## Scramble one specific token (player-chosen target), honoring the owner's wards.
## Returns {ok, blocked, text}. ok=false if the token isn't editable.
static func scramble_one(target: Dictionary, token_index: int, pools: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var tokens: Array = target.tokens
	if token_index < 0 or token_index >= tokens.size():
		return {"ok": false}
	var tok: Dictionary = tokens[token_index]
	if not (tok.get("kind", "") in EDITABLE_KINDS):
		return {"ok": false}
	if int(target.wards) > 0:
		target.wards = int(target.wards) - 1
		return {"ok": true, "blocked": true, "text": tok.get("text", "")}
	var word := reroll_token(tok, pools, rng)
	return {"ok": true, "blocked": false, "text": word}


## Apply one item from `attacker` (offensive items hit `defender`, defensive
## items buff `attacker`). Returns a result dict for the UI/messages.
static func apply_item(attacker: Dictionary, defender: Dictionary, item_index: int, pools: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var power := item_power(attacker.tokens, item_index)
	if power.is_empty():
		return {"ok": false}
	var kind: String = power.type
	var amount: int = power.amount
	var res := {"ok": true, "type": kind, "amount": amount,
		"item": item_label(attacker.tokens, item_index)}

	match kind:
		HP_ATTACK:
			var before: int = defender.hp
			defender.hp = maxi(0, int(defender.hp) - amount)
			res["dmg"] = before - int(defender.hp)
		WORD_ATTACK:
			var r := scramble_words(defender, amount, pools, rng)
			res["scrambled"] = (r.scrambled as Array).size()
			res["blocked"] = r.blocked
		HP_DEFENSE:
			var before2: int = attacker.hp
			attacker.hp = mini(int(attacker.max_hp), int(attacker.hp) + amount)
			res["healed"] = int(attacker.hp) - before2
		WORD_DEFENSE:
			attacker.wards = int(attacker.wards) + amount
			res["wards"] = amount
	return res


## The item a fighter will use next (for the enemy telegraph). -1 if none.
static func next_item_index(fighter: Dictionary) -> int:
	var order: Array = fighter.item_order
	if order.is_empty():
		return -1
	return int(order[int(fighter.cycle_index) % order.size()])

static func advance_cycle(fighter: Dictionary) -> void:
	var order: Array = fighter.item_order
	if not order.is_empty():
		fighter.cycle_index = (int(fighter.cycle_index) + 1) % order.size()
