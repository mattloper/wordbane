## Letter-Ladder Gauntlet (2D) — the playable game.
##
## Descend a gauntlet of escalating enemies. Each enemy's weapons are its red
## nouns; each turn the survivors damage you. On your turn, click a weapon and type
## a real word made from its letters (add OR remove letters, same part of speech)
## to disarm it. Disarm them all to descend; your HP carries between fights (small
## heal each victory). Lose when HP hits 0 — your score is the depth you reached.
##
## All rules live in LadderBattle + Gauntlet + WordLadder; this is just the view.
## Run with:  godot --path game ladder.tscn
extends Control

const BANK_PATH := "res://data/word_bank.json"
const DICT_PATH := "res://data/dictionary.json"
const START_HP := 24
const HEAL := 6

var _ladder: WordLadder
var _gauntlet: Gauntlet
var _battle: LadderBattle
var _hp := START_HP
var _depth := 1
var _selected := -1
var _over := false
var _log_lines: Array = []

# UI.
var _title: Label
var _hpbar: ProgressBar
var _row: HFlowContainer
var _incoming: Label
var _selinfo: Label
var _entry: LineEdit
var _log: Label


func _ready() -> void:
	_ladder = WordLadder.load_from(DICT_PATH)
	_gauntlet = Gauntlet.new()
	_gauntlet.setup(GameLogic.load_bank(BANK_PATH))
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
	_start_enemy()
	_log_msg("A foe blocks your path. Disarm its weapons!")


func _start_enemy() -> void:
	_selected = -1
	_battle.begin(_gauntlet.generate(_depth), _hp, START_HP)
	_refresh()


func _on_disarm_pressed() -> void:
	if _over or _selected < 0:
		_selinfo.text = "Click a red weapon first, then type a word."
		return
	var res := _battle.try_move(_selected, _entry.text)
	if not res.get("ok", false):
		_selinfo.text = "✗ " + str(res.get("reason", "invalid"))
		return
	_entry.text = ""
	var calm := ("  (calmed %s)" % ", ".join(res.calmed)) if not res.calmed.is_empty() else ""
	_log_msg("You: %s → %s [%s]%s" % [res.target, res.word, res.direction, calm])
	if int(res.damage) > 0:
		_log_msg("  ↳ enemy strikes for %d" % res.damage)

	if res.get("won", false):
		_hp = mini(START_HP, _battle.player_hp + HEAL)
		_depth += 1
		_log_msg("✅ Disarmed! +%d HP. Descending to depth %d…" % [HEAL, _depth])
		_start_enemy()
		return
	_hp = _battle.player_hp
	if res.get("lost", false):
		_over = true
		_log_msg("💀 You fell at depth %d. Score: %d enemies cleared." % [_depth, _depth - 1])
	_refresh()


func _select(token_index: int) -> void:
	if _over:
		return
	_selected = token_index
	_entry.grab_focus()
	_refresh()


# --- rendering ---------------------------------------------------------------

func _refresh() -> void:
	_title.text = "LETTER-LADDER GAUNTLET    —    Depth %d" % _depth
	_hpbar.max_value = START_HP
	_hpbar.value = _hp
	_hpbar.modulate = Color(0.35, 0.75, 0.4) if _hp > START_HP / 3 else Color(0.9, 0.35, 0.35)

	_render_sentence()
	_incoming.text = "" if _over else "If you stall, you take %d damage next turn." % _battle.incoming_damage()
	if _over:
		_selinfo.text = "GAME OVER — press New Run."
	elif _selected >= 0:
		var tok: Dictionary = _battle.enemy.tokens[_selected]
		_selinfo.text = "Disarming: %s   (letters: %s)   → type a noun (add or remove letters)" % [
			tok.get("text", ""), " ".join(_letters(tok.get("text", "")))]
	else:
		_selinfo.text = "Click a red weapon (noun) to target it."
	_log.text = "\n".join(_log_lines)


func _render_sentence() -> void:
	for c in _row.get_children():
		c.queue_free()
	var tokens: Array = _battle.enemy.tokens
	var weapons := _battle.weapon_indices()
	for i in range(tokens.size()):
		var token: Dictionary = tokens[i]
		if i in weapons and not _over:
			var dmg := _battle.weapon_damage(i)
			var btn := Button.new()
			btn.text = "%s ⚔%d" % [token.get("text", ""), dmg]
			btn.add_theme_font_size_override("font_size", 22)
			btn.add_theme_color_override("font_color",
				Color(1.0, 0.9, 0.3) if i == _selected else WordStyle.NEGATIVE)
			btn.pressed.connect(_select.bind(i))
			_row.add_child(btn)
		else:
			var lbl := Label.new()
			lbl.text = token.get("text", "")
			lbl.add_theme_font_size_override("font_size", 22)
			lbl.add_theme_color_override("font_color", WordStyle.color_for(token))
			_row.add_child(lbl)


func _log_msg(text: String) -> void:
	_log_lines.append(text)
	if _log_lines.size() > 7:
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
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 26)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	_title = _label("", 24)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)

	_hpbar = ProgressBar.new()
	_hpbar.show_percentage = false
	_hpbar.custom_minimum_size = Vector2(0, 20)
	col.add_child(_hpbar)

	col.add_child(HSeparator.new())

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

	_incoming = _label("", 16)
	_incoming.add_theme_color_override("font_color", Color(0.95, 0.6, 0.4))
	col.add_child(_incoming)

	_selinfo = _label("", 16)
	col.add_child(_selinfo)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	_entry = LineEdit.new()
	_entry.placeholder_text = "type a word…"
	_entry.custom_minimum_size = Vector2(280, 0)
	_entry.text_submitted.connect(func(_t): _on_disarm_pressed())
	controls.add_child(_entry)
	var go := Button.new()
	go.text = "Disarm"
	go.pressed.connect(_on_disarm_pressed)
	controls.add_child(go)
	col.add_child(controls)

	col.add_child(HSeparator.new())

	_log = _label("", 15)
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.custom_minimum_size = Vector2(0, 150)
	_log.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	col.add_child(_log)

	var restart := Button.new()
	restart.text = "New Run"
	restart.pressed.connect(_start_run)
	var center := CenterContainer.new()
	center.add_child(restart)
	col.add_child(center)


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l
