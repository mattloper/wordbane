# wordplay-tools

Build-time tooling that regenerates the two committed data files: `../data/word_bank.json`
(the enemy vocabulary pools — creatures, weapons, adjectives) and
`../data/dictionary.json` (the ~50k valid words, a plain sorted list the game uses
to check "is this a real word?").

You **don't need this to play or mod** — both files are committed. Regenerate only
if you edit the curated vocabulary. Quick version:

```bash
cd tools
uv venv
uv pip install -e ".[dev]"                        # installs spaCy + nltk + pytest
uv run python -m spacy download en_core_web_sm     # one-time English model
uv run python -m nltk.downloader wordnet omw-1.4   # one-time WordNet corpus
uv run wordplay-generate                           # -> ../data/word_bank.json
uv run wordplay-dictionary                         # -> ../data/dictionary.json
uv run pytest
```

- `lexicon.py` — the curated game vocabulary (creatures, typed weapons with base
  power, multiplier adjectives). This is the source of truth for `word_bank.json`.
- `dictionary.py` — filters the WordNet word set into a gameable list (length +
  membership only; the game no longer uses part-of-speech or sentiment).
- `parse.py` — spaCy sentence parsing used by the word-bank generator (with a
  heuristic fallback via `wordplay-generate --no-spacy`).
