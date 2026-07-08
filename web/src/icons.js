// Emoji clipart — a word -> emoji map (ports game/core/icon_bank.gd), with sensible
// fallbacks so every creature/weapon shows *something*. Emoji render natively in the
// browser, so this is the web build's art (no AI daemon).
const MAP = {
  // creatures
  dragon: '🐉', ogre: '👹', wolf: '🐺', demon: '😈', serpent: '🐍', goblin: '👺',
  kitten: '🐱', puppy: '🐶', lamb: '🐑', bunny: '🐰', fawn: '🦌', duckling: '🐥',
  knight: '🤺', mage: '🧙', sheep: '🐑', badger: '🦡', heron: '🐦', goat: '🐐',
  // weapons / items
  knife: '🔪', dagger: '🗡️', axe: '🪓', spear: '🔱', blade: '🗡️', claw: '🐾',
  fang: '🦷', hex: '🔮', curse: '💀', jinx: '🧿', club: '🏏', sword: '⚔️',
  hammer: '🔨', shield: '🛡️', wand: '🪄', scroll: '📜', spell: '✨', potion: '🧪',
  mace: '🔨', maul: '🔨', flail: '⛓️', whip: '🪢', lance: '🔱', trident: '🔱',
  scythe: '🌾', frost: '❄️', blaze: '🔥', quake: '🌋', squall: '🌪️', venom: '🐍',
  toxin: '☠️', plague: '🦠', doom: '💀', wraith: '👻', specter: '👻', spike: '📌',
};

// Per-boon emoji (used for the reward buttons on the web build).
const BOON = { tough: '🛡️', mend: '🧪', focus: '🔍', double: '🪙' };

export function iconFor(word) {
  return MAP[String(word).toLowerCase()] || '';
}

// A creature always gets a face; weapons fall back to crossed swords.
export function creatureIcon(word) {
  return iconFor(word) || '👾';
}
export function weaponIcon(word) {
  return iconFor(word) || '⚔️';
}
export function boonIcon(id) {
  return BOON[id] || '⭐';
}
export const TOMBSTONE = '🪦';
