## Letter-Pool Gauntlet (2D) — the playable game.
##
## Descend chapters of escalating word-creatures. Each enemy shows a POOL OF LETTERS
## (the distinct letters of its red weapon-nouns) and an HP bar equal to their total
## rarity weight. Type ANY real word using its letters: it deals damage = the summed
## rarity weight of the letters it covers (rare letters — j/x/q/z — hit hardest), so
## draining the bar rewards big, rare-lettered words. Drain HP to 0 to win the
## chapter; pick a boon between chapters. The enemy strikes back each turn, softer as
## you wear it down. Lose at 0 HP — your score is how far + how hard you hit.
##
## Rules live in PoolBattle + Gauntlet + Lexicon; this is the view.
## Run with:  godot --path game pool_gauntlet.tscn
extends Control

const BANK_PATH := "res://data/word_bank.json"
const DICT_PATH := "res://data/dictionary.json"

const COL_BG := Color(0.11, 0.12, 0.17)
const COL_PANEL := Color(0.16, 0.17, 0.23)
const COL_SELECT := Color(1.0, 0.86, 0.3)
const COL_MUTED := Color(0.55, 0.56, 0.64)
const COL_TILE := Color(0.22, 0.23, 0.3)
const COL_TILE_RARE := Color(0.3, 0.26, 0.14)
const COL_HIT_ENEMY := Color(1.0, 0.95, 0.55)  # our damage floats up in gold
const COL_HIT_YOU := Color(1.0, 0.45, 0.45)    # their damage floats up in red
const BAR_DRAIN := 0.45                          # seconds for an HP bar to ease down

var _lexicon: Lexicon
var _gauntlet: Gauntlet
var _battle: PoolBattle
var _icons := IconBank.new()

var _max_hp := Gauntlet.START_HP
var _hp := Gauntlet.START_HP
var _chapter := 1
var _score := 0
var _over := false
var _choosing := false
var _has_hint := false
var _log_lines: Array = []

# UI nodes.
var _chapter_label: Label
var _score_label: Label
var _enemy_head: Label
var _portrait: Label
var _portrait_holder: Control
var _ehp_tween: Tween
var _php_tween: Tween
var _sentence: HFlowContainer
var _enemy_hpbar: ProgressBar
var _enemy_hp_label: Label
var _letters_row: HFlowContainer
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
	_lexicon = Lexicon.load_from(DICT_PATH)
	_gauntlet = Gauntlet.new()
	_gauntlet.setup(GameLogic.load_bank(BANK_PATH))
	_battle = PoolBattle.new()
	_battle.lexicon = _lexicon
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
	_log_msg("A foe blocks your path. Spell from its letters to drain its HP!")


func _start_enemy() -> void:
	_choosing = false
	_battle.begin(_gauntlet.generate(_chapter), _hp, _max_hp)
	_entry.text = ""
	# Snap both bars to their starting values so a fresh enemy doesn't "fill up".
	_enemy_hpbar.max_value = _battle.enemy_max_hp()
	_enemy_hpbar.value = _battle.enemy_max_hp()
	_hpbar.max_value = _max_hp
	_hpbar.value = _hp
	_refresh()
	_entry.grab_focus()


func _on_strike_pressed() -> void:
	if _over or _choosing:
		return
	var res := _battle.try_move(_entry.text)
	if not res.get("ok", false):
		_selinfo.text = "Can't: " + str(res.get("reason", "invalid"))
		return
	_entry.text = ""
	var dealt: int = int(res.dealt)
	var gain: int = dealt * 3  # damage (more/rarer letters) scores more
	_score += gain
	var uses := ("  [uses %s]" % ", ".join(Lexicon.upper_letters(res.covered))) if not res.covered.is_empty() else ""
	_log_msg("You: %s hits for %d%s  +%d" % [res.word, dealt, uses, gain])
	_float_number(_enemy_hpbar, dealt, COL_HIT_ENEMY)  # our hit floats over the enemy
	if int(res.damage) > 0:
		_log_msg("   enemy strikes for %d" % res.damage)

	if res.get("won", false):
		_score += _chapter * 25  # chapter-clear bonus
		_hp = _battle.player_hp   # no free heal — recover via boons
		_log_msg("Chapter %d cleared!  (+%d score)  Choose a reward." % [_chapter, _chapter * 25])
		_offer_boons()
		return
	if int(res.damage) > 0:  # the enemy struck back
		_float_number(_hpbar, int(res.damage), COL_HIT_YOU)
		_lunge_enemy()
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
	if int(res.damage) > 0:
		_float_number(_hpbar, int(res.damage), COL_HIT_YOU)
		_lunge_enemy()
	_hp = _battle.player_hp
	if res.get("lost", false):
		_lose()
	_refresh()


func _on_hint_pressed() -> void:
	if _over or _choosing:
		return
	var w := _lexicon.best_word("".join(_battle.letters()), _battle.used)
	_selinfo.text = "Hint: try '%s'" % w if w != "" else "Hint: no fresh word found — Skip."


