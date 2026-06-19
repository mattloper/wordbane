# wordplay-tools

Build-time NLP tooling for the Wordplay game. Generates `../game/data/word_bank.json`.

See the [top-level README](../README.md) for full setup. Quick version:

```bash
cd tools
uv venv
uv pip install -e ".[dev]"                      # installs spaCy + pytest
uv run python -m spacy download en_core_web_sm   # one-time English model
uv run wordplay-generate                         # writes ../game/data/word_bank.json
uv run pytest
```

`parse.py` uses spaCy's dependency parse to find each character's owner (the
grammatical subject). Run `wordplay-generate --no-spacy` to use the heuristic
fallback instead.
