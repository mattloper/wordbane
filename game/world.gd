## World prototype (NOT the game yet) — 3D.
##
## A step toward "a place made of words": a real 3D scene with a slowly orbiting
## camera. Each character is its *sentence*, laid out in reading order (left to
## right, top to bottom) but with rows that widen then narrow, so the pile of
## words takes on a rough body silhouette. The owner word is bold but stays in
## its sentence position — it is NOT pulled out to the top. Words are billboarded
## Label3Ds so they always face the camera; scenery (a "tree") is a word too.
##
## View it with:  godot --path game world.tscn
extends Node3D

const COLOR_POSITIVE := Color(0.50, 0.90, 0.55)
const COLOR_NEGATIVE := Color(0.97, 0.43, 0.43)
const COLOR_NEUTRAL := Color(0.88, 0.88, 0.93)
const COLOR_FIXED := Color(0.58, 0.58, 0.66)

# Words per row, top to bottom — a narrow-wide-narrow profile reads as a body
# (head, shoulders/torso, legs) while preserving left-to-right reading order.
const BODY_PROFILE := [1, 2, 3, 3, 2, 2, 1]
const TOP_Y := 3.7
const ROW_H := 0.56
const COL_W := 1.15

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
		_add_figure(enemy.tokens, Vector3(-3.3, 0.0, 0.0))
	if not player.is_empty():
		_add_figure(player.tokens, Vector3(3.3, 0.0, 0.0))

	_add_caption("a place made of words — 3D prototype")


func _process(delta: float) -> void:
	# Gentle orbit for depth / parallax.
	_angle += delta * 0.18
	_place_camera()


func _place_camera() -> void:
	var r := 9.5
	_cam.position = Vector3(sin(_angle) * r, 3.1, cos(_angle) * r)
	_cam.look_at(Vector3(0, 1.7, 0), Vector3.UP)


# --- scene building ----------------------------------------------------------

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


func _word(text: String, font_size: int, color: Color, bold: bool) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.012
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.double_sided = true
	if bold:
		l.outline_size = 14
		l.outline_modulate = Color(0, 0, 0, 0.85)
	return l


func _sentiment_color(token: Dictionary) -> Color:
	if token.get("kind", "") == GameLogic.KIND_FIXED:
		return COLOR_FIXED
	match token.get("sentiment", ""):
		GameLogic.POSITIVE: return COLOR_POSITIVE
		GameLogic.NEGATIVE: return COLOR_NEGATIVE
		_: return COLOR_NEUTRAL


## Lay a character's sentence into a body-shaped pile, in reading order.
func _add_figure(tokens: Array, base: Vector3) -> void:
	var fig := Node3D.new()
	fig.position = base
	add_child(fig)

	var idx := 0
	var row := 0
	while idx < tokens.size():
		var count: int = (BODY_PROFILE[row] if row < BODY_PROFILE.size() else 2)
		count = mini(count, tokens.size() - idx)
		var y := TOP_Y - row * ROW_H
		var start_x := -COL_W * (count - 1) * 0.5
		for k in range(count):
			var token: Dictionary = tokens[idx]
			var is_owner: bool = token.get("kind", "") == GameLogic.KIND_CREATURE \
				and bool(token.get("is_owner", false))
			var label := _word(token.get("text", ""),
				54 if is_owner else 38, _sentiment_color(token), is_owner)
			label.position = Vector3(start_x + k * COL_W, y, 0.0)
			fig.add_child(label)
			idx += 1
		row += 1


## Scenery is made of words too. "tree" stood on end like a trunk.
func _add_scenery() -> void:
	var tree := _word("tree", 64, Color(0.46, 0.72, 0.46), false)
	tree.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	tree.double_sided = true
	tree.rotation_degrees = Vector3(0, 0, 90)  # on its side -> a vertical trunk
	tree.position = Vector3(-7.0, 1.6, -3.0)
	add_child(tree)

	var hill := _word("hill", 52, Color(0.34, 0.46, 0.36), false)
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


func _find(chars: Array, name: String) -> Dictionary:
	for c in chars:
		if (c as Dictionary).get("name", "") == name:
			return c
	return {}
