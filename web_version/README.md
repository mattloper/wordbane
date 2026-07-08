# Wordplay — web build

The browser version of Wordplay. Same game logic as the Godot version, drawn with
emoji, no install and no server needed. This is the **shared, hackable build** — the
one to play and modify.

## Play / run it

It needs to be *served* (browsers block loading data from `file://`). Two easy ways:

**Locally** — from the repo root:
```
python3 -m http.server 8000
```
then open <http://localhost:8000/web_version/>.

**Hosted (GitHub Pages)** — push the repo, enable Pages, and it's a link anyone can
open. Nothing to install.

## Modify it

Three levels, easiest first — you can change a *lot* without touching code:

1. **Tuning & rewards** — edit `shared_data/rules.json`: letter values, starting HP,
   score rates, the boon list. (Shared with the Godot version.)
2. **Monsters, weapons, adjectives** — edit `shared_data/word_bank.json`
   (`pools.creature.negative`, `pools.item.negative`, `pools.adjective.negative`).
   Add a monster/weapon and give it an emoji in `shared_data/icons.json`.
3. **Logic** — the core is small, readable ES modules in `web_version/src/`
   (`lexicon.js`, `poolbattle.js`, `gauntlet.js`, `boons.js`, `rng.js`). Edit,
   refresh the browser. No build step.

## Don't break parity with the Godot version

Both builds read the same `shared_data/*.json` and are checked against the same golden
vectors. After changing shared logic, run:
```
node web_version/test/conformance.js      # -> "conformance: 35 passed, 0 failed"
```
If it fails, the JS and Godot logic have drifted apart.

## What's here
- `index.html` — the page (UI + CSS).
- `src/` — game logic (mirrors `godot_version/core/*.gd`) + `game.js` (the DOM app) + `icons.js` (emoji).
- `test/conformance.js` — runs the shared fixtures against the JS core.
