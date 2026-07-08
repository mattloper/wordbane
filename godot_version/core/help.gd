## Shared "How to play" copy + a ready-made overlay panel, so the title screen and
## the in-game menu show the same rules without duplicating text.
class_name Help
extends RefCounted

const RULES := \
	"Each enemy is a POOL OF LETTERS with an HP bar equal to their total rarity weight.\n\n" \
	+ "Type ANY real word using its letters — it deals damage equal to the rarity weight of " \
	+ "the letters it covers. Rare letters (j, x, q, z) hit hardest, but common ones chip away " \
	+ "too, so you never get stuck.\n\n" \
	+ "Drain the HP to 0 to clear the chapter and pick a reward. You can't type the enemy's own " \
	+ "weapon words, and no word twice per run. The enemy hits you every turn — so kill fast.\n\n" \
	+ "You lose at 0 HP. Score = damage dealt + how deep you go."


## A hidden, centered rules panel with its own "Got it" close button. Add it to a
## scene and toggle `.visible` to show/hide.
static func make_rules_panel() -> PanelContainer:
	var panel := UI.overlay_panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(560, 0)
	panel.add_child(box)
	box.add_child(UI.label("How to play", 26, UI.SELECT))
	box.add_child(UI.label(RULES, 15))
	var close := Button.new()
	close.text = "Got it"
	close.pressed.connect(panel.hide)
	box.add_child(close)
	return panel
