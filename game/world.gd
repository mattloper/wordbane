## World prototype (NOT the game yet) — 3D, with clickable words.
##
## Each character is its *sentence*, rendered by the 2D rich-text engine into an
## off-screen SubViewport and shown on a single quad in 3D (so layout/wrapping/
## colour are free). Editable words are wrapped in [url] meta tags, and the quad
## has an Area3D collider: a 3D click is mapped to the viewport's pixel and pushed
## in as a synthetic mouse click, so RichTextLabel emits `meta_clicked`. Clicking
## a word randomizes it (via GameLogic.reroll_token) to prove the loop end to end.
##
## Prototype simplification: the camera is static and each card is oriented once
## to face it (no billboard), so the collider exactly matches what's drawn. Re-
## enabling the orbiting camera will need the collider to track the billboard.
##
## View it with:  godot --path game world.tscn  (then click the coloured words)
extends Node3D

const CARD_SIZE := Vector2i(440, 360)  # off-screen render resolution per character
const CARD_FONT := 40
const OWNER_FONT := 60
const PIXEL_SIZE := 0.011             # world units per texture pixel (overall scale)

var _rng := RandomNumberGenerator.new()
var _pools: Dictionary = {}
var _cam: Camera3D
var _hint: Label


func _ready() -> void:
	_rng.randomize()
	get_viewport().physics_object_picking = true  # needed for Area3D mouse picking

	_build_environment()
	_cam = Camera3D.new()
	_cam.fov = 58
	_cam.position = Vector3(0, 1.9, 12)
	add_child(_cam)
	_cam.current = true
	_cam.look_at(Vector3(0, 1.9, 0), Vector3.UP)
	_build_ground()
	_add_scenery()

	var bank := GameLogic.load_bank("res://data/word_bank.json")
	_pools = bank.get("pools", {})
	var chars: Array = bank.get("characters", [])
	var enemy := _find(chars, "Dragon")
	var player := _find(chars, "Knight")
	if not enemy.is_empty():
		_add_character(enemy.tokens, Vector3(-3.4, 1.9, 0.0))
	if not player.is_empty():
		_add_character(player.tokens, Vector3(3.4, 1.9, 0.0))

	_add_overlay()


# --- characters: a clickable sentence on a quad ------------------------------

## BBCode for a sentence: each word coloured by sentiment, owner bold/large, and
## every editable word wrapped in a [url=<token index>] so it can be clicked.
func _sentence_bbcode(tokens: Array) -> String:
	var parts: Array = []
	for i in range(tokens.size()):
		var token: Dictionary = tokens[i]
		var kind: String = token.get("kind", "")
		var hex := WordStyle.color_for(token).to_html(false)
		var word: String = token.get("text", "")
		var styled: String
		if kind == GameLogic.KIND_CREATURE and bool(token.get("is_owner", false)):
			styled = "[font_size=%d][b][color=#%s]%s[/color][/b][/font_size]" % [OWNER_FONT, hex, word]
		else:
			styled = "[color=#%s]%s[/color]" % [hex, word]
		if kind in GameLogic.EDITABLE_KINDS:
			styled = "[url=%d]%s[/url]" % [i, styled]
		parts.append(styled)
	return "[center]" + " ".join(parts) + "[/center]"


func _add_character(tokens: Array, pos: Vector3) -> void:
	# Off-screen viewport renders the sentence as 2D rich text.
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
	rtl.meta_clicked.connect(_on_word_clicked.bind(rtl, tokens))
	sv.add_child(rtl)

	# A quad facing the (static) camera, textured by the viewport, plus a matching
	# collider so we can pick words by raycast.
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	root.look_at(2.0 * pos - _cam.global_position, Vector3.UP)  # +Z toward camera

	var card := Sprite3D.new()
	card.shaded = false
	card.texture = sv.get_texture()
	card.pixel_size = PIXEL_SIZE
	root.add_child(card)

	var w := CARD_SIZE.x * PIXEL_SIZE
	var h := CARD_SIZE.y * PIXEL_SIZE
	var area := Area3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, h, 0.1)
	cs.shape = box
	area.add_child(cs)
	area.input_event.connect(_on_card_input.bind(root, sv, Vector2(w, h)))
	root.add_child(area)


## A 3D click on a card -> the viewport pixel under it -> a synthetic mouse click.
func _on_card_input(_camera: Node, event: InputEvent, event_position: Vector3,
		_normal: Vector3, _shape_idx: int, root: Node3D, sv: SubViewport, size: Vector2) -> void:
	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var local := root.to_local(event_position)
	var uv := Vector2(local.x / size.x + 0.5, 0.5 - local.y / size.y)
	var pixel := Vector2(uv.x * CARD_SIZE.x, uv.y * CARD_SIZE.y)
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.position = pixel
		mb.pressed = pressed
		sv.push_input(mb)


## Fired when a [url] word is clicked: randomize that word and redraw the card.
func _on_word_clicked(meta: Variant, rtl: RichTextLabel, tokens: Array) -> void:
	var idx := int(str(meta))
	if idx < 0 or idx >= tokens.size():
		return
	var before: String = tokens[idx].get("text", "")
	GameLogic.reroll_token(tokens[idx], _pools, _rng)
	rtl.text = _sentence_bbcode(tokens)
	_set_hint("clicked '%s' → '%s'" % [before, tokens[idx].get("text", "")])


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


func _add_overlay() -> void:
	var layer := CanvasLayer.new()
	var caption := Label.new()
	caption.text = "a place made of words — click a coloured word to randomize it"
	caption.position = Vector2(20, 16)
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_color", WordStyle.FIXED)
	layer.add_child(caption)

	_hint = Label.new()
	_hint.position = Vector2(20, 40)
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", WordStyle.NEUTRAL)
	layer.add_child(_hint)
	add_child(layer)


func _set_hint(text: String) -> void:
	if _hint:
		_hint.text = text


func _find(chars: Array, name: String) -> Dictionary:
	for c in chars:
		if (c as Dictionary).get("name", "") == name:
			return c
	return {}
