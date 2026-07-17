"""Build the in-game validation word list from ESDB/SCOWL instead of WordNet.

Experiment: the WordNet list (dictionary.py) only carries base forms, so the
game patches plurals up at runtime with a heuristic. The English Speller
Database (ESDB — the SCOWL v2 rewrite, https://github.com/en-wl/wordlist)
stores inflected forms *and* a lemma_id linking them, which gives us both
halves for free:

  - inflections are real dictionary entries ('wolves', 'ran', 'running'), and
  - forms sharing a lemma_id are the same word, so the no-reuse rule can
    collapse 'run'/'ran'/'running' by id instead of guessing with pluralize.

Output schema (version 3): ``words`` maps each form to its sorted list of
lemma ids. Curated lexicon words missing from SCOWL get an empty list — the
JS side falls back to the plural heuristic for those.

This needs a built ``scowl.db``: clone https://github.com/en-wl/wordlist
(branch ``v2``) and run ``make`` (Python 3.7+, SQLite 3.33+). Then:

    wordplay-dictionary-esdb --db path/to/scowl.db
"""

from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path

from .dictionary import MAX_LEN, MIN_LEN, _DEFAULT_OUT, _curated_words

# SCOWL size 60 is the "large" list — big enough to feel like "any real word
# works", small enough to stay clear of the junk in the 70+ lists.
DEFAULT_SIZE = 60

# One row per distinct (form, lemma) pair: American spellings only (spelling
# '_' = common to all, 'A' = American; region '' = universal, 'US'), no rare
# variants, plain lowercase ASCII words only (drops possessives, hyphens,
# abbreviations, and proper nouns in one stroke).
_QUERY = """
WITH pairs AS (
  SELECT DISTINCT
         word AS form,
         lemma_id AS id
  FROM scowl_
  WHERE size <= :size
    AND spelling IN ('_', 'A')
    AND region IN ('', 'US')
    AND variant_level <= 1
    AND word GLOB '[a-z]*'
    AND word NOT GLOB '*[^a-z]*'
    AND length(word) BETWEEN :min_len AND :max_len
)
SELECT form, id FROM pairs ORDER BY form, id
"""


def build_dictionary(conn: sqlite3.Connection, size: int = DEFAULT_SIZE) -> dict[str, list[int]]:
    """form -> sorted lemma ids, plus the curated game vocabulary (empty ids)."""
    words: dict[str, list[int]] = {}
    params = {"size": size, "min_len": MIN_LEN, "max_len": MAX_LEN}
    for form, lemma_id in conn.execute(_QUERY, params):
        words.setdefault(form, []).append(lemma_id)

    # Same guarantee as the WordNet build: everything the enemy sentences use
    # (creatures/items/adjectives) is always a valid word to type.
    for w in _curated_words():
        words.setdefault(w, [])
    return dict(sorted(words.items()))


def write_dictionary(db_path: Path, out_path: Path, size: int = DEFAULT_SIZE) -> dict:
    with sqlite3.connect(db_path) as conn:
        words = build_dictionary(conn, size)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema_version": 3,
        "source": "esdb-scowl",
        "scowl_size": size,
        "min_len": MIN_LEN,
        "max_len": MAX_LEN,
        "count": len(words),
        "words": words,
    }
    out_path.write_text(json.dumps(payload) + "\n", encoding="utf-8")
    return payload


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Build the validation dictionary from ESDB/SCOWL (scowl.db)."
    )
    parser.add_argument("--db", type=Path, required=True, help="path to a built scowl.db")
    parser.add_argument("-o", "--out", type=Path, default=_DEFAULT_OUT)
    parser.add_argument("--size", type=int, default=DEFAULT_SIZE, help="max SCOWL size (default 60)")
    args = parser.parse_args(argv)

    payload = write_dictionary(args.db, args.out, args.size)
    words = payload["words"]
    size_kb = args.out.stat().st_size / 1024
    print(f"Wrote {args.out}  ({payload['count']} words, {size_kb:.0f} KB)")
    for w in ["dragon", "darn", "road", "fine", "knife", "nag", "adorn", "gore"]:
        print(f"  {w:8} -> {'ok' if w in words else 'NOT FOUND'}")
    # The point of the experiment: inflected forms are in, and share lemma ids.
    for a, b in [("wolf", "wolves"), ("run", "running"), ("quality", "qualities")]:
        shared = set(words.get(a, [])) & set(words.get(b, []))
        print(f"  {a}/{b} -> {'same lemma ' + str(sorted(shared)) if shared else 'NO SHARED LEMMA'}")
    uncovered = sorted(w for w, ids in words.items() if not ids)
    print(f"  curated words not in SCOWL (plural-heuristic fallback): {len(uncovered)}")
    if uncovered:
        print(f"    {', '.join(uncovered[:12])}{' ...' if len(uncovered) > 12 else ''}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
