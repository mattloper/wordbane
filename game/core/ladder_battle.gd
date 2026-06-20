## One letter-ladder battle: disarm the enemy's weapons before they grind you down.
##
## The enemy's weapons are its negative item-nouns; each deals base x adjective
## multiplier damage. On your move you transform ONE weapon noun into a harmless
## word (a real word, same part of speech, add/remove letters, not reused) — that
## disarms it. Then every weapon still standing hits you. Win when all weapons are
## disarmed; lose if your HP hits 0. So order matters: kill the biggest threats
## first, and damage racks up if you can't find a word.
##
## Pure logic (RefCounted): the enemy turn resolves instantly, so no timers/signals
## — callers invoke try_move() and read the returned result.
class_name LadderBattle
extends RefCounted

const STATE_PLAY := "play"
const STATE_WON := "won"
const STATE_LOST := "lost"

var ladder: WordLadder
var enemy: Dictionary = {}
var player_hp := 0
var player_max := 0
var used: Array = []
var state := STATE_PLAY


func begin(enemy_fighter: Dictionary, hp: int, max_hp: int) -> void:
	enemy = enemy_fighter
	player_hp = hp
	player_max = max_hp
	used = []
	state = STATE_PLAY


## Indices of the enemy's surviving weapons (still-negative item nouns).
func weapon_indices() -> Array:
	var out: Array = []
	var tokens: Array = enemy.get("tokens", [])
	for i in range(tokens.size()):
		var t: Dictionary = tokens[i]
		if t.get("kind", "") == GameLogic.KIND_ITEM and t.get("sentiment", "") == GameLogic.NEGATIVE:
			out.append(i)
	return out


## Damage a single weapon token deals (base x adjective multipliers).
func weapon_damage(token_index: int) -> int:
	var t: Dictionary = enemy.tokens[token_index]
	return int(GameLogic.item_power(enemy.tokens, int(t.get("item_index", -1))).get("amount", 0))


## Total damage you'll take next enemy turn from all surviving weapons.
func incoming_damage() -> int:
	var total := 0
	for i in weapon_indices():
		total += weapon_damage(i)
	return total


## Attempt to disarm weapon `idx` by typing `word`. Invalid words cost nothing
## (retry freely); a valid transform ends your turn and the enemy strikes back.
## Returns a rich result dict for the view/log.
func try_move(idx: int, word: String) -> Dictionary:
	if state != STATE_PLAY:
		return {"ok": false, "reason": "battle is over"}
	var tokens: Array = enemy.tokens
	if idx < 0 or idx >= tokens.size():
		return {"ok": false, "reason": "no such word"}
	var tok: Dictionary = tokens[idx]
	if tok.get("kind", "") != GameLogic.KIND_ITEM or tok.get("sentiment", "") != GameLogic.NEGATIVE:
		return {"ok": false, "reason": "pick a red weapon (a noun) to disarm"}

	var target: String = tok.get("text", "")
	var r := ladder.validate(word, target, "noun", used)
	if not r.get("ok", false):
		return r  # invalid — no turn consumed

	# Disarm: rewrite the weapon, re-tag, calm its adjectives.
	var w := word.strip_edges().to_lower()
	tok["text"] = w
	tok["sentiment"] = r.get("sentiment", "neutral")
	used.append(w)
	var calmed := _calm_adjectives_of(tok)

	var res := {"ok": true, "target": target, "word": w,
		"direction": r.get("direction", "?"), "sentiment": r.get("sentiment", "?"),
		"calmed": calmed, "damage": 0, "won": false, "lost": false}

	if weapon_indices().is_empty():
		state = STATE_WON
		res["won"] = true
		return res

	# Enemy turn: surviving weapons strike.
	var dmg := incoming_damage()
	player_hp = maxi(0, player_hp - dmg)
	res["damage"] = dmg
	if player_hp <= 0:
		state = STATE_LOST
		res["lost"] = true
	return res


## Take an enemy hit without disarming (when you truly can't find a word).
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


func _calm_adjectives_of(noun: Dictionary) -> Array:
	var key := "item:%d" % int(noun.get("item_index", -1))
	var calmed: Array = []
	for t in enemy.tokens:
		if t.get("kind", "") == GameLogic.KIND_ADJ and t.get("attaches", "") == key \
				and t.get("sentiment", "") == GameLogic.NEGATIVE:
			t["sentiment"] = GameLogic.NEUTRAL
			calmed.append(t.get("text", ""))
	return calmed
