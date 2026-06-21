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

	# --- HP defense heals (find a character that actually has one) ---
	var healer := GameLogic.make_fighter(_find(characters, "Ogre"))
	var heal_idx := -1
	for t in healer.tokens:
		if t.get("kind", "") == GameLogic.KIND_ITEM and t.get("item_type", "") == GameLogic.HP_DEFENSE:
			heal_idx = int(t.get("item_index", -1))
	_check(heal_idx >= 0, "Ogre has an HP-defense item")
	healer.hp = healer.max_hp - 5
	var r_heal := GameLogic.apply_item(healer, healer, heal_idx, pools, rng)
	_check(r_heal.type == GameLogic.HP_DEFENSE and healer.hp > healer.max_hp - 5,
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

	# --- Battle flow (the shared state machine) ---
	var battle := Battle.new()
	root.add_child(battle)
	battle.setup(bank)
	battle.new_game()
	_check(not battle.player.is_empty() and not battle.enemy.is_empty(),
		"battle.new_game sets up both fighters")
	_check(battle.state == Battle.ST_CHOOSE, "battle starts on the player's turn")

	# A word-randomizer item enters targeting mode (this path doesn't await a
	# turn timer, so it's safe to drive synchronously here). The HP-attack /
	# damage math is covered by the apply_item test above.
	var word_idx := -1
	for t in battle.player.tokens:
		if t.get("kind", "") == GameLogic.KIND_ITEM and t.get("item_type", "") == GameLogic.WORD_ATTACK:
			word_idx = int(t.get("item_index", -1))
	if word_idx >= 0:
		battle.use_item(word_idx)
		_check(battle.state == Battle.ST_TARGET, "word-attack item enters targeting mode")
	battle.queue_free()

	# --- WordLadder validation (letter-ladder mechanic) ---
	_check(WordLadder.is_submultiset("fine", "knife"), "'fine' is a sub-multiset of 'knife'")
	_check(not WordLadder.is_submultiset("fix", "knife"), "'fix' is NOT a sub-multiset of 'knife' (no x)")

	var wl := WordLadder.load_from("res://data/dictionary.json")
	_check(not wl.words.is_empty(), "dictionary loads")
	_check(wl.is_word("knife") and wl.is_word("fine"), "known words present")

	# knife -> fin: a valid same-POS shrink (noun -> noun), direction auto-detected.
	var shrink := wl.validate("fin", "knife", "noun", [])
	_check(shrink.get("ok", false) and shrink.get("direction", "") == "shrink",
		"shrink knife->fin is valid (noun->noun)")
	# wolf -> airflow: a valid same-POS grow (bidirectional escapes dead-ends).
	var grow := wl.validate("airflow", "wolf", "noun", [])
	_check(grow.get("ok", false) and grow.get("direction", "") == "grow",
		"grow wolf->airflow is valid (noun->noun)")
	# POS mismatch is rejected: 'fin' is a noun, not an adjective.
	var posbad := wl.validate("fin", "knife", "adjective", [])
	_check(not posbad.get("ok", false), "POS mismatch (fin as adjective) is rejected")
	# Multi-POS now accepted: 'fan' is tagged noun+verb, valid for a noun slot.
	var multi := wl.validate("fan", "fang", "noun", [])
	_check(multi.get("ok", false), "multi-POS 'fan' accepted for a noun slot (fang->fan)")
	# Reuse is rejected.
	var reuse := wl.validate("fin", "knife", "noun", ["fin"])
	_check(not reuse.get("ok", false), "reused word is rejected")
	# Substitution (not pure add/remove) is rejected.
	var subst := wl.validate("wife", "knife", "noun", [])
	_check(not subst.get("ok", false), "substitution (knife->wife) is rejected")

	# --- LadderBattle: disarm, enemy damage, win ---
	var lb := LadderBattle.new()
	lb.ladder = wl
	var foe := {"name": "Test", "tokens": [
		{"text": "A", "kind": GameLogic.KIND_FIXED},
		{"text": "knife", "kind": GameLogic.KIND_ITEM, "sentiment": GameLogic.NEGATIVE,
			"item_type": "hp_attack", "base": 2, "item_index": 0},   # ⚔2
		{"text": "axe", "kind": GameLogic.KIND_ITEM, "sentiment": GameLogic.NEGATIVE,
			"item_type": "hp_attack", "base": 3, "item_index": 1},   # ⚔3
	]}
	lb.begin(foe, 10, 10)
	_check(lb.incoming_damage() == 3, "incoming damage = deadliest weapon (max of 2,3)")
	var d1 := lb.try_move(2, "axle")  # disarm axe(3); surviving knife(2) now deadliest
	_check(d1.get("ok", false) and lb.player_hp == 8, "disarm axe, take knife's 2 damage")
	var d2 := lb.try_move(1, "fin")   # disarm knife; none left -> win, no damage
	_check(d2.get("won", false) and lb.state == LadderBattle.STATE_WON, "disarm all weapons -> win")

	# --- solvability: 'jinx' is a near-dead-end, 'spear' is rich ---
	_check(wl.count_transforms("jinx", "noun", 10) < 10, "'jinx' has few disarms (unfair)")
	_check(wl.count_transforms("spear", "noun", 10) >= 10, "'spear' has plenty of disarms")

	# --- Gauntlet: escalating, distinct, fairly-solvable weapons ---
	var g := Gauntlet.new()
	g.setup(bank, wl)
	var e := g.generate(3)
	var weps: Array = []
	for t in e.tokens:
		if t.get("kind", "") == GameLogic.KIND_ITEM:
			weps.append(t.get("text", ""))
	_check(weps.size() >= 2, "gauntlet enemy has multiple weapons")
	var uniq := {}
	for w in weps:
		uniq[w] = true
	_check(uniq.size() == weps.size(), "gauntlet weapons are distinct (no duplicates)")
	var all_solvable := true
	for w in weps:
		if wl.count_transforms(w, "noun", Gauntlet.MIN_DISARMS) < Gauntlet.MIN_DISARMS:
			all_solvable = false
	_check(all_solvable, "every gauntlet weapon is fairly solvable (no 'jinx')")

	# --- IconBank: emoji clipart for known words ---
	var icons := IconBank.new()
	_check(icons.of("dragon") == "🐉" and icons.of("knife") == "🔪", "known words map to emoji")
	_check(icons.of("zzznotaword") == "", "unknown words map to no emoji")

	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILURES: %d" % _failures)
		quit(1)
