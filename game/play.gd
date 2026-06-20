## Headless CLI to play the full letter-ladder gauntlet from the command line.
##
## Drives the real LadderBattle + Gauntlet + WordLadder; run state persists between
## invocations in a JSON file, so each call is one move.
##
##   godot --headless --script res://play.gd -- new
##   godot --headless --script res://play.gd -- state
##   godot --headless --script res://play.gd -- move <index> <word>
##   godot --headless --script res://play.gd -- pass
extends SceneTree

const BANK_PATH := "res://data/word_bank.json"
const DICT_PATH := "res://data/dictionary.json"
const STATE_PATH := "user://wp_run.json"
const START_HP := 24
const HEAL := 6

var _ladder: WordLadder
var _gauntlet: Gauntlet


func _initialize() -> void:
	_ladder = WordLadder.load_from(DICT_PATH)
	_gauntlet = Gauntlet.new()
	_gauntlet.setup(GameLogic.load_bank(BANK_PATH))
	var args := OS.get_cmdline_user_args()
	var cmd: String = args[0] if args.size() > 0 else "state"
	match cmd:
		"new": _cmd_new()
		"move": _cmd_move(args)
		"pass": _cmd_pass()
		_: _print_run(_load())
	quit(0)


func _cmd_new() -> void:
	var run := {"depth": 1, "hp": START_HP, "max": START_HP,
		"enemy": _gauntlet.generate(1), "used": [], "over": ""}
	_save(run)
	print("=== NEW RUN ===")
	_print_run(run)


func _cmd_move(args: Array) -> void:
	var run := _load()
	if run.is_empty() or run.get("over", "") != "":
		print("No active run. Run: new"); return
	if args.size() < 3:
		print("usage: move <index> <word>"); return
	var battle := _battle_from(run)
	var res := battle.try_move(int(args[1]), String(args[2]))
	_after_move(run, battle, res)


func _cmd_pass() -> void:
	var run := _load()
	if run.is_empty() or run.get("over", "") != "":
		print("No active run. Run: new"); return
	var battle := _battle_from(run)
	var res := battle.pass_turn()
	_after_move(run, battle, res)


## Apply a battle result back into the run: log it, advance/heal on win, end on loss.
func _after_move(run: Dictionary, battle: LadderBattle, res: Dictionary) -> void:
	if not res.get("ok", false):
		print("REJECTED: " + str(res.get("reason", "invalid")))
		_print_run(run)  # unchanged
		return

	# Persist the battle's mutations back into the run.
	run.enemy = battle.enemy
	run.used = battle.used
	run.hp = battle.player_hp

	if res.get("passed", false):
		print("You hesitate — enemy strikes for %d." % res.damage)
	else:
		var note := ("  (calmed %s)" % ", ".join(res.calmed)) if not res.calmed.is_empty() else ""
		print("YOU: %s -> %s  [%s, %s]%s" % [
			res.target, res.word, res.direction, res.sentiment, note])
		if int(res.damage) > 0:
			print("ENEMY strikes for %d." % res.damage)

	if res.get("lost", false):
		run.over = "lost"
		_save(run)
		print("\n*** DEFEATED at depth %d. Final score: %d enemies cleared. ***" % [
			run.depth, run.depth - 1])
		return

	if res.get("won", false):
		var cleared: int = run.depth
		run.hp = mini(int(run.max), int(run.hp) + HEAL)
		run.depth = cleared + 1
		run.enemy = _gauntlet.generate(run.depth)
		run.used = []
		_save(run)
		print("\n*** ENEMY DISARMED! +%d HP. Descending to depth %d... ***\n" % [HEAL, run.depth])
		_print_run(run)
		return

	_save(run)
	_print_run(run)


# --- helpers -----------------------------------------------------------------

func _battle_from(run: Dictionary) -> LadderBattle:
	var b := LadderBattle.new()
	b.ladder = _ladder
	b.enemy = run.enemy
	b.player_hp = int(run.hp)
	b.player_max = int(run.max)
	b.used = run.used
	b.state = LadderBattle.STATE_PLAY
	return b


func _print_run(run: Dictionary) -> void:
	if run.is_empty():
		print("No run. Run: new"); return
	var battle := _battle_from(run)
	print("DEPTH %d    HP %d/%d" % [run.depth, run.hp, run.max])
	var tokens: Array = run.enemy.tokens
	var parts: Array = []
	for i in range(tokens.size()):
		var t: Dictionary = tokens[i]
		if t.get("kind", "") == GameLogic.KIND_FIXED:
			parts.append(t.get("text", ""))
		else:
			var sign: String = {"positive": "+", "negative": "-", "neutral": "0"}.get(t.get("sentiment", ""), "?")
			parts.append("[%d]%s(%s)" % [i, t.get("text", ""), sign])
	print("  " + " ".join(parts))
	var weapons := battle.weapon_indices()
	print("  incoming damage next turn: %d   (weapons: %d)" % [battle.incoming_damage(), weapons.size()])
	for i in weapons:
		var t: Dictionary = tokens[i]
		print("    [%d] %s  (⚔%d)  letters: %s" % [
			i, t.get("text", ""), battle.weapon_damage(i), " ".join(_letters(t.get("text", "")))])
	if not (run.used as Array).is_empty():
		print("  used: " + ", ".join(run.used))


func _letters(w: String) -> Array:
	var chars: Array = []
	for ch in w.to_lower():
		chars.append(ch)
	chars.sort()
	return chars


func _save(run: Dictionary) -> void:
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(run))


func _load() -> Dictionary:
	if not FileAccess.file_exists(STATE_PATH):
		return {}
	var f := FileAccess.open(STATE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
