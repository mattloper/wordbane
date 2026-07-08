## Small visual-feedback helpers (Tween-based) for combat feel. Static — pass the
## `host` node that should own the tweens / hold the floating labels.
class_name Juice
extends RefCounted

const BAR_DRAIN := 0.45  # seconds for an HP bar to ease down


## Ease a progress bar toward `target`, killing any in-flight tween on it first so
## rapid hits don't jitter. Returns the new tween (keep it to pass back next time).
static func drain_bar(host: Node, bar: ProgressBar, target: float, prev: Tween) -> Tween:
	if prev != null and prev.is_valid():
		prev.kill()
	var t := host.create_tween()
	t.tween_property(bar, "value", target, BAR_DRAIN).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	return t


## A "-N" that rises from `anchor` and fades. Bigger hits -> bigger font + longer
## rise, so damage is legible at a glance.
static func float_number(host: Node, anchor: Control, amount: int, color: Color) -> void:
	if amount <= 0 or anchor == null:
		return
	var lbl := Label.new()
	lbl.text = "-%d" % amount
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", clampi(22 + amount * 2, 22, 60))
	lbl.add_theme_color_override("font_color", color)
	host.add_child(lbl)
	var r := anchor.get_global_rect()
	lbl.position = r.position + Vector2(r.size.x * 0.5 - 8, -8)
	var rise := 34.0 + amount * 1.5
	var t := host.create_tween().set_parallel(true)
	t.tween_property(lbl, "position:y", lbl.position.y - rise, 0.7).set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "modulate:a", 0.0, 0.7).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(lbl.queue_free)


## `node` surges forward (right) and swells, then springs back — reads as the enemy
## lunging AT you, not being knocked down.
static func lunge(host: Node, node: Control) -> void:
	if node == null:
		return
	var t := host.create_tween()
	t.tween_property(node, "position", Vector2(16, 0), 0.10).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(node, "scale", Vector2(1.3, 1.3), 0.10).set_ease(Tween.EASE_OUT)
	t.chain().tween_property(node, "position", Vector2.ZERO, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(node, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
