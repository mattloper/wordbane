## Letter-ladder prototype (2D).
##
## Proves the core idea: disarm an enemy by rewriting its weapon words with word
## ladders. Click a red NOUN, then type a real word made from its letters — add or
## remove letters (direction auto-detected), same part of speech (noun->noun). The
## word is replaced and re-tagged; disarm every negative noun to win. Adjectives
## are multipliers (clickable adj->adj, but harmless once their noun is gone), so
## the goal is the nouns. No word may be reused.
##
## This is a focused slice (disarm only — no HP/turns yet) to test the feel.
## Run with:  godot --path game ladder.tscn
extends Control

const BANK_PATH := "res://data/word_bank.json"
const DICT_PATH := "res://data/dictionary.json"

var _rng := RandomNumberGenerator.new()
var _ladder: WordLadder
var _characters: Array = []
var _enemy: Dictionary = {}
var _selected := -1            # token index currently being transformed
var _used: Array = []          # words spent this battle (no reuse)
var _won := false

# Token kind -> required part of speech for a transform (keeps the sentence grammatical).
const KIND_POS := {
	GameLogic.KIND_ITEM: "noun",
	GameLogic.KIND_CREATURE: "noun",
	GameLogic.KIND_ADJ: "adjective",
}

# UI.
var _header: Label
var _row: HFlowContainer
var _selinfo: Label
var _entry: LineEdit
var _msg: Label
var _used_label: Label


func _ready() -> void:
	_rng.randomize()
	_ladder = WordLadder.load_from(DICT_PATH)
	var bank := GameLogic.load_bank(BANK_PATH)
	_characters = bank.get("characters", [])
	_build_ui()
	_new_battle()


# --- UI ----------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 28)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var title := _label("LETTER-LADDER — pacify the enemy (prototype)", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_header = _label("", 19)
	col.add_child(_header)

	_row = HFlowContainer.new()
	_row.add_theme_constant_override("h_separation", 8)
	_row.add_theme_constant_override("v_separation", 6)
	var panel := PanelContainer.new()
	var inner := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + s, 12)
	inner.add_child(_row)
	panel.add_child(inner)
	col.add_child(panel)

	_selinfo = _label("Click an enemy word to select it.", 16)
	col.add_child(_selinfo)

	# Entry row (no shrink/grow toggle — either direction is auto-detected).
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	_entry = LineEdit.new()
	_entry.placeholder_text = "type a word…"
	_entry.custom_minimum_size = Vector2(260, 0)
	_entry.text_submitted.connect(func(_t): _submit())
	controls.add_child(_entry)
	var go := Button.new()
	go.text = "Transform"
	go.pressed.connect(_submit)
	controls.add_child(go)
	col.add_child(controls)

	_msg = _label("", 17)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size = Vector2(0, 48)
	col.add_child(_msg)

	_used_label = _label("", 14)
	_used_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_used_label)

	var restart := Button.new()
	restart.text = "New Enemy"
	restart.pressed.connect(_new_battle)
	var center := CenterContainer.new()
	center.add_child(restart)
	col.add_child(center)


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


# --- battle ------------------------------------------------------------------

func _new_battle() -> void:
	var template := GameLogic.pick_character(_characters, "enemy", _rng)
	_enemy = GameLogic.make_fighter(template)
	_selected = -1
	_used = []
	_won = false
	_msg.text = ""
	_entry.text = ""
	_refresh()


func _refresh() -> void:
	var threats := _negative_nouns()
	_header.text = "ENEMY — %s    weapons left: %d   (disarm the red nouns)" % [
		_enemy.name, threats]
	_render_words()
	if _selected >= 0:
		var tok: Dictionary = _enemy.tokens[_selected]
		var w: String = tok.get("text", "")
		var pos: String = KIND_POS.get(tok.get("kind", ""), "?")
		_selinfo.text = "Selected: %s   (letters: %s)   → type a %s (add or remove letters)" % [
			w, " ".join(_sorted_letters(w)), pos]
	else:
		_selinfo.text = "Click a red noun to select it."
	_used_label.text = "Used words: " + (", ".join(_used) if not _used.is_empty() else "—")
	if threats == 0 and not _won:
		_won = true
		_msg.text = "✅ DISARMED — %s has no weapons left! (New Enemy to play again)" % _enemy.name


