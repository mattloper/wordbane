## Difficulty-balancing harness (dev tool, not part of the game).
##
## Auto-plays the gauntlet to measure the difficulty curve after tuning changes.
## Models a LIMITED-VOCABULARY player: they command every word up to a max LENGTH
## (everyone knows short words; fewer know long ones). With run-wide no-reuse, those
## known words get spent, so the player eventually must Skip (take a hit).
##
## Reports reached depth for several max-lengths, so you can tune HP/bite/ramp
## against a realistic player, not a perfect solver.
##
## Perf: the hot path is "best words for an enemy's letter set". We precompute a
## 26-bit letter mask per dictionary word once, score each letter-set with cheap bit
## ops (no per-word allocations), and cache the result PER SET (not per max-length).
##
##   godot --headless --script res://balance.gd            # all tiers (serial)
##   godot --headless --script res://balance.gd -- 4       # just max-length 4 (one shard)
##   # Parallel (one process per tier — finishes in ~one tier's time):
##   for k in 3 4 5 99; do godot --headless --path game --script res://balance.gd -- $k & done; wait
extends SceneTree

const RUNS := 60
const DEPTH_CAP := 60
const VOCAB_LENS := [3, 4, 5, 99]  # 99 = knows every word (a perfect speller)
const A := 97  # 'a'
const CAP := 400  # keep only the top-N hardest hitters per set (a run spends far fewer)

var _lexicon: Lexicon
var _words: PackedStringArray = PackedStringArray()
var _wmask: PackedInt64Array = PackedInt64Array()  # 26-bit letter set per word
var _wlen: PackedInt32Array = PackedInt32Array()
var _bit_weight: PackedInt32Array = PackedInt32Array()  # rarity weight per letter a..z
var _known_cache: Dictionary = {}  # "letters|maxlen" -> PackedStringArray (capped, best first)


func _initialize() -> void:
	_lexicon = Lexicon.load_from("res://../shared_data/dictionary.json")
	_prep()
	var g := Gauntlet.new()
	g.setup(WordBank.load_bank("res://../shared_data/word_bank.json"))

	var tiers: Array = VOCAB_LENS
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:  # sharded: run a single tier so N processes can run in parallel
		tiers = [int(args[0])]
	else:
		print("Tuning: START_HP=%d  (%d words)" % [Gauntlet.START_HP, _words.size()])

	for k in tiers:
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


## Precompute a letter bitmask + length for every word, and the weight of each
## letter by bit — so scoring a letter-set is pure integer work, zero allocations.
func _prep() -> void:
	_bit_weight.resize(26)
	for i in range(26):
		_bit_weight[i] = Lexicon.letter_weight(String.chr(A + i))
	for wv in _lexicon.words:
		var w := String(wv)
		var m := 0
		for i in range(w.length()):
			var b := w.unicode_at(i) - A
			if b >= 0 and b < 26:
				m |= 1 << b
		_words.append(w)
		_wmask.append(m)
		_wlen.append(w.length())


## The up-to-CAP hardest-hitting words (length <= maxlen) for an enemy's `letters`,
## best-damage first. Cached per (set, maxlen). Bucket-selects by damage — no full
## sort, and retains only CAP words — so it's cheap in both time and memory.
func _known_words(letters: String, maxlen: int) -> PackedStringArray:
	var key := letters + "|" + str(maxlen)
	if _known_cache.has(key):
		return _known_cache[key]
	# Distinct set letters as (bit-mask, weight); track the max possible damage.
	var bit_masks: Array = []
	var bit_weights: Array = []
	var seen := {}
	var maxd := 0
	for i in range(letters.length()):
		var b := letters.unicode_at(i) - A
		if b >= 0 and b < 26 and not seen.has(b):
			seen[b] = true
			bit_masks.append(1 << b)
			bit_weights.append(_bit_weight[b])
			maxd += _bit_weight[b]
	var nb := bit_masks.size()
	# Bucket word indices by their damage against this set (damage is a small int).
	var buckets: Array = []
	buckets.resize(maxd + 1)
	for d in range(maxd + 1):
		buckets[d] = PackedInt32Array()
	for wi in range(_words.size()):
		if _wlen[wi] > maxlen:
			continue
		var wm: int = _wmask[wi]
		var d := 0
		for k in range(nb):
			if wm & int(bit_masks[k]):
				d += int(bit_weights[k])
		if d > 0:
			buckets[d].append(wi)
	# Collect the top CAP, highest-damage buckets first.
	var out := PackedStringArray()
	var dd := maxd
	while dd >= 1 and out.size() < CAP:
		for wi in buckets[dd]:
			out.append(_words[wi])
			if out.size() >= CAP:
				break
		dd -= 1
	_known_cache[key] = out
	return out


## Play one run with a max-length vocabulary; return depth reached.
func _play_run(g: Gauntlet, maxlen: int, seed: int) -> int:
	var rng := Rng.new(seed)  # deterministic per run -> reproducible curves
	g.rng = rng
	var hp: int = Gauntlet.START_HP
	var max_hp: int = Gauntlet.START_HP
	var used_set: Dictionary = {}  # words spent this run (no-reuse spans the run)
	var hints := 0                 # unspent Focus charges (optimal word, then consumed)
	var depth := 0
	while depth < DEPTH_CAP:
		depth += 1
		var b := PoolBattle.new()
		b.lexicon = _lexicon
		b.begin(g.generate(depth), hp, max_hp)
		b.used = used_set.keys()
		var safety := 0
		while b.state == PoolBattle.STATE_PLAY and safety < 60:
			safety += 1
			var word := _best_known_move(b, maxlen, used_set)
			if word.is_empty() and hints > 0:  # spend a hint to find any optimal word
				word = _lexicon.best_word("".join(b.letters()), b.used + b.weapons())
				if word != "":
					hints -= 1
			if word.is_empty():
				b.pass_turn()  # no findable word — eat a hit
			else:
				b.try_move(word)
				used_set[word] = true
		if b.state != PoolBattle.STATE_WON:
			break  # lost, or stuck (couldn't drain the pool) — run ends
		hp = b.player_hp
		# Model a survival-optimal player (to measure the depth ceiling): always take
		# an HP boon over the score-only ones. Heal first when low, else grow.
		var order: Array = ["mend", "tough", "focus", "double"] if hp <= max_hp * 0.45 \
			else ["tough", "mend", "focus", "double"]
		var pick := _pick_boon(Boons.offer(rng), order)
		var s := {"hp": hp, "max_hp": max_hp, "hints": hints}
		Boons.apply(pick, s)
		hp = int(s.hp); max_hp = int(s.max_hp); hints = int(s.hints)
	return depth


## The highest-priority available boon (by id `order`), else the first offered.
func _pick_boon(offer: Array, order: Array) -> Dictionary:
	for want in order:
		for boon in offer:
			if boon.id == want:
				return boon
	return offer[0]


## The best fresh word (within our max length) for this enemy's letters, skipping
## used words and the enemy's own (banned) weapon words.
func _best_known_move(b: PoolBattle, maxlen: int, used_set: Dictionary) -> String:
	var weapons: Array = b.weapons()
	for w in _known_words("".join(b.letters()), maxlen):
		if not used_set.has(w) and not (w in weapons):
			return w  # list is best-damage first
	return ""
