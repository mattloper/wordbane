"""Build the in-game validation dictionary: word -> {pos, sentiment}.

The letter-ladder combat needs to answer three things about any word a player
types: is it real, what part of speech is it, and is it positive/negative? This
builds that lookup once, at build time, so the game ships a plain JSON table.

Source: WordNet for the word set + part of speech, SentiWordNet for sentiment.
Our curated lexicon (lexicon.py) overrides tags for words it knows, so the core
game vocabulary stays authoritative and on-theme.

Run via the console script:  ``wordplay-dictionary``  (see pyproject.toml).
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

from . import lexicon

# Game-facing parts of speech.
POS_NOUN = "noun"
POS_ADJ = "adjective"
POS_VERB = "verb"
POS_OTHER = "other"

# Keep words short enough to be gameable and the file small.
MIN_LEN = 3
MAX_LEN = 9

# SentiWordNet score gap needed to call a word positive/negative (else neutral).
SENTI_MARGIN = 0.15

_WN_POS = {"n": POS_NOUN, "a": POS_ADJ, "s": POS_ADJ, "v": POS_VERB, "r": POS_OTHER}

_DEFAULT_OUT = (
    Path(__file__).resolve().parents[2] / "game" / "data" / "dictionary.json"
)


def _all_pos(synsets) -> list[str]:
    """Every game-POS the word can be (e.g. 'fan' is both noun and verb).

    Stored as a list so the game accepts a word in any of its valid roles —
    tagging a single 'primary' POS wrongly rejects common words.
    """
    found = {_WN_POS.get(s.pos(), POS_OTHER) for s in synsets}
    order = [POS_NOUN, POS_ADJ, POS_VERB, POS_OTHER]
    return [p for p in order if p in found]


def _sentiment(word: str, swn) -> str:
    """Average SentiWordNet pos/neg over ALL the word's senses, then threshold."""
    senses = list(swn.senti_synsets(word))
    if not senses:
        return lexicon.NEUTRAL
    pos = sum(s.pos_score() for s in senses) / len(senses)
    neg = sum(s.neg_score() for s in senses) / len(senses)
    if pos - neg >= SENTI_MARGIN:
        return lexicon.POSITIVE
    if neg - pos >= SENTI_MARGIN:
        return lexicon.NEGATIVE
    return lexicon.NEUTRAL


def _curated_overrides() -> dict:
    """Tags for words our lexicon already defines, mapped to game POS names."""
    kind_to_pos = {
        lexicon.KIND_CREATURE: POS_NOUN,
        lexicon.KIND_ITEM: POS_NOUN,
        lexicon.KIND_ADJ: POS_ADJ,
    }
    out: dict = {}
    for word, meta in lexicon.word_index().items():
        pos = kind_to_pos.get(meta["kind"])
        if pos:
            out[word] = {"pos": [pos], "sentiment": meta["sentiment"]}
    return out


def build_dictionary() -> dict:
    from nltk.corpus import sentiwordnet as swn
    from nltk.corpus import wordnet as wn

    entries: dict = {}
    for lemma in wn.all_lemma_names():
        if not lemma.isalpha() or not lemma.islower():
            continue
        if not (MIN_LEN <= len(lemma) <= MAX_LEN):
            continue
        synsets = wn.synsets(lemma)
        if not synsets:
            continue
        entries[lemma] = {
            "pos": _all_pos(synsets),
            "sentiment": _sentiment(lemma, swn),
        }

    entries.update(_curated_overrides())  # curated tags win
    return entries


def write_dictionary(out_path: Path) -> dict:
    entries = build_dictionary()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema_version": 1,
        "min_len": MIN_LEN,
        "max_len": MAX_LEN,
        "count": len(entries),
        "words": entries,
    }
    out_path.write_text(json.dumps(payload) + "\n", encoding="utf-8")
    return payload


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build the validation dictionary.")
    parser.add_argument("-o", "--out", type=Path, default=_DEFAULT_OUT)
    args = parser.parse_args(argv)

    payload = write_dictionary(args.out)
    words = payload["words"]
    by_pos = Counter(p for v in words.values() for p in v["pos"])
    by_sent = Counter(v["sentiment"] for v in words.values())
    size_kb = args.out.stat().st_size / 1024
    print(f"Wrote {args.out}  ({payload['count']} words, {size_kb:.0f} KB)")
    print(f"  by pos      : {dict(by_pos)}")
    print(f"  by sentiment: {dict(by_sent)}")
    for w in ["dragon", "darn", "road", "fine", "knife", "nag", "adorn", "gore"]:
        print(f"  {w:8} -> {words.get(w, 'NOT FOUND')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
