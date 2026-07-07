## One letter-pool battle: drain the enemy's HP before it grinds you down.
##
## The enemy is a POOL OF LETTERS — the distinct letters across all its weapon
## nouns — and an HP bar equal to the total rarity weight of those letters (common
## e/a/t = 1, rare k=5, j/x=8, q/z=10). On your move you type ANY real word that
## uses at least one of its letters; it deals damage = the summed rarity weight of
## the letters it covers, draining the bar. Rare letters are a big burst (landing an
## X is +8) but never required — you can whittle it down with common letters too, so
## you never get walled. Drain HP to 0 to win. Each turn the enemy strikes back
## (a flat bite). Lose at 0 HP. No word may be reused in a run, so vocabulary is the
## real limiter.
##
## Pure logic (RefCounted): the enemy turn resolves instantly, so no timers/signals
## — callers invoke try_move() and read the returned result.
class_name PoolBattle
extends RefCounted

const STATE_PLAY := "play"
const STATE_WON := "won"
const STATE_LOST := "lost"

var lexicon: Lexicon
var enemy: Dictionary = {}
var player_hp := 0
var player_max := 0
var used: Array = []
var state := STATE_PLAY
var letter_mult: Dictionary = {}  # letter -> value multiplier (from Double boons)


## Start a fight. NOTE: `used` is NOT cleared here — no-reuse spans the whole run,
## so the caller seeds `used` once at run start and it carries between battles.
func begin(enemy_fighter: Dictionary, hp: int, max_hp: int) -> void:
	enemy = enemy_fighter
	player_hp = hp
	player_max = max_hp
	state = STATE_PLAY
	seed_enemy(enemy)


## Derive the letter pool / HP / bite from an enemy's weapon tokens, if absent.
## Idempotent: the Gauntlet seeds this at generation, so it survives the CLI's
## JSON save; this also covers hand-built/test enemies.
static func seed_enemy(e: Dictionary) -> void:
	if not e.has("weapons"):
		e["weapons"] = weapon_words(e.get("tokens", []))
	if not e.has("letters"):
		e["letters"] = weapon_letters(e.get("tokens", []))
	if not e.has("max_hp"):
		e["max_hp"] = Lexicon.letters_weight(e["letters"])
	if not e.has("hp"):
		e["hp"] = e["max_hp"]
	if not e.has("base_bite"):
		e["base_bite"] = max_bite(e.get("tokens", []))


## The enemy's weapon nouns (lowercased). You can't just echo these back at it —
## typing the weapon you can see is a one-shot cheat — so they're banned this fight.
static func weapon_words(tokens: Array) -> Array:
	var out: Array = []
	for t in tokens:
		if t.get("kind", "") == WordBank.KIND_ITEM and t.get("sentiment", "") == WordBank.NEGATIVE:
			out.append(String(t.get("text", "")).to_lower())
	return out


## The distinct letters across all of an enemy's weapon nouns (its negative items).
static func weapon_letters(tokens: Array) -> Array:
	var set: Dictionary = {}
	for t in tokens:
		if t.get("kind", "") == WordBank.KIND_ITEM and t.get("sentiment", "") == WordBank.NEGATIVE:
			for ch in Lexicon.distinct_letters(t.get("text", "")):
				set[ch] = true
	var out: Array = set.keys()
	out.sort()
	return out


## The enemy's full-strength bite: its deadliest weapon (base x adjective mult).
static func max_bite(tokens: Array) -> int:
	var worst := 0
	for t in tokens:
		if t.get("kind", "") == WordBank.KIND_ITEM and t.get("sentiment", "") == WordBank.NEGATIVE:
			worst = maxi(worst, int(WordBank.item_power(tokens, int(t.get("item_index", -1))).get("amount", 0)))
	return worst


# --- live state --------------------------------------------------------------

## The enemy's letters (fixed — a damage guide; they aren't consumed as you drain).
func letters() -> Array:
	return enemy.get("letters", [])

## The enemy's own weapon words — banned as moves this fight (no echoing them back).
func weapons() -> Array:
	return enemy.get("weapons", [])

## Remaining HP (drains as you land words; the letters themselves stay).
func enemy_hp() -> int:
	return int(enemy.get("hp", 0))

func enemy_max_hp() -> int:
	return int(enemy.get("max_hp", enemy_hp()))


## Damage the enemy deals each turn while it's still alive (its deadliest weapon).
## Flat — it hits just as hard at 1 HP as at full — so drawn-out fights really cost
## you, and a fast, hard-hitting drain is rewarded. 0 once it's dead.
func incoming_damage() -> int:
	return 0 if enemy_hp() <= 0 else int(enemy.get("base_bite", 0))


# --- moves -------------------------------------------------------------------

## Validate a move WITHOUT applying it — bans the enemy's own weapon words, then
## defers to the usual dictionary/letter/reuse rules. Same result shape as
## Lexicon.validate, so the view can reuse it for a live preview.
func check(word: String) -> Dictionary:
	var w := word.strip_edges().to_lower()
	if w in weapons():
		return {"ok": false, "reason": "'%s' is the enemy's own weapon — use a different word" % w}
	var letters_str := "".join(letters())
	var r := lexicon.validate(word, letters_str, used)
	if r.get("ok", false):  # re-weight damage by any Double-boon letter multipliers
		r["dealt"] = Lexicon.weighted_overlap(w, letters_str, letter_mult)
	return r


## Attempt to strike the enemy by typing `word`. Invalid words cost nothing (retry
## freely); a valid word deals its covered-letter damage, drains the HP bar, ends
## your turn, and the enemy strikes back. Returns a rich result for view/log.
func try_move(word: String) -> Dictionary:
	if state != STATE_PLAY:
		return {"ok": false, "reason": "battle is over"}

	var letters_str := "".join(letters())
	var r := check(word)
	if not r.get("ok", false):
		return r  # invalid — no turn consumed

	# Land the hit: spend the word, drain HP by the letters it covers.
	var w := word.strip_edges().to_lower()
	var dealt: int = int(r.get("dealt", 0))
	var covered: Array = Lexicon.covered_letters(w, letters_str)
	used.append(w)
	enemy["hp"] = maxi(0, enemy_hp() - dealt)

	var res := {"ok": true, "word": w, "dealt": dealt, "covered": covered,
		"hp_left": enemy_hp(), "damage": 0, "won": false, "lost": false}

	if enemy_hp() <= 0:
		state = STATE_WON
		res["won"] = true
		return res

	# Enemy turn.
	var dmg := incoming_damage()
	player_hp = maxi(0, player_hp - dmg)
	res["damage"] = dmg
	if player_hp <= 0:
		state = STATE_LOST
		res["lost"] = true
	return res


## Take an enemy hit without striking (when you truly can't find a word).
func pass_turn() -> Dictionary:
	if state != STATE_PLAY:
		return {"ok": false}
	var dmg := incoming_damage()
	player_hp = maxi(0, player_hp - dmg)
	var res := {"ok": true, "passed": true, "damage": dmg, "lost": false}
	if player_hp <= 0:
		state = STATE_LOST
		res["lost"] = true
	return res
