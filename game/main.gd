## Wordplay — main scene controller.
##
## Turn-based duel between two sentences. Each character has an *owner* (its
## subject noun, found by syntax at build time) and *items* (its other nouns).
## Owners deal no damage; items do. Adjectives multiply their item's effect.
##
## Your turn: click one of YOUR item words to use it. The enemy cycles through
## its items in a fixed, telegraphed order (you always see what's coming next).
## Win by reducing the enemy to 0 HP *or* pacifying it (no negative words left);
## lose if your HP hits 0.
extends Control

const BANK_PATH := "res://data/word_bank.json"

const COLOR_POSITIVE := Color(0.40, 0.85, 0.45)
const COLOR_NEGATIVE := Color(0.96, 0.36, 0.36)
const COLOR_NEUTRAL := Color(0.80, 0.80, 0.85)
const COLOR_FIXED := Color(0.55, 0.55, 0.62)

var _rng := RandomNumberGenerator.new()
var _pools: Dictionary = {}
var _characters: Array = []

var _player: Dictionary = {}
var _enemy: Dictionary = {}
var _state := "player"  # "player" | "busy" | "over"
var _player_msg := ""

# UI nodes.
var _enemy_header: Label
var _enemy_hp: ProgressBar
var _enemy_row: HFlowContainer
var _telegraph: Label
var _status: Label
var _player_header: Label
var _player_hp: ProgressBar
var _player_row: HFlowContainer
var _player_items: Label


func _ready() -> void:
	_rng.randomize()
	var bank := GameLogic.load_bank(BANK_PATH)
	if bank.is_empty():
		_fatal("Could not load %s.\nGenerate it: cd tools && uv run wordplay-generate" % BANK_PATH)
		return
	_pools = bank.get("pools", {})
	_characters = bank.get("characters", [])
	_build_ui()
	_new_game()


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
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var title := _label("WORDPLAY", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	# Enemy block.
	_enemy_header = _label("", 20)
	col.add_child(_enemy_header)
	_enemy_hp = _hp_bar(Color(0.85, 0.30, 0.30))
	col.add_child(_enemy_hp)
	_enemy_row = _word_row()
	col.add_child(_panel(_enemy_row))
	_telegraph = _label("", 16)
	_telegraph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_telegraph)

	col.add_child(_separator())

	_status = _label("", 17)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 52)
	col.add_child(_status)

	col.add_child(_separator())

	# Player block.
	_player_header = _label("", 20)
	col.add_child(_player_header)
	_player_hp = _hp_bar(Color(0.35, 0.70, 0.95))
	col.add_child(_player_hp)
	_player_row = _word_row()
	col.add_child(_panel(_player_row))
	_player_items = _label("", 16)
	_player_items.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_player_items)

	var restart := Button.new()
	restart.text = "New Battle"
	restart.add_theme_font_size_override("font_size", 17)
	restart.pressed.connect(_new_game)
	var center := CenterContainer.new()
	center.add_child(restart)
	col.add_child(center)


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _separator() -> HSeparator:
	return HSeparator.new()


func _hp_bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 18)
	bar.modulate = color
	return bar


func _word_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	return row


func _panel(child: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	var inner := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + s, 10)
	inner.add_child(child)
	panel.add_child(inner)
	return panel


# --- game flow ---------------------------------------------------------------

func _new_game() -> void:
	var enemy_t := GameLogic.pick_character(_characters, "enemy", _rng)
	var player_t := GameLogic.pick_character(_characters, "player", _rng)
	if enemy_t.is_empty() or player_t.is_empty():
		_status.text = "Word bank is missing player/enemy characters."
		return
	_enemy = GameLogic.make_fighter(enemy_t)
	_player = GameLogic.make_fighter(player_t)
	_state = "player"
	_player_msg = ""
	_status.text = "Your turn — click one of your item words below to use it."
	_refresh()


func _refresh() -> void:
	_enemy_hp.max_value = _enemy.max_hp
	_enemy_hp.value = _enemy.hp
	_player_hp.max_value = _player.max_hp
	_player_hp.value = _player.hp

	_enemy_header.text = "ENEMY — %s    HP %d/%d    threats: %d    wards: %d" % [
		_enemy.name, _enemy.hp, _enemy.max_hp,
		GameLogic.count_negative(_enemy.tokens), _enemy.wards]
	_player_header.text = "YOU — %s    HP %d/%d    wards: %d" % [
		_player.name, _player.hp, _player.max_hp, _player.wards]

	_render_words(_enemy_row, _enemy.tokens, false)
	_render_words(_player_row, _player.tokens, _state == "player")

	_telegraph.text = _telegraph_text()
	_player_items.text = _player_items_text()


