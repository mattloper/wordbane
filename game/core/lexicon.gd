## The word dictionary plus the letter-rarity scoring the game is built on.
##
## A move is any real word that shares AT LEAST ONE letter with the enemy's letters.
## Its DAMAGE is the summed rarity weight of the enemy letters it covers, so covering
## more letters — and rarer ones (Scrabble-style: q/z/x/j hit hardest) — deals more.
## An enemy's HP is the total weight of its letters, so a word covering all of them
## can drop it in one blow. Same word can't be reused in a run.
##
## Backed by the build-time dictionary (word -> {pos, sentiment}); pure data, no UI.
class_name Lexicon
extends RefCounted

var words: Dictionary = {}  # word -> {pos, sentiment}

## Rarity weight per letter (Scrabble English values): rare letters hit harder.
const LETTER_WEIGHT := {
	"a": 1, "e": 1, "i": 1, "o": 1, "u": 1, "n": 1, "r": 1, "t": 1, "l": 1, "s": 1,
	"d": 2, "g": 2,
	"b": 3, "c": 3, "m": 3, "p": 3,
	"f": 4, "h": 4, "v": 4, "w": 4, "y": 4,
	"k": 5,
	"j": 8, "x": 8,
	"q": 10, "z": 10,
}


static func load_from(path: String) -> Lexicon:
	var lex := Lexicon.new()
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			lex.words = parsed.get("words", {})
	if lex.words.is_empty():
		push_error("dictionary not found/empty: %s" % path)
	return lex


func is_word(w: String) -> bool:
	return words.has(w.to_lower())

func tags(w: String) -> Dictionary:
	return words.get(w.to_lower(), {})


# --- letters & rarity --------------------------------------------------------

static func letter_weight(ch: String) -> int:
	return int(LETTER_WEIGHT.get(ch, 1))

## The distinct letters of a word, as a set {letter: true}.
static func distinct_letters(w: String) -> Dictionary:
	var s: Dictionary = {}
	for ch in w.to_lower():
		s[ch] = true
	return s

## Summed rarity weight of a collection of letters.
static func letters_weight(letters) -> int:
	var total := 0
	for ch in letters:
		total += letter_weight(ch)
	return total

## A word's HP contribution: the summed rarity weight of its distinct letters.
static func word_weight(w: String) -> int:
	return letters_weight(distinct_letters(w).keys())

## True if `a` and `b` share at least one letter (the only validity rule).
static func shares_letter(a: String, b: String) -> bool:
	var bl := distinct_letters(b)
	for ch in distinct_letters(a):
		if bl.has(ch):
			return true
	return false

## The distinct letters of `letters` that `typed` covers (for UI: "uses e, x").
static func covered_letters(typed: String, letters: String) -> Array:
	var tl := distinct_letters(typed)
	var out: Array = []
	for ch in distinct_letters(letters):
		if tl.has(ch):
			out.append(ch)
	out.sort()
	return out

## Damage `typed` deals to `letters`: rarity weight of the letters it covers.
static func overlap_damage(typed: String, letters: String) -> int:
	return letters_weight(covered_letters(typed, letters))

## ["i","n","x"] -> ["I","N","X"], for tidy log/preview display.
static func upper_letters(letters: Array) -> Array:
	var out: Array = []
	for ch in letters:
		out.append(String(ch).to_upper())
	return out


# --- validation & hints ------------------------------------------------------

## The highest-damage fresh word for a set of `letters` (for the Hint button /
## solvers), or "" if none. Ties broken by the shorter word (easier to think of).
func best_word(letters: String, used: Array) -> String:
	var best := ""
	var best_dmg := 0
	for w in words:
		if w in used or not shares_letter(w, letters):
			continue
		var d := overlap_damage(w, letters)
		if d > best_dmg or (d == best_dmg and best != "" and w.length() < best.length()):
			best_dmg = d
			best = w
	return best


## Validate a typed strike against a set of `letters` (the enemy's pool). Must be a
## real word, not already `used`, and share at least one of those letters.
## Returns {ok, reason, dealt, sentiment} (dealt/sentiment only when ok).
func validate(typed: String, letters: String, used: Array) -> Dictionary:
	var w := typed.strip_edges().to_lower()
	if w == "":
		return {"ok": false, "reason": "type a word"}
	if w in used:
		return {"ok": false, "reason": "'%s' already used this run" % w}
	if not is_word(w):
		return {"ok": false, "reason": "'%s' isn't in the dictionary" % w}
	if not shares_letter(w, letters):
		return {"ok": false, "reason": "'%s' uses none of its letters" % w}
	return {"ok": true, "reason": "", "dealt": overlap_damage(w, letters),
		"sentiment": tags(w).get("sentiment", "neutral")}
