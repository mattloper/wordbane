"""Curated game vocabulary with combat metadata.

Three kinds of editable words:

- **creatures** — can be a character's *owner* (the subject noun). Owners do no
  damage themselves; they only carry items. Tagged with sentiment.
- **items** — the non-owner nouns. Each has an ``item_type`` (one of four) and a
  ``base`` power, plus sentiment. Items are what actually attack/defend.
- **adjectives** — *multipliers*. Each has a ``mult`` applied to the item it
  modifies (big/deadly scale up, tiny/gentle scale down), plus sentiment.

Verbs and function words are "fixed" scenery: they count toward a character's
word total (and thus max HP) but can't be clicked or randomized.

``generate.py`` turns this plus the character sentences into ``word_bank.json``;
the part-of-speech / owner structure is recovered by syntax parsing in
``parse.py``. Curating metadata here keeps combat numbers authoritative.
"""

from __future__ import annotations

# Word "kinds" (coarse part of speech for the game).
KIND_FIXED = "fixed"
KIND_ADJ = "adjective"
KIND_CREATURE = "creature"
KIND_ITEM = "item"

# Sentiment labels.
POSITIVE = "positive"
NEGATIVE = "negative"
NEUTRAL = "neutral"
SENTIMENTS = (POSITIVE, NEGATIVE, NEUTRAL)

# Item types (the four required categories).
HP_ATTACK = "hp_attack"        # offensive: direct HP damage
WORD_ATTACK = "word_attack"    # offensive: randomizes opponent words
HP_DEFENSE = "hp_defense"      # defensive: restores own HP
WORD_DEFENSE = "word_defense"  # defensive: wards off incoming randomization
ITEM_TYPES = (HP_ATTACK, WORD_ATTACK, HP_DEFENSE, WORD_DEFENSE)
OFFENSIVE_TYPES = (HP_ATTACK, WORD_ATTACK)
DEFENSIVE_TYPES = (HP_DEFENSE, WORD_DEFENSE)


# -----------------------------------------------------------------------------
# Creatures (possible owners). (word, sentiment)
# -----------------------------------------------------------------------------
CREATURES: list[tuple[str, str]] = [
    ("dragon", NEGATIVE), ("ogre", NEGATIVE), ("wolf", NEGATIVE),
    ("demon", NEGATIVE), ("serpent", NEGATIVE), ("goblin", NEGATIVE),
    ("kitten", POSITIVE), ("puppy", POSITIVE), ("lamb", POSITIVE),
    ("bunny", POSITIVE), ("fawn", POSITIVE), ("duckling", POSITIVE),
    ("knight", NEUTRAL), ("mage", NEUTRAL), ("sheep", NEUTRAL),
    ("badger", NEUTRAL), ("heron", NEUTRAL), ("goat", NEUTRAL),
]

# -----------------------------------------------------------------------------
# Items. (word, item_type, base_power, sentiment)
# -----------------------------------------------------------------------------
ITEMS: list[tuple[str, str, int, str]] = [
    # HP attackers (weapons)
    ("knife", HP_ATTACK, 2, NEGATIVE), ("dagger", HP_ATTACK, 1, NEGATIVE),
    ("axe", HP_ATTACK, 3, NEGATIVE), ("spear", HP_ATTACK, 2, NEGATIVE),
    ("blade", HP_ATTACK, 3, NEGATIVE), ("claw", HP_ATTACK, 2, NEGATIVE),
    ("fang", HP_ATTACK, 2, NEGATIVE), ("club", HP_ATTACK, 2, NEUTRAL),
    ("sword", HP_ATTACK, 3, NEUTRAL), ("hammer", HP_ATTACK, 3, NEUTRAL),
    # Word attackers (chaos magic)
    ("hex", WORD_ATTACK, 2, NEGATIVE), ("curse", WORD_ATTACK, 2, NEGATIVE),
    ("jinx", WORD_ATTACK, 2, NEGATIVE), ("wand", WORD_ATTACK, 1, NEUTRAL),
    ("scroll", WORD_ATTACK, 1, NEUTRAL), ("rune", WORD_ATTACK, 1, NEUTRAL),
    ("spell", WORD_ATTACK, 2, NEUTRAL),
    # HP defense (heals / shields)
    ("shield", HP_DEFENSE, 2, NEUTRAL), ("armor", HP_DEFENSE, 3, NEUTRAL),
    ("wall", HP_DEFENSE, 2, NEUTRAL), ("potion", HP_DEFENSE, 2, POSITIVE),
    ("salve", HP_DEFENSE, 2, POSITIVE), ("bandage", HP_DEFENSE, 1, POSITIVE),
    # Word defense (wards)
    ("amulet", WORD_DEFENSE, 1, POSITIVE), ("charm", WORD_DEFENSE, 1, POSITIVE),
    ("ward", WORD_DEFENSE, 1, NEUTRAL), ("talisman", WORD_DEFENSE, 2, NEUTRAL),
    ("totem", WORD_DEFENSE, 1, NEUTRAL),
]

