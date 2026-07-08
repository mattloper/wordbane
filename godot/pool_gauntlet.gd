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

const BANK_PATH := "res://../data/word_bank.json"
const DICT_PATH := "res://../data/dictionary.json"
const MONSTER_PX := 220  # enemy portrait size (monster drawn with its weapons)

const COL_BG := UI.BG
const COL_PANEL := UI.PANEL
const COL_SELECT := UI.SELECT
const COL_MUTED := UI.MUTED
const COL_TILE := Color(0.22, 0.23, 0.3)       # game-specific (letter tiles)
const COL_TILE_RARE := Color(0.3, 0.26, 0.14)
const COL_HIT_ENEMY := Color(1.0, 0.95, 0.55)  # our damage floats up in gold
const COL_HIT_YOU := Color(1.0, 0.45, 0.45)    # their damage floats up in red

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
var _hints := 0  # hint charges from Focus (consumable, no refill)
var _letter_mult: Dictionary = {}  # letter -> score multiplier (from Double boons)
var _rng := Rng.new()              # one seeded stream drives all run randomness
var _log_lines: Array = []

var _art: Art
var _style := Settings.DEFAULT_STYLE   # current art style (from Settings; set in Options)
var _model := Settings.DEFAULT_MODEL   # current portrait model
var _next_enemy: Dictionary = {}  # look-ahead so we can prefetch the next chapter
var _portrait_gen := 0            # bumps per enemy; ignore late portrait callbacks

# UI nodes.
var _chapter_label: Label
var _score_label: Label
var _art_status: Label
var _dmg_label: Label
var _rules: PanelContainer
var _options: PanelContainer
var _gameover: Control      # full-screen GAME OVER overlay
var _gameover_stats: Label
var _enemy_head: Label
var _portrait: Label
var _portrait_holder: Control
var _portrait_content: Control
var _portrait_tex: TextureRect
var _ehp_tween: Tween
var _php_tween: Tween
var _sentence: HFlowContainer
var _enemy_hpbar: ProgressBar
var _enemy_hp_label: Label
var _letters_row: HFlowContainer
var _letter_tiles: Dictionary = {}  # letter -> its "in use" underline bar
var _atk_label: Label
var _atk_badge: PanelContainer
var _action_line: Label
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
	_gauntlet.setup(WordBank.load_bank(BANK_PATH))
	_battle = PoolBattle.new()
	_battle.lexicon = _lexicon
	_style = Settings.get_style()  # chosen in the Options screen
	_model = Settings.get_model()
	_build_ui()
	_rules = Help.make_rules_panel()
	add_child(_rules)
	_options = OptionsPanel.make(_on_art_settings_changed)  # redraw when style/model changes
	add_child(_options)
	_build_game_over()
	_art = Art.new()
	add_child(_art)
	_art.daemon_status_changed.connect(_on_art_status)
	_on_art_status(_art.is_online())
	_start_run()


# --- run / battle flow -------------------------------------------------------

func _start_run() -> void:
	_max_hp = Gauntlet.START_HP
	_hp = _max_hp
	_chapter = 1
	_score = 0
	_over = false
	_choosing = false
	_hints = 0
	_letter_mult = {}
	_battle.letter_mult = _letter_mult
	_rng = Rng.new(int(Time.get_unix_time_from_system() * 1000.0) & 0xffffffff)
	_gauntlet.rng = _rng
	_log_lines = []
	_gameover.visible = false
	_battle.used = []  # no-reuse spans the whole run
	_next_enemy = {}
	_start_enemy()
	_prefetch_boons()  # warm reward icons in the background for chapter-clear
	_log_msg("A foe blocks your path. Spell from its letters to drain its HP!")


