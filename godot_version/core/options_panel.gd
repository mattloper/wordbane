## Shared Options overlay (art style + portrait model), shown on top of whatever
## screen is active — so opening it never tears down an in-progress run. Writes
## through Settings; `on_changed` (optional) fires after a change so a live game can
## redraw the current portrait.
class_name OptionsPanel
extends RefCounted


static func make(on_changed := Callable()) -> PanelContainer:
	var panel := UI.overlay_panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(440, 0)
	panel.add_child(box)
	box.add_child(UI.label("Options", 28, UI.SELECT))
	box.add_child(UI.label("Monster art is generated locally by Draw Things and cached.", 13, UI.MUTED))

	var style_btn := _dropdown(box, "Art style",
		Settings.STYLES.map(func(s): return s.label), _index(Settings.STYLES, "key", Settings.get_style()))
	style_btn.item_selected.connect(func(i):
		Settings.set_style(Settings.STYLES[i].key)
		if on_changed.is_valid(): on_changed.call())

	var model_btn := _dropdown(box, "Portrait model",
		Settings.MODELS.map(func(m): return m.label), _index(Settings.MODELS, "file", Settings.get_model()))
	model_btn.item_selected.connect(func(i):
		Settings.set_model(Settings.MODELS[i].file)
		if on_changed.is_valid(): on_changed.call())

	box.add_child(UI.label("Dev looks best but is very slow; Klein 9b is the balanced pick.", 12, UI.MUTED))

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 38)
	close.pressed.connect(panel.hide)
	box.add_child(close)
	return panel


static func _index(list: Array, field: String, value) -> int:
	for i in range(list.size()):
		if list[i][field] == value:
			return i
	return 0


static func _dropdown(box: VBoxContainer, caption: String, labels: Array, selected: int) -> OptionButton:
	box.add_child(UI.label(caption, 15))
	var btn := OptionButton.new()
	for l in labels:
		btn.add_item(l)
	btn.select(selected)
	btn.custom_minimum_size = Vector2(0, 36)
	box.add_child(btn)
	return btn
