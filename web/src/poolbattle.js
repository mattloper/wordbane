// One letter-pool battle. Mirrors godot/core/pool_battle.gd.
import * as Lex from './lexicon.js';
import * as WB from './wordbank.js';

export const STATE_PLAY = 'play';
export const STATE_WON = 'won';
export const STATE_LOST = 'lost';

// The enemy's weapon nouns (lowercased) — banned as moves (no echoing them back).
export function weaponWords(tokens) {
  return tokens
    .filter((t) => t.kind === WB.KIND_ITEM)
    .map((t) => String(t.text || '').toLowerCase());
}

// Distinct letters across all of an enemy's weapon nouns, sorted.
export function weaponLetters(tokens) {
  const set = new Set();
  for (const t of tokens) {
    if (t.kind === WB.KIND_ITEM) {
      for (const ch of Lex.distinctLetters(t.text || '')) set.add(ch);
    }
  }
  return [...set].sort();
}

// The enemy's full-strength bite: its deadliest weapon (base x adjective mult).
export function maxBite(tokens) {
  let worst = 0;
  for (const t of tokens) {
    if (t.kind === WB.KIND_ITEM) {
      worst = Math.max(worst, WB.itemPower(tokens, t.item_index ?? -1).amount || 0);
    }
  }
  return worst;
}

// Derive letters/HP/bite from weapon tokens if absent (idempotent).
export function seedEnemy(e) {
  const tokens = e.tokens || [];
  if (e.weapons === undefined) e.weapons = weaponWords(tokens);
  if (e.letters === undefined) e.letters = weaponLetters(tokens);
  if (e.max_hp === undefined) e.max_hp = Lex.lettersWeight(e.letters);
  if (e.hp === undefined) e.hp = e.max_hp;
  if (e.base_bite === undefined) e.base_bite = maxBite(tokens);
}

export class PoolBattle {
  constructor() {
    this.lexicon = null;
    this.enemy = {};
    this.player_hp = 0;
    this.player_max = 0;
    this.used = [];
    this.state = STATE_PLAY;
    this.letter_mult = {};
  }

  // NOTE: `used` is NOT cleared here — no-reuse spans the whole run.
  begin(enemyFighter, hp, maxHp) {
    this.enemy = enemyFighter;
    this.player_hp = hp;
    this.player_max = maxHp;
    this.state = STATE_PLAY;
    seedEnemy(this.enemy);
  }

  letters() {
    return this.enemy.letters || [];
  }
  weapons() {
    return this.enemy.weapons || [];
  }
  enemyHp() {
    return this.enemy.hp | 0;
  }
  enemyMaxHp() {
    return this.enemy.max_hp ?? this.enemyHp();
  }
  incomingDamage() {
    return this.enemyHp() <= 0 ? 0 : this.enemy.base_bite | 0;
  }

  // Validate a move without applying it (also the live preview).
  check(word) {
    const w = word.trim().toLowerCase();
    if (this.weapons().includes(w)) {
      return { ok: false, reason: `'${w}' is the enemy's own weapon — use a different word` };
    }
    const lettersStr = this.letters().join('');
    const r = this.lexicon.validate(word, lettersStr, this.used);
    if (r.ok) r.dealt = Lex.weightedOverlap(w, lettersStr, this.letter_mult);
    return r;
  }

  // Strike the enemy. Invalid = no turn consumed; valid = drain HP, enemy hits back.
  tryMove(word) {
    if (this.state !== STATE_PLAY) return { ok: false, reason: 'battle is over' };
    const lettersStr = this.letters().join('');
    const r = this.check(word);
    if (!r.ok) return r;

    const w = word.trim().toLowerCase();
    const dealt = r.dealt | 0;
    const covered = Lex.coveredLetters(w, lettersStr);
    this.used.push(w);
    this.enemy.hp = Math.max(0, this.enemyHp() - dealt);

    const res = { ok: true, word: w, dealt, covered, hp_left: this.enemyHp(), damage: 0, won: false, lost: false };
    if (this.enemyHp() <= 0) {
      this.state = STATE_WON;
      res.won = true;
      return res;
    }
    const dmg = this.incomingDamage();
    this.player_hp = Math.max(0, this.player_hp - dmg);
    res.damage = dmg;
    if (this.player_hp <= 0) {
      this.state = STATE_LOST;
      res.lost = true;
    }
    return res;
  }

  // Take a hit without striking.
  passTurn() {
    if (this.state !== STATE_PLAY) return { ok: false };
    const dmg = this.incomingDamage();
    this.player_hp = Math.max(0, this.player_hp - dmg);
    const res = { ok: true, passed: true, damage: dmg, lost: false };
    if (this.player_hp <= 0) {
      this.state = STATE_LOST;
      res.lost = true;
    }
    return res;
  }
}
