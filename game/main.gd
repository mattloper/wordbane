## Wordplay — main scene controller.
##
## Turn-based duel between two sentences. Each character has an *owner* (its
## subject noun, found by syntax at build time) and *items* (its other nouns).
## Owners deal no damage; items do. Adjectives multiply their item's effect.
##
## Your turn: click one of YOUR item words to use it. If it's a word-attack item,
## you then click which ENEMY word(s) to randomize. The enemy cycles through its
## items in a fixed, telegraphed order. Win by reducing the enemy to 0 HP *or*
## pacifying it (no negative words left); lose if your HP hits 0.
extends Control

const BANK_PATH := "res://data/word_bank.json"

# Interaction states.
const ST_CHOOSE := "choose"   # your turn: pick one of your items
const ST_TARGET := "target"   # picking which enemy word(s) to randomize
const ST_BUSY := "busy"       # enemy acting / animating
const ST_OVER := "over"       # battle finished

var _rng := RandomNumberGenerator.new()
var _pools: Dictionary = {}
var _characters: Array = []

var _player: Dictionary = {}
var _enemy: Dictionary = {}
var _state := ST_CHOOSE
var _player_msg := ""
var _pending_targets := 0
var _pending_label := ""
var _battle_id := 0  # bumped each New Battle; guards stale timer coroutines

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
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var title := _label("WORDPLAY", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	# Enemy block.
	_enemy_header = _label("", 19)
	col.add_child(_enemy_header)
	_enemy_hp = _hp_bar(Color(0.85, 0.30, 0.30))
	col.add_child(_enemy_hp)
	_enemy_being = _being()
	col.add_child(_panel(_enemy_being))
	_telegraph = _label("", 15)
	_telegraph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_telegraph)

	col.add_child(_separator())

	# Turn banner + message log.
	_banner = _label("", 22)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_banner)
	_status = _label("", 16)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 48)
	col.add_child(_status)

	col.add_child(_separator())

	# Player block.
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


# --- game flow ---------------------------------------------------------------

func _new_game() -> void:
	var enemy_t := GameLogic.pick_character(_characters, "enemy", _rng)
	var player_t := GameLogic.pick_character(_characters, "player", _rng)
	if enemy_t.is_empty() or player_t.is_empty():
		_status.text = "Word bank is missing player/enemy characters."
		return
	_battle_id += 1
	_enemy = GameLogic.make_fighter(enemy_t)
	_player = GameLogic.make_fighter(player_t)
	_state = ST_CHOOSE
	_player_msg = ""
	_pending_targets = 0
	_status.text = "Click one of your item words below to use it."
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

	_render_being(_enemy_being, _enemy, "target" if _state == ST_TARGET else "none")
	_render_being(_player_being, _player, "items" if _state == ST_CHOOSE else "none")

	_banner.text = _banner_text()
	_banner.add_theme_color_override("font_color", _banner_color())
	_telegraph.text = _telegraph_text()
	_player_items.text = _player_items_text()


func _banner_text() -> String:
	match _state:
		ST_CHOOSE: return "● YOUR TURN — use an item"
		ST_TARGET: return "◎ PICK A TARGET — click %d enemy word(s)" % _pending_targets
		ST_BUSY: return "ENEMY TURN…"
		ST_OVER: return "GAME OVER"
	return ""


func _banner_color() -> Color:
	match _state:
		ST_CHOOSE: return WordStyle.POSITIVE
		ST_TARGET: return Color(1.0, 0.85, 0.3)
		ST_BUSY: return WordStyle.NEGATIVE
		_: return WordStyle.NEUTRAL


## Render a character as a small sideways tree: the owner is the body (top),
## each item branches below it as a limb carrying its adjectives. This is the
## dependency structure spaCy found at build time, shown directly.
## mode: "items" (player item buttons), "target" (enemy word buttons), "none".
func _render_being(box: VBoxContainer, fighter: Dictionary, mode: String) -> void:
	for c in box.get_children():
		c.queue_free()
	var tokens: Array = fighter.tokens

	# Owner line: the owner word (big), preceded by its adjectives.
	var owner_line := _branch_row()
	var owner_idx := -1
	for i in range(tokens.size()):
		var t: Dictionary = tokens[i]
		if t.get("kind", "") == GameLogic.KIND_ADJ and t.get("attaches", "") == "owner":
			owner_line.add_child(_token_control(t, i, tokens, mode, 22))
		elif t.get("kind", "") == GameLogic.KIND_CREATURE and t.get("is_owner", false):
			owner_idx = i
	if owner_idx >= 0:
		owner_line.add_child(_token_control(tokens[owner_idx], owner_idx, tokens, mode, 30))
	box.add_child(owner_line)

	# One branch per item, in cycle order: connector + adjectives + item noun.
	for item_index in fighter.item_order:
		var line := _branch_row()
		line.add_child(_connector("   ┗━"))
		var noun_idx := -1
		for i in range(tokens.size()):
			var t: Dictionary = tokens[i]
			if t.get("kind", "") == GameLogic.KIND_ADJ and t.get("attaches", "") == "item:%d" % int(item_index):
				line.add_child(_token_control(t, i, tokens, mode, 22))
			elif t.get("kind", "") == GameLogic.KIND_ITEM and int(t.get("item_index", -1)) == int(item_index):
				noun_idx = i
		if noun_idx >= 0:
			line.add_child(_token_control(tokens[noun_idx], noun_idx, tokens, mode, 22))
		box.add_child(line)