func _start_enemy() -> void:
	_choosing = false
	# Use the enemy we already generated (and prefetched art for) last chapter.
	var enemy: Dictionary = _next_enemy if not _next_enemy.is_empty() else _gauntlet.generate(_chapter)
	_next_enemy = {}
	_battle.begin(enemy, _hp, _max_hp)
	_entry.text = ""
	# Snap both bars to their starting values so a fresh enemy doesn't "fill up".
	_enemy_hpbar.max_value = _battle.enemy_max_hp()
	_enemy_hpbar.value = _battle.enemy_max_hp()
	_hpbar.max_value = _max_hp
	_hpbar.value = _hp
	_show_placeholder()  # emoji until this enemy's art arrives
	_render()
	_request_portrait()
	_prefetch_next()
	# Warm this creature's tombstone now, so it's ready the instant you defeat it.
	_art.prefetch("tombstone", _owner_of(_battle.enemy), _style, _model)
	_entry.grab_focus()


## Show the emoji placeholder and bump the generation token, so a late portrait
## callback for a previous enemy is ignored.
func _show_placeholder() -> void:
	_portrait_gen += 1
	_portrait_tex.visible = false
	_portrait.visible = true


## Request the enemy portrait — the monster drawn WITH its weapons, from a noun
## phrase (no adjectives, so it caches per creature+weapons).
func _request_portrait() -> void:
	_show_art("portrait", _portrait_subject(_battle.enemy))


## Fetch a piece of art and show it in the portrait slot once it arrives — but only
## if it's still the current enemy (the generation token guards against a late
## callback landing on the next one).
func _show_art(kind: String, subject: String) -> void:
	var gen := _portrait_gen
	_art.request(kind, subject, _style, _model, func(tex):
		if gen == _portrait_gen:
			_portrait_tex.texture = tex
			_portrait_tex.visible = true
			_portrait.visible = false)


## The noun phrase an enemy's portrait is drawn from: creature + weapon nouns, no
## adjectives — e.g. "a dragon monster wielding a axe and a hex".
func _portrait_subject(enemy: Dictionary) -> String:
	var phrase := "a %s monster" % _owner_of(enemy)
	var weapons: Array = _weapons_of(enemy)
	if not weapons.is_empty():
		var held: Array = weapons.map(func(w): return "a " + w)
		phrase += " wielding " + " and ".join(held)
	return phrase


## On victory: swap the monster for the defeated creature's tombstone (prefetched,
## so it's usually instant).
func _show_tombstone(creature: String) -> void:
	_show_art("tombstone", creature)


## Generate the next chapter's enemy now and warm its monster + weapon art in the
## background, so it's instant when we get there. That same enemy is reused on advance.
func _prefetch_next() -> void:
	_next_enemy = _gauntlet.generate(_chapter + 1)
	_art.prefetch("portrait", _portrait_subject(_next_enemy), _style, _model)


## The weapon nouns of an enemy (its item tokens), for prompts/prefetch.
func _weapons_of(enemy: Dictionary) -> Array:
	var out: Array = []
	for t in enemy.get("tokens", []):
		if t.get("kind", "") == WordBank.KIND_ITEM:
			out.append(t.get("text", ""))
	return out


func _owner_of(enemy: Dictionary) -> String:
	for t in enemy.get("tokens", []):
		if t.get("kind", "") == WordBank.KIND_CREATURE and t.get("is_owner", false):
			return t.get("text", "")
	return ""


func _on_art_status(online: bool) -> void:
	_art_status.text = "● art: online" if online else "○ art: offline"
	_art_status.add_theme_color_override("font_color",
		Color(0.45, 0.78, 0.5) if online else Color(0.78, 0.45, 0.45))