# -----------------------------------------------------------------------------
# Adjectives = multipliers. (word, mult, sentiment)
# -----------------------------------------------------------------------------
ADJECTIVES: list[tuple[str, float, str]] = [
    # bigger
    ("big", 1.5, NEUTRAL), ("large", 1.5, NEUTRAL), ("huge", 2.0, NEUTRAL),
    ("massive", 2.0, NEUTRAL), ("great", 1.5, NEUTRAL), ("giant", 2.0, NEGATIVE),
    # smaller
    ("tiny", 0.5, NEUTRAL), ("small", 0.75, NEUTRAL), ("wee", 0.6, NEUTRAL),
    ("little", 0.75, POSITIVE), ("puny", 0.5, NEGATIVE),
    # dangerous (big + negative)
    ("sharp", 1.5, NEGATIVE), ("fierce", 1.75, NEGATIVE), ("wicked", 1.75, NEGATIVE),
    ("savage", 2.0, NEGATIVE), ("brutal", 2.0, NEGATIVE), ("deadly", 2.5, NEGATIVE),
    ("vicious", 2.0, NEGATIVE), ("cruel", 1.75, NEGATIVE), ("jagged", 1.5, NEGATIVE),
    ("venomous", 2.0, NEGATIVE),
    # gentle (small + positive)
    ("gentle", 0.75, POSITIVE), ("soft", 0.7, POSITIVE), ("cozy", 0.7, POSITIVE),
    ("fuzzy", 0.7, POSITIVE), ("kind", 0.75, POSITIVE), ("sweet", 0.7, POSITIVE),
    ("warm", 0.8, POSITIVE), ("cheerful", 0.8, POSITIVE), ("lovely", 0.8, POSITIVE),
    # sturdy / heroic (big, friendly-ish)
    ("mighty", 1.75, NEUTRAL), ("sturdy", 1.25, NEUTRAL), ("strong", 1.5, NEUTRAL),
    ("heavy", 1.5, NEUTRAL), ("glowing", 1.25, NEUTRAL), ("trusty", 1.2, POSITIVE),
    ("brave", 1.25, POSITIVE), ("lucky", 1.25, POSITIVE),
    # plain (no scaling)
    ("tall", 1.0, NEUTRAL), ("round", 1.0, NEUTRAL), ("wooden", 1.0, NEUTRAL),
    ("plain", 1.0, NEUTRAL), ("old", 1.0, NEUTRAL), ("clever", 1.0, NEUTRAL),
]


def build_pools() -> dict:
    """Group the vocabulary into the draw pools the game randomizes from.

    Shape: {kind: {sentiment: [ {text, ...metadata}, ... ]}}
    """
    pools: dict = {
        KIND_CREATURE: {s: [] for s in SENTIMENTS},
        KIND_ITEM: {s: [] for s in SENTIMENTS},
        KIND_ADJ: {s: [] for s in SENTIMENTS},
    }
    for text, sentiment in CREATURES:
        pools[KIND_CREATURE][sentiment].append({"text": text})
    for text, item_type, base, sentiment in ITEMS:
        pools[KIND_ITEM][sentiment].append(
            {"text": text, "item_type": item_type, "base": base}
        )
    for text, mult, sentiment in ADJECTIVES:
        pools[KIND_ADJ][sentiment].append({"text": text, "mult": mult})
    return pools


def word_index() -> dict:
    """word -> metadata, authoritative source for tagging parsed sentences."""
    idx: dict = {}
    for text, sentiment in CREATURES:
        idx[text] = {"kind": KIND_CREATURE, "sentiment": sentiment}
    for text, item_type, base, sentiment in ITEMS:
        idx[text] = {
            "kind": KIND_ITEM, "sentiment": sentiment,
            "item_type": item_type, "base": base,
        }
    for text, mult, sentiment in ADJECTIVES:
        idx[text] = {"kind": KIND_ADJ, "sentiment": sentiment, "mult": mult}
    return idx


# -----------------------------------------------------------------------------
# Character sentences. Owners & items are recovered by parsing (see parse.py),
# NOT hand-tagged — the rules require owner detection via syntax.
# Each sentence is one owner (subject) plus two items, so the item cycle loops.
# -----------------------------------------------------------------------------
CHARACTER_SENTENCES: list[dict] = [
    {"name": "Dragon", "role": "enemy",
     "text": "The fierce dragon swings a sharp knife and casts a wicked hex."},
    {"name": "Ogre", "role": "enemy",
     "text": "A savage ogre raises a brutal axe and grips a sturdy shield."},
    {"name": "Wolf", "role": "enemy",
     "text": "The vicious wolf bares a deadly fang and swings a jagged claw."},
    {"name": "Knight", "role": "player",
     "text": "The brave knight thrusts a mighty spear and lifts a sturdy shield."},
    {"name": "Mage", "role": "player",
     "text": "A clever mage waves a glowing wand and wears a lucky amulet."},
    {"name": "Kitten", "role": "player",
     "text": "The cozy kitten swings a trusty club and sips a sweet potion."},
]
