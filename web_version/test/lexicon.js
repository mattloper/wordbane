// Tests plural-tolerant Lexicon.isWord (dogs/qualities/wolves accepted when
// only the singular is in the dictionary) and the no-reuse collapse (a run
// can't spend both 'quality' and 'qualities').
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
for (const w of ['xyzzys', 'qwerties', 'blarghves', 'zzzz']) {
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
  check(!r.ok && /already used/.test(r.reason), 'then: qualities blocked as already used');
}
{
  const b = fresh(); // reverse order: plural first, singular blocked
  check(b.tryMove('qualities').ok, 'first: qualities is accepted');
  const r = b.tryMove('quality');
  check(!r.ok && /already used/.test(r.reason), 'then: quality blocked as already used');
}
{
  const b = fresh(); // unrelated second word still allowed
  b.tryMove('quality');
  check(b.tryMove('quilt').ok, 'a different word is still allowed');
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
  check(!plural.ok && plural.reason === "'knives' is just 'knife', the enemy's own weapon — use a different word",
    'weapon plural banned with the it-is-just message');
}
{
  const b = armed(); // a non-weapon word from the same pool is fine
  check(b.tryMove('fins').ok, 'a non-weapon word is still allowed');
}

console.log(`lexicon: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
