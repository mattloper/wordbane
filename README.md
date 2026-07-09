# Wordbane

A word game. Each enemy is a set of letters; you beat it by typing real words made
from those letters. Longer, rarer words do more damage.

> A dragon shows up wielding a knife → its letters are `e f i k n`.
> Type `fine` → f+i+n+e = 7 damage. (Rarer letters are worth more: `k` is 5, `q` and
> `z` are 10.)

It runs in the browser. Most of the game is plain-text files you can edit.

## Play it

The files have to be served (a browser won't load them straight off disk). From this
folder:

```bash
python3 serve.py
```

Then open <http://localhost:8000/web_version/> and press Play.

## How to play

- Each enemy has a row of letters and an HP bar (its size is the letters' total
  worth: common letters = 1, `k` = 5, `j`/`x` = 8, `q`/`z` = 10).
- Type any real word that uses at least one of those letters. It does damage equal
  to the letters it covers, so longer and rarer-lettered words do more.
- Drain the HP to 0 to win the round and pick a reward.
- The enemy hits back every turn, harder the deeper you go.
- You can't repeat a word or type the enemy's own weapon. You lose at 0 HP.

## Change it

Much of the game is text in `shared_data/`:

| To change | Edit | Example |
|---|---|---|
| numbers & rewards | `shared_data/rules.json` | letter values, starting HP, the reward list |
| monsters & weapons | `shared_data/word_bank.json` | words in the `creature` / `item` pools |
| a monster's emoji | `shared_data/icons.json` | `"griffin": "🦅"` |

Edit a file and refresh the page.

The rules themselves are JavaScript in `web_version/src/`. After changing those, run
`node web_version/test/conformance.js` to check they still pass the tests (see
[docs/](docs/ARCHITECTURE.md)).

## What's in here

```
web_version/    the browser game
shared_data/    the game's content (text + art)
docs/           how it works
```

`wordlist_generator/` and `ai_art_server/` are optional tooling — see the docs.

The monster art is AI-generated and baked into `shared_data/art/`, so it ships with
the game. To regenerate it or add an art "skin," see `ai_art_server/` and the
[docs](docs/ARCHITECTURE.md).

There's also a Godot build (same game, generates art live) on the
[`godot`](../../tree/godot) branch; it needs a Mac set up for it.

## License

[MIT](LICENSE).
