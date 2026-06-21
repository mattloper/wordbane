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

# word -> emoji. Covers enemy creatures + their weapon items (and a few friendlies).
const MAP := {
	# creatures
	"dragon": "🐉", "ogre": "👹", "wolf": "🐺", "demon": "😈", "serpent": "🐍",
	"goblin": "👺", "kitten": "🐱", "puppy": "🐶", "lamb": "🐑", "bunny": "🐰",
	"fawn": "🦌", "duckling": "🐥", "knight": "🤺", "mage": "🧙", "sheep": "🐑",
	"badger": "🦡", "heron": "🐦", "goat": "🐐",
	# items / weapons
	"knife": "🔪", "dagger": "🗡️", "axe": "🪓", "spear": "🔱", "blade": "🗡️",
	"claw": "🐾", "fang": "🦷", "hex": "🔮", "curse": "💀", "jinx": "🧿",
	"club": "🏏", "sword": "⚔️", "hammer": "🔨", "shield": "🛡️", "wand": "🪄",
	"scroll": "📜", "spell": "✨", "potion": "🧪",
}


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
