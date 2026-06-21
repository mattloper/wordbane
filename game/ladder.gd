## Letter-Ladder Gauntlet (2D) — the playable game.
##
## Descend a gauntlet of escalating enemies. Each enemy's weapons are its red
## nouns; each turn the deadliest survivor damages you. On your turn, click a
## weapon tile and type a real word made from its letters (add OR remove letters,
## same part of speech) to disarm it. Disarm them all to descend; HP carries
## between fights (small heal each victory). Lose at 0 HP — score is the depth.
##
## All rules live in LadderBattle + Gauntlet + WordLadder; this is just the view.
## Run with:  godot --path game ladder.tscn
extends Control

const BANK_PATH := "res://data/word_bank.json"
const DICT_PATH := "res://data/dictionary.json"
const START_HP := Gauntlet.START_HP
const HEAL := Gauntlet.HEAL

const COL_BG := Color(0.11, 0.12, 0.17)
const COL_PANEL := Color(0.16, 0.17, 0.23)
const COL_WEAPON_FILL := Color(0.34, 0.13, 0.15)
const COL_SELECT := Color(1.0, 0.86, 0.3)
const COL_MUTED := Color(0.55, 0.56, 0.64)

var _ladder: WordLadder
var _gauntlet: Gauntlet
var _battle: LadderBattle
var _hp := START_HP
var _depth := 1
var _selected := -1
var _over := false
var _log_lines: Array = []

# UI nodes.
var _depth_label: Label
var _enemy_head: Label
var _row: HFlowContainer
var _incoming: Label
var _selinfo: Label
var _entry: LineEdit
var _hpbar: ProgressBar
var _hp_label: Label
var _spent_label: Label
var _log: Label


func _ready() -> void:
	_ladder = WordLadder.load_from(DICT_PATH)
	_gauntlet = Gauntlet.new()
	_gauntlet.setup(GameLogic.load_bank(BANK_PATH), _ladder)
	_battle = LadderBattle.new()
	_battle.ladder = _ladder
	_build_ui()
	_start_run()


# --- run / battle flow -------------------------------------------------------

func _start_run() -> void:
	_hp = START_HP
	_depth = 1
	_over = false
	_log_lines = []
	_battle.used = []  # no-reuse spans the whole run
	_start_enemy()
	_log_msg("A foe blocks your path. Disarm its weapons!")


func _start_enemy() -> void:
	_selected = -1
	_battle.begin(_gauntlet.generate(_depth), _hp, START_HP)
	_refresh()


func _on_disarm_pressed() -> void:
	if _over:
		return
	if _selected < 0:
		_selinfo.text = "Pick a weapon tile above, then type a word."
		return
	var res := _battle.try_move(_selected, _entry.text)
	if not res.get("ok", false):
		_selinfo.text = "Can't: " + str(res.get("reason", "invalid"))
		return
	_entry.text = ""
	var calm := ("  (calmed %s)" % ", ".join(res.calmed)) if not res.calmed.is_empty() else ""
	_log_msg("You: %s -> %s [%s]%s" % [res.target, res.word, res.direction, calm])
	if int(res.damage) > 0:
		_log_msg("   enemy strikes for %d" % res.damage)
	_selected = -1

	if res.get("won", false):
		_hp = mini(START_HP, _battle.player_hp + HEAL)
		_depth += 1
		_log_msg("Disarmed! +%d HP. Descending to depth %d." % [HEAL, _depth])
		_start_enemy()
		return
	_hp = _battle.player_hp
	if res.get("lost", false):
		_lose()
	_refresh()


func _on_skip_pressed() -> void:
	if _over:
		return
	var res := _battle.pass_turn()
	if not res.get("ok", false):
		return
	_log_msg("You skip — enemy strikes for %d." % res.damage)
	_hp = _battle.player_hp
	if res.get("lost", false):
		_lose()
	_refresh()


func _lose() -> void:
	_over = true
	_log_msg("DEFEATED at depth %d. Score: %d enemies cleared." % [_depth, _depth - 1])


func _select(token_index: int) -> void:
	if _over:
		return
	_selected = token_index
	_entry.grab_focus()
	_refresh()


# --- rendering ---------------------------------------------------------------

func _refresh() -> void:
	_depth_label.text = "DEPTH %d" % _depth
	_enemy_head.text = "ENEMY   ·   click a weapon tile (number = damage it deals)"

	_render_sentence()

	if _over:
		_incoming.text = "GAME OVER"
	else:
		_incoming.text = "! its deadliest weapon will hit you for %d next turn" % _battle.incoming_damage()

	if _over:
		_selinfo.text = "Press New Run to try again."
	elif _selected >= 0:
		var tok: Dictionary = _battle.enemy.tokens[_selected]
		_selinfo.text = "Disarming  %s  (letters: %s)  —  type a noun, adding or removing letters" % [
			tok.get("text", ""), " ".join(_letters(tok.get("text", "")))]
	else:
		_selinfo.text = "Pick a weapon to disarm."

	_hpbar.max_value = START_HP
	_hpbar.value = _hp
	_hpbar.modulate = Color(0.4, 0.78, 0.45) if _hp > START_HP / 3 else Color(0.92, 0.36, 0.36)
	_hp_label.text = "HP  %d / %d" % [_hp, START_HP]
	_spent_label.text = "words spent: %d  (no reuse)" % _battle.used.size()
	_log.text = "\n".join(_log_lines)


