## Letter-Ladder Gauntlet (2D) — the playable game.
##
## Descend chapters of escalating word-creatures. Each enemy's weapons are its red
## nouns (with emoji clipart); each turn the deadliest survivor damages you. Click a
## weapon and type a real word from its letters (add OR remove letters, same part of
## speech, no reuse) to disarm it. Clear all weapons to advance; pick a boon between
## chapters. Lose at 0 HP — your score is how far + how well you played.
##
## Rules live in LadderBattle + Gauntlet + WordLadder; this is the view.
## Run with:  godot --path game ladder.tscn
extends Control

const BANK_PATH := "res://data/word_bank.json"
const DICT_PATH := "res://data/dictionary.json"
const HEAL := Gauntlet.HEAL

const COL_BG := Color(0.11, 0.12, 0.17)
const COL_PANEL := Color(0.16, 0.17, 0.23)
const COL_WEAPON_FILL := Color(0.34, 0.13, 0.15)
const COL_SELECT := Color(1.0, 0.86, 0.3)
const COL_MUTED := Color(0.55, 0.56, 0.64)

# Between-chapter rewards. 3 are offered (at random) after each victory.
const BOONS := [
	{"id": "tough", "label": "Toughness", "desc": "+6 Max HP"},
	{"id": "mend", "label": "Mend", "desc": "Heal to full"},
	{"id": "eraser", "label": "Eraser", "desc": "Forget all spent words (reuse them)"},
	{"id": "focus", "label": "Focus", "desc": "Gain a Hint button"},
]

var _ladder: WordLadder
var _gauntlet: Gauntlet
var _battle: LadderBattle
var _icons := IconBank.new()

var _max_hp := Gauntlet.START_HP
var _hp := Gauntlet.START_HP
var _chapter := 1
var _score := 0
var _selected := -1
var _over := false
var _choosing := false
var _has_hint := false
var _log_lines: Array = []

# UI nodes.
var _chapter_label: Label
var _score_label: Label
var _enemy_head: Label
var _portrait: Label
var _row: HFlowContainer
var _incoming: Label
var _selinfo: Label
var _controls: HBoxContainer
var _boon_row: HBoxContainer
var _hint_btn: Button
var _entry: LineEdit
var _hpbar: ProgressBar
var _hp_label: Label
var _spent_label: Label
var _log: Label


func _ready() -> void:
	var font := IconBank.text_font_with_emoji()
	if font != null:
		var t := Theme.new()
		t.default_font = font
		t.default_font_size = 18
		theme = t
	_ladder = WordLadder.load_from(DICT_PATH)
	_gauntlet = Gauntlet.new()
	_gauntlet.setup(GameLogic.load_bank(BANK_PATH), _ladder)
	_battle = LadderBattle.new()
	_battle.ladder = _ladder
	_build_ui()
	_start_run()


# --- run / battle flow -------------------------------------------------------

func _start_run() -> void:
	_max_hp = Gauntlet.START_HP
	_hp = _max_hp
	_chapter = 1
	_score = 0
	_over = false
	_choosing = false
	_has_hint = false
	_log_lines = []
	_battle.used = []  # no-reuse spans the whole run
	_start_enemy()
	_log_msg("A foe blocks your path. Disarm its weapons!")


func _start_enemy() -> void:
	_selected = -1
	_choosing = false
	_battle.begin(_gauntlet.generate(_chapter), _hp, _max_hp)
	_refresh()


func _on_disarm_pressed() -> void:
	if _over or _choosing:
		return
	if _selected < 0:
		_selinfo.text = "Pick a weapon tile above, then type a word."
		return
	var res := _battle.try_move(_selected, _entry.text)
	if not res.get("ok", false):
		_selinfo.text = "Can't: " + str(res.get("reason", "invalid"))
		return
	var word := _entry.text.strip_edges()
	_entry.text = ""
	_score += word.length() * 5  # longer words score more
	var calm := ("  (calmed %s)" % ", ".join(res.calmed)) if not res.calmed.is_empty() else ""
	_log_msg("You: %s -> %s [%s]%s  +%d" % [res.target, res.word, res.direction, calm, word.length() * 5])
	if int(res.damage) > 0:
		_log_msg("   enemy strikes for %d" % res.damage)
	_selected = -1

	if res.get("won", false):
		_score += _chapter * 25  # chapter-clear bonus
		_hp = _battle.player_hp   # no free heal — recover via boons
		_log_msg("Chapter %d cleared!  (+%d score)  Choose a reward." % [_chapter, _chapter * 25])
		_offer_boons()
		return
	_hp = _battle.player_hp
	if res.get("lost", false):
		_lose()
	_refresh()