func _branch_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	return row


func _connector(glyph: String) -> Label:
	var l := _label(glyph, 20)
	l.add_theme_color_override("font_color", WordStyle.FIXED)
	return l


## One word as a Button (when interactive) or Label, colored by sentiment.
func _token_control(token: Dictionary, idx: int, tokens: Array, mode: String, font_size: int) -> Control:
	var color := WordStyle.color_for(token)
	var kind: String = token.get("kind", "")
	var cb := Callable()
	if mode == "items" and kind == GameLogic.KIND_ITEM:
		cb = Callable(self, "_on_player_item_pressed").bind(int(token.get("item_index", -1)))
	elif mode == "target" and kind in GameLogic.EDITABLE_KINDS:
		cb = Callable(self, "_on_enemy_word_pressed").bind(idx)

	if not cb.is_null():
		var btn := Button.new()
		btn.text = token.get("text", "")
		btn.add_theme_font_size_override("font_size", font_size)
		btn.add_theme_color_override("font_color", color)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		if mode == "items":
			btn.tooltip_text = _item_effect_text(tokens, int(token.get("item_index", -1)))
		btn.pressed.connect(cb)
		return btn

	var lbl := Label.new()
	lbl.text = token.get("text", "")
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl


func _on_player_item_pressed(item_index: int) -> void:
	if _state != ST_CHOOSE or item_index < 0:
		return
	var power := GameLogic.item_power(_player.tokens, item_index)
	if power.get("type", "") == GameLogic.WORD_ATTACK:
		# Enter targeting mode: player clicks which enemy words to randomize.
		_pending_targets = int(power.amount)
		_pending_label = GameLogic.item_label(_player.tokens, item_index)
		_state = ST_TARGET
		_refresh()
		_status.text = "%s readies %s — click an enemy word to randomize it." % [
			_player.name, _pending_label]
		return
	# Non-targeted items (HP attack, defenses) resolve immediately.
	var res := GameLogic.apply_item(_player, _enemy, item_index, _pools, _rng)
	_player_msg = _describe(_player.name, res, _enemy.name)
	await _finish_player_action()


func _on_enemy_word_pressed(token_index: int) -> void:
	if _state != ST_TARGET:
		return
	var r := GameLogic.scramble_one(_enemy, token_index, _pools, _rng)
	if not r.get("ok", false):
		return
	_pending_targets -= 1
	var note := ("blocked by %s's ward!" % _enemy.name) if r.get("blocked", false) \
		else ("→ randomized to '%s'." % r.get("text", ""))
	_refresh()
	if _check_end():
		return
	var no_targets: bool = GameLogic.editable_indices(_enemy.tokens).is_empty()
	if _pending_targets <= 0 or no_targets:
		_player_msg = "%s used %s (%s)" % [_player.name, _pending_label, note]
		await _finish_player_action()
	else:
		_status.text = "%s  Click %d more enemy word(s)." % [note, _pending_targets]


func _finish_player_action() -> void:
	var id := _battle_id
	_status.text = _player_msg
	_state = ST_BUSY
	_refresh()
	if _check_end():
		return
	await get_tree().create_timer(0.55).timeout
	if id != _battle_id:
		return  # a New Battle started during the pause; abandon this coroutine
	_enemy_turn()


func _enemy_turn() -> void:
	if _state == ST_OVER:
		return
	var idx := GameLogic.next_item_index(_enemy)
	var res := GameLogic.apply_item(_enemy, _player, idx, _pools, _rng)
	GameLogic.advance_cycle(_enemy)
	_status.text = _player_msg + "\n" + _describe(_enemy.name, res, _player.name)
	if _check_end():
		return
	_state = ST_CHOOSE
	_refresh()


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
	_state = ST_OVER
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
	var parts: Array = []
	for item_index in _player.item_order:
		parts.append(_item_effect_text(_player.tokens, item_index))
	return "Your items:   " + "      ".join(parts)
