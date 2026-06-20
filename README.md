# Wordplay

A turn-based word-battle game. Each **character is a sentence**. The sentence's
**subject is its "owner"** (the creature itself); every **other noun is an item**.
Owners deal no damage — only items do. **Adjectives are multipliers** that scale
the item they modify.

> 🐉 `The fierce dragon swings a sharp knife and casts a wicked hex.`
> &nbsp;&nbsp;&nbsp;&nbsp;owner = **dragon** · items = **sharp knife** (HP attack), **wicked hex** (word attack)

## How it plays

- **Your turn:** click one of *your* item words to use it.
- **Enemy turn:** the enemy cycles through its items in a **fixed, telegraphed
  order** — you always see what it will do next (Inscryption-style).
- Every action is one of two kinds:
  - **General attack** → direct **HP** damage. Amount = the item noun's base power
    × its adjective multiplier (e.g. `knife` base 2 × `sharp` ×1.5 = **3**).
  - **Word-randomization attack** → scrambles the opponent's words (same part of
    speech), which can change their items *and* their sentiment.
- **Items come in four types:**

  | type | offensive/defensive | effect |
  |------|---------------------|--------|
  | `hp_attack`    | offensive | direct HP damage |
  | `word_attack`  | offensive | randomizes opponent words |
  | `hp_defense`   | defensive | restores your HP |
  | `word_defense` | defensive | raises **wards** that block incoming randomization |

- **Max HP = the number of words** in your sentence.
- **Win** by either **defeating** the enemy (HP → 0) *or* **pacifying** it
  (randomize its words until **none are negative**).
- **Lose** if **your HP** hits 0. (Corruption doesn't kill you — only HP does.)

## Architecture

The NLP runs **at build time** in Python, so the game ships pure data and needs
no Python runtime:

```
tools/   →  Python (uv): curated combat lexicon + spaCy sentence parsing.
            Emits ↓
game/data/word_bank.json   →  read by ↓
game/    →  Godot 4.6 project: combat engine + UI.
```

- **Owner via syntax** — spaCy's dependency parse finds the grammatical **subject**
  (`nsubj`); that's the owner. Other nouns become items. spaCy's POS tags are noisy
  on terse fantasy text, so the curated lexicon is the authority on each word's
  *kind* while spaCy supplies the *structure* (subject + which noun each adjective
  modifies). See `tools/wordplay_tools/parse.py`.
- **Items & multipliers** — the lexicon assigns each item noun an `item_type` +
  `base` power and each adjective a `mult`. `parse.py` links adjectives to the noun
  they modify, so `item power = base × ∏(adjective mults)`.
- **Pure logic** — `game/game_logic.gd` (`GameLogic`) holds all combat rules with
  no UI, so it's unit-tested headlessly.

## Prerequisites

- [Godot 4.6+](https://godotengine.org/) (`godot` on PATH)
- [uv](https://docs.astral.sh/uv/)

## Setup

### 1. Generate the word bank (Python / uv)

```bash
cd tools
uv venv
uv pip install -e ".[dev]"                       # installs spaCy + pytest
uv run python -m spacy download en_core_web_sm    # one-time: the English model
uv run wordplay-generate                          # writes ../game/data/word_bank.json
uv run pytest
```

`word_bank.json` is committed, so you can run the game without regenerating — but
re-run `wordplay-generate` whenever you edit the lexicon or characters.

Without the spaCy model the generator still works via a heuristic owner detector
(`uv run wordplay-generate --no-spacy`); spaCy is the intended path.

### 2. Run the game (Godot)

```bash
godot --path game            # or open game/ in the editor and press F5
```

## Project layout

```
wordplay/
├── README.md  ·  .gitignore
├── tools/                       # Python build tooling (uv project)
│   ├── pyproject.toml
│   ├── wordplay_tools/
│   │   ├── lexicon.py           # creatures, typed items, multiplier adjectives,
│   │   │                        #   and the character sentences
│   │   ├── parse.py             # spaCy owner/item/adjective parsing (+ fallback)
│   │   └── generate.py          # builds word_bank.json
│   └── tests/test_generate.py
└── game/                        # Godot 4.6 project
    ├── project.godot
    ├── core/                    # view-agnostic logic (class_name globals)
    │   ├── game_logic.gd        #   GameLogic — pure combat rules
    │   ├── battle.gd            #   Battle — item-combat turn machine (older mode)
    │   ├── word_ladder.gd       #   WordLadder — typed-word transform validator
    │   ├── ladder_battle.gd     #   LadderBattle — one disarm-the-weapons fight
    │   ├── gauntlet.gd          #   Gauntlet — escalating enemy generator
    │   ├── combat_text.gd       #   CombatText — shared phrasing
    │   └── word_style.gd        #   WordStyle — shared word colours
    ├── ladder.tscn / ladder.gd  # ★ Letter-Ladder Gauntlet — the current game
    ├── play.gd                  # headless CLI to play the gauntlet
    ├── main.tscn / main.gd      # 2D item-combat view (older mode)
    ├── world.tscn / world.gd    # 3D item-combat view (older mode)
    ├── selftest.gd              # headless smoke test
    └── data/
        ├── word_bank.json       # characters + word pools (generated)
        └── dictionary.json      # 50k words -> {pos, sentiment} (generated)
```

## The game: Letter-Ladder Gauntlet

`godot --path game ladder.tscn` (or play it headless via `play.gd`, below).

Descend a gauntlet of escalating enemies. Each enemy's **weapons are its red
nouns**; every turn the survivors damage you (`base × adjective multiplier`). On
your turn, click a weapon and **type a real word made from its letters** — add OR
remove letters (a *word ladder*), same part of speech — to disarm it. Disarm them
all to descend; HP carries between fights with a small heal per victory. You lose
when HP hits 0, and your score is the depth reached.

Why it takes thought: you must (a) find a valid word (vocabulary), (b) disarm the
*biggest* threats first to minimise incoming damage (ordering), and (c) never
reuse a word, so variety runs down. Short weapons (`hex`, `axe`) have no shorter
word, forcing you to *grow* them — the hardest puzzles.

### Play it from the command line (`play.gd`)

```bash
godot --headless --path game --script res://play.gd -- new
godot --headless --path game --script res://play.gd -- move <index> <word>
godot --headless --path game --script res://play.gd -- pass
```
Run state persists between calls, so each invocation is one move.

Both views are thin: they render a `Battle` and forward clicks. The shared
`core/` classes hold all rules, flow, and presentation strings, so the 2D and 3D
scenes never duplicate logic.

## Testing

```bash
cd tools && uv run pytest                                   # Python tooling
godot --headless --path game --script res://selftest.gd     # Godot combat logic
```

## Extending it

- **Words / item powers / multipliers** → edit `tools/wordplay_tools/lexicon.py`
  (`CREATURES`, `ITEMS`, `ADJECTIVES`).
- **New characters** → add a sentence to `CHARACTER_SENTENCES`; the parser finds
  its owner and items automatically. Keep one subject + a couple of object nouns.
- **Difficulty / feel** → tweak base powers and multipliers in the lexicon.
- Re-run `uv run wordplay-generate` after any lexicon change.

## Ideas / next steps

- Let the player *target* which enemy word a randomizer scrambles (currently random).
- Multi-sentence characters; status effects; an energy economy so turns are choices.
- Smarter enemy AI instead of a fixed cycle (the cycle is intentional for now —
  it's the telegraph).
- Richer sentiment/POS from a larger model instead of the curated lexicon.

## License

TBD.
