// Runs game/data/conformance.json against the JS core — the SAME fixtures the Godot
// selftest runs. Matching outputs = the two implementations haven't drifted.
//
//   node web/test/conformance.js
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { setRules } from '../src/rules.js';
import * as Lex from '../src/lexicon.js';
import * as Boons from '../src/boons.js';
import { Gauntlet } from '../src/gauntlet.js';
import { Rng } from '../src/rng.js';

const DATA = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'game', 'data');
const readJson = (f) => JSON.parse(readFileSync(join(DATA, f), 'utf8'));

setRules(readJson('rules.json'));
const bank = readJson('word_bank.json');
const c = readJson('conformance.json');

let pass = 0;
let fail = 0;
const check = (cond, msg) => {
  if (cond) pass++;
  else {
    fail++;
    console.log('  FAIL -', msg);
  }
};

const eq = (a, b) => {
  if (typeof a === 'number' && typeof b === 'number') return a === b;
  if (Array.isArray(a) && Array.isArray(b)) return a.length === b.length && a.every((x, i) => eq(x, b[i]));
  if (a && b && typeof a === 'object' && typeof b === 'object') {
    const ka = Object.keys(a);
    const kb = Object.keys(b);
    return ka.length === kb.length && ka.every((k) => k in b && eq(a[k], b[k]));
  }
  return a === b;
};

for (const [ch, w] of c.letter_weight) check(Lex.letterWeight(ch) === w, `letter_weight(${ch})`);
for (const [w, exp] of c.word_weight) check(Lex.wordWeight(w) === exp, `word_weight(${w})`);
for (const [t, l, exp] of c.overlap_damage) check(Lex.overlapDamage(t, l) === exp, `overlap_damage(${t},${l})`);
for (const [t, l, m, exp] of c.weighted_overlap) check(Lex.weightedOverlap(t, l, m) === exp, `weighted_overlap(${t},${l})`);
for (const [a, b, exp] of c.shares_letter) check(Lex.sharesLetter(a, b) === exp, `shares_letter(${a},${b})`);
for (const [t, l, exp] of c.covered_letters) check(eq(Lex.coveredLetters(t, l), exp), `covered_letters(${t},${l})`);

for (const t of c.boon_apply) {
  const s = structuredClone(t.in);
  Boons.apply(t.boon, s);
  check(eq(s, t.out), `boon_apply(${t.boon.id})`);
}

for (const [seed, expected] of c.rng_u32) {
  const r = new Rng(seed);
  const got = expected.map(() => r.nextU32());
  check(eq(got, expected), `rng_u32(seed=${seed})`);
}

for (const [seed, round, expected] of c.generate_sentence) {
  const g = new Gauntlet();
  g.setup(bank);
  g.rng = new Rng(seed);
  const e = g.generate(round);
  const sentence = e.tokens.map((tok) => tok.text || '').join(' ');
  check(sentence === expected, `generate_sentence(seed=${seed}) -> "${sentence}"`);
}

console.log(`conformance: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
