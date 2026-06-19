## Headless smoke test for the game logic + data.
##
## Run with:  godot --headless --script res://selftest.gd
## Exits 0 on success, 1 on failure — handy for CI without a display server.
extends SceneTree

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok  - %s" % msg)
	else:
		print("  FAIL- %s" % msg)
		_failures += 1


func _initialize() -> void:
	print("Wordplay selftest")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	var bank := GameLogic.load_bank("res://data/word_bank.json")
	_check(not bank.is_empty(), "word bank loads")
	var pools: Dictionary = bank.get("word_pools", {})
	var characters: Array = bank.get("characters", [])
	_check(pools.has("ADJ") and pools.has("NOUN"), "pools have ADJ and NOUN")

	var enemy := GameLogic.pick_character(characters, "enemy", rng)
	var player := GameLogic.pick_character(characters, "player", rng)
	_check(not enemy.is_empty(), "found an enemy character")
	_check(not player.is_empty(), "found a player character")

	var enemy_tokens := GameLogic.clone_tokens(enemy.get("tokens", []))
	_check(GameLogic.count_negative(enemy_tokens) > 0, "enemy starts with negatives")
	_check(not GameLogic.is_defanged(enemy_tokens), "enemy starts threatening")

	# Re-rolls must preserve part of speech.
	var pos_preserved := true
	for t in enemy_tokens:
		if t.get("editable", false):
			var before: String = t.get("pos", "")
			GameLogic.reroll_token(t, pools, [GameLogic.POSITIVE], rng)
			if t.get("pos", "") != before:
				pos_preserved = false
			if t.get("sentiment", "") != GameLogic.POSITIVE:
				pos_preserved = false
	_check(pos_preserved, "reroll preserves POS and applies requested sentiment")
	_check(GameLogic.is_defanged(enemy_tokens), "enemy defanged after all-positive rerolls")

	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILURES: %d" % _failures)
		quit(1)