func _on_strike_pressed() -> void:
	if _over or _choosing:
		return
	var res := _battle.try_move(_entry.text)
	if not res.get("ok", false):
		_action_line.text = "Can't: " + str(res.get("reason", "invalid"))
		return
	_entry.text = ""
	var dealt: int = int(res.dealt)  # already includes Double-boon letter multipliers
	var gain: int = dealt * Gauntlet.SCORE_PER_DAMAGE
	_score += gain
	var uses := ("  [uses %s]" % ", ".join(Lexicon.upper_letters(res.covered))) if not res.covered.is_empty() else ""
	_log_msg("You: %s hits for %d%s  +%d" % [res.word, dealt, uses, gain])
	Juice.float_number(self,_enemy_hpbar, dealt, COL_HIT_ENEMY)  # our hit floats over the enemy
	if int(res.damage) > 0:
		_log_msg("   enemy strikes for %d" % res.damage)

	if res.get("won", false):
		var bonus := _chapter * Gauntlet.CHAPTER_BONUS
		_score += bonus
		_hp = _battle.player_hp   # no free heal — recover via boons
		_log_msg("Chapter %d cleared!  (+%d score)  Choose a reward." % [_chapter, bonus])
		_show_tombstone(_owner_of(_battle.enemy))  # R.I.P. the defeated monster
		_offer_boons()
		return
	if int(res.damage) > 0:  # the enemy struck back
		Juice.float_number(self,_hpbar, int(res.damage), COL_HIT_YOU)
		Juice.lunge(self, _portrait_content)
	_hp = _battle.player_hp
	if res.get("lost", false):
		_lose()
	_render()


func _on_hint_pressed() -> void:
	if _over or _choosing or _hints <= 0:
		return
	var w := _lexicon.best_word("".join(_battle.letters()), _battle.used + _battle.weapons())
	if w == "":
		_action_line.text = "Hint: no fresh word found."
		return
	_hints -= 1  # a hint charge is spent whether or not you use the word
	# Update just the hint button; a full _render() would clobber this action line.
	_hint_btn.text = "Hint (%d)" % _hints
	_hint_btn.visible = _hints > 0
	_action_line.text = "Hint: try '%s'   (%d left)" % [w, _hints]


func _lose() -> void:
	_over = true
	var record := Settings.record_run(_chapter, _score)
	_log_msg("DEFEATED in chapter %d. Final score: %d." % [_chapter, _score])
	if record:
		_log_msg("New best!")
	# Big, unmissable end-of-run cue.
	_gameover_stats.text = "Reached chapter %d   ·   Score %d%s" % [
		_chapter, _score, "\n★ New best! ★" if record else ""]
	_gameover.visible = true
	_gameover.modulate.a = 0.0
	create_tween().tween_property(_gameover, "modulate:a", 1.0, 0.4)


## The action-line text: final/boon prompts, else a live damage preview of what
## you've typed against the enemy's letters (teaches "rare letters hit harder").
func _update_action_line() -> void:
	if _over:
		_action_line.text = "Final score: %d  ·  reached chapter %d" % [_score, _chapter]
		_set_dmg_preview(-1)
		return
	if _choosing:
		_action_line.text = "Choose a boon:"
		_set_dmg_preview(-1)
		_highlight_tiles([])
		return
	var typed := _entry.text.strip_edges()
	if typed == "":
		_action_line.text = ""
		_set_dmg_preview(0)
		_highlight_tiles([])
		return
	var r := _battle.check(typed)
	if r.get("ok", false):
		# Damage goes in its own big readout; the line names the letters, and the used
		# tiles are underlined below.
		var covered := Lexicon.covered_letters(typed, "".join(_battle.letters()))
		_set_dmg_preview(int(r.dealt))
		_action_line.text = "'%s' uses %s" % [typed.to_lower(), ", ".join(Lexicon.upper_letters(covered))]
		_highlight_tiles(covered)
	else:
		_set_dmg_preview(0)
		_action_line.text = str(r.get("reason", ""))
		_highlight_tiles([])


## The big projected-damage readout beside the entry (-1 = blank, else the number).
func _set_dmg_preview(amount: int) -> void:
	_dmg_label.text = "" if amount < 0 else str(amount)