## Negative noun-kind words (owner + items) are the weapons to disarm.
func _negative_nouns() -> int:
	var n := 0
	for t in _enemy.tokens:
		if t.get("kind", "") in [GameLogic.KIND_ITEM, GameLogic.KIND_CREATURE] \
				and t.get("sentiment", "") == GameLogic.NEGATIVE:
			n += 1
	return n


func _render_words() -> void:
	for c in _row.get_children():
		c.queue_free()
	var tokens: Array = _enemy.tokens
	for i in range(tokens.size()):
		var token: Dictionary = tokens[i]
		var color := WordStyle.color_for(token)
		if token.get("kind", "") in GameLogic.EDITABLE_KINDS:
			var btn := Button.new()
			btn.text = token.get("text", "")
			btn.add_theme_font_size_override("font_size", 22)
			btn.add_theme_color_override("font_color", color)
			if i == _selected:
				btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
			btn.pressed.connect(_select.bind(i))
			_row.add_child(btn)
		else:
			var lbl := _label(token.get("text", ""), 22)
			lbl.add_theme_color_override("font_color", color)
			_row.add_child(lbl)


func _select(token_index: int) -> void:
	if _won:
		return
	_selected = token_index
	_msg.text = ""
	_entry.grab_focus()
	_refresh()


func _submit() -> void:
	if _won:
		return
	if _selected < 0:
		_msg.text = "Pick a word first."
		return
	var tok: Dictionary = _enemy.tokens[_selected]
	var target: String = tok.get("text", "")
	var required_pos: String = KIND_POS.get(tok.get("kind", ""), "")
	var r := _ladder.validate(_entry.text, target, required_pos, _used)
	if not r.get("ok", false):
		_msg.text = "✗ " + str(r.get("reason", "invalid"))
		return
	# Apply: rewrite the word in place, re-tag its sentiment.
	var w := _entry.text.strip_edges().to_lower()
	var was_sent: String = tok.get("sentiment", "")
	tok["text"] = w
	tok["sentiment"] = r.get("sentiment", "neutral")
	_used.append(w)
	_entry.text = ""
	var note := ""
	# Disarming a noun neutralizes its adjective(s) — a multiplier with no
	# weapon to sharpen is harmless.
	if tok.get("kind", "") in [GameLogic.KIND_ITEM, GameLogic.KIND_CREATURE] \
			and r.get("sentiment", "") != GameLogic.NEGATIVE:
		var calmed := _neutralize_adjectives_of(tok)
		if not calmed.is_empty():
			note = "   (calmed: %s)" % ", ".join(calmed)
	_msg.text = "✓ %s → %s  (%s, %s, was %s)%s" % [
		target, w, r.get("direction", "?"), r.get("sentiment", "?"), was_sent, note]
	_refresh()


## Neutralize the adjectives attached to a just-disarmed noun. Returns their names.
func _neutralize_adjectives_of(noun: Dictionary) -> Array:
	var key := ""
	if noun.get("kind", "") == GameLogic.KIND_ITEM:
		key = "item:%d" % int(noun.get("item_index", -1))
	elif noun.get("kind", "") == GameLogic.KIND_CREATURE:
		key = "owner"
	if key == "":
		return []
	var calmed: Array = []
	for t in _enemy.tokens:
		if t.get("kind", "") == GameLogic.KIND_ADJ and t.get("attaches", "") == key \
				and t.get("sentiment", "") == GameLogic.NEGATIVE:
			t["sentiment"] = GameLogic.NEUTRAL
			calmed.append(t.get("text", ""))
	return calmed


func _sorted_letters(w: String) -> Array:
	var chars: Array = []
	for ch in w.to_lower():
		chars.append(ch)
	chars.sort()
	return chars
