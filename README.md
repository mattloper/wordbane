# Wordplay

A tiny turn-based **word battler**. Each enemy is a **pool of letters**; you beat
it by typing real words made from those letters. Rare letters (`j x q z`) hit
hardest, but you can whittle anything down with common ones — so you never get
stuck, you just get rewarded for a good vocabulary.

> 🐉 A savage **dragon** wields a cruel **axe** and a wicked **hex**.
> Its letters: `a c e h u x`. Type `hue` (h+e+u = 6) or land the big `hex` letters…

It runs in a browser with **no install** and is **easy to tinker with** — most of
the game is plain JSON you can edit in a text editor.

## Play it

It's a static web page; it just needs to be *served* (browsers block loading data
straight from a file). From the repo root:

```bash
python3 -m http.server 8000
```

then open **<http://localhost:8000/web/>**.

*(Once it's hosted on GitHub Pages it'll be a plain link — no server needed.)*

## How it plays

- Each enemy shows its **letters** and an **HP bar** (= the total rarity weight of
  those letters). Common letters are worth 1; `k`=5, `j x`=8, `q z`=10.
- On your turn, **type any real word** that uses at least one of its letters. It
  deals damage equal to the rarity weight of the letters it covers.
- **Drain the HP to 0** to clear the chapter and pick a **reward** (boon).
- The enemy **hits you every turn**, harder the deeper you go — so kill fast.
- You **can't reuse a word** in a run, and you can't just type the enemy's own
  weapon words. You lose at 0 HP. Score = damage dealt + how deep you reach.

## Modify it

You can change a *lot* without touching code — it's all plain JSON in **`data/`**:

| To change… | Edit | Example |
|---|---|---|
| **Tuning & rewards** | `data/rules.json` | letter values, starting HP, score rates, the boon list |
| **Monsters, weapons, adjectives** | `data/word_bank.json` | add to `pools.creature.negative`, `pools.item.negative`, … |
| **A monster/weapon's emoji** | `data/icons.json` | `"griffin": "🦅"` |

Edit a file, refresh the browser — done. (Both the web and Godot versions read
the same `data/`, so a change shows up in both.)

Want to change the **rules themselves**? The game logic is small, readable
JavaScript in **`web/src/`** (`lexicon.js`, `poolbattle.js`, `gauntlet.js`,
`boons.js`). Edit, refresh — no build step.

> After changing shared logic, run `node web/test/conformance.js` — it checks the
> JS against a set of golden vectors so the two builds stay in sync. See
> [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## What's in here

```
wordplay/
├── web/     ▶ the browser game — play & hack this (no install)
├── data/    ★ the game's content — plain JSON, edit to change the game
├── godot/     a fancier build in the Godot engine, with AI-generated art
├── tools/     optional Python scripts that regenerate the word list
├── art/       optional AI-art pipeline (Draw Things) for the Godot build
└── docs/      how it's built, for developers
```

There are **two builds** of the same game:

- **`web/`** — the shared, install-free one. This is the one to play and modify.
- **`godot/`** — a local "deluxe" version in the [Godot](https://godotengine.org/)
  engine that draws each monster with a local AI image model. Nice to look at, but
  needs a Mac + [Draw Things](https://drawthings.ai/) set up; the web version is
  the accessible one.

Both read the same `data/` and are held in sync by a shared test suite — see
**[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** for how that works, the Godot
build, and the word-list generator.

## License

TBD.
