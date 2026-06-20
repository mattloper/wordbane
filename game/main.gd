## Wordplay — 2D scene view.
##
## Renders a Battle as two "being" trees (owner = body, items = branches) with HP
## bars and a turn banner. All turn logic lives in Battle; this script only draws
## and forwards clicks (use_item / target_word).
extends Control

const BANK_PATH := "res://data/word_bank.json"

var _battle: Battle

# UI nodes.
var _banner: Label
var _enemy_header: Label
var _enemy_hp: ProgressBar
var _enemy_being: VBoxContainer
var _telegraph: Label
var _status: Label
var _player_header: Label
var _player_hp: ProgressBar
var _player_being: VBoxContainer
var _player_items: Label


func _ready() -> void:
	var bank := GameLogic.load_bank(BANK_PATH)
	if bank.is_empty():
		_fatal("Could not load %s.\nGenerate it: cd tools && uv run wordplay-generate" % BANK_PATH)
		return
	_battle = Battle.new()
	add_child(_battle)
	_build_ui()
	_battle.changed.connect(_refresh)
	_battle.logged.connect(func(t: String): _status.text = t)
	_battle.setup(bank)
	_battle.new_game()


# --- UI construction ---------------------------------------------------------

func _fatal(msg: String) -> void:
	var l := Label.new()
	l.text = msg
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(l)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 26)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var title := _label("WORDPLAY", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_enemy_header = _label("", 19)
	col.add_child(_enemy_header)
	_enemy_hp = _hp_bar(Color(0.85, 0.30, 0.30))
	col.add_child(_enemy_hp)
	_enemy_being = _being()
	col.add_child(_panel(_enemy_being))
	_telegraph = _label("", 15)
	_telegraph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_telegraph)

	col.add_child(HSeparator.new())

	_banner = _label("", 22)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_banner)
	_status = _label("", 16)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 48)
	col.add_child(_status)

	col.add_child(HSeparator.new())

	_player_header = _label("", 19)
	col.add_child(_player_header)
	_player_hp = _hp_bar(Color(0.35, 0.70, 0.95))
	col.add_child(_player_hp)
	_player_being = _being()
	col.add_child(_panel(_player_being))
	_player_items = _label("", 15)
	_player_items.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_player_items)

	var restart := Button.new()
	restart.text = "New Battle"
	restart.add_theme_font_size_override("font_size", 16)
	restart.pressed.connect(func(): _battle.new_game())
	var center := CenterContainer.new()
	center.add_child(restart)
	col.add_child(center)


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _hp_bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 18)
	bar.modulate = color
	return bar


func _being() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	return box


func _panel(child: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	var inner := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + s, 10)
	inner.add_child(child)
	panel.add_child(inner)
	return panel


# --- rendering (driven by Battle) --------------------------------------------

func _refresh() -> void:
	var e: Dictionary = _battle.enemy
	var p: Dictionary = _battle.player
	if e.is_empty():
		return
	_enemy_hp.max_value = e.max_hp
	_enemy_hp.value = e.hp
	_player_hp.max_value = p.max_hp
	_player_hp.value = p.hp

	_enemy_header.text = "ENEMY — %s    HP %d/%d    threats: %d    wards: %d" % [
		e.name, e.hp, e.max_hp, GameLogic.count_negative(e.tokens), e.wards]
	_player_header.text = "YOU — %s    HP %d/%d    wards: %d" % [
		p.name, p.hp, p.max_hp, p.wards]

	_render_being(_enemy_being, e, "target" if _battle.state == Battle.ST_TARGET else "none")
	_render_being(_player_being, p, "items" if _battle.state == Battle.ST_CHOOSE else "none")

	_banner.text = _battle.banner_text()
	_banner.add_theme_color_override("font_color", WordStyle.phase_color(_battle.state))
	_telegraph.text = CombatText.telegraph(e)
	_player_items.text = _player_items_text(p)


## Render a character as a sideways tree: owner is the body (top), each item a
## branch carrying its adjectives. mode: "items" (use), "target" (scramble), "none".
func _render_being(box: VBoxContainer, fighter: Dictionary, mode: String) -> void:
	for c in box.get_children():
		c.queue_free()
	var tokens: Array = fighter.tokens

	var owner_line := _branch_row()
	var owner_idx := -1
	for i in range(tokens.size()):
		var t: Dictionary = tokens[i]
		if t.get("kind", "") == GameLogic.KIND_ADJ and t.get("attaches", "") == "owner":
			owner_line.add_child(_token_control(t, i, mode, 22))
		elif t.get("kind", "") == GameLogic.KIND_CREATURE and t.get("is_owner", false):
			owner_idx = i
	if owner_idx >= 0:
		owner_line.add_child(_token_control(tokens[owner_idx], owner_idx, mode, 30))
	box.add_child(owner_line)

	for item_index in fighter.item_order:
		var line := _branch_row()
		line.add_child(_connector("   ┗━"))
		var noun_idx := -1
		for i in range(tokens.size()):
			var t: Dictionary = tokens[i]
			if t.get("kind", "") == GameLogic.KIND_ADJ and t.get("attaches", "") == "item:%d" % int(item_index):
				line.add_child(_token_control(t, i, mode, 22))
			elif t.get("kind", "") == GameLogic.KIND_ITEM and int(t.get("item_index", -1)) == int(item_index):
				noun_idx = i
		if noun_idx >= 0:
			line.add_child(_token_control(tokens[noun_idx], noun_idx, mode, 22))
		box.add_child(line)


func _branch_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	return row


func _connector(glyph: String) -> Label:
	var l := _label(glyph, 20)
	l.add_theme_color_override("font_color", WordStyle.FIXED)
	return l


## One word as a Button (when actionable) or Label, coloured by sentiment.
func _token_control(token: Dictionary, idx: int, mode: String, font_size: int) -> Control:
	var color := WordStyle.color_for(token)
	var kind: String = token.get("kind", "")
	var cb := Callable()
	if mode == "items" and kind == GameLogic.KIND_ITEM:
		cb = _battle.use_item.bind(int(token.get("item_index", -1)))
	elif mode == "target" and kind in GameLogic.EDITABLE_KINDS:
		cb = _battle.target_word.bind(idx)

	if not cb.is_null():
		var btn := Button.new()
		btn.text = token.get("text", "")
		btn.add_theme_font_size_override("font_size", font_size)
		btn.add_theme_color_override("font_color", color)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		if mode == "items":  # items mode is only ever the player's being
			btn.tooltip_text = CombatText.item_effect(_battle.player.tokens, int(token.get("item_index", -1)))
		btn.pressed.connect(cb)
		return btn

	var lbl := Label.new()
	lbl.text = token.get("text", "")
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl


func _player_items_text(fighter: Dictionary) -> String:
	var parts: Array = []
	for item_index in fighter.item_order:
		parts.append(CombatText.item_effect(fighter.tokens, item_index))
	return "Your items:   " + "      ".join(parts)
