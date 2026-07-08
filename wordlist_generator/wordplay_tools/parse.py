"""Turn a character *sentence* into structured combat tokens.

The game rules require the **owner** (the character itself) to be found by
*syntax*: it's the grammatical subject. We use spaCy's dependency parse to find
the subject (``nsubj``) and to attach each adjective to the noun it modifies
(``amod``).

spaCy's *part-of-speech* tags are unreliable on terse, fantasy-flavored sentences
(it will call "bares" or "waves" a noun), so the **curated lexicon** is the
authority on each word's *kind* (creature / item / adjective / fixed). spaCy
provides the *structure* (which creature is the subject, what each adjective
modifies); the lexicon provides the *categories and values*. This hybrid is far
more robust than trusting either alone.

If spaCy isn't installed, a dependency-free heuristic is used (the creature-kind
noun is the owner). spaCy is the intended path and a declared dependency; the
fallback only keeps generation from hard-failing.
"""

from __future__ import annotations

import functools

from . import lexicon
from .lexicon import (
    KIND_ADJ, KIND_CREATURE, KIND_FIXED, KIND_ITEM,
    HP_ATTACK, NEUTRAL,
)


@functools.lru_cache(maxsize=1)
def load_nlp():
    """Load the spaCy English model once, or return None if unavailable."""
    try:
        import spacy
        return spacy.load("en_core_web_sm")
    except Exception:
        return None


def _meta(word: str, lex_index: dict) -> dict:
    return lex_index.get(word.lower().strip(".,!?;:\"'"), {})


def _build_token(text: str, kind: str, meta: dict, *, is_owner: bool = False,
                 item_index: int | None = None, attaches: str | None = None) -> dict:
    """Assemble one token dict from its role + curated metadata."""
    if kind == KIND_FIXED:
        return {"text": text, "kind": KIND_FIXED}
    tok: dict = {"text": text, "kind": kind, "sentiment": meta.get("sentiment", NEUTRAL)}
    if kind == KIND_CREATURE:
        tok["is_owner"] = is_owner
    elif kind == KIND_ITEM:
        tok["item_type"] = meta.get("item_type", HP_ATTACK)
        tok["base"] = meta.get("base", 1)
        tok["item_index"] = item_index
    elif kind == KIND_ADJ:
        tok["mult"] = meta.get("mult", 1.0)
        tok["attaches"] = attaches or "none"
    return tok


def _attach_label(pos: int | None, owner_pos: int | None,
                  item_index_by_pos: dict) -> str | None:
    """Map a noun's position to an attachment label, or None if it's not a noun."""
    if pos is None:
        return None
    if pos == owner_pos:
        return "owner"
    if pos in item_index_by_pos:
        return "item:%d" % item_index_by_pos[pos]
    return None


def _nearest_noun_attach(pos: int, owner_pos: int | None, item_index_by_pos: dict,
                         noun_positions: list[int]) -> str:
    """Attach an adjective to the closest noun (preferring one to the right)."""
    right = [p for p in noun_positions if p > pos]
    left = [p for p in noun_positions if p < pos]
    target = right[0] if right else (left[-1] if left else None)
    return _attach_label(target, owner_pos, item_index_by_pos) or "none"


def _assemble(words: list[str], kinds: list[str], owner_pos: int | None,
              attach_head: list[int | None], lex_index: dict) -> list[dict]:
    """Build the token list from per-word kinds + owner + adjective heads.

    ``attach_head[i]`` is the *position* of the noun adjective ``i`` modifies
    (or None to fall back to the nearest noun). Non-adjectives ignore it.
    """
    item_positions = [p for p, k in enumerate(kinds) if k == KIND_ITEM]
    item_index_by_pos = {p: idx for idx, p in enumerate(item_positions)}
    noun_positions = sorted(
        ([owner_pos] if owner_pos is not None else []) + item_positions
    )

    tokens: list[dict] = []
    for p, word in enumerate(words):
        meta = _meta(word, lex_index)
        kind = kinds[p]
        if p == owner_pos:
            tokens.append(_build_token(word, KIND_CREATURE, meta, is_owner=True))
        elif p in item_index_by_pos:
            tokens.append(_build_token(word, KIND_ITEM, meta,
                                       item_index=item_index_by_pos[p]))
        elif kind == KIND_ADJ:
            attaches = _attach_label(attach_head[p], owner_pos, item_index_by_pos)
            if attaches is None:
                attaches = _nearest_noun_attach(p, owner_pos, item_index_by_pos,
                                                noun_positions)
            tokens.append(_build_token(word, KIND_ADJ, meta, attaches=attaches))
        else:
            tokens.append(_build_token(word, KIND_FIXED, meta))
    return tokens


