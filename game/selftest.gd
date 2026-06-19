## Headless smoke test for the combat logic + generated data.
##
## Run:  godot --headless --script res://selftest.gd
## Exits 0 on success, 1 on failure.
extends SceneTree

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok  - %s" % msg)
	else:
		print("  FAIL- %s" % msg)
		_failures += 1


func _find(characters: Array, name: String) -> Dictionary:
	for c in characters:
		if (c as Dictionary).get("name", "") == name:
			return c
	return {}


func _initialize() -> void:
	print("Wordplay selftest")
	var rng := RandomNumberGenerator.new()
	rng.seed = 99

	var bank := GameLogic.load_bank("res://data/word_bank.json")
	_check(not bank.is_empty(), "word bank loads")
	var pools: Dictionary = bank.get("pools", {})
	var characters: Array = bank.get("characters", [])
	_check(pools.has("creature") and pools.has("item") and pools.has("adjective"),
		"pools have creature/item/adjective")

	# --- fighter setup ---
	var dragon_t := _find(characters, "Dragon")
	_check(not dragon_t.is_empty(), "found Dragon template")
	var enemy := GameLogic.make_fighter(dragon_t)
	_check(enemy.hp == enemy.max_hp and enemy.max_hp == (enemy.tokens as Array).size(),
		"max HP equals word count")

	var owner_ok := false
	for t in enemy.tokens:
		if t.get("kind", "") == GameLogic.KIND_CREATURE and t.get("is_owner", false):
			owner_ok = true
	_check(owner_ok, "enemy has a syntactic owner")
	_check(not GameLogic.is_pacified(enemy.tokens), "Dragon starts un-pacified")

	# --- item power: sharp knife = base 2 x1.5 = 3 ---
	var p0 := GameLogic.item_power(enemy.tokens, 0)
	_check(p0.type == GameLogic.HP_ATTACK and p0.amount == 3,
		"knife resolves to HP attack of 3 (got %s/%d)" % [p0.type, p0.amount])
	var p1 := GameLogic.item_power(enemy.tokens, 1)
	_check(p1.type == GameLogic.WORD_ATTACK and p1.amount >= 1, "hex is a word attack")

	# --- general (HP) attack reduces HP ---
	var knight_t := _find(characters, "Knight")
	var player := GameLogic.make_fighter(knight_t)
	var before_hp: int = enemy.hp
	var r_atk := GameLogic.apply_item(player, enemy, 0, pools, rng)  # spear
	_check(r_atk.type == GameLogic.HP_ATTACK and enemy.hp < before_hp,
		"HP attack lowers enemy HP")

	# --- wards block word attacks ---
	player.wards = 20
	var r_block := GameLogic.apply_item(enemy, player, 1, pools, rng)  # hex
	_check(r_block.scrambled == 0 and r_block.blocked == r_block.amount,
		"wards fully block a word attack")

	# --- HP defense heals ---
	player.wards = 0
	player.hp = player.max_hp - 5
	var r_heal := GameLogic.apply_item(player, enemy, 1, pools, rng)  # shield
	_check(r_heal.type == GameLogic.HP_DEFENSE and player.hp > player.max_hp - 5,
		"HP defense heals the user")

	# --- pacify check responds to sentiment ---
	var pac := GameLogic.make_fighter(dragon_t)
	for t in pac.tokens:
		if t.get("kind", "") in GameLogic.EDITABLE_KINDS:
			t["sentiment"] = GameLogic.POSITIVE
	_check(GameLogic.is_pacified(pac.tokens), "all-positive character is pacified")

	# --- enemy item cycle loops in a known order ---
	var cyc := GameLogic.make_fighter(dragon_t)
	var order: Array = cyc.item_order
	var i0 := GameLogic.next_item_index(cyc); GameLogic.advance_cycle(cyc)
	var i1 := GameLogic.next_item_index(cyc); GameLogic.advance_cycle(cyc)
	var i2 := GameLogic.next_item_index(cyc)
	_check(i0 == order[0] and i1 == order[order.size() - 1] and i2 == order[0],
		"item cycle telegraph loops")

	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILURES: %d" % _failures)
		quit(1)