func _lose() -> void:
	_over = true
	_log_msg("DEFEATED in chapter %d. Final score: %d." % [_chapter, _score])


## The action-line text: final/boon prompts, else a live damage preview of what
## you've typed against the enemy's letters (teaches "rare letters hit harder").
func _update_selinfo() -> void:
	if _over:
		_selinfo.text = "Final score: %d  ·  reached chapter %d" % [_score, _chapter]
		return
	if _choosing:
		_selinfo.text = "Choose a boon:"
		return
	var letters_str := "".join(_battle.letters())
	var head := "Drain its letters  —  enemy HP %d/%d" % [_battle.enemy_hp(), _battle.enemy_max_hp()]
	var typed := _entry.text.strip_edges()
	if typed == "":
		_selinfo.text = head + "  ·  type any word using its letters"
		return
	var r := _lexicon.validate(typed, letters_str, _battle.used)
	if r.get("ok", false):
		_selinfo.text = "%s  ·  '%s' deals %d  (uses %s)" % [head, typed.to_lower(),
			int(r.dealt), ", ".join(Lexicon.upper_letters(Lexicon.covered_letters(typed, letters_str)))]
	else:
		_selinfo.text = "%s  ·  %s" % [head, str(r.get("reason", ""))]


# --- boons (between-chapter progression) -------------------------------------

func _offer_boons() -> void:
	_choosing = true
	var pool: Array = Boons.ALL.duplicate()
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
	var s := {"hp": _hp, "max_hp": _max_hp, "used": _battle.used, "has_hint": _has_hint}
	Boons.apply(id, s)
	_hp = int(s.hp)
	_max_hp = int(s.max_hp)
	_battle.used = s.used
	_has_hint = bool(s.has_hint)
	_log_msg("Boon: %s" % id)
	_chapter += 1
	_start_enemy()


# --- rendering ---------------------------------------------------------------

func _refresh() -> void:
	_chapter_label.text = "CHAPTER %d" % _chapter
	_score_label.text = "SCORE %d" % _score
	_enemy_head.text = "ENEMY   ·   spell words from its letters to drain its HP (rare letters hit hardest)"

	_render_enemy()

	_enemy_hpbar.max_value = _battle.enemy_max_hp()
	_ehp_tween = _drain_bar(_enemy_hpbar, _battle.enemy_hp(), _ehp_tween)
	_enemy_hp_label.text = "HP  %d / %d" % [_battle.enemy_hp(), _battle.enemy_max_hp()]

	if _over:
		_incoming.text = "GAME OVER — press New Run"
	elif _choosing:
		_incoming.text = "Chapter cleared — choose a reward to descend"
	else:
		_incoming.text = "! it will hit you for %d every turn until it's dead" % _battle.incoming_damage()

	_update_selinfo()

	_controls.visible = not _choosing and not _over
	_boon_row.visible = _choosing
	_hint_btn.visible = _has_hint

	_hpbar.max_value = _max_hp
	_php_tween = _drain_bar(_hpbar, _hp, _php_tween)
	_hpbar.modulate = Color(0.4, 0.78, 0.45) if _hp > _max_hp / 3 else Color(0.92, 0.36, 0.36)
	_hp_label.text = "HP  %d / %d" % [_hp, _max_hp]
	_spent_label.text = "words spent: %d  (no reuse)" % _battle.used.size()
	_log.text = "\n".join(_log_lines)


func _render_enemy() -> void:
	# Portrait = the owner creature's emoji (big).
	var tokens: Array = _battle.enemy.tokens
	var owner_word := ""
	for t in tokens:
		if t.get("kind", "") == GameLogic.KIND_CREATURE and t.get("is_owner", false):
			owner_word = t.get("text", "")
	_portrait.text = _icons.of(owner_word)

	# Sentence (flavor): weapons red, creature with emoji, rest plain.
	for c in _sentence.get_children():
		c.queue_free()
	for token in tokens:
		var lbl := Label.new()
		var emoji := _icons.of(token.get("text", "")) if token.get("kind", "") == GameLogic.KIND_CREATURE else ""
		lbl.text = (emoji + " " + token.get("text", "")) if emoji != "" else token.get("text", "")
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.add_theme_color_override("font_color", WordStyle.color_for(token))
		_sentence.add_child(lbl)

	# Letter pool: a tile per letter with its point value (rare ones highlighted).
	# It's a damage guide — the letters stay; your words drain the HP bar above.
	for c in _letters_row.get_children():
		c.queue_free()
	for ch in _battle.letters():
		_letters_row.add_child(_letter_tile(ch, Lexicon.letter_weight(ch)))


## A single letter tile: big glyph + its point value; gold if rare.
func _letter_tile(ch: String, weight: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_TILE_RARE if weight >= 5 else COL_TILE
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	if weight >= 5:
		sb.set_border_width_all(2)
		sb.border_color = COL_SELECT
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(40, 46)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var glyph := Label.new()
	glyph.text = ch.to_upper()
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 22)
	glyph.add_theme_color_override("font_color",
		COL_SELECT if weight >= 5 else Color(0.9, 0.92, 0.98))
	var pts := Label.new()
	pts.text = str(weight)
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pts.add_theme_font_size_override("font_size", 11)
	pts.add_theme_color_override("font_color", COL_MUTED)
	box.add_child(glyph)
	box.add_child(pts)
	panel.add_child(box)
	return panel


