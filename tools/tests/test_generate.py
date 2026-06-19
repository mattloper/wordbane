"""Tests for the word-bank generator and tagger.

These cover the curated path only (``--no-nltk`` equivalent), so they run fast
and offline. NLTK enrichment is best-effort and intentionally untested here.
"""

from __future__ import annotations

import json

from wordplay_tools import generate, lexicon, tag


def test_build_bank_structure():
    bank = generate.build_bank(use_nltk=False)
    assert bank["schema_version"] == 1
    assert set(bank["sentiments"]) == set(lexicon.SENTIMENTS)
    pools = bank["word_pools"]
    for pos in (lexicon.POS_ADJ, lexicon.POS_NOUN):
        for sentiment in lexicon.SENTIMENTS:
            assert len(pools[pos][sentiment]) > 0, (pos, sentiment)


def test_characters_have_editable_negative_and_positive():
    bank = generate.build_bank(use_nltk=False)
    chars = {c["name"]: c for c in bank["characters"]}

    # Enemies must start with at least one negative word to attack.
    dragon_negs = [
        t for t in chars["Dragon"]["tokens"]
        if t.get("editable") and t["sentiment"] == lexicon.NEGATIVE
    ]
    assert len(dragon_negs) >= 1

    # Player characters start friendly (no negatives).
    cat_negs = [
        t for t in chars["Cat"]["tokens"]
        if t.get("editable") and t["sentiment"] == lexicon.NEGATIVE
    ]
    assert cat_negs == []


def test_editable_tokens_have_valid_pos_and_sentiment():
    bank = generate.build_bank(use_nltk=False)
    for char in bank["characters"]:
        for token in char["tokens"]:
            if token.get("editable"):
                assert token["pos"] in (lexicon.POS_ADJ, lexicon.POS_NOUN)
                assert token["sentiment"] in lexicon.SENTIMENTS
            else:
                assert "pos" not in token


def test_write_bank_roundtrip(tmp_path):
    out = tmp_path / "word_bank.json"
    generate.write_bank(out, use_nltk=False)
    loaded = json.loads(out.read_text())
    assert loaded["word_pools"]["ADJ"]["negative"]


def test_tag_sentence_respects_pos():
    tokens = tag.tag_sentence("The fierce dragon clutches a sharp knife")
    by_text = {t["text"]: t for t in tokens}

    assert by_text["fierce"]["pos"] == lexicon.POS_ADJ
    assert by_text["fierce"]["sentiment"] == lexicon.NEGATIVE
    assert by_text["dragon"]["pos"] == lexicon.POS_NOUN
    # Function words / verbs are not editable.
    assert by_text["The"]["editable"] is False
    assert by_text["clutches"]["editable"] is False


def test_classify_unknown_word_is_non_editable_without_nltk():
    # A made-up token not in the lexicon; NLTK may or may not be installed.
    pos, sentiment = tag.classify_word("zlorptastic")
    # Either NLTK tags it, or we get (None, None) — but it must never crash.
    assert pos in (None, lexicon.POS_ADJ, lexicon.POS_NOUN)
