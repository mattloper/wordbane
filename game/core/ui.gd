## Shared UI palette + tiny widget builders, so every screen uses the same colours
## and doesn't re-declare the same helpers.
class_name UI
extends RefCounted

# Palette (single source of truth for the game's colours).
const BG := Color(0.11, 0.12, 0.17)
const PANEL := Color(0.16, 0.17, 0.23)
const SELECT := Color(1.0, 0.86, 0.3)
const MUTED := Color(0.55, 0.56, 0.64)
const TEXT := Color(0.85, 0.87, 0.93)


## A Label with a font size and colour, word-wrapping on.
static func label(text: String, size: int, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## A hidden, centered modal panel (bg + rounded gold border) for overlays like the
## rules card and the options menu. Add it to a scene and toggle `.visible`.
static func overlay_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_CENTER)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(22)
	sb.set_border_width_all(2)
	sb.border_color = SELECT
	panel.add_theme_stylebox_override("panel", sb)
	return panel
