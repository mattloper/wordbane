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

	# --- Lexicon: letter rarity, damage, validation (letter-overlap mechanic) ---
	_check(Lexicon.letter_weight("e") == 1 and Lexicon.letter_weight("x") == 8
		and Lexicon.letter_weight("z") == 10, "rare letters weigh more than common ones")
	# 'hex' = h(4)+e(1)+x(8) = 13 HP; 'rat' = r+a+t = 3 HP.
	_check(Lexicon.word_weight("hex") == 13, "weapon HP = summed letter weights ('hex' = 13)")
	_check(Lexicon.word_weight("rat") == 3, "'rat' HP = 3")
	# Distinct letters only: repeats don't double-count.
	_check(Lexicon.word_weight("otto") == 2, "distinct-letter HP ('otto' = o+t = 2)")
	_check(Lexicon.shares_letter("art", "rat") and not Lexicon.shares_letter("dog", "rat"),
		"shares_letter detects a common letter")
	# 'vex' vs 'hex': covers e(1)+x(8) but not h -> 9 of 13 damage.
	_check(Lexicon.overlap_damage("vex", "hex") == 9, "damage = weight of covered letters (vex vs hex = 9)")
	_check(Lexicon.overlap_damage("art", "rat") == 3, "full-coverage word deals full HP (art vs rat = 3)")

	var wl := Lexicon.load_from("res://data/dictionary.json")
	_check(not wl.words.is_empty(), "dictionary loads")
	_check(wl.is_word("knife") and wl.is_word("fine"), "known words present")

	# Any real word sharing a letter is valid; result carries its damage.
	var hit := wl.validate("fine", "knife", [])
	_check(hit.get("ok", false) and int(hit.get("dealt", 0)) == Lexicon.overlap_damage("fine", "knife"),
		"a shared-letter word is a valid strike carrying its damage")
	# No shared letter is rejected.
	var nomatch := wl.validate("gum", "knife", [])
	_check(not nomatch.get("ok", false), "a word with no shared letter is rejected")
	# Not-a-word is rejected.
	var nonword := wl.validate("zzzq", "knife", [])
	_check(not nonword.get("ok", false), "a non-dictionary word is rejected")
	# Reuse is rejected.
	var reuse := wl.validate("fine", "knife", ["fine"])
	_check(not reuse.get("ok", false), "reused word is rejected")
	# Hint finds a real, fresh, shared-letter word.
	var hint := wl.best_word("knife", [])
	_check(hint != "" and wl.is_word(hint) and Lexicon.shares_letter(hint, "knife"),
		"best_word returns a real shared-letter word")

	# --- PoolBattle: letter pool, drain damage, flat bite, win ---
	var lb := PoolBattle.new()
	lb.lexicon = wl
	var foe := {"name": "Test", "tokens": [
		{"text": "A", "kind": GameLogic.KIND_FIXED},
		{"text": "axe", "kind": GameLogic.KIND_ITEM, "sentiment": GameLogic.NEGATIVE,
			"item_type": "hp_attack", "base": 3, "item_index": 0},   # bite 3
		{"text": "knife", "kind": GameLogic.KIND_ITEM, "sentiment": GameLogic.NEGATIVE,
			"item_type": "hp_attack", "base": 2, "item_index": 1},   # bite 2
	]}
	lb.begin(foe, 30, 30)
	# pool = distinct(axe + knife) = a,e,f,i,k,n,x ; HP = 1+1+4+1+5+1+8 = 21.
	_check(lb.enemy_max_hp() == 21 and lb.enemy_hp() == 21, "enemy HP = total rarity weight of its letters (21)")
	_check(lb.incoming_damage() == 3, "full bite = deadliest weapon (3)")
	# 'fake' covers f+a+k+e = 4+1+5+1 = 11 -> HP 21 -> 10.
	var m1 := lb.try_move("fake")
	_check(m1.get("ok", false) and int(m1.dealt) == 11 and lb.enemy_hp() == 10,
		"a word drains HP by the letters it covers (deals 11)")
	_check(("a" in lb.letters()) and ("x" in lb.letters()), "letters persist as a guide (not consumed)")
	_check(lb.incoming_damage() == 3, "bite is flat while alive (still 3)")
	_check(lb.player_hp == 27, "enemy struck back for its full 3")
	# A word using none of the enemy's letters is rejected — no turn spent.
	var miss := lb.try_move("mob")
	_check(not miss.get("ok", false) and lb.player_hp == 27, "a word sharing no letter is rejected")
	# Common letters keep chipping (they persist): 'fan' covers f+a+n = 6 -> HP 4.
	var m2 := lb.try_move("fan")
	_check(int(m2.dealt) == 6 and lb.enemy_hp() == 4 and lb.player_hp == 24,
		"you can whittle HP with common letters (no rare-letter wall)")
	# 'ink' covers i+n+k = 1+1+5 = 7 >= 4 -> HP 0 -> win.
	var m3 := lb.try_move("ink")
	_check(m3.get("won", false) and lb.state == PoolBattle.STATE_WON, "draining HP to 0 -> win")

	# --- Gauntlet: escalating, distinct weapons, seeded letter pool ---
	var g := Gauntlet.new()
	g.setup(bank)
	var e := g.generate(3)
	var weps: Array = []
	for t in e.tokens:
		if t.get("kind", "") == GameLogic.KIND_ITEM:
			weps.append(t.get("text", ""))
	_check(weps.size() >= 2, "gauntlet enemy has multiple weapons")
	_check(e.has("letters") and not (e.letters as Array).is_empty(),
		"gauntlet seeds the enemy's letter pool")
	_check(int(e.max_hp) == Lexicon.letters_weight(e.letters)
		and int(e.hp) == int(e.max_hp) and int(e.base_bite) > 0,
		"gauntlet seeds enemy HP (letter weight, full) and bite")
	var uniq := {}
	for w in weps:
		uniq[w] = true
	_check(uniq.size() == weps.size(), "gauntlet weapons are distinct (no duplicates)")

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
