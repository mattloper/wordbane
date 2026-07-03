## Headless CLI to play the full letter-pool gauntlet from the command line.
##
## Drives the real PoolBattle + Gauntlet + Lexicon; run state persists between
## invocations in a JSON file, so each call is one move.
##
##   godot --headless --script res://play.gd -- new
##   godot --headless --script res://play.gd -- state
##   godot --headless --script res://play.gd -- move <word>
##   godot --headless --script res://play.gd -- pass
extends SceneTree

const BANK_PATH := "res://data/word_bank.json"
const DICT_PATH := "res://data/dictionary.json"
const STATE_PATH := "user://wp_run.json"
const START_HP := Gauntlet.START_HP

var _lexicon: Lexicon
var _gauntlet: Gauntlet
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.randomize()
	_lexicon = Lexicon.load_from(DICT_PATH)
	_gauntlet = Gauntlet.new()
	_gauntlet.setup(GameLogic.load_bank(BANK_PATH))
	var args := OS.get_cmdline_user_args()
	var cmd: String = args[0] if args.size() > 0 else "state"
	match cmd:
		"new": _cmd_new()
		"move": _cmd_move(args)
		"pass": _cmd_pass()
		"boon": _cmd_boon(args)
		_: _print_run(_load())
	quit(0)


func _cmd_new() -> void:
	var run := {"depth": 1, "hp": START_HP, "max": START_HP, "score": 0,
		"enemy": _gauntlet.generate(1), "used": [], "over": "",
		"has_hint": false, "choosing": false, "boons": []}
	_save(run)
	print("=== NEW RUN ===")
	_print_run(run)


func _cmd_move(args: Array) -> void:
	var run := _load()
	if run.is_empty() or run.get("over", "") != "":
		print("No active run. Run: new"); return
	if run.get("choosing", false):
		print("Pick a reward first:  boon <id>"); _print_run(run); return
	if args.size() < 2:
		print("usage: move <word>"); return
	var battle := _battle_from(run)
	var word := String(args[1])
	var res := battle.try_move(word)
	if res.get("ok", false) and not res.get("passed", false):
		run.score = int(run.score) + int(res.get("dealt", 0)) * 3
	_after_move(run, battle, res)


func _cmd_pass() -> void:
	var run := _load()
	if run.is_empty() or run.get("over", "") != "":
		print("No active run. Run: new"); return
	var battle := _battle_from(run)
	var res := battle.pass_turn()
	_after_move(run, battle, res)


func _cmd_boon(args: Array) -> void:
	var run := _load()
	if not run.get("choosing", false):
		print("No reward to pick right now."); return
	var id: String = String(args[1]) if args.size() > 1 else ""
	if not (id in run.boons):
		print("Choose one of: %s" % ", ".join(run.boons)); return
	var s := {"hp": run.hp, "max_hp": run.max, "used": run.used, "has_hint": run.has_hint}
	Boons.apply(id, s)
	run.hp = s.hp
	run.max = s.max_hp
	run.used = s.used
	run.has_hint = s.has_hint
	run.choosing = false
	run.boons = []
	run.depth = int(run.depth) + 1
	run.enemy = _gauntlet.generate(int(run.depth))
	_save(run)
	print("Took %s.  Descending to chapter %d...\n" % [id, run.depth])
	_print_run(run)


## Apply a battle result back into the run: log it, advance on win, end on loss.
func _after_move(run: Dictionary, battle: PoolBattle, res: Dictionary) -> void:
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
		var uses := ("  [uses %s]" % ", ".join(Lexicon.upper_letters(res.covered))) if not res.covered.is_empty() else ""
		var tail := "  (enemy HP %d left)" % int(res.hp_left) if not res.get("won", false) else "  -- ENEMY DOWN!"
		print("YOU: %s hits for %d%s%s" % [res.word, int(res.dealt), uses, tail])
		if int(res.damage) > 0:
			print("ENEMY strikes for %d." % res.damage)

	if res.get("lost", false):
		run.over = "lost"
		_save(run)
		print("\n*** DEFEATED in chapter %d. Final score: %d. ***" % [run.depth, run.score])
		return

	if res.get("won", false):
		run.score = int(run.score) + int(run.depth) * 25  # chapter-clear bonus
		run.choosing = true                               # no free heal — recover via boons
		run.boons = _offer_boons(run)
		_save(run)
		print("\n*** CHAPTER %d CLEARED! +%d score. Choose a reward: ***" % [
			run.depth, int(run.depth) * 25])
		for id in run.boons:
			print("    boon %-7s  %s" % [id, Boons.describe(id)])
		return

	_save(run)
	_print_run(run)


## Pick 3 random boon ids to offer (excluding Focus once owned).
func _offer_boons(run: Dictionary) -> Array:
	var pool: Array = Boons.ids()
	if run.get("has_hint", false):
		pool.erase("focus")
	pool.shuffle()
	return pool.slice(0, 3)


# --- helpers -----------------------------------------------------------------

func _battle_from(run: Dictionary) -> PoolBattle:
	var b := PoolBattle.new()
	b.lexicon = _lexicon
	b.enemy = run.enemy
	b.player_hp = int(run.hp)
	b.player_max = int(run.max)
	b.used = run.used
	b.state = PoolBattle.STATE_PLAY
	return b


func _print_run(run: Dictionary) -> void:
	if run.is_empty():
		print("No run. Run: new"); return
	var battle := _battle_from(run)
	var hint := "  [hint]" if run.get("has_hint", false) else ""
	print("CHAPTER %d    HP %d/%d    SCORE %d%s" % [run.depth, run.hp, run.max, run.get("score", 0), hint])
	if run.get("choosing", false):
		print("  Chapter cleared — choose a reward:")
		for id in run.boons:
			print("    boon %-7s  %s" % [id, Boons.describe(id)])
		return
	var tokens: Array = run.enemy.tokens
	var parts: Array = []
	for t in tokens:
		parts.append(t.get("text", ""))
	print("  " + " ".join(parts))  # the enemy sentence (flavor)
	print("  enemy HP %d/%d    bites for %d next turn" % [
		battle.enemy_hp(), battle.enemy_max_hp(), battle.incoming_damage()])
	# The letter pool (a damage guide): each letter with its point value.
	var tiles: Array = []
	for ch in run.enemy.get("letters", []):
		tiles.append("%s:%d" % [String(ch).to_upper(), Lexicon.letter_weight(ch)])
	print("  letters: " + "  ".join(tiles))
	if not (run.used as Array).is_empty():
		print("  used: " + ", ".join(run.used))


func _save(run: Dictionary) -> void:
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(run))


func _load() -> Dictionary:
	if not FileAccess.file_exists(STATE_PATH):
		return {}
	var f := FileAccess.open(STATE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