func _render_sentence() -> void:
	for c in _row.get_children():
		c.queue_free()
	var tokens: Array = _battle.enemy.tokens
	var weapons := _battle.weapon_indices()
	for i in range(tokens.size()):
		var token: Dictionary = tokens[i]
		# Weapons are clickable tiles; everything else (owner, adjectives, glue)
		# is plain text coloured by sentiment.
		if i in weapons and not _over:
			_row.add_child(_weapon_tile(token.get("text", ""), _battle.weapon_damage(i), i == _selected, i))
		else:
			var lbl := Label.new()
			lbl.text = token.get("text", "")
			lbl.add_theme_font_size_override("font_size", 22)
			lbl.add_theme_color_override("font_color", WordStyle.color_for(token))
			_row.add_child(lbl)


func _log_msg(text: String) -> void:
	_log_lines.append(text)
	if _log_lines.size() > 8:
		_log_lines.pop_front()
	if _log:
		_log.text = "\n".join(_log_lines)


func _letters(w: String) -> Array:
	var chars: Array = []
	for ch in w.to_lower():
		chars.append(ch)
	chars.sort()
	return chars


# --- UI construction ---------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 24)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	# Header: title + depth chip.
	var header := HBoxContainer.new()
	var title := _label("LETTER-LADDER GAUNTLET", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_depth_label = _label("DEPTH 1", 22)
	_depth_label.add_theme_color_override("font_color", COL_SELECT)
	header.add_child(_depth_label)
	col.add_child(header)

	# --- ENEMY zone ---
	var enemy_box := _zone(col)
	_enemy_head = _label("", 14)
	_enemy_head.add_theme_color_override("font_color", COL_MUTED)
	enemy_box.add_child(_enemy_head)
	_row = HFlowContainer.new()
	_row.add_theme_constant_override("h_separation", 8)
	_row.add_theme_constant_override("v_separation", 8)
	enemy_box.add_child(_row)
	_incoming = _label("", 16)
	_incoming.add_theme_color_override("font_color", Color(0.96, 0.62, 0.42))
	enemy_box.add_child(_incoming)

	# --- ACTION zone ---
	_selinfo = _label("", 16)
	_selinfo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_selinfo)
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 8)
	_entry = LineEdit.new()
	_entry.placeholder_text = "type a word…"
	_entry.custom_minimum_size = Vector2(300, 0)
	_entry.text_submitted.connect(func(_t): _on_disarm_pressed())
	controls.add_child(_entry)
	var go := Button.new()
	go.text = "Disarm"
	go.pressed.connect(_on_disarm_pressed)
	controls.add_child(go)
	var skip := Button.new()
	skip.text = "Skip (take the hit)"
	skip.pressed.connect(_on_skip_pressed)
	controls.add_child(skip)
	col.add_child(controls)

	# --- YOU zone ---
	var you_box := _zone(col)
	var you_head := _label("YOU", 14)
	you_head.add_theme_color_override("font_color", COL_MUTED)
	you_box.add_child(you_head)
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 12)
	_hp_label = _label("", 18)
	hp_row.add_child(_hp_label)
	_hpbar = ProgressBar.new()
	_hpbar.show_percentage = false
	_hpbar.custom_minimum_size = Vector2(0, 18)
	_hpbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_row.add_child(_hpbar)
	_spent_label = _label("", 14)
	_spent_label.add_theme_color_override("font_color", COL_MUTED)
	hp_row.add_child(_spent_label)
	you_box.add_child(hp_row)

	# --- LOG (fills remaining space) + New Run ---
	var log_box := _zone(col)
	log_box.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log = _label("", 14)
	_log.add_theme_color_override("font_color", Color(0.8, 0.82, 0.88))
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.add_child(_log)

	var restart := Button.new()
	restart.text = "New Run"
	restart.pressed.connect(_start_run)
	var center := CenterContainer.new()
	center.add_child(restart)
	col.add_child(center)


## Add a rounded padded panel to `parent` and return its inner VBox to fill.
## (Set the returned box's parent — box.get_parent() — to expand if it should grow.)
func _zone(parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	parent.add_child(panel)
	return box


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


## A clickable weapon word as a bordered tile: "word  N" (N = damage).
func _weapon_tile(word: String, dmg: int, selected: bool, idx: int) -> Button:
	var b := Button.new()
	b.text = "%s   %d" % [word, dmg]
	b.add_theme_font_size_override("font_size", 22)
	var border := COL_SELECT if selected else WordStyle.NEGATIVE
	var fill := Color(0.46, 0.18, 0.2) if selected else COL_WEAPON_FILL
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill.lightened(0.12) if state == "hover" else fill
		sb.set_border_width_all(2)
		sb.border_color = border
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", COL_SELECT if selected else Color(1.0, 0.82, 0.82))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.pressed.connect(_select.bind(idx))
	return b
