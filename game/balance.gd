## Difficulty-balancing harness (dev tool, not part of the game).
##
## Auto-plays the gauntlet to measure the difficulty curve after tuning changes.
## Models a LIMITED-VOCABULARY player: for each weapon they know only the K
## easiest (shortest, then alphabetical) disarms — a rough proxy for what a person
## can actually think of. With run-wide no-reuse, those known words get spent, so
## the player eventually must Skip (take a hit) — which is the real new difficulty.
##
## Reports reached depth for several vocab sizes K, so you can tune HP/HEAL/ramp
## (in Gauntlet) against a realistic player, not a perfect solver.
##
##   godot --headless --script res://balance.gd
extends SceneTree

const RUNS := 60
const DEPTH_CAP := 60
const VOCAB_SIZES := [4, 6, 8, 999]  # 999 ≈ perfect vocabulary

var _ladder: WordLadder
var _disarm_cache: Dictionary = {}  # weapon word -> [disarms, easiest first]


func _initialize() -> void:
	_ladder = WordLadder.load_from("res://data/dictionary.json")
	var g := Gauntlet.new()
	g.setup(GameLogic.load_bank("res://data/word_bank.json"), _ladder)

	print("Tuning: START_HP=%d HEAL=%d" % [Gauntlet.START_HP, Gauntlet.HEAL])
	for k in VOCAB_SIZES:
		var depths: Array = []
		for run in range(RUNS):
			depths.append(_play_run(g, k, run))
		depths.sort()
		var sum := 0.0
		for d in depths:
			sum += d
		var label: String = "perfect" if k >= 999 else str(k)
		print("  vocab=%-7s depth: min=%2d median=%2d max=%2d mean=%.1f" % [
			label, depths[0], depths[depths.size() / 2], depths[-1], sum / depths.size()])
	quit(0)


## Play one run with a K-word-per-weapon vocabulary; return depth reached.
func _play_run(g: Gauntlet, vocab: int, seed_offset: int) -> int:
	var hp: int = Gauntlet.START_HP
	var used: Array = []
	var depth := 0
	while depth < DEPTH_CAP:
		depth += 1
		var b := LadderBattle.new()
		b.ladder = _ladder
		b.begin(g.generate(depth), hp, Gauntlet.START_HP)
		b.used = used
		var safety := 0
		while b.state == LadderBattle.STATE_PLAY and safety < 40:
			safety += 1
			var word := _best_known_move(b, vocab)
			if word.is_empty():
				b.pass_turn()  # no known unused word — eat a hit
			else:
				b.try_move(word[0], word[1])
		if b.state == LadderBattle.STATE_LOST:
			break
		hp = mini(Gauntlet.START_HP, b.player_hp + Gauntlet.HEAL)
	return depth


## Pick the deadliest weapon we have an unused known word for. Returns [idx, word]
## or [] if none.
func _best_known_move(b: LadderBattle, vocab: int) -> Array:
	var weps := b.weapon_indices()
	weps.sort_custom(func(a, c): return b.weapon_damage(a) > b.weapon_damage(c))
	for wi in weps:
		var target: String = b.enemy.tokens[wi].text
		for w in _known_disarms(target, vocab):
			if not (w in b.used):
				return [wi, w]
	return []


## The K easiest disarms a player would know for a weapon (cached).
func _known_disarms(target: String, vocab: int) -> Array:
	if not _disarm_cache.has(target):
		var found: Array = []
		for w in _ladder.words:
			var m: Dictionary = _ladder.words[w]
			if w == target or m.get("sentiment", "") == "negative" or not ("noun" in m.get("pos", [])):
				continue
			var grew: bool = w.length() > target.length() and WordLadder.is_submultiset(target, w)
			var shrank: bool = w.length() < target.length() and WordLadder.is_submultiset(w, target)
			if grew or shrank:
				found.append(w)
		# easiest first: shorter, then alphabetical
		found.sort_custom(func(a, c): return a.length() < c.length() if a.length() != c.length() else a < c)
		_disarm_cache[target] = found
	var all: Array = _disarm_cache[target]
	return all.slice(0, mini(vocab, all.size()))
