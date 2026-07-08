// Generates an escalating run of enemies from the word-bank pools. Mirrors
// game/core/gauntlet.gd — including the exact RNG draw order, so a given seed
// produces the same enemies as the Godot version.
import { num } from './rules.js';
import * as WB from './wordbank.js';
import * as PB from './poolbattle.js';
import { Rng } from './rng.js';

// Run tuning (from rules.json) — accessed as functions to stay live after load.
export const tuning = {
  startHp: () => num('gauntlet', 'start_hp', 36),
  maxItems: () => num('gauntlet', 'max_items', 2),
  minDangerMult: () => num('gauntlet', 'min_danger_mult', 1.5),
  scorePerDamage: () => num('gauntlet', 'score_per_damage', 3),
  chapterBonus: () => num('gauntlet', 'chapter_bonus', 25),
  hpPerChapter: () => num('gauntlet', 'hp_per_chapter', 1),
};

export class Gauntlet {
  constructor() {
    this._pools = {};
    this.rng = new Rng();
    this._usableItems = [];
  }

  setup(bank) {
    this._pools = bank.pools || {};
    this._usableItems = this._neg(WB.KIND_ITEM);
  }

  _neg(kind) {
    return (this._pools[kind] || {})[WB.NEGATIVE] || [];
  }

  _pick(arr) {
    return this.rng.pick(arr);
  }

  _dangerAdjectives() {
    const out = this._neg(WB.KIND_ADJ).filter((a) => (a.mult ?? 1.0) >= tuning.minDangerMult());
    return out.length ? out : this._neg(WB.KIND_ADJ);
  }

  _fixed(text) {
    return { text, kind: WB.KIND_FIXED };
  }

  _adj(entry, attaches) {
    return { text: entry.text || 'grim', kind: WB.KIND_ADJ, sentiment: WB.NEGATIVE, mult: entry.mult ?? 1.5, attaches };
  }

  // Build the enemy for a 1-based round. Draw order must match the Godot version:
  // creature, owner_adj, shuffle(items), then one adjective per weapon.
  generate(round) {
    const numItems = Math.max(1, Math.min(this.maxItemsClamped(round), tuning.maxItems()));
    const adjs = this._dangerAdjectives();
    const creature = this._pick(this._neg(WB.KIND_CREATURE));
    const ownerAdj = this._pick(adjs);

    const tokens = [];
    tokens.push(this._fixed('A'));
    tokens.push(this._adj(ownerAdj, 'owner'));
    tokens.push({ text: creature.text || 'foe', kind: WB.KIND_CREATURE, sentiment: WB.NEGATIVE, is_owner: true });
    tokens.push(this._fixed('wields'));

    const items = this._usableItems.slice();
    this.rng.shuffle(items);
    for (let i = 0; i < numItems; i++) {
      if (i > 0) tokens.push(this._fixed('and'));
      tokens.push(this._fixed('a'));
      tokens.push(this._adj(this._pick(adjs), `item:${i}`));
      const item = items[i % items.length];
      const scaledBase = (item.base ?? 2) + Math.floor((round - 1) / 2);
      tokens.push({
        text: item.text || 'blade',
        kind: WB.KIND_ITEM,
        sentiment: WB.NEGATIVE,
        item_type: item.item_type || 'hp_attack',
        base: scaledBase,
        item_index: i,
      });
    }

    const enemy = {
      name: capitalize(creature.text || 'foe'),
      role: 'enemy',
      tokens,
      item_order: [...Array(numItems).keys()],
      round,
    };
    PB.seedEnemy(enemy);
    const hpBonus = (round - 1) * tuning.hpPerChapter();
    enemy.max_hp = (enemy.max_hp | 0) + hpBonus;
    enemy.hp = enemy.max_hp;
    return enemy;
  }

  // 1 weapon for the first two chapters, 2 thereafter (matches clampi(1+(r-1)/2,1,MAX)).
  maxItemsClamped(round) {
    return 1 + Math.floor((round - 1) / 2);
  }
}

function capitalize(s) {
  // Godot's String.capitalize() upper-cases the first letter of each word; our
  // creature names are single words, so title-case the first letter is equivalent.
  return s.length ? s[0].toUpperCase() + s.slice(1) : s;
}
