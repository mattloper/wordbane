## World prototype (NOT the game yet) — 3D.
##
## A step toward "a place made of words". Each character is its *sentence*,
## rendered by the normal 2D rich-text engine (so wrapping, spacing, per-word
## colour and a bold owner all come for free) into an off-screen SubViewport,
## then shown on a single Sprite3D billboard that always faces the camera. This
## is much easier to tune than hand-placing each word in 3D: change the font size
## or wrap width and the layout just works.
##
## Scenery (a "tree", a "hill") are word-objects too. A slow camera orbit gives
## depth / parallax. Purely visual — no combat yet.
##
## View it with:  godot --path game world.tscn
extends Node3D

const COLOR_POSITIVE := Color(0.50, 0.90, 0.55)
const COLOR_NEGATIVE := Color(0.97, 0.43, 0.43)
const COLOR_NEUTRAL := Color(0.88, 0.88, 0.93)
const COLOR_FIXED := Color(0.62, 0.62, 0.70)

const CARD_SIZE := Vector2i(440, 360)  # off-screen render resolution per character
const CARD_FONT := 40
const OWNER_FONT := 60
const PIXEL_SIZE := 0.011             # world units per texture pixel (overall scale)

var _cam: Camera3D
var _angle := 0.0


func _ready() -> void:
	_build_environment()
	_cam = Camera3D.new()
	_cam.fov = 58
	add_child(_cam)
	_cam.current = true
	_place_camera()
	_build_ground()
	_add_scenery()

	var bank := GameLogic.load_bank("res://data/word_bank.json")
	var chars: Array = bank.get("characters", [])
	var enemy := _find(chars, "Dragon")
	var player := _find(chars, "Knight")
	if not enemy.is_empty():
		_add_character(enemy.tokens, Vector3(-3.4, 1.9, 0.0))
	if not player.is_empty():
		_add_character(player.tokens, Vector3(3.4, 1.9, 0.0))

	_add_caption("a place made of words — 3D prototype")


func _process(delta: float) -> void:
	_angle += delta * 0.18  # gentle orbit for depth / parallax
	_place_camera()


func _place_camera() -> void:
	var r := 9.5
	_cam.position = Vector3(sin(_angle) * r, 3.1, cos(_angle) * r)
	_cam.look_at(Vector3(0, 1.7, 0), Vector3.UP)


# --- characters: a sentence on a billboard -----------------------------------

## Build the BBCode for a character's sentence: each word coloured by sentiment,
## the owner bold and larger, all in natural reading order.
func _sentence_bbcode(tokens: Array) -> String:
	var parts: Array = []
	for t in tokens:
		var token: Dictionary = t
		var hex := _sentiment_color(token).to_html(false)
		var word: String = token.get("text", "")
		var is_owner: bool = token.get("kind", "") == GameLogic.KIND_CREATURE \
			and bool(token.get("is_owner", false))
		if is_owner:
			parts.append("[font_size=%d][b][color=#%s]%s[/color][/b][/font_size]"
				% [OWNER_FONT, hex, word])
		else:
			parts.append("[color=#%s]%s[/color]" % [hex, word])
	return "[center]" + " ".join(parts) + "[/center]"


func _add_character(tokens: Array, pos: Vector3) -> void:
	# Off-screen viewport that renders the sentence as 2D rich text.
	var sv := SubViewport.new()
	sv.size = CARD_SIZE
	sv.transparent_bg = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)

	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.scroll_active = false
	rtl.size = CARD_SIZE
	rtl.add_theme_font_size_override("normal_font_size", CARD_FONT)
	rtl.text = _sentence_bbcode(tokens)
	sv.add_child(rtl)

	# A single billboard that always faces the camera, textured by the viewport.
	var card := Sprite3D.new()
	card.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	card.shaded = false
	card.texture = sv.get_texture()
	card.pixel_size = PIXEL_SIZE
	card.position = pos
	add_child(card)


# --- scenery / environment ---------------------------------------------------

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.18)
	we.environment = env
	add_child(we)


func _build_ground() -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.14, 0.18, 0.15)
	mi.material_override = mat
	add_child(mi)


func _word(text: String, font_size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.012
	l.modulate = color
	l.double_sided = true
	return l


func _add_scenery() -> void:
	var tree := _word("tree", 64, Color(0.46, 0.72, 0.46))
	tree.rotation_degrees = Vector3(0, 0, 90)  # on its side -> a vertical trunk
	tree.position = Vector3(-7.0, 1.6, -3.0)
	add_child(tree)

	var hill := _word("hill", 52, Color(0.34, 0.46, 0.36))
	hill.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hill.position = Vector3(7.0, 0.6, -4.0)
	add_child(hill)


func _add_caption(text: String) -> void:
	var layer := CanvasLayer.new()
	var l := Label.new()
	l.text = text
	l.position = Vector2(20, 16)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", COLOR_FIXED)
	layer.add_child(l)
	add_child(layer)


func _sentiment_color(token: Dictionary) -> Color:
	if token.get("kind", "") == GameLogic.KIND_FIXED:
		return COLOR_FIXED
	match token.get("sentiment", ""):
		GameLogic.POSITIVE: return COLOR_POSITIVE
		GameLogic.NEGATIVE: return COLOR_NEGATIVE
		_: return COLOR_NEUTRAL


func _find(chars: Array, name: String) -> Dictionary:
	for c in chars:
		if (c as Dictionary).get("name", "") == name:
			return c
	return {}