func _on_skip_pressed() -> void:
	if _over or _choosing:
		return
	var res := _battle.pass_turn()
	if not res.get("ok", false):
		return
	_log_msg("You skip — enemy strikes for %d." % res.damage)
	_hp = _battle.player_hp
	if res.get("lost", false):
		_lose()
	_refresh()


func _on_hint_pressed() -> void:
	if _over or _choosing or _selected < 0:
		return
	var target: String = _battle.enemy.tokens[_selected].get("text", "")
	var w := _ladder.find_transform(target, "noun", _battle.used)
	_selinfo.text = "Hint: try '%s'" % w if w != "" else "Hint: no fresh word found — Skip."


func _lose() -> void:
	_over = true
	_log_msg("DEFEATED in chapter %d. Final score: %d." % [_chapter, _score])


func _select(token_index: int) -> void:
	if _over or _choosing:
		return
	_selected = token_index
	_entry.grab_focus()
	_refresh()


# --- boons (between-chapter progression) -------------------------------------

func _offer_boons() -> void:
	_choosing = true
	_selected = -1
	var pool: Array = BOONS.duplicate()
	if _has_hint:
		pool = pool.filter(func(b): return b.id != "focus")  # don't re-offer hint
	pool.shuffle()
	for c in _boon_row.get_children():
		c.queue_free()
	for i in range(mini(3, pool.size())):
		var boon: Dictionary = pool[i]
		var btn := Button.new()
		btn.text = "%s\n%s" % [boon.label, boon.desc]
		btn.custom_minimum_size = Vector2(180, 56)
		btn.pressed.connect(_take_boon.bind(boon.id))
		_boon_row.add_child(btn)
	_refresh()


func _take_boon(id: String) -> void:
	match id:
		"tough": _max_hp += 6; _hp = mini(_max_hp, _hp + 6)
		"mend": _hp = _max_hp
		"eraser": _battle.used = []
		"focus": _has_hint = true
	_log_msg("Boon: %s" % id)
	_chapter += 1
	_start_enemy()


# --- rendering ---------------------------------------------------------------

func _refresh() -> void:
	_chapter_label.text = "CHAPTER %d" % _chapter
	_score_label.text = "SCORE %d" % _score
	_enemy_head.text = "ENEMY   ·   click a weapon (number = damage), then type a word"

	_render_enemy()

	if _over:
		_incoming.text = "GAME OVER — press New Run"
	elif _choosing:
		_incoming.text = "Chapter cleared — choose a reward to descend"
	else:
		_incoming.text = "! its deadliest weapon will hit you for %d next turn" % _battle.incoming_damage()

	if _over:
		_selinfo.text = "Final score: %d  ·  reached chapter %d" % [_score, _chapter]
	elif _choosing:
		_selinfo.text = "Choose a boon:"
	elif _selected >= 0:
		var tok: Dictionary = _battle.enemy.tokens[_selected]
		_selinfo.text = "Disarming  %s  (letters: %s)  —  type a noun, adding or removing letters" % [
			tok.get("text", ""), " ".join(_letters(tok.get("text", "")))]
	else:
		_selinfo.text = "Pick a weapon to disarm."

	_controls.visible = not _choosing and not _over
	_boon_row.visible = _choosing
	_hint_btn.visible = _has_hint

	_hpbar.max_value = _max_hp
	_hpbar.value = _hp
	_hpbar.modulate = Color(0.4, 0.78, 0.45) if _hp > _max_hp / 3 else Color(0.92, 0.36, 0.36)
	_hp_label.text = "HP  %d / %d" % [_hp, _max_hp]
	_spent_label.text = "words spent: %d  (no reuse)" % _battle.used.size()
	_log.text = "\n".join(_log_lines)


