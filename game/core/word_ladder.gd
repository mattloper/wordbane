## Letter-ladder validation: is a typed word a legal transform of a target?
##
## A move takes a target word's letters and the player types a new real word that
## is either a strict SUBSET (shrink: remove letters) or strict SUPERSET (grow:
## add letters) of them — never a substitution. Bidirectional + no-reuse means you
## can always move (big words shrink, small words grow) without dead-ends.
##
## Backed by the build-time dictionary (word -> {pos, sentiment}); pure data, no UI.
class_name WordLadder
extends RefCounted

const MODE_SHRINK := "shrink"
const MODE_GROW := "grow"

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


## Validate a typed transform of `target` under `mode`, given already-used words.
## Returns {ok: bool, reason: String, pos, sentiment} (tags present only if ok).
func validate(typed: String, target: String, mode: String, used: Array) -> Dictionary:
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

	if mode == MODE_SHRINK:
		if w.length() >= t.length() or not is_submultiset(w, t):
			return {"ok": false, "reason": "shrink: use only letters from '%s'" % t}
	elif mode == MODE_GROW:
		if w.length() <= t.length() or not is_submultiset(t, w):
			return {"ok": false, "reason": "grow: must contain all letters of '%s'" % t}
	else:
		return {"ok": false, "reason": "unknown mode"}

	var tg := tags(w)
	return {"ok": true, "reason": "", "pos": tg.get("pos", "other"),
		"sentiment": tg.get("sentiment", "neutral")}
