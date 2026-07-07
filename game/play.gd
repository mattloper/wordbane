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

var _lexicon: Lexicon
var _gauntlet: Gauntlet
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_rng.randomize()
	_lexicon = Lexicon.load_from(DICT_PATH)
	_gauntlet = Gauntlet.new()
	_gauntlet.setup(WordBank.load_bank(BANK_PATH))
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
	# One seeded RNG stream per run; its 32-bit state persists in the save so the
	# stream continues (and stays reproducible) across CLI invocations.
	_gauntlet.rng = Rng.new(int(Time.get_unix_time_from_system() * 1000.0) & 0xffffffff)
	var run := {"depth": 1, "hp": Gauntlet.START_HP, "max": Gauntlet.START_HP, "score": 0,
		"enemy": _gauntlet.generate(1), "used": [], "over": "",
		"hints": 0, "letter_mult": {}, "choosing": false, "boons": [],
		"rng_state": _gauntlet.rng.state}
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
		# res.dealt already includes any Double-boon letter multipliers.
		run.score = int(run.score) + int(res.get("dealt", 0)) * Gauntlet.SCORE_PER_DAMAGE
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
	var chosen: Dictionary = {}
	for b in run.boons:
		if b.get("id", "") == id:
			chosen = b
	if chosen.is_empty():
		var ids: Array = (run.boons as Array).map(func(b): return b.id)
		print("Choose one of: %s" % ", ".join(ids)); return
	var s := {"hp": run.hp, "max_hp": run.max, "hints": run.get("hints", 0),
		"letter_mult": run.get("letter_mult", {})}
	Boons.apply(chosen, s)
	run.hp = s.hp
	run.max = s.max_hp
	run.hints = s.hints
	run.letter_mult = s.letter_mult
	run.choosing = false
	run.boons = []
	run.depth = int(run.depth) + 1
	_gauntlet.rng = Rng.new()
	_gauntlet.rng.state = int(run.get("rng_state", 0))
	run.enemy = _gauntlet.generate(int(run.depth))
	run.rng_state = _gauntlet.rng.state
	_save(run)
	print("Took %s.  Descending to chapter %d...\n" % [chosen.label, run.depth])
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
		var bonus := int(run.depth) * Gauntlet.CHAPTER_BONUS
		run.score = int(run.score) + bonus
		run.choosing = true  # no free heal — recover via boons
		run.boons = _offer_boons(run)
		_save(run)
		print("\n*** CHAPTER %d CLEARED! +%d score. Choose a reward: ***" % [run.depth, bonus])
		for b in run.boons:
			print("    boon %-7s  %s" % [b.id, Boons.describe(b)])
		return

	_save(run)
	_print_run(run)


## Pick 3 random boon ids to offer (excluding Focus once owned).
func _offer_boons(run: Dictionary) -> Array:
	var rng := Rng.new()
	rng.state = int(run.get("rng_state", 0))
	var out := Boons.offer(rng)
	run.rng_state = rng.state  # persist the advanced stream
	return out


# --- helpers -----------------------------------------------------------------

func _battle_from(run: Dictionary) -> PoolBattle:
	var b := PoolBattle.new()
	b.lexicon = _lexicon
	b.enemy = run.enemy
	b.player_hp = int(run.hp)
	b.player_max = int(run.max)
	b.used = run.used
	b.letter_mult = run.get("letter_mult", {})
	b.state = PoolBattle.STATE_PLAY
	return b


func _print_run(run: Dictionary) -> void:
	if run.is_empty():
		print("No run. Run: new"); return
	var battle := _battle_from(run)
	var hint := "  [hints %d]" % int(run.hints) if int(run.get("hints", 0)) > 0 else ""
	print("CHAPTER %d    HP %d/%d    SCORE %d%s" % [run.depth, run.hp, run.max, run.get("score", 0), hint])
	if run.get("choosing", false):
		print("  Chapter cleared — choose a reward:")
		for b in run.boons:
			print("    boon %-7s  %s" % [b.id, Boons.describe(b)])
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
