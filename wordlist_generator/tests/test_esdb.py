"""Tests for the ESDB/SCOWL dictionary builder (esdb.py).

Runs against a tiny in-memory table shaped like the ``scowl_`` view, so no
built scowl.db is needed.
"""

from __future__ import annotations

import sqlite3

import pytest

from wordplay_tools import esdb
from wordplay_tools.dictionary import MAX_LEN, MIN_LEN, _curated_words


def _fake_db(rows: list[tuple]) -> sqlite3.Connection:
    """rows: (word, lemma_id, size, spelling, region, variant_level)"""
    conn = sqlite3.connect(":memory:")
    conn.execute(
        "CREATE TABLE scowl_ (word TEXT, lemma_id INT, size INT,"
        " spelling TEXT, region TEXT, variant_level INT)"
    )
    conn.executemany("INSERT INTO scowl_ VALUES (?,?,?,?,?,?)", rows)
    return conn


def _ok(word: str, lemma_id: int, **kw) -> tuple:
    """A row that passes every filter unless overridden."""
    d = {"size": 35, "spelling": "_", "region": "", "variant_level": 0}
    d.update(kw)
    return (word, lemma_id, d["size"], d["spelling"], d["region"], d["variant_level"])


def test_forms_grouped_by_lemma():
    conn = _fake_db([
        _ok("wolf", 7), _ok("wolf", 9),  # noun + verb lemma
        _ok("wolves", 7),
        _ok("wolves", 7, spelling="A", region="US"),  # dupes collapse
        _ok("quilt", 30),
    ])
    words = esdb.build_dictionary(conn)
    assert words["wolf"] == [7, 9]
    assert words["wolves"] == [7]
    assert set(words["wolf"]) & set(words["wolves"])  # same word for no-reuse
    assert not set(words["quilt"]) & set(words["wolf"])


def test_filters_size_spelling_region_variant():
    conn = _fake_db([
        _ok("keep", 1),
        _ok("huge", 2, size=70),                # too obscure
        _ok("colour", 3, spelling="B"),         # British spelling
        _ok("outback", 4, region="AU"),         # non-US region
        _ok("olde", 5, variant_level=2),        # rare variant
    ])
    words = esdb.build_dictionary(conn)
    curated = _curated_words()
    assert "keep" in words
    for w in ("huge", "colour", "outback", "olde"):
        assert w not in words or w in curated


def test_filters_shape_and_length():
    conn = _fake_db([
        _ok("fine", 1),
        _ok("Amsterdam", 2),      # capitalized (proper noun)
        _ok("o'clock", 3),        # punctuation
        _ok("ice-cream", 4),      # hyphen
        _ok("ox", 5),             # too short
        _ok("x" * (MAX_LEN + 1), 6),  # too long
        _ok("x" * MIN_LEN, 7),
        _ok("x" * MAX_LEN, 8),
    ])
    words = esdb.build_dictionary(conn)
    assert "fine" in words
    assert "x" * MIN_LEN in words and "x" * MAX_LEN in words
    curated = _curated_words()
    for w in ("Amsterdam", "o'clock", "ice-cream", "ox", "x" * (MAX_LEN + 1)):
        assert w not in words or w in curated


def test_curated_words_always_included():
    conn = _fake_db([_ok("fine", 1)])
    words = esdb.build_dictionary(conn)
    curated = _curated_words()
    assert curated <= set(words)
    # Curated words SCOWL doesn't know get no lemma ids (JS falls back to the
    # plural heuristic for those).
    assert all(words[w] == [] for w in curated if w != "fine")


def test_output_sorted():
    conn = _fake_db([_ok("zebra", 1), _ok("apple", 2)])
    words = esdb.build_dictionary(conn)
    keys = list(words)
    assert keys == sorted(keys)


def test_write_dictionary_payload(tmp_path):
    conn_rows = [_ok("fine", 1)]
    db_path = tmp_path / "scowl.db"
    conn = sqlite3.connect(db_path)
    conn.execute(
        "CREATE TABLE scowl_ (word TEXT, lemma_id INT, size INT,"
        " spelling TEXT, region TEXT, variant_level INT)"
    )
    conn.executemany("INSERT INTO scowl_ VALUES (?,?,?,?,?,?)", conn_rows)
    conn.commit()
    conn.close()

    out = tmp_path / "dictionary.json"
    payload = esdb.write_dictionary(db_path, out)
    assert payload["schema_version"] == 3
    assert payload["source"] == "esdb-scowl"
    assert payload["count"] == len(payload["words"])
    assert payload["words"]["fine"] == [1]
    assert out.exists()
