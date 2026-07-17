# wordplay-tools

Build-time tooling that regenerates the two committed data files: `../shared_data/word_bank.json`
(the enemy vocabulary pools — creatures, weapons, adjectives) and
`../shared_data/dictionary.json` (the ~50k valid words the game uses to check "is this a
real word?" — each form mapped to its SCOWL lemma ids, so inflections of one word are linked).

You **don't need this to play or mod** — both files are committed. Regenerate only
if you edit the curated vocabulary. Quick version:

```bash
cd wordlist_generator
uv venv
uv pip install -e ".[dev]"                        # installs spaCy + nltk + pytest
uv run python -m spacy download en_core_web_sm     # one-time English model
uv run wordplay-generate                           # -> ../shared_data/word_bank.json
uv run wordplay-dictionary-esdb --db path/to/scowl.db  # -> ../shared_data/dictionary.json
uv run pytest
```

The dictionary is built from **ESDB/SCOWL** (the English Speller Database,
<https://github.com/en-wl/wordlist> branch `v2`). Build `scowl.db` once with `make` in a
clone of that repo (Python 3.7+, SQLite 3.33+), then point `wordplay-dictionary-esdb` at it.
It takes American spellings up to SCOWL size 60, lowercase-ASCII-only forms, 3–9 letters.
Because ESDB stores inflected forms *and* the lemma id linking them, the game gets
'wolves'/'ran'/'running' as real entries and collapses forms of one lemma for the
no-reuse rule.

- `lexicon.py` — the curated game vocabulary (creatures, typed weapons with base
  power, multiplier adjectives). This is the source of truth for `word_bank.json`.
- `esdb.py` — builds the dictionary from a `scowl.db` (see above).
- `dictionary.py` — the previous WordNet-based dictionary build (base forms only,
  plural handling left to a runtime heuristic), kept for comparison via
  `wordplay-dictionary`; needs `uv run python -m nltk.downloader wordnet omw-1.4` once.
- `parse.py` — spaCy sentence parsing used by the word-bank generator (with a
  heuristic fallback via `wordplay-generate --no-spacy`).
