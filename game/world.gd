## The 3D world — now an actual playable battle (in progress).
##
## Each character is its *sentence* on a quad in a 3D field. The camera gently
## sways for parallax; each card is re-oriented every frame to face the camera, so
## its picking collider always matches what's drawn (no billboard needed).
##
## Turn rules (ported from the 2D scene, sharing GameLogic / CombatText / WordStyle):
##   YOUR TURN  — click one of your item words. A word-attack item then lets you
##                click which enemy word(s) to randomize; other items resolve at once.
##   ENEMY TURN — it cycles through its items in order (shown in the telegraph).
##   Win by HP->0 or pacifying the enemy; lose if your HP hits 0.
##
## Still TODO (#3): move the HUD from a flat overlay onto the 3D cards.
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

const ST_CHOOSE := "choose"
const ST_TARGET := "target"
const ST_BUSY := "busy"
const ST_OVER := "over"

var _rng := RandomNumberGenerator.new()
var _pools: Dictionary = {}
var _characters: Array = []

var _player: Dictionary = {}
var _enemy: Dictionary = {}
var _state := ST_CHOOSE
var _player_msg := ""
var _pending_targets := 0
var _pending_label := ""
var _battle_id := 0
var _time := 0.0

var _cards: Dictionary = {}  # side -> {root: Node3D, sv: SubViewport, rtl: RichTextLabel}
var _cam: Camera3D
var _banner: Label
var _enemy_stats: Label
var _telegraph: Label
var _player_stats: Label
var _log: Label


func _ready() -> void:
	_rng.randomize()
	get_viewport().physics_object_picking = true
	_build_environment()
	_cam = Camera3D.new()
	_cam.fov = 58
	add_child(_cam)
	_cam.current = true
	_build_ground()
	_add_scenery()
	_build_hud()

	var bank := GameLogic.load_bank(BANK_PATH)
	_pools = bank.get("pools", {})
	_characters = bank.get("characters", [])
	_update_camera()
	_new_game()


func _process(delta: float) -> void:
	_time += delta
	_update_camera()
	# Keep each card (and its collider) facing the camera.
	for side in _cards:
		var root: Node3D = _cards[side]["root"]
		root.look_at(2.0 * root.global_position - _cam.global_position, Vector3.UP)


func _update_camera() -> void:
	var a := sin(_time * 0.5) * CAM_SWAY
	_cam.position = Vector3(sin(a) * CAM_RADIUS, CAM_HEIGHT, cos(a) * CAM_RADIUS)
	_cam.look_at(Vector3(0, CAM_HEIGHT, 0), Vector3.UP)


# --- battle flow -------------------------------------------------------------

func _new_game() -> void:
	_battle_id += 1
	for side in _cards.keys():
		(_cards[side]["root"] as Node3D).queue_free()
	_cards.clear()

	var enemy_t := GameLogic.pick_character(_characters, "enemy", _rng)
	var player_t := GameLogic.pick_character(_characters, "player", _rng)
	if enemy_t.is_empty() or player_t.is_empty():
		_set_log("Word bank is missing player/enemy characters.")
		return
	_enemy = GameLogic.make_fighter(enemy_t)
	_player = GameLogic.make_fighter(player_t)
	_state = ST_CHOOSE
	_player_msg = ""
	_pending_targets = 0
	_build_card("enemy", Vector3(-3.4, 1.9, 0.0))
	_build_card("player", Vector3(3.4, 1.9, 0.0))
	_set_log("Your turn — click one of your item words.")
	_refresh()


func _refresh() -> void:
	if _cards.has("enemy"):
		(_cards["enemy"]["rtl"] as RichTextLabel).text = _card_bbcode(_enemy, "enemy")
	if _cards.has("player"):
		(_cards["player"]["rtl"] as RichTextLabel).text = _card_bbcode(_player, "player")
	_update_hud()


func _on_card_meta(meta: Variant, side: String) -> void:
	var s := str(meta)
	if s.begins_with("item:") and side == "player" and _state == ST_CHOOSE:
		_use_item(int(s.substr(5)))
	elif s.begins_with("tok:") and side == "enemy" and _state == ST_TARGET:
		_target_word(int(s.substr(4)))


