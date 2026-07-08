"""Build ``word_bank.json`` for the Godot game.

Combines the curated lexicon (draw pools + combat metadata) with syntax-parsed
character sentences (owner + items recovered via spaCy) into one JSON file:

- ``pools``       : {kind: {sentiment: [words+metadata]}} — re-roll draw pools
- ``characters``  : parsed combat-ready characters (tokens, items, max_hp, ...)
- ``item_types``  : the four item-type names (kept in sync with the game)

Run via the console script:  ``wordplay-generate``  (see pyproject.toml).
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from . import lexicon, parse

_DEFAULT_OUT = (
    Path(__file__).resolve().parents[2] / "data" / "word_bank.json"
)


def build_bank(use_spacy: bool = True) -> dict:
    nlp = parse.load_nlp() if use_spacy else None
    characters = parse.parse_all(lexicon.CHARACTER_SENTENCES, nlp=nlp)
    return {
        "schema_version": 2,
        "sentiments": list(lexicon.SENTIMENTS),
        "kinds": [lexicon.KIND_CREATURE, lexicon.KIND_ITEM, lexicon.KIND_ADJ],
        "item_types": list(lexicon.ITEM_TYPES),
        "offensive_types": list(lexicon.OFFENSIVE_TYPES),
        "defensive_types": list(lexicon.DEFENSIVE_TYPES),
        "pools": lexicon.build_pools(),
        "characters": characters,
        "_meta": {
            "owner_detection": "spacy" if nlp is not None else "heuristic",
        },
    }


def write_bank(out_path: Path, use_spacy: bool = True) -> dict:
    bank = build_bank(use_spacy=use_spacy)
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
        "--no-spacy", action="store_true",
        help="Skip spaCy and use the heuristic owner detector.",
    )
    args = parser.parse_args(argv)

    bank = write_bank(args.out, use_spacy=not args.no_spacy)
    print(f"Wrote {args.out}")
    print(f"  owner detection: {bank['_meta']['owner_detection']}")
    for c in bank["characters"]:
        owner = next(
            (t["text"] for t in c["tokens"]
             if t["kind"] == lexicon.KIND_CREATURE and t.get("is_owner")),
            "?",
        )
        items = [
            f"{t['text']}({t['item_type']})"
            for t in sorted(
                (t for t in c["tokens"] if t["kind"] == lexicon.KIND_ITEM),
                key=lambda t: t["item_index"],
            )
        ]
        print(f"  {c['role']:6} {c['name']:8} hp={c['max_hp']:2} "
              f"owner={owner:8} via {c['owner_method']:16} items={items}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