## Render a sentence. When `clickable`, item nouns become Buttons that use them.
func _render_words(row: HFlowContainer, tokens: Array, clickable: bool) -> void:
	for c in row.get_children():
		c.queue_free()
	for t in tokens:
		var token: Dictionary = t
		var color := _sentiment_color(token)
		if clickable and token.get("kind", "") == GameLogic.KIND_ITEM:
			var btn := Button.new()
			btn.text = token.get("text", "")
			btn.add_theme_font_size_override("font_size", 22)
			btn.add_theme_color_override("font_color", color)
			btn.add_theme_color_override("font_hover_color", Color.WHITE)
			btn.tooltip_text = _item_effect_text(tokens, int(token.get("item_index", -1)))
			btn.pressed.connect(_on_player_item_pressed.bind(int(token.get("item_index", -1))))
			row.add_child(btn)
		else:
			var lbl := Label.new()
			lbl.text = token.get("text", "")
			lbl.add_theme_font_size_override("font_size", 22)
			lbl.add_theme_color_override("font_color", color)
			row.add_child(lbl)


func _sentiment_color(token: Dictionary) -> Color:
	match token.get("kind", ""):
		GameLogic.KIND_FIXED:
			return COLOR_FIXED
		_:
			match token.get("sentiment", ""):
				GameLogic.POSITIVE:
					return COLOR_POSITIVE
				GameLogic.NEGATIVE:
					return COLOR_NEGATIVE
				_:
					return COLOR_NEUTRAL


func _on_player_item_pressed(item_index: int) -> void:
	if _state != "player" or item_index < 0:
		return
	_state = "busy"
	var res := GameLogic.apply_item(_player, _enemy, item_index, _pools, _rng)
	_player_msg = _describe(_player.name, res, _enemy.name)
	_status.text = _player_msg
	_refresh()
	if _check_end():
		return
	await get_tree().create_timer(0.55).timeout
	_enemy_turn()


func _enemy_turn() -> void:
	if _state == "over":
		return
	var idx := GameLogic.next_item_index(_enemy)
	var res := GameLogic.apply_item(_enemy, _player, idx, _pools, _rng)
	GameLogic.advance_cycle(_enemy)
	_status.text = _player_msg + "\n" + _describe(_enemy.name, res, _player.name)
	_refresh()
	if _check_end():
		return
	_state = "player"


func _check_end() -> bool:
	if int(_enemy.hp) <= 0:
		_end("VICTORY — you defeated %s (HP 0)!" % _enemy.name)
		return true
	if GameLogic.is_pacified(_enemy.tokens):
		_end("VICTORY — %s is pacified: no negative words left!" % _enemy.name)
		return true
	if int(_player.hp) <= 0:
		_end("DEFEAT — %s knocked your HP to 0." % _player.name)
		return true
	return false


func _end(msg: String) -> void:
	_state = "over"
	_status.text = msg + "\nPress New Battle to play again."
	_refresh()


# --- text helpers ------------------------------------------------------------

func _describe(actor: String, res: Dictionary, target: String) -> String:
	if not res.get("ok", false):
		return ""
	match res.type:
		GameLogic.HP_ATTACK:
			return "%s used %s — %d damage to %s." % [actor, res.item, res.dmg, target]
		GameLogic.WORD_ATTACK:
			var s := "%s used %s — scrambled %d of %s's words" % [
				actor, res.item, res.scrambled, target]
			if int(res.blocked) > 0:
				s += " (%d blocked by wards)" % res.blocked
			return s + "."
		GameLogic.HP_DEFENSE:
			return "%s used %s — healed %d HP." % [actor, res.item, res.healed]
		GameLogic.WORD_DEFENSE:
			return "%s used %s — raised %d ward(s)." % [actor, res.item, res.wards]
	return ""


func _item_effect_text(tokens: Array, item_index: int) -> String:
	var p := GameLogic.item_power(tokens, item_index)
	if p.is_empty():
		return ""
	var verb := ""
	match p.type:
		GameLogic.HP_ATTACK: verb = "HP -%d" % p.amount
		GameLogic.WORD_ATTACK: verb = "scramble %d" % p.amount
		GameLogic.HP_DEFENSE: verb = "heal +%d" % p.amount
		GameLogic.WORD_DEFENSE: verb = "ward %d" % p.amount
	return "%s  →  %s  (base %d x%.2f)" % [
		GameLogic.item_label(tokens, item_index), verb, p.base, p.mult]


func _telegraph_text() -> String:
	var order: Array = _enemy.item_order
	if order.is_empty():
		return ""
	var parts: Array = []
	for i in range(order.size()):
		var item_index: int = order[i]
		var marker := "▸ " if i == int(_enemy.cycle_index) else "  "
		parts.append(marker + _item_effect_text(_enemy.tokens, item_index))
	return "Enemy plan (loops):   " + "      ".join(parts)


func _player_items_text() -> String:
	var order: Array = _player.item_order
	var parts: Array = []
	for item_index in order:
		parts.append(_item_effect_text(_player.tokens, item_index))
	return "Your items:   " + "      ".join(parts)
