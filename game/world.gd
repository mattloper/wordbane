## The 3D world view.
##
## Renders a Battle in 3D: each character is its sentence on a quad in a field,
## the camera gently sways, and every card is re-oriented each frame to face it so
## its picking collider matches what's drawn. All turn logic lives in Battle; this
## script only draws and forwards clicks (use_item / target_word).
##
## Still TODO (#3): move the HUD from the flat overlay onto the 3D cards.
##
## View it with:  godot --path game world.tscn
extends Node3D

const BANK_PATH := "res://data/word_bank.json"

const CARD_SIZE := Vector2i(440, 360)
const CARD_FONT := 40
const OWNER_FONT := 60
const PIXEL_SIZE := 0.011
const CAM_RADIUS := 12.0
const CAM_HEIGHT := 1.9
const CAM_SWAY := 0.30  # radians of gentle left/right orbit

var _battle: Battle
var _cards: Dictionary = {}  # side -> {root: Node3D, sv: SubViewport, rtl: RichTextLabel}
var _cam: Camera3D
var _time := 0.0

var _banner: Label
var _enemy_stats: Label
var _telegraph: Label
var _player_stats: Label
var _log: Label


func _ready() -> void:
	get_viewport().physics_object_picking = true
	_build_environment()
	_cam = Camera3D.new()
	_cam.fov = 58
	add_child(_cam)
	_cam.current = true
	_build_ground()
	_add_scenery()
	_build_hud()
	_update_camera()

	_battle = Battle.new()
	add_child(_battle)
	_battle.changed.connect(_refresh)
	_battle.logged.connect(_set_log)
	_battle.setup(GameLogic.load_bank(BANK_PATH))
	_build_card("enemy", Vector3(-3.4, 1.9, 0.0))
	_build_card("player", Vector3(3.4, 1.9, 0.0))
	_battle.new_game()


func _process(delta: float) -> void:
	_time += delta
	_update_camera()
	for side in _cards:  # keep each card (and its collider) facing the camera
		var root: Node3D = _cards[side]["root"]
		root.look_at(2.0 * root.global_position - _cam.global_position, Vector3.UP)


func _update_camera() -> void:
	var a := sin(_time * 0.5) * CAM_SWAY
	_cam.position = Vector3(sin(a) * CAM_RADIUS, CAM_HEIGHT, cos(a) * CAM_RADIUS)
	_cam.look_at(Vector3(0, CAM_HEIGHT, 0), Vector3.UP)


# --- rendering (driven by Battle) --------------------------------------------

func _refresh() -> void:
	if _battle.enemy.is_empty():
		return
	for side in _cards:
		var fighter: Dictionary = _battle.enemy if side == "enemy" else _battle.player
		(_cards[side]["rtl"] as RichTextLabel).text = _card_bbcode(fighter, side)
	_update_hud()


func _card_bbcode(fighter: Dictionary, side: String) -> String:
	var tokens: Array = fighter.tokens
	var items_clickable := side == "player" and _battle.state == Battle.ST_CHOOSE
	var words_clickable := side == "enemy" and _battle.state == Battle.ST_TARGET
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
		if items_clickable and kind == GameLogic.KIND_ITEM:
			styled = "[url=item:%d]%s[/url]" % [int(token.get("item_index", -1)), styled]
		elif words_clickable and kind in GameLogic.EDITABLE_KINDS:
			styled = "[url=tok:%d]%s[/url]" % [i, styled]
		parts.append(styled)
	return "[center]" + " ".join(parts) + "[/center]"


func _on_card_meta(meta: Variant, side: String) -> void:
	var s := str(meta)
	if s.begins_with("item:") and side == "player":
		_battle.use_item(int(s.substr(5)))
	elif s.begins_with("tok:") and side == "enemy":
		_battle.target_word(int(s.substr(4)))


# --- card construction -------------------------------------------------------

func _build_card(side: String, pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)

	var sv := SubViewport.new()
	sv.size = CARD_SIZE
	sv.transparent_bg = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sv)

	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.scroll_active = false
	rtl.size = CARD_SIZE
	rtl.add_theme_font_size_override("normal_font_size", CARD_FONT)
	rtl.meta_clicked.connect(_on_card_meta.bind(side))
	sv.add_child(rtl)

	var card := Sprite3D.new()
	card.shaded = false
	card.double_sided = true
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

	_cards[side] = {"root": root, "sv": sv, "rtl": rtl}


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


# --- scenery / HUD -----------------------------------------------------------

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


func _add_scenery() -> void:
	var tree := Label3D.new()
	tree.text = "tree"
	tree.font_size = 64
	tree.modulate = Color(0.46, 0.72, 0.46)
	tree.double_sided = true
	tree.rotation_degrees = Vector3(0, 0, 90)
	tree.position = Vector3(-7.0, 1.6, -3.0)
	add_child(tree)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_banner = _hud_label(layer, Vector2(0, 14), 22, 900, true)
	_enemy_stats = _hud_label(layer, Vector2(20, 48), 16, 0, false)
	_telegraph = _hud_label(layer, Vector2(20, 72), 14, 860, false)
	_log = _hud_label(layer, Vector2(20, 590), 15, 860, false)
	_player_stats = _hud_label(layer, Vector2(20, 670), 16, 0, false)

	var restart := Button.new()
	restart.text = "New Battle"
	restart.position = Vector2(770, 12)
	restart.pressed.connect(func(): _battle.new_game())
	layer.add_child(restart)


## width 0 = single line (no wrap); width > 0 = wrap at that width.
func _hud_label(layer: CanvasLayer, pos: Vector2, font: int, width: int, centered: bool) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", font)
	if width > 0:
		l.size = Vector2(width, 50)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(l)
	return l


func _update_hud() -> void:
	_banner.text = _battle.banner_text()
	_banner.add_theme_color_override("font_color", WordStyle.phase_color(_battle.state))
	var e: Dictionary = _battle.enemy
	var p: Dictionary = _battle.player
	_enemy_stats.text = "ENEMY — %s    HP %d/%d    threats: %d    wards: %d" % [
		e.name, e.hp, e.max_hp, GameLogic.count_negative(e.tokens), e.wards]
	_telegraph.text = CombatText.telegraph(e)
	_player_stats.text = "YOU — %s    HP %d/%d    wards: %d" % [
		p.name, p.hp, p.max_hp, p.wards]


func _set_log(text: String) -> void:
	if _log:
		_log.text = text
