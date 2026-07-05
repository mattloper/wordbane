## Shared word styling: maps a token's sentiment to a colour, so every view
## colours words the same way. Single source of truth for word colour.
class_name WordStyle
extends RefCounted

const POSITIVE := Color(0.45, 0.88, 0.50)
const NEGATIVE := Color(0.97, 0.40, 0.42)
const NEUTRAL := Color(0.85, 0.85, 0.90)
const FIXED := Color(0.60, 0.60, 0.68)


static func color_for(token: Dictionary) -> Color:
	if token.get("kind", "") == WordBank.KIND_FIXED:
		return FIXED
	match token.get("sentiment", ""):
		WordBank.POSITIVE: return POSITIVE
		WordBank.NEGATIVE: return NEGATIVE
		_: return NEUTRAL
