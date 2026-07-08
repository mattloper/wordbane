// The word dictionary + the letter-rarity scoring. Mirrors godot/core/lexicon.gd.
// Pure functions on data; no UI.
import { section } from './rules.js';

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

// The word dictionary — a Set of real words (membership is all the game needs).
export class Lexicon {
  // Accepts the slim word list (array) or a legacy {word: ...} object.
  constructor(words = []) {
    this.words = new Set(Array.isArray(words) ? words : Object.keys(words));
  }

  isWord(w) {
    return this.words.has(w.toLowerCase());
  }

  // Highest-damage fresh word for a set of letters (Hint), ties -> shorter word.
  bestWord(letters, used) {
    const usedSet = new Set(used);
    let best = '';
    let bestDmg = 0;
    for (const w of this.words) {
      if (usedSet.has(w) || !sharesLetter(w, letters)) continue;
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
    if (used.includes(w)) return { ok: false, reason: `'${w}' already used this run` };
    if (!this.isWord(w)) return { ok: false, reason: `'${w}' isn't in the dictionary` };
    if (!sharesLetter(w, letters)) return { ok: false, reason: `'${w}' uses none of its letters` };
    return { ok: true, reason: '', dealt: overlapDamage(w, letters) };
  }
}