func _use_item(item_index: int) -> void:
	var power := GameLogic.item_power(_player.tokens, item_index)
	if power.get("type", "") == GameLogic.WORD_ATTACK:
		_pending_targets = int(power.amount)
		_pending_label = GameLogic.item_label(_player.tokens, item_index)
		_state = ST_TARGET
		_refresh()
		_set_log("%s readies %s — click an enemy word to randomize it." % [
			_player.name, _pending_label])
		return
	var res := GameLogic.apply_item(_player, _enemy, item_index, _pools, _rng)
	_player_msg = CombatText.describe(_player.name, res, _enemy.name)
	_finish_player_action()


func _target_word(token_index: int) -> void:
	var r := GameLogic.scramble_one(_enemy, token_index, _pools, _rng)
	if not r.get("ok", false):
		return
	_pending_targets -= 1
	var note: String = "blocked by %s's ward!" % _enemy.name if r.get("blocked", false) \
		else "→ '%s'" % r.get("text", "")
	_refresh()
	if _check_end():
		return
	if _pending_targets <= 0 or GameLogic.editable_indices(_enemy.tokens).is_empty():
		_player_msg = "%s used %s (%s)" % [_player.name, _pending_label, note]
		_finish_player_action()
	else:
		_set_log("%s  Click %d more enemy word(s)." % [note, _pending_targets])


func _finish_player_action() -> void:
	var id := _battle_id
	_set_log(_player_msg)
	_state = ST_BUSY
	_refresh()
	if _check_end():
		return
	await get_tree().create_timer(0.55).timeout
	if id != _battle_id:
		return
	_enemy_turn()


func _enemy_turn() -> void:
	if _state == ST_OVER:
		return
	var idx := GameLogic.next_item_index(_enemy)
	var res := GameLogic.apply_item(_enemy, _player, idx, _pools, _rng)
	GameLogic.advance_cycle(_enemy)
	_set_log(_player_msg + "\n" + CombatText.describe(_enemy.name, res, _player.name))
	if _check_end():
		return
	_state = ST_CHOOSE
	_refresh()


func _check_end() -> bool:
	if int(_enemy.hp) <= 0:
		_end("VICTORY — you defeated %s (HP 0)!" % _enemy.name)
		return true
	if GameLogic.is_pacified(_enemy.tokens):
		_end("VICTORY — %s is pacified: no negative words left!" % _enemy.name)
		return true
	if int(_player.hp) <= 0:
		_end("DEFEAT — %s knocked your HP to 0." % _player.name)
		return true
	return false


func _end(msg: String) -> void:
	_state = ST_OVER
	_refresh()
	_set_log(msg + "\nPress New Battle to play again.")


# --- card construction / text ------------------------------------------------

func _card_bbcode(fighter: Dictionary, side: String) -> String:
	var tokens: Array = fighter.tokens
	var items_clickable := side == "player" and _state == ST_CHOOSE
	var words_clickable := side == "enemy" and _state == ST_TARGET
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
	restart.pressed.connect(_new_game)
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
	_banner.text = _banner_text()
	_banner.add_theme_color_override("font_color", _banner_color())
	_enemy_stats.text = "ENEMY — %s    HP %d/%d    threats: %d    wards: %d" % [
		_enemy.name, _enemy.hp, _enemy.max_hp,
		GameLogic.count_negative(_enemy.tokens), _enemy.wards]
	_telegraph.text = _telegraph_text()
	_player_stats.text = "YOU — %s    HP %d/%d    wards: %d" % [
		_player.name, _player.hp, _player.max_hp, _player.wards]


func _banner_text() -> String:
	match _state:
		ST_CHOOSE: return "● YOUR TURN — click an item word"
		ST_TARGET: return "◎ PICK A TARGET — click %d enemy word(s)" % _pending_targets
		ST_BUSY: return "ENEMY TURN…"
		ST_OVER: return "GAME OVER"
	return ""


func _banner_color() -> Color:
	match _state:
		ST_CHOOSE: return WordStyle.POSITIVE
		ST_TARGET: return Color(1.0, 0.85, 0.3)
		ST_BUSY: return WordStyle.NEGATIVE
		_: return WordStyle.NEUTRAL


func _telegraph_text() -> String:
	var order: Array = _enemy.item_order
	if order.is_empty():
		return ""
	var parts: Array = []
	for i in range(order.size()):
		var item_index: int = order[i]
		var marker := "▸ " if i == int(_enemy.cycle_index) else "  "
		parts.append(marker + CombatText.item_effect(_enemy.tokens, item_index))
	return "Enemy plan (loops):   " + "      ".join(parts)


func _set_log(text: String) -> void:
	if _log:
		_log.text = text
