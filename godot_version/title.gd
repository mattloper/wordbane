## Start screen: typography-only title card with the main menu. No art generation,
## so it's instant and works whether or not the art daemon is up.
extends Control

var _rules: PanelContainer    # "How to play" overlay, toggled
var _options: PanelContainer  # Options overlay, toggled


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)

	var title := UI.label("WORDPLAY", 64, UI.SELECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var tag := UI.label("a letter-pool word battler", 18, UI.MUTED)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)

	var best := Settings.get_best()
	var best_text := "Best:  chapter %d  ·  score %d" % [best.depth, best.score] if best.score > 0 else "No runs yet — go set a record."
	var best_label := UI.label(best_text, 15, UI.MUTED)
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(best_label)

	col.add_child(_spacer(14))
	col.add_child(_menu_button("Play", _on_play))
	col.add_child(_menu_button("How to play", _on_how))
	col.add_child(_menu_button("Options", _on_options))
	col.add_child(_menu_button("Quit", _on_quit))

	_rules = Help.make_rules_panel()
	add_child(_rules)
	_options = OptionsPanel.make()
	add_child(_options)


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b


# --- actions -----------------------------------------------------------------

func _on_play() -> void:
	get_tree().change_scene_to_file("res://pool_gauntlet.tscn")

func _on_options() -> void:
	_options.visible = true

func _on_quit() -> void:
	get_tree().quit()

func _on_how() -> void:
	_rules.visible = not _rules.visible


# --- helpers -----------------------------------------------------------------

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
