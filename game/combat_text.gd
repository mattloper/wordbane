## Shared, view-agnostic combat phrasing.
##
## Turns game state into the human-readable strings both the 2D scene and the 3D
## world show (item forecasts, action summaries). Pure functions over GameLogic.
class_name CombatText
extends RefCounted

## "sharp knife  →  HP -3  (base 2 x1.50)" — what an item will do (tooltips/telegraph).
static func item_effect(tokens: Array, item_index: int) -> String:
	var p := GameLogic.item_power(tokens, item_index)
	if p.is_empty():
		return ""
	var verb := ""
	match p.type:
		GameLogic.HP_ATTACK: verb = "HP -%d" % p.amount
		GameLogic.WORD_ATTACK: verb = "scramble %d" % p.amount
		GameLogic.HP_DEFENSE: verb = "heal +%d" % p.amount
		GameLogic.WORD_DEFENSE: verb = "ward %d" % p.amount
	return "%s  →  %s  (base %d x%.2f)" % [
		GameLogic.item_label(tokens, item_index), verb, p.base, p.mult]


## Past-tense summary of a resolved action, for the message log.
static func describe(actor: String, res: Dictionary, target: String) -> String:
	if not res.get("ok", false):
		return ""
	match res.type:
		GameLogic.HP_ATTACK:
			return "%s used %s — %d damage to %s." % [actor, res.item, res.dmg, target]
		GameLogic.WORD_ATTACK:
			var s := "%s used %s — scrambled %d of %s's words" % [
				actor, res.item, res.scrambled, target]
			if int(res.blocked) > 0:
				s += " (%d blocked by wards)" % res.blocked
			return s + "."
		GameLogic.HP_DEFENSE:
			return "%s used %s — healed %d HP." % [actor, res.item, res.healed]
		GameLogic.WORD_DEFENSE:
			return "%s used %s — raised %d ward(s)." % [actor, res.item, res.wards]
	return ""