## Underline the letter tiles the currently-typed word covers.
func _highlight_tiles(covered: Array) -> void:
	var used := {}
	for ch in covered:
		used[ch] = true
	for ch in _letter_tiles:
		_letter_tiles[ch].visible = used.has(ch)


# --- boons (between-chapter progression) -------------------------------------

func _offer_boons() -> void:
	_choosing = true
	for c in _boon_row.get_children():
		c.queue_free()
	for boon in Boons.offer(_rng):
		var btn := Button.new()
		btn.text = "%s\n%s" % [boon.label, boon.desc]
		btn.custom_minimum_size = Vector2(150, 150)
		# Icon above the text; fills the button once the daemon returns it.
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.expand_icon = true
		btn.add_theme_constant_override("icon_max_width", 96)
		btn.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # no aliasing at 96px
		_art.request("boon", boon.id, _style, _model, func(tex): btn.icon = tex)
		btn.pressed.connect(_take_boon.bind(boon))
		_boon_row.add_child(btn)
	_render()


## Warm all boon icons for the current style/model, so they're ready at chapter end.
func _prefetch_boons() -> void:
	for id in Boons.ids():
		_art.prefetch("boon", id, _style, _model)


func _take_boon(boon: Dictionary) -> void:
	var s := {"hp": _hp, "max_hp": _max_hp, "hints": _hints, "letter_mult": _letter_mult}
	Boons.apply(boon, s)
	_hp = int(s.hp)
	_max_hp = int(s.max_hp)
	_hints = int(s.hints)
	_letter_mult = s.letter_mult
	_battle.letter_mult = _letter_mult  # damage + score use the multipliers
	_log_msg("Boon: %s" % boon.label)
	_chapter += 1
	_start_enemy()


# --- rendering ---------------------------------------------------------------

func _render() -> void:
	_chapter_label.text = "CHAPTER %d" % _chapter
	_score_label.text = "SCORE %d" % _score
	_enemy_head.text = "ENEMY   ·   spell words from its letters (reuse freely; not its own weapon words) to drain its HP"

	_render_enemy()

	_enemy_hpbar.max_value = _battle.enemy_max_hp()
	_ehp_tween = Juice.drain_bar(self,_enemy_hpbar, _battle.enemy_hp(), _ehp_tween)
	_enemy_hp_label.text = "HP  %d / %d" % [_battle.enemy_hp(), _battle.enemy_max_hp()]

	# Attack badge only while fighting (a defeated monster becomes a grave).
	_atk_badge.visible = not _over and not _choosing
	if _atk_badge.visible:
		_atk_label.text = "⚔ %d" % _battle.incoming_damage()

	_update_action_line()

	_controls.visible = not _choosing and not _over
	_boon_row.visible = _choosing
	_hint_btn.visible = _hints > 0
	_hint_btn.text = "Hint (%d)" % _hints

	_hpbar.max_value = _max_hp
	_php_tween = Juice.drain_bar(self,_hpbar, _hp, _php_tween)
	_hpbar.modulate = Color(0.4, 0.78, 0.45) if _hp > _max_hp / 3 else Color(0.92, 0.36, 0.36)
	_hp_label.text = "HP  %d / %d" % [_hp, _max_hp]
	_spent_label.text = "words spent: %d  (no reuse)" % _battle.used.size()
	_log.text = "\n".join(_log_lines)


