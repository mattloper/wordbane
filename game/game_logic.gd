## Pure game logic for Wordplay, with no UI dependencies.
##
## Kept separate from main.gd so it can be exercised headlessly (see selftest.gd).
## A "character" is an array of token Dictionaries shaped like the JSON emitted by
## the Python tooling:
##   { "text": String, "editable": bool, "pos": "ADJ"|"NOUN", "sentiment": "..." }
class_name GameLogic
extends RefCounted

const POSITIVE := "positive"
const NEGATIVE := "negative"
const NEUTRAL := "neutral"

## How many negative words the player can accumulate before losing.
const LOSE_THRESHOLD := 3

## Load and parse the generated word bank. Returns {} on any failure.
static func load_bank(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("word bank not found: %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("could not open: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("word bank is not valid JSON object")
		return {}
	return parsed

## Deep-copy a character's token list so re-rolls don't mutate the template.
static func clone_tokens(tokens: Array) -> Array:
	var out: Array = []
	for t in tokens:
		out.append((t as Dictionary).duplicate(true))
	return out

## Pick a character template matching a role ("player" or "enemy").
static func pick_character(characters: Array, role: String, rng: RandomNumberGenerator) -> Dictionary:
	var matches: Array = []
	for c in characters:
		if (c as Dictionary).get("role", "") == role:
			matches.append(c)
	if matches.is_empty():
		return {}
	return matches[rng.randi_range(0, matches.size() - 1)]

## Choose a sentiment from a weighted bag (array of sentiment strings w/ repeats).
static func _pick_sentiment(bag: Array, rng: RandomNumberGenerator) -> String:
	return bag[rng.randi_range(0, bag.size() - 1)]

## Re-roll one token in place: same part of speech, a fresh random word whose
## sentiment is drawn from `bag`. Returns the new word, or "" if it couldn't roll.
static func reroll_token(token: Dictionary, pools: Dictionary, bag: Array, rng: RandomNumberGenerator) -> String:
	if not token.get("editable", false):
		return ""
	var pos: String = token.get("pos", "")
	if not pools.has(pos):
		return ""
	var sentiment := _pick_sentiment(bag, rng)
	var words: Array = pools[pos].get(sentiment, [])
	if words.is_empty():
		return ""
	# Avoid handing back the exact same word.
	var current: String = token.get("text", "")
	var choice: String = current
	for _attempt in range(8):
		choice = words[rng.randi_range(0, words.size() - 1)]
		if choice != current:
			break
	token["text"] = choice
	token["sentiment"] = sentiment
	return choice

## Count negative editable words in a token list.
static func count_negative(tokens: Array) -> int:
	var n := 0
	for t in tokens:
		if (t as Dictionary).get("editable", false) and t.get("sentiment", "") == NEGATIVE:
			n += 1
	return n

## An enemy is defeated (defanged) when it has no negative words left.
static func is_defanged(tokens: Array) -> bool:
	return count_negative(tokens) == 0

## Editable token indices, optionally filtered to a sentiment.
static func editable_indices(tokens: Array, sentiment_filter: String = "") -> Array:
	var idx: Array = []
	for i in range(tokens.size()):
		var t: Dictionary = tokens[i]
		if not t.get("editable", false):
			continue
		if sentiment_filter != "" and t.get("sentiment", "") != sentiment_filter:
			continue
		idx.append(i)
	return idx
