## Wordplay — main scene controller.
##
## Builds the whole UI in code from the generated word bank, then runs a simple
## turn-based loop: you click the enemy's red (negative) words to randomize them,
## trying to leave it with no negatives; the enemy randomizes your words back,
## trying to corrupt you. All re-rolls respect part of speech (ADJ->ADJ, NOUN->NOUN).
extends Control

const BANK_PATH := "res://data/word_bank.json"

# Re-roll sentiment bags (arrays with repeats act as weights).
const PLAYER_BAG := [GameLogic.POSITIVE, GameLogic.NEGATIVE, GameLogic.NEUTRAL]
const ENEMY_BAG := [
	GameLogic.NEGATIVE, GameLogic.NEGATIVE, GameLogic.NEGATIVE,
	GameLogic.POSITIVE, GameLogic.NEUTRAL,
]

const COLOR_POSITIVE := Color(0.40, 0.85, 0.45)
const COLOR_NEGATIVE := Color(0.96, 0.36, 0.36)
const COLOR_NEUTRAL := Color(0.78, 0.78, 0.82)
const COLOR_FIXED := Color(0.62, 0.62, 0.68)

var _rng := RandomNumberGenerator.new()
var _pools: Dictionary = {}
var _characters: Array = []

var _enemy_tokens: Array = []
var _player_tokens: Array = []
var _enemy_name := ""
var _player_name := ""
var _game_over := false
var _busy := false

# Cached UI nodes.
var _title: Label
var _enemy_header: Label
var _enemy_row: HFlowContainer
var _player_header: Label
var _player_row: HFlowContainer
var _status: Label


func _ready() -> void:
	_rng.randomize()
	var bank := GameLogic.load_bank(BANK_PATH)
	if bank.is_empty():
		_build_fatal("Could not load %s.\nRun the generator: cd tools && uv run wordplay-generate" % BANK_PATH)
		return
	_pools = bank.get("word_pools", {})
	_characters = bank.get("characters", [])
	_build_ui()
	_new_game()


# --- UI construction ---------------------------------------------------------

func _build_fatal(msg: String) -> void:
	var label := Label.new()
	label.text = msg
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(col)

	_title = _make_label("WORDPLAY", 30)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)

	# Enemy block.
	_enemy_header = _make_label("", 20)
	col.add_child(_enemy_header)
	_enemy_row = _make_word_row()
	col.add_child(_make_panel(_enemy_row))

	col.add_child(_make_label("", 14))  # spacer

	_status = _make_label("", 18)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)

	col.add_child(_make_label("", 14))  # spacer

	# Player block.
	_player_header = _make_label("", 20)
	col.add_child(_player_header)
	_player_row = _make_word_row()
	col.add_child(_make_panel(_player_row))

	var restart := Button.new()
	restart.text = "New Battle"
	restart.add_theme_font_size_override("font_size", 18)
	restart.pressed.connect(_new_game)
	var center := CenterContainer.new()
	center.add_child(restart)
	col.add_child(center)


func _make_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _make_word_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row


func _make_panel(child: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 12)
	inner.add_child(child)
	panel.add_child(inner)
	return panel


# --- Game flow ---------------------------------------------------------------

func _new_game() -> void:
	var enemy := GameLogic.pick_character(_characters, "enemy", _rng)
	var player := GameLogic.pick_character(_characters, "player", _rng)
	if enemy.is_empty() or player.is_empty():
		_status.text = "Word bank has no player/enemy characters."
		return
	_enemy_name = enemy.get("name", "Enemy")
	_player_name = player.get("name", "You")
	_enemy_tokens = GameLogic.clone_tokens(enemy.get("tokens", []))
	_player_tokens = GameLogic.clone_tokens(player.get("tokens", []))
	_game_over = false
	_busy = false
	_status.text = "Click the enemy's red words to randomize them. Leave it with none to win!"
	_refresh()


func _refresh() -> void:
	var enemy_neg := GameLogic.count_negative(_enemy_tokens)
	var player_neg := GameLogic.count_negative(_player_tokens)
	_enemy_header.text = "ENEMY — %s   (threats: %d)" % [_enemy_name, enemy_neg]
	_player_header.text = "YOU — %s   (corruption: %d / %d)" % [
		_player_name, player_neg, GameLogic.LOSE_THRESHOLD
	]
	_render_tokens(_enemy_row, _enemy_tokens, not _game_over)
	_render_tokens(_player_row, _player_tokens, false)


## Rebuild a row of word controls. Editable+clickable tokens become Buttons.
func _render_tokens(row: HFlowContainer, tokens: Array, clickable: bool) -> void:
	for child in row.get_children():
		child.queue_free()
	for i in range(tokens.size()):
		var token: Dictionary = tokens[i]
		var color := _sentiment_color(token)
		if token.get("editable", false) and clickable:
			var btn := Button.new()
			btn.text = token.get("text", "")
			btn.add_theme_font_size_override("font_size", 22)
			btn.add_theme_color_override("font_color", color)
			btn.add_theme_color_override("font_hover_color", Color.WHITE)
			btn.pressed.connect(_on_enemy_word_pressed.bind(i))
			row.add_child(btn)
		else:
			var lbl := Label.new()
			lbl.text = token.get("text", "")
			lbl.add_theme_font_size_override("font_size", 22)
			lbl.add_theme_color_override("font_color", color)
			row.add_child(lbl)


func _sentiment_color(token: Dictionary) -> Color:
	if not token.get("editable", false):
		return COLOR_FIXED
	match token.get("sentiment", ""):
		GameLogic.POSITIVE:
			return COLOR_POSITIVE
		GameLogic.NEGATIVE:
			return COLOR_NEGATIVE
		_:
			return COLOR_NEUTRAL


func _on_enemy_word_pressed(index: int) -> void:
	if _game_over or _busy:
		return
	_busy = true
	var token: Dictionary = _enemy_tokens[index]
	GameLogic.reroll_token(token, _pools, PLAYER_BAG, _rng)
	_refresh()

	if GameLogic.is_defanged(_enemy_tokens):
		_end_game(true)
		return

	# Enemy strikes back after a short beat.
	await get_tree().create_timer(0.45).timeout
	_enemy_turn()


func _enemy_turn() -> void:
	if _game_over:
		return
	# Prefer corrupting a word that isn't already negative.
	var targets := GameLogic.editable_indices(_player_tokens)
	var fresh: Array = []
	for i in targets:
		if (_player_tokens[i] as Dictionary).get("sentiment", "") != GameLogic.NEGATIVE:
			fresh.append(i)
	var pool: Array = fresh if not fresh.is_empty() else targets
	if not pool.is_empty():
		var idx: int = pool[_rng.randi_range(0, pool.size() - 1)]
		GameLogic.reroll_token(_player_tokens[idx], _pools, ENEMY_BAG, _rng)
	_refresh()

	if GameLogic.count_negative(_player_tokens) >= GameLogic.LOSE_THRESHOLD:
		_end_game(false)
		return
	_busy = false


func _end_game(player_won: bool) -> void:
	_game_over = true
	_busy = false
	if player_won:
		_status.text = "✅ Victory! %s is harmless now. Press New Battle to play again." % _enemy_name
	else:
		_status.text = "💀 Defeat — %s corrupted you. Press New Battle to try again." % _player_name
	_refresh()
