# wordplay-tools

Build-time NLP tooling for the Wordplay game. Generates `../game/data/word_bank.json`.

See the [top-level README](../README.md) for full setup. Quick version:

```bash
cd tools
uv venv
uv pip install -e ".[dev]"      # add ",nlp" for optional NLTK enrichment
uv run wordplay-generate        # writes ../game/data/word_bank.json
uv run pytest
```
