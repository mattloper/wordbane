// Between-chapter rewards. Mirrors godot/core/boons.gd. Catalog + params come from
// rules.json; offer() returns resolved instances {id, label, desc, arg}; apply()
// mutates a state dict {hp, max_hp, hints, letter_mult} in place.
import { section } from './rules.js';

export function hintsPerFocus() {
  return section('boons').hints_per_focus ?? 3;
}
export function doubleLetters() {
  return section('boons').double_letters || 'eariotnslc';
}
export function all() {
  return section('boons').catalog || [];
}
export function ids() {
  return all().map((b) => b.id);
}

// One offerable instance of `id`, resolving a Double's random letter via `rng`.
export function instance(id, rng) {
  if (id === 'double') {
    const letters = doubleLetters();
    const letter = letters[rng.rangeInt(0, letters.length - 1)];
    return {
      id: 'double',
      arg: letter,
      label: 'Double ' + letter.toUpperCase(),
      desc: `2x score for '${letter.toUpperCase()}' (rest of run)`,
    };
  }
  for (const b of all()) {
    if (b.id === id) return { id: b.id, arg: '', label: b.label, desc: b.desc };
  }
  return {};
}

// Up to 3 resolved instances.
export function offer(rng) {
  const pool = ids();
  rng.shuffle(pool);
  return pool.slice(0, 3).map((id) => instance(id, rng));
}

export function describe(boon) {
  return `${boon.label} (${boon.desc})`;
}

// Apply a boon instance to a state dict, in place.
export function apply(boon, s) {
  switch (boon.id) {
    case 'tough':
      s.max_hp = (s.max_hp | 0) + 6;
      s.hp = Math.min(s.max_hp | 0, (s.hp | 0) + 6);
      break;
    case 'mend':
      s.hp = s.max_hp;
      break;
    case 'focus':
      s.hints = (s.hints || 0) + hintsPerFocus();
      break;
    case 'double': {
      const mult = s.letter_mult || {};
      mult[boon.arg] = (mult[boon.arg] || 1) * 2;
      s.letter_mult = mult;
      break;
    }
  }
}
