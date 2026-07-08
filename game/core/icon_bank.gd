## Clipart for the game, via emoji.
##
## Our creatures and items are a small fixed vocabulary, so a hand-authored
## word→emoji map is more reliable than matching art with a model. Emoji are free,
## instant, colourful clipart; real PNG art could replace this later. Also provides
## an emoji-capable font so the glyphs actually render (Godot's default font can't).
class_name IconBank
extends RefCounted

# Common emoji-capable fonts by platform; first that exists is used.
const EMOJI_FONT_PATHS := [
	"/System/Library/Fonts/Apple Color Emoji.ttc",          # macOS
	"/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf",    # Linux (Noto)
	"C:/Windows/Fonts/seguiemj.ttf",                        # Windows
]

# word -> emoji, from game/data/icons.json — shared with the web build so the two
# can't drift. Loaded once (static).
const ICONS_PATH := "res://data/icons.json"
static var MAP: Dictionary = _load_map()

static func _load_map() -> Dictionary:
	return JsonFile.load_dict(ICONS_PATH).get("words", {})


## The emoji for a word, or "" if we have none.
func of(word: String) -> String:
	return MAP.get(word.to_lower(), "")


## A text font with emoji support (system UI font + emoji fallback), or null if no
## emoji font is available on this platform.
static func text_font_with_emoji() -> Font:
	for path in EMOJI_FONT_PATHS:
		if FileAccess.file_exists(path):
			var emoji := FontFile.new()
			if emoji.load_dynamic_font(path) == OK:
				var base := SystemFont.new()
				base.fallbacks = [emoji]
				return base
	return null
