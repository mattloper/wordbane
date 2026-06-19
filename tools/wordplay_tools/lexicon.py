"""Curated seed lexicon and character templates.

Every game-relevant word lives here with an explicit part of speech (``ADJ`` or
``NOUN``) and sentiment (``positive`` / ``negative`` / ``neutral``). Hand-curating
the core vocabulary guarantees the game always has correct, on-theme data even
with no network or NLP model available. ``generate.py`` can *enrich* these pools
with NLTK if it's installed, but never depends on it.

Sentiment convention
--------------------
- ``positive``  : cozy, gentle, friendly things  (defanged / safe)
- ``negative``  : threatening, hostile things     (what you attack to remove)
- ``neutral``   : descriptive but not charged

The whole game loop is: an enemy starts with negative words; you click them to
re-roll (same part of speech) hoping to turn the enemy harmless, while it tries
to corrupt your positive words.
"""

from __future__ import annotations

# --- Part of speech tags we treat as editable/targetable ---------------------
POS_ADJ = "ADJ"
POS_NOUN = "NOUN"

# Sentiment labels.
POSITIVE = "positive"
NEGATIVE = "negative"
NEUTRAL = "neutral"
SENTIMENTS = (POSITIVE, NEGATIVE, NEUTRAL)

# -----------------------------------------------------------------------------
# Curated word pools. Keep these clean and on-theme; the game draws random
# replacements from exactly these lists, so quality here == quality in-game.
# -----------------------------------------------------------------------------
ADJECTIVES: dict[str, list[str]] = {
    POSITIVE: [
        "cozy", "gentle", "fuzzy", "kind", "cheerful", "warm", "soft",
        "friendly", "radiant", "playful", "sweet", "calm", "lovely",
        "graceful", "bright", "tender", "merry", "snug", "darling", "serene",
    ],
    NEGATIVE: [
        "fierce", "sharp", "cruel", "jagged", "venomous", "savage", "wicked",
        "menacing", "brutal", "ruthless", "spiky", "vicious", "grim",
        "monstrous", "dreadful", "hostile", "rabid", "sinister", "deadly",
        "ferocious",
    ],
    NEUTRAL: [
        "tall", "round", "wooden", "ancient", "distant", "quiet", "hollow",
        "damp", "grey", "wide", "narrow", "plain", "ordinary", "still",
        "heavy", "pale", "smooth", "vast", "faint", "dim",
    ],
}

NOUNS: dict[str, list[str]] = {
    POSITIVE: [
        "kitten", "pillow", "garden", "friend", "blanket", "puppy", "bakery",
        "meadow", "teacup", "songbird", "cupcake", "hearth", "lantern",
        "bouquet", "harp", "cottage", "rainbow", "honey", "quilt", "daisy",
    ],
    NEGATIVE: [
        "dragon", "knife", "fang", "serpent", "blade", "wolf", "spear",
        "claw", "demon", "scorpion", "axe", "viper", "skull", "grave",
        "shackle", "ogre", "dagger", "wraith", "hornet", "thorn",
    ],
    NEUTRAL: [
        "rock", "table", "river", "tower", "cloud", "road", "stone", "barrel",
        "window", "fence", "wheel", "lamp", "crate", "hill", "bucket", "post",
        "shelf", "gate", "bench", "wall",
    ],
}


def all_pools() -> dict[str, dict[str, list[str]]]:
    """Return the full {pos: {sentiment: [words]}} structure (copies)."""
    return {
        POS_ADJ: {s: list(w) for s, w in ADJECTIVES.items()},
        POS_NOUN: {s: list(w) for s, w in NOUNS.items()},
    }


def _tok(text: str, pos: str | None = None, sentiment: str | None = None) -> dict:
    """Build one sentence token.

    ``editable`` tokens (adjectives & nouns) are the ones the player/enemy can
    click to re-roll. Function words and verbs are fixed scenery.
    """
    editable = pos in (POS_ADJ, POS_NOUN)
    token: dict = {"text": text, "editable": editable}
    if editable:
        token["pos"] = pos
        token["sentiment"] = sentiment
    return token


# -----------------------------------------------------------------------------
# Character templates: each character *is* a sentence. Negative words make a
# character threatening; the point of the game is to add/remove them.
# -----------------------------------------------------------------------------
def character_templates() -> list[dict]:
    """Pre-tokenized starting characters.

    Returned as plain dicts so they serialize straight to JSON for Godot.
    """
    return [
        {
            "name": "Dragon",
            "role": "enemy",
            "tokens": [
                _tok("The"),
                _tok("fierce", POS_ADJ, NEGATIVE),
                _tok("dragon", POS_NOUN, NEGATIVE),
                _tok("clutches"),
                _tok("a"),
                _tok("sharp", POS_ADJ, NEGATIVE),
                _tok("knife", POS_NOUN, NEGATIVE),
            ],
        },
        {
            "name": "Cat",
            "role": "player",
            "tokens": [
                _tok("The"),
                _tok("cozy", POS_ADJ, POSITIVE),
                _tok("kitten", POS_NOUN, POSITIVE),
                _tok("hugs"),
                _tok("a"),
                _tok("fuzzy", POS_ADJ, POSITIVE),
                _tok("pillow", POS_NOUN, POSITIVE),
            ],
        },
        {
            "name": "Ogre",
            "role": "enemy",
            "tokens": [
                _tok("A"),
                _tok("savage", POS_ADJ, NEGATIVE),
                _tok("ogre", POS_NOUN, NEGATIVE),
                _tok("swings"),
                _tok("a"),
                _tok("brutal", POS_ADJ, NEGATIVE),
                _tok("axe", POS_NOUN, NEGATIVE),
            ],
        },
        {
            "name": "Bunny",
            "role": "player",
            "tokens": [
                _tok("A"),
                _tok("gentle", POS_ADJ, POSITIVE),
                _tok("puppy", POS_NOUN, POSITIVE),
                _tok("nibbles"),
                _tok("a"),
                _tok("sweet", POS_ADJ, POSITIVE),
                _tok("cupcake", POS_NOUN, POSITIVE),
            ],
        },
    ]
