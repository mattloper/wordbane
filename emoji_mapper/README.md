# wordbane-emoji

Maps every playable word to an emoji, offline, so the game can bonk an enemy with a
relevant emoji when you play a word — with **zero** machine learning at runtime.

It's a preprocess: embed the dictionary and the emoji vocabulary with a pinned
sentence-transformer, pick each word's nearest emoji, and write a static lookup the
game reads like any other data file.

## What it produces

- `../shared_data/word_emoji.json` — `{ "words": { "dragon": "🐉", ... } }`, the map the
  game ships. Only words that clear a confidence threshold are included; the rest fall
  through to a generic bonk at runtime.
- `../shared_data/word_emoji.manifest.json` — the reproducibility record: model id +
  resolved revision, emoji-vocab hash, input-dictionary hash, threshold, counts.

Both are layered *under* the hand-authored `shared_data/icons.json`, which always wins.
So humans curate the ~50 important monsters/weapons there; this fills the long tail.

## Regenerate

```bash
uv sync
uv run python -m wordbane_emoji.build          # dictionary -> word_emoji.json + manifest
```

Deterministic: same inputs + same model → byte-identical output. Word embeddings are
cached under `.cache/`, so re-runs after a dictionary tweak only embed the new words.

To refresh the emoji set itself (new Unicode emoji, better keywords):

```bash
uv run python -m wordbane_emoji.vocab          # regenerates data/emoji_vocab.json
```

## Knobs

`build.py` has the pinned `MODEL_ID`, the `THRESHOLD` (raise it for fewer/safer matches,
lower it for more coverage), and the `TEMPLATE` used to phrase each word for the encoder.
All three are recorded in the manifest so a run is fully described by it.
