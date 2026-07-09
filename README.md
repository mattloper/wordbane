# Wordbane

A tiny **word battle** game. Each enemy is a bunch of **letters**; you beat it by
typing real words made from those letters. Bigger, rarer words hit harder.

> A dragon shows up wielding a **knife** → its letters are **e f i k n**.
> Type **`fine`** → f+i+n+e = **7 damage**. (Rare letters are worth more: `k` alone
> is 5, `q` and `z` are 10.)

Runs in a browser, no install. And it's easy to mess with — most of the game is
plain text files you can edit.

## Play it

It just needs to be *served* (a browser won't load the game's files straight off
disk). From this folder, run:

```bash
python3 serve.py
```

Then open **<http://localhost:8000/web_version/>** and hit **Play**.

## How to play

- Each enemy has a row of **letters** and an **HP bar** (its size = the letters'
  total worth: common letters = 1, `k` = 5, `j` `x` = 8, `q` `z` = 10).
- **Type any real word** that uses at least one of those letters. It deals damage
  equal to the letters it covers — so long, rare-letter words hit hardest.
- Drain the HP to **0** to win the round and pick a **reward**.
- The enemy **hits back every turn**, harder the deeper you get — so win fast.
- You can't repeat a word, and you can't just type the enemy's own weapon. You
  lose at 0 HP.

## Change it

Loads of it is just text you can edit in **`shared_data/`** — no coding:

| To change… | Edit this file | For example |
|---|---|---|
| numbers & rewards | `shared_data/rules.json` | letter values, starting HP, the reward list |
| monsters & weapons | `shared_data/word_bank.json` | add words to the `creature` / `item` pools |
| a monster's emoji | `shared_data/icons.json` | `"griffin": "🦅"` |

Save the file, refresh the page. Done.

Want to change the **actual rules**? The game's brains are small, readable
JavaScript files in **`web_version/src/`**. Edit, refresh — no build step. (After
changing those, run `node web_version/test/conformance.js` to check it still
passes the golden tests — see [docs/](docs/ARCHITECTURE.md).)

## What's in here

```
web_version/    ▶ the game you play in a browser — start here
shared_data/    ★ the game's content, as plain text — edit this
docs/           how it all works, for developers
```

(`wordlist_generator/` and `ai_art_server/` are optional extras — see the docs.)

The monster art is real AI art, generated with a local tool and **baked into
`shared_data/art/`**, so it ships with the game — no setup needed to see it. If you
want to regenerate it or add your own art "skin," that's what `ai_art_server/` is
for (see the [docs](docs/ARCHITECTURE.md)).

<sub>There's also a fancier **Godot** build (same game, draws each monster live) on
the [`godot`](../../tree/godot) branch — needs a Mac set up for it.</sub>

## License

[MIT](LICENSE) — do what you like with it.
