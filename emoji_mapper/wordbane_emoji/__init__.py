"""Offline word -> emoji mapper for Wordbane.

Two steps, both deterministic and re-runnable:

  1. vocab.py  -> data/emoji_vocab.json   (emoji -> name + keywords; checked in)
  2. build.py  -> shared_data/word_emoji.json + .manifest.json

Only step 2 runs normally. Step 1 is rerun when you want to refresh the emoji set.
"""
