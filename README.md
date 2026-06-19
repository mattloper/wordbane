# Wordplay

A word-battle game. Each **character is a sentence**. You fight by **clicking the
enemy's words**, which **randomizes** them — and the enemy does the same back to you.

Words are tagged by **part of speech** (adjective / noun) and **sentiment**
(positive / negative / neutral):

> 🐉 `The fierce dragon clutches a sharp knife`  ← all-negative: dangerous
> 🐱 `The cozy kitten hugs a fuzzy pillow`        ← all-positive: harmless

Click the enemy's **red** (negative) words to re-roll them. Every re-roll keeps the
**same part of speech** (an adjective becomes another adjective, a noun another noun)
but lands on a random sentiment. Leave the enemy with **zero negative words** and you
win; let the enemy push **3 negative words** onto you and you lose.

```
ENEMY — Dragon   (threats: 4)
┌──────────────────────────────────────────────┐
│ The  [fierce]  [dragon]  clutches  a  [sharp]  [knife] │   ← red = click to randomize
└──────────────────────────────────────────────┘

YOU — Cat   (corruption: 0 / 3)
┌──────────────────────────────────────────────┐
│ The  cozy  kitten  hugs  a  fuzzy  pillow      │   ← green = safe
└──────────────────────────────────────────────┘
```

## Architecture

The NLP runs **at build time** in Python, so the game ships pure data and never
needs a Python runtime or model weights:

```
tools/   →  Python (uv) tooling: curated, sentiment-tagged lexicon + optional
            NLTK enrichment + a sentence tagger.  Emits ↓
game/data/word_bank.json   →  read by ↓
game/    →  Godot 4.6 project: loads the word bank, renders each sentence as
            clickable word-buttons, runs the turn loop.
```

- **Part-of-speech awareness** — every editable word carries `pos` (`ADJ`/`NOUN`);
  re-rolls draw only from the matching pool, so grammar never breaks.
- **Sentiment awareness** — every word carries a `sentiment`; the win/lose check is
  literally "does this character still have any negative words?"
- The Python tooling is the place to add words, characters, or smarter NLP.

## Prerequisites

- [Godot 4.6+](https://godotengine.org/) (`godot` on your PATH)
- [uv](https://docs.astral.sh/uv/)

Both are already installed if `godot --version` and `uv --version` work.

## Setup

### 1. Generate the word bank (Python / uv)

```bash
cd tools
uv venv
uv pip install -e ".[dev]"          # core + pytest
uv run wordplay-generate            # writes ../game/data/word_bank.json
uv run pytest                       # run the tests
```

Optional — richer vocabulary via NLTK (otherwise the curated lexicon is used):

```bash
uv pip install -e ".[dev,nlp]"
uv run python -m nltk.downloader averaged_perceptron_tagger wordnet sentiwordnet omw-1.4
uv run wordplay-generate            # now enriches pools from WordNet/SentiWordNet
```

`word_bank.json` is committed, so you can run the game without this step — but
regenerate it whenever you edit the lexicon or characters.

### 2. Run the game (Godot)

```bash
godot --path game                   # opens and runs the project
# or open the `game/` folder in the Godot editor and press Play (F5)
```

## Project layout

```
wordplay/
├── README.md
├── .gitignore
├── tools/                       # Python build tooling (uv project)
│   ├── pyproject.toml
│   ├── wordplay_tools/
│   │   ├── lexicon.py           # curated word pools + character templates
│   │   ├── generate.py          # builds word_bank.json (+ optional NLTK)
│   │   └── tag.py               # POS+sentiment tagger for raw sentences
│   └── tests/test_generate.py
└── game/                        # Godot 4.6 project
    ├── project.godot
    ├── main.tscn / main.gd      # UI + turn loop (built in code)
    ├── game_logic.gd            # pure, UI-free game rules (GameLogic class)
    ├── selftest.gd              # headless smoke test
    └── data/word_bank.json      # generated; consumed at runtime
```

## Testing

```bash
# Python tooling
cd tools && uv run pytest

# Godot logic (headless, no display needed)
godot --headless --path game --script res://selftest.gd
```

## Extending it

- **New words** → edit the pools in `tools/wordplay_tools/lexicon.py`.
- **New characters** → add templates in `lexicon.py` (`character_templates()`), or
  author them from English using `tag.tag_sentence("Your sentence here")`.
- **Tune difficulty** → `LOSE_THRESHOLD` in `game/game_logic.gd`, and the re-roll
  sentiment weighting bags (`PLAYER_BAG` / `ENEMY_BAG`) in `game/main.gd`.
- Always re-run `uv run wordplay-generate` after editing the lexicon.

## Ideas / next steps

- Multi-sentence characters and longer battles.
- Make re-rolls strategic rather than pure chance (e.g. spend "energy", preview odds).
- Verb editing and more parts of speech.
- Richer sentiment via a real model instead of the lexicon.

## License

TBD.
