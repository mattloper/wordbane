"""Tests for the word-bank generator and syntax parser.

The parser tests run twice in spirit: the heuristic path (no spaCy) is always
exercised so the suite passes offline; the spaCy path is exercised only when the
model is installed.
"""

from __future__ import annotations

import json

import pytest

from wordplay_tools import generate, lexicon, parse


def _owner(char: dict) -> dict | None:
    for t in char["tokens"]:
        if t["kind"] == lexicon.KIND_CREATURE and t.get("is_owner"):
            return t
    return None


def _items(char: dict) -> list[dict]:
    return sorted(
        (t for t in char["tokens"] if t["kind"] == lexicon.KIND_ITEM),
        key=lambda t: t["item_index"],
    )


# --- pools -------------------------------------------------------------------

def test_pools_have_all_kinds_and_sentiments():
    pools = lexicon.build_pools()
    for kind in (lexicon.KIND_CREATURE, lexicon.KIND_ITEM, lexicon.KIND_ADJ):
        for sentiment in lexicon.SENTIMENTS:
            assert pools[kind][sentiment], (kind, sentiment)


def test_item_pool_entries_have_type_and_base():
    pools = lexicon.build_pools()
    for sentiment in lexicon.SENTIMENTS:
        for entry in pools[lexicon.KIND_ITEM][sentiment]:
            assert entry["item_type"] in lexicon.ITEM_TYPES
            assert entry["base"] >= 1


def test_adjective_pool_entries_have_mult():
    pools = lexicon.build_pools()
    for sentiment in lexicon.SENTIMENTS:
        for entry in pools[lexicon.KIND_ADJ][sentiment]:
            assert entry["mult"] > 0


def test_all_four_item_types_present():
    pools = lexicon.build_pools()
    seen = {
        e["item_type"]
        for sub in pools[lexicon.KIND_ITEM].values()
        for e in sub
    }
    assert seen == set(lexicon.ITEM_TYPES)


# --- parsing (heuristic path, always available) ------------------------------

def test_heuristic_finds_owner_and_items():
    spec = lexicon.CHARACTER_SENTENCES[0]  # Dragon
    char = parse.parse_character(spec, nlp=None)
    owner = _owner(char)
    assert owner is not None and owner["text"] == "dragon"
    items = _items(char)
    assert [i["text"] for i in items] == ["knife", "hex"]
    assert items[0]["item_type"] == lexicon.HP_ATTACK
    assert items[1]["item_type"] == lexicon.WORD_ATTACK


def test_adjective_attaches_to_its_noun():
    char = parse.parse_character(lexicon.CHARACTER_SENTENCES[0], nlp=None)
    adjs = {t["text"]: t for t in char["tokens"] if t["kind"] == lexicon.KIND_ADJ}
    assert adjs["fierce"]["attaches"] == "owner"
    assert adjs["sharp"]["attaches"] == "item:0"
    assert adjs["wicked"]["attaches"] == "item:1"


def test_max_hp_is_word_count():
    char = parse.parse_character(lexicon.CHARACTER_SENTENCES[0], nlp=None)
    assert char["max_hp"] == len(char["tokens"])
    assert char["max_hp"] > 0


def test_owner_is_not_an_item():
    for spec in lexicon.CHARACTER_SENTENCES:
        char = parse.parse_character(spec, nlp=None)
        owner = _owner(char)
        assert owner is not None
        assert "item_index" not in owner


# --- generated bank ----------------------------------------------------------

def test_build_bank_structure():
    bank = generate.build_bank(use_spacy=False)
    assert bank["schema_version"] == 2
    assert set(bank["item_types"]) == set(lexicon.ITEM_TYPES)
    for char in bank["characters"]:
        assert _owner(char) is not None
        assert len(_items(char)) >= 1
        assert char["item_order"] == sorted(char["item_order"])


def test_each_role_has_offensive_capability():
    bank = generate.build_bank(use_spacy=False)
    for char in bank["characters"]:
        types = {i["item_type"] for i in _items(char)}
        assert types & set(lexicon.OFFENSIVE_TYPES), char["name"]


def test_every_player_can_randomize():
    # Every player needs a word-randomizer item so "click an enemy word to
    # randomize it" is always an available action.
    bank = generate.build_bank(use_spacy=False)
    for char in bank["characters"]:
        if char["role"] != "player":
            continue
        types = {i["item_type"] for i in _items(char)}
        assert lexicon.WORD_ATTACK in types, char["name"]


def test_write_bank_roundtrip(tmp_path):
    out = tmp_path / "word_bank.json"
    generate.write_bank(out, use_spacy=False)
    loaded = json.loads(out.read_text())
    assert loaded["characters"]
    assert loaded["pools"]["item"]["negative"]


# --- spaCy path (only if installed) ------------------------------------------

@pytest.mark.skipif(parse.load_nlp() is None, reason="spaCy model not installed")
def test_spacy_finds_subject_as_owner():
    char = parse.parse_character(lexicon.CHARACTER_SENTENCES[0])  # Dragon
    owner = _owner(char)
    assert owner["text"] == "dragon"
    assert char["owner_method"].startswith("spacy")
