"""Part-of-speech + sentiment tagging for arbitrary sentences.

This is the optional "real NLP" entry point. Given a raw sentence it returns the
same token structure used by the character templates, so you can author new
characters by typing English instead of hand-tagging.

NLTK is imported lazily and is entirely optional. If it (or its data) is missing,
we fall back to looking words up in the curated lexicon, and finally to a neutral
guess. Either way you get usable tokens.
"""

from __future__ import annotations

from . import lexicon

# Build reverse lookups once: word -> (pos, sentiment) from the curated pools.
_WORD_INDEX: dict[str, tuple[str, str]] = {}
for _pos, _pools in lexicon.all_pools().items():
    for _sent, _words in _pools.items():
        for _w in _words:
            _WORD_INDEX.setdefault(_w.lower(), (_pos, _sent))


def _nltk_pos_sentiment(word: str):
    """Return (pos, sentiment) using NLTK, or None if NLTK is unavailable."""
    try:
        import nltk
        from nltk.corpus import sentiwordnet as swn
        from nltk.corpus import wordnet as wn
    except Exception:
        return None

    try:
        tag = nltk.pos_tag([word])[0][1]
    except Exception:
        return None

    if tag.startswith("JJ"):
        pos = lexicon.POS_ADJ
        wn_pos = wn.ADJ
    elif tag.startswith("NN"):
        pos = lexicon.POS_NOUN
        wn_pos = wn.NOUN
    else:
        return None  # not a target word (verb, determiner, ...)

    sentiment = lexicon.NEUTRAL
    try:
        synsets = list(swn.senti_synsets(word, wn_pos))
        if synsets:
            s = synsets[0]
            if s.pos_score() > s.neg_score() and s.pos_score() >= 0.25:
                sentiment = lexicon.POSITIVE
            elif s.neg_score() > s.pos_score() and s.neg_score() >= 0.25:
                sentiment = lexicon.NEGATIVE
    except Exception:
        pass
    return pos, sentiment


def classify_word(word: str) -> tuple[str | None, str | None]:
    """Classify a single word into (pos, sentiment).

    Curated lexicon wins (it's authoritative and on-theme); NLTK fills gaps.
    Returns (None, None) for function words / verbs we don't make editable.
    """
    key = word.lower().strip(".,!?;:\"'")
    if key in _WORD_INDEX:
        return _WORD_INDEX[key]
    result = _nltk_pos_sentiment(key)
    if result is not None:
        return result
    return None, None


def tag_sentence(sentence: str) -> list[dict]:
    """Tokenize a raw sentence into game tokens (see lexicon._tok)."""
    tokens: list[dict] = []
    for raw in sentence.split():
        word = raw.strip(".,!?;:\"'")
        pos, sentiment = classify_word(word)
        if pos in (lexicon.POS_ADJ, lexicon.POS_NOUN):
            tokens.append(
                {"text": word, "editable": True, "pos": pos, "sentiment": sentiment}
            )
        else:
            tokens.append({"text": raw, "editable": False})
    return tokens