func _render_enemy() -> void:
	for c in _row.get_children():
		c.queue_free()
	var tokens: Array = _battle.enemy.tokens
	var weapons := _battle.weapon_indices()
	# Portrait = the owner creature's emoji (big).
	var owner_word := ""
	for t in tokens:
		if t.get("kind", "") == GameLogic.KIND_CREATURE and t.get("is_owner", false):
			owner_word = t.get("text", "")
	_portrait.text = _icons.of(owner_word)

	for i in range(tokens.size()):
		var token: Dictionary = tokens[i]
		if i in weapons and not _over:
			_row.add_child(_weapon_tile(token.get("text", ""), _battle.weapon_damage(i), i == _selected, i))
		else:
			var lbl := Label.new()
			var emoji := _icons.of(token.get("text", "")) if token.get("kind", "") == GameLogic.KIND_CREATURE else ""
			lbl.text = (emoji + " " + token.get("text", "")) if emoji != "" else token.get("text", "")
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
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	# Header: title (left) · CHAPTER (center, big) · SCORE (right).
	var header := HBoxContainer.new()
	var title := _label("Wordplay", 16)
	title.add_theme_color_override("font_color", COL_MUTED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_chapter_label = _label("CHAPTER 1", 30)
	_chapter_label.add_theme_color_override("font_color", COL_SELECT)
	header.add_child(_chapter_label)
	_score_label = _label("SCORE 0", 18)
	_score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_score_label)
	col.add_child(header)

	# --- ENEMY zone: portrait + sentence ---
	var enemy_box := _zone(col)
	_enemy_head = _label("", 14)
	_enemy_head.add_theme_color_override("font_color", COL_MUTED)
	enemy_box.add_child(_enemy_head)
	var enemy_row := HBoxContainer.new()
	enemy_row.add_theme_constant_override("separation", 14)
	_portrait = _label("", 56)
	_portrait.custom_minimum_size = Vector2(72, 72)
	_portrait.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	enemy_row.add_child(_portrait)
	var enemy_text := VBoxContainer.new()
	enemy_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_text.add_theme_constant_override("separation", 8)
	_row = HFlowContainer.new()
	_row.add_theme_constant_override("h_separation", 8)
	_row.add_theme_constant_override("v_separation", 8)
	enemy_text.add_child(_row)
	_incoming = _label("", 16)
	_incoming.add_theme_color_override("font_color", Color(0.96, 0.62, 0.42))
	enemy_text.add_child(_incoming)
	enemy_row.add_child(enemy_text)
	enemy_box.add_child(enemy_row)

	# --- ACTION zone ---
	_selinfo = _label("", 16)
	_selinfo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_selinfo)

	_controls = HBoxContainer.new()
	_controls.alignment = BoxContainer.ALIGNMENT_CENTER
	_controls.add_theme_constant_override("separation", 8)
	_entry = LineEdit.new()
	_entry.placeholder_text = "type a word…"
	_entry.custom_minimum_size = Vector2(300, 0)
	_entry.text_submitted.connect(func(_t): _on_disarm_pressed())
	_controls.add_child(_entry)
	var go := Button.new()
	go.text = "Disarm"
	go.pressed.connect(_on_disarm_pressed)
	_controls.add_child(go)
	var skip := Button.new()
	skip.text = "Skip (take the hit)"
	skip.pressed.connect(_on_skip_pressed)
	_controls.add_child(skip)
	_hint_btn = Button.new()
	_hint_btn.text = "Hint"
	_hint_btn.pressed.connect(_on_hint_pressed)
	_controls.add_child(_hint_btn)
	col.add_child(_controls)

	_boon_row = HBoxContainer.new()
	_boon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_boon_row.add_theme_constant_override("separation", 10)
	col.add_child(_boon_row)

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


## A clickable weapon as a bordered tile: "<emoji> word  N" (N = damage).
func _weapon_tile(word: String, dmg: int, selected: bool, idx: int) -> Button:
	var b := Button.new()
	var emoji := _icons.of(word)
	b.text = ("%s %s   %d" % [emoji, word, dmg]) if emoji != "" else ("%s   %d" % [word, dmg])
	b.add_theme_font_size_override("font_size", 22)
	var border := COL_SELECT if selected else WordStyle.NEGATIVE
	var fill := Color(0.46, 0.18, 0.2) if selected else COL_WEAPON_FILL
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = fill.lightened(0.12) if state == "hover" else fill
		box.set_border_width_all(2)
		box.border_color = border
		box.set_corner_radius_all(6)
		box.content_margin_left = 12
		box.content_margin_right = 12
		box.content_margin_top = 5
		box.content_margin_bottom = 5
		b.add_theme_stylebox_override(state, box)
	b.add_theme_color_override("font_color", COL_SELECT if selected else Color(1.0, 0.82, 0.82))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.pressed.connect(_select.bind(idx))
	return b
