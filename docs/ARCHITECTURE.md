# Architecture

How Wordplay is put together, for anyone changing more than the JSON in `shared_data/`.
For playing and light modding, the top-level [README](../README.md) is enough.

## Two builds, one source of truth

There are two implementations of the same game:

- **`web_version/`** — plain HTML/JS, emoji art, no build step. The shared, accessible
  build; the one meant to be played and hacked.
- **`godot_version/`** — a [Godot 4](https://godotengine.org/) project. The same game, plus
  a local AI-art pipeline that draws each monster (see [Art](#art-godot-only)). Run
  from source; it's the "deluxe" local build.

Both read the same **`shared_data/`** and are kept honest by a shared **conformance
suite**, so they can't quietly drift apart.

### Shared data (`shared_data/`)

| file | what |
|---|---|
| `rules.json` | tuning: letter weights, HP/score numbers, the boon catalog |
| `word_bank.json` | enemy vocabulary pools (creatures / items / adjectives) |
| `icons.json` | word → emoji clipart |
| `dictionary.json` | the ~50k valid words (a plain sorted list) |
| `conformance.json` | golden test vectors (see below) |

The web build fetches these over HTTP; the Godot build reads them with
`res://../shared_data/…` (which resolves to the repo root when run from source).

### Conformance: how drift is prevented

`shared_data/conformance.json` is a language-neutral list of `input → expected` vectors
for the pure logic — letter scoring, damage, `boon.apply`, the RNG stream, and a
full seeded enemy generation. **Both** builds run the same file:

```bash
node web_version/test/conformance.js                                 # the JS core
godot --headless --path godot_version --script res://selftest.gd     # the Godot core (+ more)
```

If the two implementations diverge, one of these fails. When you change shared
logic, update `conformance.json` and make sure both pass.

The randomness is a seedable **mulberry32** PRNG (`rng.js` / `rng.gd`) — identical
32-bit stream from the same seed in either language — so even a whole seeded run is
reproducible across the two builds.

### The core modules

The logic is a small set of pure modules, mirrored 1:1:

| concept | web | godot |
|---|---|---|
| letter scoring + dictionary | `web_version/src/lexicon.js` | `godot_version/core/lexicon.gd` |
| one battle | `web_version/src/poolbattle.js` | `godot_version/core/pool_battle.gd` |
| enemy generation | `web_version/src/gauntlet.js` | `godot_version/core/gauntlet.gd` |
| rewards | `web_version/src/boons.js` | `godot_version/core/boons.gd` |
| RNG | `web_version/src/rng.js` | `godot_version/core/rng.gd` |
| tuning/catalog loader | `web_version/src/rules.js` | `godot_version/core/rules.gd` |

The view layers (`web_version/src/game.js`, `godot_version/pool_gauntlet.gd`) are separate and do
not share code — only data and the conformance contract.

## Art (Godot only)

The web build uses emoji. The Godot build generates a picture of each monster (with
its weapons) using [Draw Things](https://drawthings.ai/), a local diffusion app:

```
godot_version/  ──HTTP──▶  ai_art_server/wordplay_art/server.py  ──gRPC──▶  Draw Things
                   (a tiny daemon; caches PNGs in .cache/)
```

`ai_art_server/` is a [uv](https://docs.astral.sh/uv/) Python project. One endpoint,
`/image?kind=&subject=`, covers portraits, boon icons, and tombstones. The Godot
`Art` node launches and health-checks the daemon, prefetches the next chapter, and
falls back to emoji if it's down. This needs a Mac + Draw Things + models, which is
why it's the local-only build.

## Generating the word lists (`wordlist_generator/`)

`shared_data/word_bank.json` and `shared_data/dictionary.json` are committed, so you don't need
this to play or mod. To regenerate (Python / uv):

```bash
cd wordlist_generator
uv venv && uv pip install -e ".[dev]"
uv run python -m spacy download en_core_web_sm   # one-time
uv run wordplay-generate      # -> ../shared_data/word_bank.json (curated creatures/items/adjectives)
uv run wordplay-dictionary    # -> ../shared_data/dictionary.json (WordNet word set, filtered)
uv run pytest
```

The curated game vocabulary lives in `wordlist_generator/wordplay_tools/lexicon.py`. Editing
`shared_data/word_bank.json` directly is fine for quick mods, but a regenerate will
overwrite it — put lasting changes in `lexicon.py`.

## Testing

```bash
node web_version/test/conformance.js                                 # JS core vs golden vectors
godot --headless --path godot_version --script res://selftest.gd     # Godot core + conformance
godot --headless --path godot_version --script res://balance.gd      # difficulty-curve harness
cd wordlist_generator && uv run pytest                                    # the generators
```

## Adding things

- **A monster/weapon:** add the word to the right pool in `shared_data/word_bank.json` and
  an emoji in `shared_data/icons.json`. (Both builds pick it up.)
- **A boon:** add it to `rules.json` `boons.catalog`, implement its effect in
  `boons.apply` on **both** sides, add a `boon_apply` vector to `conformance.json`,
  and an emoji in `icons.json` (+ a prompt in `ai_art_server/wordplay_art/artwork.py` for the
  Godot art).
- **A new art type (Godot):** add a prompt template to `artwork.py`'s `PROMPTS`; the
  single `/image` endpoint handles it.

### Porting gotchas (learned the hard way)

- JSON numbers parse as floats; a container `==` can be type-strict — compare
  numerically.
- The RNG masks to 32 bits and splits the multiply to avoid 64-bit overflow; don't
  "simplify" it.
- In GDScript, don't name methods `randf`/`randi_range` — they shadow globals.
