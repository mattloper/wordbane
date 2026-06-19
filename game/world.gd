## World prototype (NOT the game yet).
##
## A first step toward "a place made of words": a 2.5D field where each character
## is a *pile of its sentence's words arranged into a rough figure*, and scenery
## (a "tree") is itself a word-object. This is purely visual — no combat — meant
## to find the look before wiring it to gameplay.
##
## View it with:  godot --path game world.tscn
extends Node2D

const COLOR_POSITIVE := Color(0.45, 0.88, 0.50)
const COLOR_NEGATIVE := Color(0.96, 0.40, 0.40)
const COLOR_NEUTRAL := Color(0.85, 0.85, 0.90)
const COLOR_FIXED := Color(0.62, 0.62, 0.70)

const SKY := Color(0.12, 0.13, 0.20)
const GROUND := Color(0.16, 0.20, 0.17)
const GROUND_Y := 400.0

# A loose humanoid skeleton: word slots relative to the figure's centre (y down).
# Words fill these in order; leftovers pile near the belly. The point is a
# body-ish silhouette, not a neat layout.
const SKELETON := [
	Vector2(0, -120),                                   # head
	Vector2(0, -88),                                    # neck
	Vector2(-38, -66), Vector2(38, -66),               # shoulders
	Vector2(0, -54),                                    # chest
	Vector2(-74, -34), Vector2(74, -34),               # upper arms
	Vector2(0, -20),                                    # belly
	Vector2(-104, -6), Vector2(104, -6),               # hands
	Vector2(-26, 18), Vector2(26, 18),                 # hips
	Vector2(-32, 64), Vector2(32, 64),                 # thighs
	Vector2(-36, 116), Vector2(36, 116),               # feet
]

var _view: Vector2 = Vector2(900, 720)


func _ready() -> void:
	_view = get_viewport_rect().size
	_add_scenery()
	# Two characters standing in the field. Enemy is further back (higher +
	# smaller), player is closer (lower + larger) — cheap 2.5D depth cues.
	var bank := GameLogic.load_bank("res://data/word_bank.json")
	var chars: Array = bank.get("characters", [])
	var enemy := _find(chars, "Dragon")
	var player := _find(chars, "Knight")
	# Origins are placed so each figure's feet rest near the ground at its depth.
	if not enemy.is_empty():
		add_child(_make_figure(enemy.tokens, Vector2(300, 285), 0.82))
	if not player.is_empty():
		add_child(_make_figure(player.tokens, Vector2(615, 350), 1.08))

	var caption := _word_label("a place made of words — prototype", 16, COLOR_FIXED)
	caption.position = Vector2(20, 16)
	add_child(caption)
	queue_redraw()


func _draw() -> void:
	# Sky + ground bands for a flat 2.5D horizon.
	draw_rect(Rect2(Vector2.ZERO, Vector2(_view.x, GROUND_Y)), SKY)
	draw_rect(Rect2(Vector2(0, GROUND_Y), Vector2(_view.x, _view.y - GROUND_Y)), GROUND)


func _find(chars: Array, name: String) -> Dictionary:
	for c in chars:
		if (c as Dictionary).get("name", "") == name:
			return c
	return {}


func _sentiment_color(token: Dictionary) -> Color:
	if token.get("kind", "") == GameLogic.KIND_FIXED:
		return COLOR_FIXED
	match token.get("sentiment", ""):
		GameLogic.POSITIVE: return COLOR_POSITIVE
		GameLogic.NEGATIVE: return COLOR_NEGATIVE
		_: return COLOR_NEUTRAL


func _word_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.reset_size()
	return l


## Build one character as a Node2D "word pile" shaped like a figure.
func _make_figure(tokens: Array, origin: Vector2, scale_factor: float) -> Node2D:
	var fig := Node2D.new()
	fig.position = origin
	fig.scale = Vector2(scale_factor, scale_factor)

	# Put the owner word at the head, then the rest in sentence order.
	var ordered: Array = []
	var owner: Dictionary = {}
	for t in tokens:
		if t.get("kind", "") == GameLogic.KIND_CREATURE and t.get("is_owner", false):
			owner = t
		else:
			ordered.append(t)
	if not owner.is_empty():
		ordered.push_front(owner)

	for i in range(ordered.size()):
		var token: Dictionary = ordered[i]
		var is_head := i == 0
		var lbl := _word_label(token.get("text", ""),
			26 if is_head else 18, _sentiment_color(token))
		var slot: Vector2
		if i < SKELETON.size():
			slot = SKELETON[i]
		else:
			# Extra words heap around the belly with a little spread.
			var k := i - SKELETON.size()
			slot = Vector2(-30 + 30 * (k % 3), -20 + 22 * int(k / 3))
		lbl.position = slot - lbl.size * 0.5
		fig.add_child(lbl)
	return fig


## Scenery is also made of words. A "tree" stood on its end like a trunk.
func _add_scenery() -> void:
	var tree := _word_label("tree", 40, Color(0.45, 0.70, 0.45))
	tree.rotation = -PI / 2  # on its side -> reads as a vertical trunk
	tree.position = Vector2(110, GROUND_Y - 6)
	add_child(tree)

	var hill := _word_label("hill", 30, Color(0.34, 0.46, 0.36))
	hill.position = Vector2(_view.x - 95, GROUND_Y - 52)
	add_child(hill)
