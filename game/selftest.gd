## Headless smoke test for the letter-pool game logic + generated data.
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


func _initialize() -> void:
	print("Wordplay selftest")

	var bank := WordBank.load_bank("res://data/word_bank.json")
	_check(not bank.is_empty(), "word bank loads")
	var pools: Dictionary = bank.get("pools", {})
	_check(pools.has("creature") and pools.has("item") and pools.has("adjective"),
		"pools have creature/item/adjective")

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
		{"text": "A", "kind": WordBank.KIND_FIXED},
		{"text": "axe", "kind": WordBank.KIND_ITEM, "sentiment": WordBank.NEGATIVE,
			"item_type": "hp_attack", "base": 3, "item_index": 0},   # bite 3
		{"text": "knife", "kind": WordBank.KIND_ITEM, "sentiment": WordBank.NEGATIVE,
			"item_type": "hp_attack", "base": 2, "item_index": 1},   # bite 2
	]}
	lb.begin(foe, 30, 30)
	# pool = distinct(axe + knife) = a,e,f,i,k,n,x ; HP = 1+1+4+1+5+1+8 = 21.
	_check(lb.enemy_max_hp() == 21 and lb.enemy_hp() == 21, "enemy HP = total rarity weight of its letters (21)")
	_check(lb.incoming_damage() == 3, "full bite = deadliest weapon (3)")
	# You can't echo the enemy's own weapon word back at it — no turn spent.
	_check(lb.weapons() == ["axe", "knife"], "battle exposes the enemy's weapon words")
	var echo := lb.try_move("axe")
	_check(not echo.get("ok", false) and lb.enemy_hp() == 21 and lb.player_hp == 30,
		"typing the enemy's own weapon is rejected, costs no turn")
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
	g.rng = Rng.new(99)  # deterministic generation
	var e := g.generate(3)
	var weps: Array = []
	for t in e.tokens:
		if t.get("kind", "") == WordBank.KIND_ITEM:
			weps.append(t.get("text", ""))
	_check(weps.size() >= 2, "gauntlet enemy has multiple weapons")
	_check(e.has("letters") and not (e.letters as Array).is_empty(),
		"gauntlet seeds the enemy's letter pool")
	# HP = letter weight + a per-chapter depth bonus (round 3 -> +2*HP_PER_CHAPTER).
	_check(int(e.max_hp) == Lexicon.letters_weight(e.letters) + 2 * Gauntlet.HP_PER_CHAPTER
		and int(e.hp) == int(e.max_hp) and int(e.base_bite) > 0,
		"gauntlet seeds enemy HP (letters + depth bonus) and bite")
	var uniq := {}
	for w in weps:
		uniq[w] = true
	_check(uniq.size() == weps.size(), "gauntlet weapons are distinct (no duplicates)")

	# --- IconBank: emoji clipart for known words ---
	var icons := IconBank.new()
	_check(icons.of("dragon") == "🐉" and icons.of("knife") == "🔪", "known words map to emoji")
	_check(icons.of("zzznotaword") == "", "unknown words map to no emoji")

	# --- Conformance fixtures (the shared cross-engine golden vectors) ---
	_run_conformance(wl, bank)

	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILURES: %d" % _failures)
		quit(1)


## Run the language-neutral golden vectors in data/conformance.json. A JS/HTML port
## runs the SAME file with an equivalent runner — matching outputs = no drift.
func _run_conformance(wl: Lexicon, bank: Dictionary) -> void:
	var c := JsonFile.load_dict("res://data/conformance.json")
	var n := 0

	for t in c["letter_weight"]:
		_check(Lexicon.letter_weight(t[0]) == int(t[1]), "conf letter_weight(%s)" % t[0]); n += 1
	for t in c["word_weight"]:
		_check(Lexicon.word_weight(t[0]) == int(t[1]), "conf word_weight(%s)" % t[0]); n += 1
	for t in c["overlap_damage"]:
		_check(Lexicon.overlap_damage(t[0], t[1]) == int(t[2]), "conf overlap_damage(%s,%s)" % [t[0], t[1]]); n += 1
	for t in c["weighted_overlap"]:
		_check(Lexicon.weighted_overlap(t[0], t[1], t[2]) == int(t[3]), "conf weighted_overlap(%s,%s)" % [t[0], t[1]]); n += 1
	for t in c["shares_letter"]:
		_check(Lexicon.shares_letter(t[0], t[1]) == bool(t[2]), "conf shares_letter(%s,%s)" % [t[0], t[1]]); n += 1
	for t in c["covered_letters"]:
		_check(Lexicon.covered_letters(t[0], t[1]) == t[2], "conf covered_letters(%s,%s)" % [t[0], t[1]]); n += 1
	for t in c["boon_apply"]:
		var s: Dictionary = (t["in"] as Dictionary).duplicate(true)
		Boons.apply(t["boon"], s)
		_check(_eq(s, t["out"]), "conf boon_apply(%s)" % t["boon"].get("id", "?")); n += 1
	for t in c["rng_u32"]:
		var r := Rng.new(int(t[0]))
		var got: Array = []
		for _i in range(t[1].size()):
			got.append(r.next_u32())
		_check(_eq(got, t[1]), "conf rng_u32(seed=%d)" % int(t[0])); n += 1
	for t in c["generate_sentence"]:
		var g := Gauntlet.new()
		g.setup(bank)
		g.rng = Rng.new(int(t[0]))
		var e := g.generate(int(t[1]))
		var parts: Array = []
		for tok in e.tokens:
			parts.append(tok.get("text", ""))
		_check(" ".join(parts) == String(t[2]), "conf generate_sentence(seed=%d)" % int(t[0])); n += 1

	print("  (ran %d conformance vectors)" % n)


## Numeric-aware deep equality (JSON parses all numbers as float; our code returns
## ints, and Godot's container == is type-strict, so we coerce numbers here).
func _eq(a, b) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _eq(a[k], b[k]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _eq(a[i], b[i]):
				return false
		return true
	return a == b
