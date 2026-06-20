## Headless CLI to play the letter-ladder game from the command line.
##
## Drives the real WordLadder + GameLogic + dictionary; state persists between
## invocations in a JSON file, so each call is one move. Lets a human (or an agent)
## play and playtest the actual rules without the GUI.
##
##   godot --headless --script res://play.gd -- new [EnemyName]
##   godot --headless --script res://play.gd -- state
##   godot --headless --script res://play.gd -- move <index> <word>
##   godot --headless --script res://play.gd -- hint <index> [count]   # calibration
extends SceneTree

const BANK_PATH := "res://data/word_bank.json"
const DICT_PATH := "res://data/dictionary.json"
const STATE_PATH := "user://wp_play.json"

const KIND_POS := {
	GameLogic.KIND_ITEM: "noun",
	GameLogic.KIND_CREATURE: "noun",
	GameLogic.KIND_ADJ: "adjective",
}

var _ladder: WordLadder


func _initialize() -> void:
	_ladder = WordLadder.load_from(DICT_PATH)
	var args := OS.get_cmdline_user_args()
	var cmd: String = args[0] if args.size() > 0 else "state"
	match cmd:
		"new": _cmd_new(args)
		"move": _cmd_move(args)
		"hint": _cmd_hint(args)
		_: _print_state(_load(), "")
	quit(0)


# --- commands ----------------------------------------------------------------

func _cmd_new(args: Array) -> void:
	var bank := GameLogic.load_bank(BANK_PATH)
	var characters: Array = bank.get("characters", [])
	var template: Dictionary = {}
	if args.size() > 1:
		for c in characters:
			if (c as Dictionary).get("name", "").to_lower() == String(args[1]).to_lower():
				template = c
	if template.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		template = GameLogic.pick_character(characters, "enemy", rng)
	var state := {
		"enemy": GameLogic.make_fighter(template),
		"used": [],
	}
	_save(state)
	_print_state(state, "New enemy: %s" % state.enemy.name)


func _cmd_move(args: Array) -> void:
	var state := _load()
	if state.is_empty():
		print("No game in progress. Run: new"); return
	if args.size() < 3:
		print("usage: move <index> <word>"); return
	var idx := int(args[1])
	var word := String(args[2])
	var tokens: Array = state.enemy.tokens
	if idx < 0 or idx >= tokens.size():
		print("bad index %d" % idx); return
	var tok: Dictionary = tokens[idx]
	if not (tok.get("kind", "") in GameLogic.EDITABLE_KINDS):
		print("token [%d] '%s' is fixed scenery — not editable" % [idx, tok.get("text", "")]); return

	var target: String = tok.get("text", "")
	var required_pos: String = KIND_POS.get(tok.get("kind", ""), "")
	var r := _ladder.validate(word, target, required_pos, state.used)
	if not r.get("ok", false):
		_print_state(state, "REJECTED %s -> %s : %s" % [target, word, r.get("reason", "")])
		return

	tok["text"] = word.strip_edges().to_lower()
	tok["sentiment"] = r.get("sentiment", "neutral")
	state.used.append(tok["text"])
	var note := ""
	if tok.get("kind", "") in [GameLogic.KIND_ITEM, GameLogic.KIND_CREATURE] \
			and r.get("sentiment", "") != GameLogic.NEGATIVE:
		var calmed := _neutralize_adjectives_of(tokens, tok)
		if not calmed.is_empty():
			note = "  (calmed: %s)" % ", ".join(calmed)
	_save(state)
	_print_state(state, "OK  %s -> %s  [%s, %s]%s" % [
		target, tok["text"], r.get("direction", "?"), r.get("sentiment", "?"), note])


## Calibration helper: list some valid ladder words for a noun (NOT used in play).
func _cmd_hint(args: Array) -> void:
	var state := _load()
	if state.is_empty() or args.size() < 2:
		print("usage: hint <index> [count]"); return
	var idx := int(args[1])
	var count: int = int(args[2]) if args.size() > 2 else 12
	var tok: Dictionary = state.enemy.tokens[idx]
	var target: String = tok.get("text", "")
	var pos: String = KIND_POS.get(tok.get("kind", ""), "")
	var found: Array = []
	for w in _ladder.words:
		if found.size() >= count:
			break
		var r := _ladder.validate(w, target, pos, state.used)
		if r.get("ok", false) and r.get("sentiment", "") != GameLogic.NEGATIVE:
			found.append("%s(%s,%s)" % [w, r.direction, r.sentiment])
	print("hint for [%d] %s (%s): %s" % [idx, target, pos, ", ".join(found)])


# --- helpers -----------------------------------------------------------------

func _neutralize_adjectives_of(tokens: Array, noun: Dictionary) -> Array:
	var key := ""
	if noun.get("kind", "") == GameLogic.KIND_ITEM:
		key = "item:%d" % int(noun.get("item_index", -1))
	elif noun.get("kind", "") == GameLogic.KIND_CREATURE:
		key = "owner"
	if key == "":
		return []
	var calmed: Array = []
	for t in tokens:
		if t.get("kind", "") == GameLogic.KIND_ADJ and t.get("attaches", "") == key \
				and t.get("sentiment", "") == GameLogic.NEGATIVE:
			t["sentiment"] = GameLogic.NEUTRAL
			calmed.append(t.get("text", ""))
	return calmed


func _weapons_left(tokens: Array) -> int:
	var n := 0
	for t in tokens:
		if t.get("kind", "") in [GameLogic.KIND_ITEM, GameLogic.KIND_CREATURE] \
				and t.get("sentiment", "") == GameLogic.NEGATIVE:
			n += 1
	return n


func _print_state(state: Dictionary, msg: String) -> void:
	if state.is_empty():
		print("No game. Run: new"); return
	if msg != "":
		print(msg)
	var tokens: Array = state.enemy.tokens
	var parts: Array = []
	for i in range(tokens.size()):
		var t: Dictionary = tokens[i]
		var kind: String = t.get("kind", "")
		if kind == GameLogic.KIND_FIXED:
			parts.append(t.get("text", ""))
		else:
			var sign: String = {"positive": "+", "negative": "-", "neutral": "0"}.get(t.get("sentiment", ""), "?")
			var k: String = {"noun": "N", "adjective": "A"}.get(KIND_POS.get(kind, ""), "?")
			parts.append("[%d]%s(%s%s)" % [i, t.get("text", ""), k, sign])
	print("  " + " ".join(parts))
	var left := _weapons_left(tokens)
	print("  weapons left (negative nouns): %d" % left)
	if left == 0:
		print("  *** DISARMED — you win! ***")
	else:
		var lines: Array = []
		for i in range(tokens.size()):
			var t: Dictionary = tokens[i]
			if t.get("kind", "") in [GameLogic.KIND_ITEM, GameLogic.KIND_CREATURE] \
					and t.get("sentiment", "") == GameLogic.NEGATIVE:
				lines.append("    [%d] %s  letters: %s" % [
					i, t.get("text", ""), " ".join(_sorted_letters(t.get("text", "")))])
		print("  targets (disarm these nouns):")
		for l in lines:
			print(l)
	if not (state.used as Array).is_empty():
		print("  used: " + ", ".join(state.used))


func _sorted_letters(w: String) -> Array:
	var chars: Array = []
	for ch in w.to_lower():
		chars.append(ch)
	chars.sort()
	return chars


func _save(state: Dictionary) -> void:
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(state))


func _load() -> Dictionary:
	if not FileAccess.file_exists(STATE_PATH):
		return {}
	var f := FileAccess.open(STATE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