func _render_enemy() -> void:
	# Portrait = the owner creature's emoji (big).
	var tokens: Array = _battle.enemy.tokens
	var owner_word := ""
	for t in tokens:
		if t.get("kind", "") == WordBank.KIND_CREATURE and t.get("is_owner", false):
			owner_word = t.get("text", "")
	_portrait.text = _icons.of(owner_word)

	# Sentence: the WEAPON nouns — whose letters form the pool you spell from — are
	# red; every other word (creature, adjectives, scenery) is muted. So "red" means
	# exactly "this word's letters are available."
	for c in _sentence.get_children():
		c.queue_free()
	for token in tokens:
		var is_weapon: bool = token.get("kind", "") == WordBank.KIND_ITEM
		var lbl := _label(token.get("text", ""), 20)
		lbl.add_theme_color_override("font_color", UI.DANGER if is_weapon else COL_MUTED)
		_sentence.add_child(lbl)

	# Letter pool: a tile per letter with its point value (rare ones highlighted).
	# It's a damage guide — the letters stay; your words drain the HP bar above.
	for c in _letters_row.get_children():
		c.queue_free()
	_letter_tiles = {}
	for ch in _battle.letters():
		_letters_row.add_child(_letter_tile(ch, Lexicon.letter_weight(ch), int(_letter_mult.get(ch, 1))))


## A single letter tile (glyph + effective point value) over a hidden underline bar
## that lights up when the typed word covers this letter (stored in `_letter_tiles`).
## `mult` is the letter's Double-boon multiplier: its value shows as base x mult, and
## a boosted (mult > 1) or rare tile is highlighted gold.
func _letter_tile(ch: String, base: int, mult: int) -> Control:
	var value := base * mult
	var boosted: bool = mult > 1
	var hot: bool = boosted or base >= 5
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_TILE_RARE if hot else COL_TILE
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	if hot:
		sb.set_border_width_all(2)
		sb.border_color = COL_SELECT
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(40, 46)
	if boosted:
		panel.tooltip_text = "%s is worth %dx (Double boon)" % [ch.to_upper(), mult]

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var glyph := Label.new()
	glyph.text = ch.to_upper()
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 22)
	glyph.add_theme_color_override("font_color",
		COL_SELECT if hot else Color(0.9, 0.92, 0.98))
	var pts := Label.new()
	pts.text = ("%d×" % value) if boosted else str(value)
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pts.add_theme_font_size_override("font_size", 11)
	pts.add_theme_color_override("font_color", COL_SELECT if boosted else COL_MUTED)
	box.add_child(glyph)
	box.add_child(pts)
	panel.add_child(box)

	# Tile above a thin "in use" underline bar (hidden until the word covers it).
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.add_child(panel)
	var bar := ColorRect.new()
	bar.color = COL_HIT_ENEMY
	bar.custom_minimum_size = Vector2(0, 3)
	bar.visible = false
	col.add_child(bar)
	_letter_tiles[ch] = bar
	return col


func _log_msg(text: String) -> void:
	_log_lines.append(text)
	if _log_lines.size() > 5:
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

	_build_header(col)
	_build_enemy_zone(col)
	_build_action_zone(col)
	_build_you_zone(col)
	_build_footer(col)


## Title + art-daemon status (left) · CHAPTER (center) · SCORE (right).
func _build_header(col: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 0)
	var title := _label("Wordplay", 16)
	title.add_theme_color_override("font_color", COL_MUTED)
	left.add_child(title)
	_art_status = _label("", 11)
	left.add_child(_art_status)
	header.add_child(left)
	_chapter_label = _label("CHAPTER 1", 30)
	_chapter_label.add_theme_color_override("font_color", COL_SELECT)
	header.add_child(_chapter_label)
	# Right: SCORE + a gear menu (how-to-play / options / main menu).
	var right := HBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", 10)
	_score_label = _label("SCORE 0", 18)
	right.add_child(_score_label)
	var gear := MenuButton.new()
	gear.text = "☰"
	gear.add_theme_font_size_override("font_size", 22)
	gear.flat = false
	var pm := gear.get_popup()
	pm.add_item("How to play", 0)
	pm.add_item("Options", 1)
	pm.add_item("Main Menu", 2)
	pm.id_pressed.connect(_on_menu_id)
	right.add_child(gear)
	header.add_child(right)
	col.add_child(header)


func _on_menu_id(id: int) -> void:
	match id:
		0: _rules.visible = true
		1: _options.visible = true
		2: get_tree().change_scene_to_file("res://title.tscn")


