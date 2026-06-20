## Letter-ladder validation: is a typed word a legal transform of a target?
##
## A move takes a target word's letters and the player types a new real word that
## is either a strict SUBSET (shrink: remove letters) or strict SUPERSET (grow:
## add letters) of them — never a substitution — and the SAME part of speech, so
## the sentence stays grammatical (noun->noun, adjective->adjective). Both
## directions are always allowed and auto-detected: big words shrink, small words
## grow, so you never dead-end. No word may be reused in a battle.
##
## Backed by the build-time dictionary (word -> {pos, sentiment}); pure data, no UI.
class_name WordLadder
extends RefCounted

var words: Dictionary = {}  # word -> {pos, sentiment}


static func load_from(path: String) -> WordLadder:
	var wl := WordLadder.new()
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			wl.words = parsed.get("words", {})
	if wl.words.is_empty():
		push_error("dictionary not found/empty: %s" % path)
	return wl


func is_word(w: String) -> bool:
	return words.has(w.to_lower())

func tags(w: String) -> Dictionary:
	return words.get(w.to_lower(), {})


## Letter multiset of a word, as {letter: count}.
static func letter_counts(w: String) -> Dictionary:
	var c: Dictionary = {}
	for ch in w.to_lower():
		c[ch] = int(c.get(ch, 0)) + 1
	return c

## True if every letter of `a` is available (with multiplicity) in `b`.
static func is_submultiset(a: String, b: String) -> bool:
	var bc := letter_counts(b)
	for ch in letter_counts(a):
		if int(letter_counts(a)[ch]) > int(bc.get(ch, 0)):
			return false
	return true


## Count how many valid *disarming* transforms a target has — same POS, a strict
## sub/superset, and non-negative (only those actually disarm a weapon). Capped at
## `limit` via early-exit. Used to reject near-dead-end weapons like 'jinx'.
func count_transforms(target: String, required_pos: String, limit: int) -> int:
	var t := target.to_lower()
	var n := 0
	for w in words:
		var meta: Dictionary = words[w]
		if w == t or meta.get("sentiment", "") == "negative" \
				or not (required_pos in meta.get("pos", [])):
			continue
		var grew: bool = w.length() > t.length() and is_submultiset(t, w)
		var shrank: bool = w.length() < t.length() and is_submultiset(w, t)
		if grew or shrank:
			n += 1
			if n >= limit:
				return n
	return n


## Find one valid disarming word for `target` (for solvers/hints), or "" if none.
func find_transform(target: String, required_pos: String, used: Array) -> String:
	for w in words:
		if w in used:
			continue
		var r := validate(w, target, required_pos, used)
		if r.get("ok", false) and r.get("sentiment", "") != "negative":
			return w
	return ""


## Validate a typed transform of `target`. The result must be a real word, the
## same `required_pos` (pass "" to skip), a strict subset OR superset of the
## target's letters (direction auto-detected), and not already `used`.
## Returns {ok, reason, pos, sentiment, direction} (tags/direction only if ok).
func validate(typed: String, target: String, required_pos: String, used: Array) -> Dictionary:
	var w := typed.strip_edges().to_lower()
	var t := target.to_lower()
	if w == "":
		return {"ok": false, "reason": "type a word"}
	if w == t:
		return {"ok": false, "reason": "must be a different word"}
	if w in used:
		return {"ok": false, "reason": "'%s' already used this battle" % w}
	if not is_word(w):
		return {"ok": false, "reason": "'%s' isn't in the dictionary" % w}

	# Same part of speech, so the sentence stays grammatical. A word can have
	# several (e.g. 'fan' is noun and verb); accept if any matches.
	var pos_list: Array = tags(w).get("pos", [])
	if required_pos != "" and not (required_pos in pos_list):
		var have := ("/".join(pos_list)) if not pos_list.is_empty() else "?"
		return {"ok": false, "reason": "'%s' is %s — need a %s" % [w, have, required_pos]}

	# Auto-detect direction: pure subset (shrink) or pure superset (grow).
	var direction := ""
	if w.length() < t.length() and is_submultiset(w, t):
		direction = "shrink"
	elif w.length() > t.length() and is_submultiset(t, w):
		direction = "grow"
	else:
		return {"ok": false, "reason":
			"'%s' must add to OR remove from the letters of '%s' (no swaps)" % [w, t]}

	return {"ok": true, "reason": "", "pos": required_pos,
		"sentiment": tags(w).get("sentiment", "neutral"), "direction": direction}
