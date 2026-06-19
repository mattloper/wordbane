"""Wordplay build-time tooling.

This package generates the data the Godot game consumes: a sentiment- and
part-of-speech-tagged word bank plus pre-tokenized character "sentences".

The NLP happens here, at build time, so the game itself never needs a Python
runtime or model weights — it just reads ``word_bank.json``.
"""

__all__ = ["lexicon", "generate", "tag"]