# --- juice: bar drain, floating damage, attack lunge --------------------------

## Ease a progress bar toward `target` over BAR_DRAIN seconds; kill any in-flight
## tween on that bar first so hits don't stack into a jitter. Returns the new tween.
func _drain_bar(bar: ProgressBar, target: float, prev: Tween) -> Tween:
	if prev != null and prev.is_valid():
		prev.kill()
	var t := create_tween()
	t.tween_property(bar, "value", target, BAR_DRAIN).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	return t


## A "-N" that rises from `anchor` and fades. Bigger hits -> bigger font + longer
## rise, so damage is legible at a glance.
func _float_number(anchor: Control, amount: int, color: Color) -> void:
	if amount <= 0 or anchor == null:
		return
	var lbl := Label.new()
	lbl.text = "-%d" % amount
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", clampi(22 + amount * 2, 22, 60))
	lbl.add_theme_color_override("font_color", color)
	add_child(lbl)
	var r := anchor.get_global_rect()
	lbl.position = r.position + Vector2(r.size.x * 0.5 - 8, -8)
	var rise := 34.0 + amount * 1.5
	var t := create_tween().set_parallel(true)
	t.tween_property(lbl, "position:y", lbl.position.y - rise, 0.7).set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "modulate:a", 0.0, 0.7).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(lbl.queue_free)


## The enemy portrait surges forward (right) and swells, then springs back — it
## reads as the enemy lunging AT you, not being knocked down.
func _lunge_enemy() -> void:
	if _portrait == null:
		return
	var t := create_tween()
	t.tween_property(_portrait, "position", Vector2(16, 0), 0.10).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_portrait, "scale", Vector2(1.3, 1.3), 0.10).set_ease(Tween.EASE_OUT)
	t.chain().tween_property(_portrait, "position", Vector2.ZERO, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_portrait, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _log_msg(text: String) -> void:
	_log_lines.append(text)
	if _log_lines.size() > 8:
		_log_lines.pop_front()
	if _log:
		_log.text = "\n".join(_log_lines)


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

	# --- ENEMY zone: portrait + sentence + HP bar + letter pool ---
	var enemy_box := _zone(col)
	_enemy_head = _label("", 14)
	_enemy_head.add_theme_color_override("font_color", COL_MUTED)
	enemy_box.add_child(_enemy_head)

	var enemy_row := HBoxContainer.new()
	enemy_row.add_theme_constant_override("separation", 14)
	# The portrait lives in a fixed-size holder so its attack-lunge (a position
	# tween) doesn't get overridden by the container's layout pass.
	_portrait_holder = Control.new()
	_portrait_holder.custom_minimum_size = Vector2(72, 72)
	_portrait = _label("", 56)
	_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_portrait.pivot_offset = Vector2(36, 36)  # scale/lunge grows from the center
	_portrait_holder.add_child(_portrait)
	enemy_row.add_child(_portrait_holder)

	var enemy_text := VBoxContainer.new()
	enemy_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_text.add_theme_constant_override("separation", 8)
	_sentence = HFlowContainer.new()
	_sentence.add_theme_constant_override("h_separation", 6)
	_sentence.add_theme_constant_override("v_separation", 4)
	enemy_text.add_child(_sentence)

	# Enemy HP bar.
	var ehp_row := HBoxContainer.new()
	ehp_row.add_theme_constant_override("separation", 12)
	_enemy_hp_label = _label("", 16)
	ehp_row.add_child(_enemy_hp_label)
	_enemy_hpbar = ProgressBar.new()
	_enemy_hpbar.show_percentage = false
	_enemy_hpbar.custom_minimum_size = Vector2(0, 16)
	_enemy_hpbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy_hpbar.modulate = Color(0.9, 0.42, 0.42)
	ehp_row.add_child(_enemy_hpbar)
	enemy_text.add_child(ehp_row)

	_incoming = _label("", 16)
	_incoming.add_theme_color_override("font_color", Color(0.96, 0.62, 0.42))
	enemy_text.add_child(_incoming)
	enemy_row.add_child(enemy_text)
	enemy_box.add_child(enemy_row)

	# Letter pool tiles.
	_letters_row = HFlowContainer.new()
	_letters_row.add_theme_constant_override("h_separation", 6)
	_letters_row.add_theme_constant_override("v_separation", 6)
	enemy_box.add_child(_letters_row)

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
	_entry.text_submitted.connect(func(_t): _on_strike_pressed())
	_entry.text_changed.connect(func(_t): _update_selinfo())
	_controls.add_child(_entry)
	var go := Button.new()
	go.text = "Strike"
	go.pressed.connect(_on_strike_pressed)
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
