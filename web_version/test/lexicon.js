// Tests plural-tolerant Lexicon.isWord (dogs/qualities/wolves accepted even
// when only the singular is in the dictionary), the no-reuse collapse (a run
// can't spend both 'quality' and 'qualities'), and — with the ESDB/SCOWL
// dictionary (schema v3) — the lemma-id collapse ('run'/'ran'/'running' are
// one word).
//
//   node web_version/test/lexicon.js
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { Lexicon, wordKey } from '../src/lexicon.js';
import { PoolBattle } from '../src/poolbattle.js';

const DATA = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'shared_data');
const dict = JSON.parse(readFileSync(join(DATA, 'dictionary.json'), 'utf8'));
const lex = new Lexicon(dict.words);

let pass = 0;
let fail = 0;
const check = (cond, msg) => {
  if (cond) pass++;
  else { fail++; console.log('  FAIL -', msg); }
};

// Singulars still work.
for (const w of ['quality', 'dog', 'stone', 'box', 'wolf', 'knife']) {
  check(lex.isWord(w), `singular in dict: ${w}`);
}

// Regular plurals are accepted via singular fallback.
for (const w of ['qualities', 'dogs', 'stones', 'boxes', 'dishes', 'wolves', 'knives', 'babies', 'notes']) {
  check(lex.isWord(w), `plural accepted: ${w}`);
}

// Irregular plurals — the reason we use pluralize rather than regex stripping.
// (Only assert on ones whose singular is actually in the dictionary.)
for (const [plural, singular] of [
  ['mice', 'mouse'], ['geese', 'goose'], ['children', 'child'],
  ['people', 'person'], ['feet', 'foot'], ['teeth', 'tooth'], ['men', 'man'],
]) {
  if (lex.words.has(singular)) check(lex.isWord(plural), `irregular plural: ${plural} -> ${singular}`);
}

// Case-insensitive.
check(lex.isWord('Qualities'), 'plural case-insensitive');

// Nonsense still rejected.
for (const w of ['xyzzys', 'wubbles', 'blarghves', 'zzzz']) {
  check(!lex.isWord(w), `nonsense rejected: ${w}`);
}

// --- no-reuse collapse: singular and plural share one identity ---------------

// wordKey maps a plural and its singular to the same key.
for (const [a, b] of [['quality', 'qualities'], ['wolf', 'wolves'], ['mouse', 'mice'], ['dog', 'dogs']]) {
  check(wordKey(a) === wordKey(b), `wordKey collapses ${a}/${b} (${wordKey(a)} == ${wordKey(b)})`);
}

// Through a real battle: playing a word bans re-spending its plural (and vice
// versa). Enemy given an explicit letter pool covering q,u,a,l,i,t,y,s so both
// forms are legal moves; no weapon words, so nothing is banned for that reason.
function fresh() {
  const b = new PoolBattle();
  b.lexicon = lex;
  b.begin({ letters: ['a', 'i', 'l', 'q', 's', 't', 'u', 'y'], weapons: [], max_hp: 999, hp: 999, base_bite: 0 }, 30, 30);
  return b;
}
{
  const b = fresh();
  check(b.tryMove('quality').ok, 'first: quality is accepted');
  const r = b.tryMove('qualities');
  check(!r.ok && r.reason === "'qualities' is too much like 'quality', which you already used — try a new word",
    'then: qualities blocked, message names quality');
}
{
  const b = fresh(); // reverse order: plural first, singular blocked
  check(b.tryMove('qualities').ok, 'first: qualities is accepted');
  const r = b.tryMove('quality');
  check(!r.ok && r.reason === "'quality' is too much like 'qualities', which you already used — try a new word",
    'then: quality blocked, message names qualities');
}
{
  const b = fresh(); // exact repeat gets the plain "already used" message
  b.tryMove('quality');
  const r = b.tryMove('quality');
  check(!r.ok && r.reason === "you already used 'quality' — try a new word",
    'exact repeat blocked with the plain message');
}
{
  const b = fresh(); // unrelated second word still allowed
  b.tryMove('quality');
  check(b.tryMove('quilt').ok, 'a different word is still allowed');
}

// --- lemma-id collapse (schema v3, ESDB/SCOWL dictionary) --------------------

// These only apply when the dictionary carries lemma ids. Then inflections are
// real entries (no fallback guessing) and any two forms of a lemma are one word.
if (lex.lemmas) {
  for (const w of ['ran', 'running', 'wolves', 'knives', 'mice']) {
    check(lex.words.has(w), `inflected form is a real entry: ${w}`);
  }
  for (const [a, b] of [['run', 'ran'], ['run', 'running'], ['mouse', 'mice'], ['wolf', 'wolves']]) {
    check(lex.sameWord(a, b) && lex.sameWord(b, a), `sameWord collapses ${a}/${b}`);
  }
  check(!lex.sameWord('quality', 'quilt'), 'unrelated words are not collapsed');

  // Through a battle: spending 'run' bans 'running' (pluralize alone can't
  // catch verb forms — this is the lemma ids working).
  const b = new PoolBattle();
  b.lexicon = lex;
  b.begin({ letters: ['g', 'i', 'n', 'r', 'u'], weapons: [], max_hp: 999, hp: 999, base_bite: 0 }, 30, 30);
  check(b.tryMove('run').ok, 'first: run is accepted');
  const r = b.tryMove('running');
  check(!r.ok && r.reason === "'running' is too much like 'run', which you already used — try a new word",
    'then: running blocked, message names run');
  check(b.tryMove('ring').ok, 'a different word is still allowed');
}

// --- weapon ban is plural-aware ---------------------------------------------

// Enemy wields 'knife'; the pool covers knife/knives letters (k,n,i,f,e,v,s).
function armed() {
  const b = new PoolBattle();
  b.lexicon = lex;
  b.begin({ letters: ['e', 'f', 'i', 'k', 'n', 's', 'v'], weapons: ['knife'], max_hp: 999, hp: 999, base_bite: 0 }, 30, 30);
  return b;
}
{
  const b = armed();
  const exact = b.tryMove('knife');
  check(!exact.ok && exact.reason === "'knife' is the enemy's own weapon — use a different word",
    'exact weapon banned with the plain message');
}
{
  const b = armed();
  const plural = b.tryMove('knives');
  check(!plural.ok && plural.reason === "'knives' is too much like 'knife', the enemy's own weapon — use a different word",
    'weapon plural banned with the too-much-like message');
}
{
  const b = armed(); // a non-weapon word from the same pool is fine
  check(b.tryMove('fins').ok, 'a non-weapon word is still allowed');
}

console.log(`lexicon: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