## Style/model was changed in the Options overlay mid-run: re-read and redraw the
## current monster + weapons, and re-warm the next chapter + boon icons in the new look.
func _on_art_settings_changed() -> void:
	_style = Settings.get_style()
	_model = Settings.get_model()
	_show_placeholder()
	_request_portrait()
	if not _next_enemy.is_empty():
		_art.prefetch("portrait", _portrait_subject(_next_enemy), _style, _model)
	_prefetch_boons()


## Portrait (emoji placeholder + generated texture) + sentence + HP bar + letter tiles.
func _build_enemy_zone(col: VBoxContainer) -> void:
	var enemy_box := _panel(col)
	_enemy_head = _label("", 14)
	_enemy_head.add_theme_color_override("font_color", COL_MUTED)
	enemy_box.add_child(_enemy_head)

	var enemy_row := HBoxContainer.new()
	enemy_row.add_theme_constant_override("separation", 14)
	# The portrait lives in a fixed-size holder so its attack-lunge (a position/scale
	# tween on the inner content) doesn't get overridden by the container's layout.
	_portrait_holder = Control.new()
	_portrait_holder.custom_minimum_size = Vector2(MONSTER_PX, MONSTER_PX)
	_portrait_content = Control.new()
	_portrait_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_content.pivot_offset = Vector2(MONSTER_PX / 2, MONSTER_PX / 2)  # scale/lunge from center
	_portrait_holder.add_child(_portrait_content)
	_portrait = _label("", 96)  # emoji placeholder / fallback if the daemon is down
	_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_portrait_content.add_child(_portrait)
	_portrait_tex = TextureRect.new()
	_portrait_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Trilinear (mipmapped) sampling, so downscaling a 1024px portrait doesn't alias.
	_portrait_tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_portrait_tex.visible = false
	_portrait_content.add_child(_portrait_tex)
	# Attack badge (⚔ N) overlaid on the portrait's top-left corner.
	_atk_badge = PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.55, 0.13, 0.14, 0.9)
	bsb.set_corner_radius_all(7)
	bsb.content_margin_left = 8
	bsb.content_margin_right = 8
	bsb.content_margin_top = 2
	bsb.content_margin_bottom = 2
	_atk_badge.add_theme_stylebox_override("panel", bsb)
	_atk_badge.position = Vector2(4, 4)
	_atk_badge.tooltip_text = "It hits you this much every turn until it's dead."
	_atk_label = _label("", 22)
	_atk_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.88))
	_atk_badge.add_child(_atk_label)
	_portrait_holder.add_child(_atk_badge)  # on top of the portrait
	enemy_row.add_child(_portrait_holder)

	var enemy_text := VBoxContainer.new()
	enemy_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_text.add_theme_constant_override("separation", 8)
	_sentence = HFlowContainer.new()
	_sentence.add_theme_constant_override("h_separation", 6)
	_sentence.add_theme_constant_override("v_separation", 4)
	enemy_text.add_child(_sentence)

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
	enemy_row.add_child(enemy_text)
	enemy_box.add_child(enemy_row)

	_letters_row = HFlowContainer.new()
	_letters_row.add_theme_constant_override("h_separation", 6)
	_letters_row.add_theme_constant_override("v_separation", 6)
	enemy_box.add_child(_letters_row)


