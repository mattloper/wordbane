"""Build ``word_bank.json`` for the Godot game.

Combines the curated lexicon (always) with optional NLTK enrichment (if present)
into a single JSON file containing:

- ``word_pools``  : {pos: {sentiment: [words]}} — the draw pools for re-rolls
- ``characters``  : pre-tokenized starting sentences
- ``sentiments``  : the sentiment vocabulary (so the game stays in sync)

Run via the console script:  ``wordplay-generate``  (see pyproject.toml).
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from . import lexicon

# Default output: the Godot project's data folder, resolved from this file.
_DEFAULT_OUT = (
    Path(__file__).resolve().parents[2] / "game" / "data" / "word_bank.json"
)


def _enrich_with_nltk(pools: dict[str, dict[str, list[str]]]) -> int:
    """Best-effort: pull extra adjectives/nouns from WordNet, tagged by SentiWordNet.

    Returns the number of words added. Silently does nothing if NLTK or its data
    is unavailable — the curated pools alone are always sufficient.
    """
    try:
        from nltk.corpus import sentiwordnet as swn
        from nltk.corpus import wordnet as wn
    except Exception:
        return 0

    existing = {w for sub in pools.values() for words in sub.values() for w in words}
    added = 0
    targets = [(lexicon.POS_ADJ, wn.ADJ), (lexicon.POS_NOUN, wn.NOUN)]
    try:
        for pos, wn_pos in targets:
            for synset in list(wn.all_synsets(wn_pos))[:4000]:
                lemma = synset.lemmas()[0].name()
                if "_" in lemma or not lemma.isalpha() or len(lemma) < 3:
                    continue
                lemma = lemma.lower()
                if lemma in existing:
                    continue
                senti = list(swn.senti_synsets(lemma, wn_pos))
                if not senti:
                    continue
                s = senti[0]
                if s.pos_score() >= 0.5:
                    sentiment = lexicon.POSITIVE
                elif s.neg_score() >= 0.5:
                    sentiment = lexicon.NEGATIVE
                else:
                    continue  # only add clearly-charged words from NLP
                pools[pos][sentiment].append(lemma)
                existing.add(lemma)
                added += 1
    except Exception:
        return added
    return added


def build_bank(use_nltk: bool = True) -> dict:
    """Assemble the full word-bank dict."""
    pools = lexicon.all_pools()
    enriched = _enrich_with_nltk(pools) if use_nltk else 0
    return {
        "schema_version": 1,
        "sentiments": list(lexicon.SENTIMENTS),
        "parts_of_speech": [lexicon.POS_ADJ, lexicon.POS_NOUN],
        "word_pools": pools,
        "characters": lexicon.character_templates(),
        "_meta": {"nltk_words_added": enriched},
    }


def write_bank(out_path: Path, use_nltk: bool = True) -> dict:
    bank = build_bank(use_nltk=use_nltk)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(bank, indent=2) + "\n", encoding="utf-8")
    return bank


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate the wordplay word bank.")
    parser.add_argument(
        "-o", "--out", type=Path, default=_DEFAULT_OUT,
        help=f"Output JSON path (default: {_DEFAULT_OUT})",
    )
    parser.add_argument(
        "--no-nltk", action="store_true",
        help="Skip optional NLTK enrichment (curated lexicon only).",
    )
    args = parser.parse_args(argv)

    bank = write_bank(args.out, use_nltk=not args.no_nltk)
    pools = bank["word_pools"]
    counts = {
        pos: {s: len(w) for s, w in sub.items()} for pos, sub in pools.items()
    }
    print(f"Wrote {args.out}")
    print(f"  word counts: {counts}")
    print(f"  characters : {[c['name'] for c in bank['characters']]}")
    print(f"  nltk added : {bank['_meta']['nltk_words_added']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
