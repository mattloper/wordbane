// The word dictionary + the letter-rarity scoring. Mirrors godot_version/core/lexicon.gd.
// Pure functions on data; no UI.
import { section } from './rules.js';
import pluralize from './vendor/pluralize.js';

export function letterWeight(ch) {
  const w = section('letter_weights')[ch];
  return w === undefined ? 1 : w;
}

// Distinct letters of a word, as a Set.
export function distinctLetters(w) {
  return new Set(w.toLowerCase().split(''));
}

export function lettersWeight(letters) {
  let total = 0;
  for (const ch of letters) total += letterWeight(ch);
  return total;
}

// A word's HP contribution: summed rarity weight of its distinct letters.
export function wordWeight(w) {
  return lettersWeight([...distinctLetters(w)]);
}

// True if a and b share at least one letter.
export function sharesLetter(a, b) {
  const bl = distinctLetters(b);
  for (const ch of distinctLetters(a)) if (bl.has(ch)) return true;
  return false;
}

// Distinct letters of `letters` that `typed` covers, sorted (matches Godot).
export function coveredLetters(typed, letters) {
  const tl = distinctLetters(typed);
  const out = [];
  for (const ch of distinctLetters(letters)) if (tl.has(ch)) out.push(ch);
  out.sort();
  return out;
}

export function overlapDamage(typed, letters) {
  return lettersWeight(coveredLetters(typed, letters));
}

// Like overlapDamage, but each covered letter's weight scaled by mult (Double boon).
export function weightedOverlap(typed, letters, mult) {
  let total = 0;
  for (const ch of coveredLetters(typed, letters)) {
    const m = mult && mult[ch] !== undefined ? mult[ch] : 1;
    total += letterWeight(ch) * m;
  }
  return total;
}

export function upperLetters(letters) {
  return letters.map((c) => c.toUpperCase());
}

// A word's heuristic identity for the no-reuse rule: its singular form. So
// 'quality' and 'qualities' (or 'wolf'/'wolves', 'mouse'/'mice') count as the
// same word within a run — you can't spend both. Used when the dictionary
// carries no lemma ids for a word (schema v2, or curated-only entries).
export function wordKey(w) {
  const word = w.trim().toLowerCase();
  return pluralize.singular(word) || word;
}

// The word dictionary — membership plus (schema v3) word identity.
export class Lexicon {
  // Accepts:
  //  - schema v2: an array of words,
  //  - schema v3 (ESDB/SCOWL): a {form: [lemma ids]} object — forms that share
  //    a lemma id are inflections of the same word (wolf/wolves, run/ran),
  //  - a legacy v1 {word: meta} object (keys only).
  constructor(words = []) {
    if (Array.isArray(words)) {
      this.words = new Set(words);
      this.lemmas = null;
    } else {
      this.words = new Set(Object.keys(words));
      const vals = Object.values(words);
      this.lemmas = vals.length > 0 && Array.isArray(vals[0]) ? new Map(Object.entries(words)) : null;
    }
  }

  // Identity keys for the no-reuse / weapon-ban rules. With lemma ids, a word's
  // keys are its ids ('mouse' -> ['#209957', '#209961', ...]); two words are the
  // same if any key matches. Without ids, fall back to the singular heuristic.
  keysOf(w) {
    const word = w.trim().toLowerCase();
    const ids = this.lemmas ? this.lemmas.get(word) : undefined;
    if (ids && ids.length > 0) return ids.map((id) => '#' + id);
    return [wordKey(word)];
  }

  // True if a and b are forms of the same word (share a lemma id, or share the
  // fallback singular key).
  sameWord(a, b) {
    const kb = new Set(this.keysOf(b));
    return this.keysOf(a).some((k) => kb.has(k));
  }

  // The v2 WordNet list only carries base forms, so a typed plural like
  // 'qualities' or 'wolves' misses. We accept the word if it's in the set, or
  // if its singular (via the pluralize library — handles irregulars like
  // mice/geese/children and uncountables like sheep) is. The v3 ESDB list has
  // inflected forms as entries, so the fallback rarely fires there.
  isWord(w) {
    const word = w.toLowerCase();
    if (this.words.has(word)) return true;
    const singular = pluralize.singular(word);
    return singular !== word && this.words.has(singular);
  }

  // Highest-damage fresh word for a set of letters (Hint), ties -> shorter word.
  // `used` holds words as typed (plus the enemy's weapon words) — expand each to
  // its identity keys so inflections of a spent word don't come back as hints.
  bestWord(letters, used) {
    const usedSet = new Set();
    for (const u of used) for (const k of this.keysOf(u)) usedSet.add(k);
    let best = '';
    let bestDmg = 0;
    for (const w of this.words) {
      // sharesLetter first so we only pay for keysOf on real candidates.
      if (!sharesLetter(w, letters) || this.keysOf(w).some((k) => usedSet.has(k))) continue;
      const d = overlapDamage(w, letters);
      if (d > bestDmg || (d === bestDmg && best !== '' && w.length < best.length)) {
        bestDmg = d;
        best = w;
      }
    }
    return best;
  }

  // Validate a typed strike. Returns {ok, reason, dealt?}.
  validate(typed, letters, used) {
    const w = typed.trim().toLowerCase();
    if (w === '') return { ok: false, reason: 'type a word' };
    // Name the earlier word so the message makes sense to a kid: a plain
    // "already used" is confusing when they typed 'ran' but spent 'running'.
    const dup = used.find((u) => this.sameWord(u, w));
    if (dup === w) return { ok: false, reason: `you already used '${w}' — try a new word` };
    if (dup !== undefined) {
      return { ok: false, reason: `'${w}' is too much like '${dup}', which you already used — try a new word` };
    }
    if (!this.isWord(w)) return { ok: false, reason: `'${w}' isn't in the dictionary` };
    if (!sharesLetter(w, letters)) return { ok: false, reason: `'${w}' uses none of its letters` };
    return { ok: true, reason: '', dealt: overlapDamage(w, letters) };
  }
}
