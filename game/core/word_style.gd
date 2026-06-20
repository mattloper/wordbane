## Shared word styling, so every view colours words the same way.
##
## Both the 2D combat scene (main.gd) and the 3D world (world.gd) map a token's
## sentiment to a colour identically; this is the single source of truth for that.
class_name WordStyle
extends RefCounted

const POSITIVE := Color(0.45, 0.88, 0.50)
const NEGATIVE := Color(0.97, 0.40, 0.42)
const NEUTRAL := Color(0.85, 0.85, 0.90)
const FIXED := Color(0.60, 0.60, 0.68)


static func color_for(token: Dictionary) -> Color:
	if token.get("kind", "") == GameLogic.KIND_FIXED:
		return FIXED
	match token.get("sentiment", ""):
		GameLogic.POSITIVE: return POSITIVE
		GameLogic.NEGATIVE: return NEGATIVE
		_: return NEUTRAL


## Colour for the turn banner, by Battle phase.
static func phase_color(state: String) -> Color:
	match state:
		Battle.ST_CHOOSE: return POSITIVE
		Battle.ST_TARGET: return Color(1.0, 0.85, 0.3)
		Battle.ST_BUSY: return NEGATIVE
		_: return NEUTRAL
