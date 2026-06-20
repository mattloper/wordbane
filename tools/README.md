# wordplay-tools

Build-time NLP tooling for the Wordplay game. Generates the two data files the
game reads: `../game/data/word_bank.json` (characters + word pools) and
`../game/data/dictionary.json` (50k words tagged with part of speech + sentiment,
used to validate typed word-ladders).

See the [top-level README](../README.md) for full setup. Quick version:

```bash
cd tools
uv venv
uv pip install -e ".[dev]"                       # installs spaCy + nltk + pytest
uv run python -m spacy download en_core_web_sm    # one-time English model
uv run python -m nltk.downloader wordnet omw-1.4 sentiwordnet  # one-time corpora
uv run wordplay-generate                          # -> ../game/data/word_bank.json
uv run wordplay-dictionary                        # -> ../game/data/dictionary.json
uv run pytest
```

- `parse.py` uses spaCy's dependency parse to find each character's owner (the
  grammatical subject). `wordplay-generate --no-spacy` uses a heuristic fallback.
- `dictionary.py` tags WordNet words with POS (all senses) + SentiWordNet
  sentiment; the curated lexicon overrides tags for words it defines.