## Action line + damage readout / word entry / buttons, then the boon row.
func _build_action_zone(col: VBoxContainer) -> void:
	_action_line = _label("", 16)
	_action_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_action_line)

	_controls = HBoxContainer.new()
	_controls.alignment = BoxContainer.ALIGNMENT_CENTER
	_controls.add_theme_constant_override("separation", 8)
	# Prominent projected-damage readout, in its own spot (big + gold).
	var dmg_box := VBoxContainer.new()
	dmg_box.custom_minimum_size = Vector2(64, 0)
	dmg_box.alignment = BoxContainer.ALIGNMENT_CENTER
	dmg_box.add_theme_constant_override("separation", 0)
	_dmg_label = _label("", 34)
	_dmg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dmg_label.add_theme_color_override("font_color", COL_SELECT)
	dmg_box.add_child(_dmg_label)
	var dmg_cap := _label("DMG", 10)
	dmg_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dmg_cap.add_theme_color_override("font_color", COL_MUTED)
	dmg_box.add_child(dmg_cap)
	_controls.add_child(dmg_box)
	_entry = LineEdit.new()
	_entry.placeholder_text = "Try any word…"
	_entry.custom_minimum_size = Vector2(300, 0)
	_entry.keep_editing_on_text_submit = true  # Godot 4.4+: stay focused after Enter
	_entry.text_submitted.connect(func(_t): _on_strike_pressed())
	_entry.text_changed.connect(func(_t): _update_action_line())
	_controls.add_child(_entry)
	_controls.add_child(_action_btn("Strike", _on_strike_pressed, true))
	_hint_btn = _action_btn("Hint", _on_hint_pressed, false)
	_controls.add_child(_hint_btn)
	col.add_child(_controls)

	_boon_row = HBoxContainer.new()
	_boon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_boon_row.add_theme_constant_override("separation", 10)
	col.add_child(_boon_row)


## Your HP bar + words-spent count.
func _build_you_zone(col: VBoxContainer) -> void:
	var you_box := _panel(col)
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


## Compact log + a spacer that pins New Run to the bottom.
func _build_footer(col: VBoxContainer) -> void:
	var log_box := _panel(col)
	_log = _label("", 13)
	_log.custom_minimum_size = Vector2(0, 86)
	_log.add_theme_color_override("font_color", Color(0.8, 0.82, 0.88))
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	log_box.add_child(_log)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	var restart := Button.new()
	restart.text = "New Run"
	restart.pressed.connect(_start_run)
	var center := CenterContainer.new()
	center.add_child(restart)
	col.add_child(center)


## A full-screen GAME OVER overlay (dim + centered card), hidden until you die.
func _build_game_over() -> void:
	_gameover = Control.new()
	_gameover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gameover.visible = false
	add_child(_gameover)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gameover.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gameover.add_child(center)

	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(28)
	sb.set_border_width_all(3)
	sb.border_color = UI.DANGER
	card.add_theme_stylebox_override("panel", sb)
	center.add_child(card)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(420, 0)
	card.add_child(box)

	var title := _label("GAME OVER", 52)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", UI.DANGER)
	box.add_child(title)

	_gameover_stats = _label("", 18)
	_gameover_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gameover_stats.add_theme_color_override("font_color", COL_SELECT)
	box.add_child(_gameover_stats)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	buttons.add_child(_action_btn("New Run", _start_run, true))
	buttons.add_child(_action_btn("Main Menu",
		func(): get_tree().change_scene_to_file("res://title.tscn"), false))
	box.add_child(buttons)


## Add a rounded padded panel to `parent` and return its inner VBox to fill.
func _panel(parent: Control) -> VBoxContainer:
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


## A clearly-clickable button. `accent` = the primary action (gold fill); otherwise a
## bordered secondary button. Both read as buttons at rest, not just on hover.
func _action_btn(text: String, cb: Callable, accent: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(cb)
	var fill := COL_SELECT if accent else Color(0.24, 0.25, 0.32)
	var text_col := Color(0.12, 0.12, 0.15) if accent else UI.TEXT
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill.lightened(0.12) if state == "hover" else fill
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 7
		sb.content_margin_bottom = 7
		if not accent:
			sb.set_border_width_all(1)
			sb.border_color = COL_MUTED
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", text_col)
	b.add_theme_color_override("font_hover_color", text_col)
	b.add_theme_color_override("font_pressed_color", text_col)
	return b