def _parse_spacy(text: str, lex_index: dict, nlp) -> tuple[list[dict], str]:
    doc = nlp(text)
    toks = [t for t in doc if not t.is_punct and not t.is_space]
    words = [t.text for t in toks]
    pos_by_doc_i = {t.i: p for p, t in enumerate(toks)}

    # Lexicon is the authority on kind (spaCy POS is too noisy here).
    kinds = [_meta(t.text, lex_index).get("kind", KIND_FIXED) for t in toks]
    creature_positions = [p for p, k in enumerate(kinds) if k == KIND_CREATURE]

    # Owner via syntax: the grammatical subject, reconciled with the lexicon.
    subj_pos = next(
        (p for p, t in enumerate(toks) if t.dep_ in ("nsubj", "nsubjpass")),
        None,
    )
    if subj_pos is not None and kinds[subj_pos] == KIND_CREATURE:
        owner_pos, method = subj_pos, "spacy:nsubj"
    elif subj_pos is not None and creature_positions:
        # spaCy found a subject but mis-tagged its part of speech; snap to the
        # nearest creature word.
        owner_pos = min(creature_positions, key=lambda p: abs(p - subj_pos))
        method = "spacy:nsubj+lexicon"
    elif creature_positions:
        owner_pos, method = creature_positions[0], "spacy:lexicon-fallback"
    else:
        owner_pos, method = None, "spacy:none"

    # Adjective attachment via dependency head (amod), mapped to our positions.
    attach_head: list[int | None] = [None] * len(toks)
    for p, t in enumerate(toks):
        if kinds[p] == KIND_ADJ:
            attach_head[p] = pos_by_doc_i.get(t.head.i)

    return _assemble(words, kinds, owner_pos, attach_head, lex_index), method


def _parse_heuristic(text: str, lex_index: dict) -> tuple[list[dict], str]:
    words = [w for w in text.replace(".", " ").replace(",", " ").split() if w]
    kinds = [_meta(w, lex_index).get("kind", KIND_FIXED) for w in words]
    owner_pos = next((p for p, k in enumerate(kinds) if k == KIND_CREATURE), None)
    # No syntax available: let attachment fall back to nearest-noun for every adj.
    attach_head: list[int | None] = [None] * len(words)
    return _assemble(words, kinds, owner_pos, attach_head, lex_index), "heuristic:creature-subject"


def parse_character(spec: dict, lex_index: dict | None = None, nlp="auto") -> dict:
    """Parse one {name, role, text} spec into a full character record."""
    lex_index = lex_index if lex_index is not None else lexicon.word_index()
    if nlp == "auto":
        nlp = load_nlp()

    if nlp is not None:
        tokens, method = _parse_spacy(spec["text"], lex_index, nlp)
    else:
        tokens, method = _parse_heuristic(spec["text"], lex_index)

    item_indices = sorted({
        t["item_index"] for t in tokens if t["kind"] == KIND_ITEM
    })
    return {
        "name": spec["name"],
        "role": spec["role"],
        "source": spec["text"],
        "owner_method": method,
        "max_hp": len(tokens),       # max HP = number of words
        "item_order": item_indices,  # enemy cycles through items in this order
        "tokens": tokens,
    }


def parse_all(specs: list[dict], nlp="auto") -> list[dict]:
    lex_index = lexicon.word_index()
    if nlp == "auto":
        nlp = load_nlp()
    return [parse_character(s, lex_index, nlp=nlp) for s in specs]
