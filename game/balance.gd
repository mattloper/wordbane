## Difficulty-balancing harness (dev tool, not part of the game).
##
## Auto-plays the gauntlet to measure the difficulty curve after tuning changes.
## Models a LIMITED-VOCABULARY player: for each weapon they know only the K
## hardest-hitting shared-letter words — a rough proxy for what a person can
## actually think of. With run-wide no-reuse, those known words get spent, so the
## player eventually must Skip (take a hit) — which is the real new difficulty.
##
## Reports reached depth for several vocab sizes K, so you can tune HP/bite/ramp
## (in Gauntlet) against a realistic player, not a perfect solver.
##
##   godot --headless --script res://balance.gd
extends SceneTree

const RUNS := 60
const DEPTH_CAP := 60
# Vocabulary modelled as the max word LENGTH a player commands: everyone knows
# short words; fewer know long ones. 99 = knows every word (a perfect speller).
const VOCAB_LENS := [3, 4, 5, 99]

var _lexicon: Lexicon
var _known_cache: Dictionary = {}  # "letters|maxlen" -> [words, best damage first]


func _initialize() -> void:
	_lexicon = Lexicon.load_from("res://data/dictionary.json")
	var g := Gauntlet.new()
	g.setup(GameLogic.load_bank("res://data/word_bank.json"))

	print("Tuning: START_HP=%d" % Gauntlet.START_HP)
	for k in VOCAB_LENS:
		var depths: Array = []
		for run in range(RUNS):
			depths.append(_play_run(g, k, run))
		depths.sort()
		var sum := 0.0
		for d in depths:
			sum += d
		var label: String = "any-len" if k >= 99 else "len<=%d" % k
		print("  vocab=%-7s depth: min=%2d median=%2d max=%2d mean=%.1f" % [
			label, depths[0], depths[depths.size() / 2], depths[-1], sum / depths.size()])
	quit(0)


## Play one run with a K-word-per-weapon vocabulary; return depth reached.
## Recovery now comes only from boons (no free heal) — the player heals when low,
## else grows. Models Focus (a hint) as being able to find ANY word for the pool.
func _play_run(g: Gauntlet, vocab: int, seed_offset: int) -> int:
	var hp: int = Gauntlet.START_HP
	var max_hp: int = Gauntlet.START_HP
	var used: Array = []
	var has_hint := false
	var depth := 0
	while depth < DEPTH_CAP:
		depth += 1
		var b := PoolBattle.new()
		b.lexicon = _lexicon
		b.begin(g.generate(depth), hp, max_hp)
		b.used = used
		var safety := 0
		while b.state == PoolBattle.STATE_PLAY and safety < 60:
			safety += 1
			var word := _best_known_move(b, vocab, has_hint)
			if word.is_empty():
				b.pass_turn()  # no findable word — eat a hit
			else:
				b.try_move(word)
		if b.state != PoolBattle.STATE_WON:
			break  # lost, or stuck (couldn't drain the pool) — run ends
		hp = b.player_hp
		# Pick a boon: heal when low, else grow, else relieve vocab, else hint.
		var offer: Array = Boons.ids() if not has_hint else Boons.ids().filter(func(x): return x != "focus")
		var pick := "focus"
		if hp <= max_hp * 0.45 and "mend" in offer:
			pick = "mend"
		elif "tough" in offer:
			pick = "tough"
		elif "eraser" in offer:
			pick = "eraser"
		var s := {"hp": hp, "max_hp": max_hp, "used": used, "has_hint": has_hint}
		Boons.apply(pick, s)
		hp = int(s.hp); max_hp = int(s.max_hp); used = s.used; has_hint = bool(s.has_hint)
	return depth


## The highest-damage fresh word (within our max-length vocabulary) for this enemy.
## If Focus is owned, fall back to the full dictionary as a hint.
func _best_known_move(b: PoolBattle, maxlen: int, has_hint: bool) -> String:
	for w in _known_words(b.letters(), maxlen):
		if not (w in b.used):
			return w  # list is pre-sorted best-damage first
	if has_hint:
		return _lexicon.best_word("".join(b.letters()), b.used)
	return ""


## Every word within our max length that uses this enemy's letters, best-damage
## first (cached by letter-set + maxlen). Models "the words a player commands".
func _known_words(letters: Array, maxlen: int) -> Array:
	var key: String = "".join(letters) + "|" + str(maxlen)
	if not _known_cache.has(key):
		var letters_str: String = "".join(letters)
		var scored: Array = []  # [word, damage]
		for w in _lexicon.words:
			if w.length() <= maxlen:
				var d := Lexicon.overlap_damage(w, letters_str)
				if d > 0:
					scored.append([w, d])
		scored.sort_custom(func(a, c): return a[1] > c[1] if a[1] != c[1] else a[0].length() < c[0].length())
		var found: Array = []
		for pair in scored:
			found.append(pair[0])
		_known_cache[key] = found
	return _known_cache[key]
