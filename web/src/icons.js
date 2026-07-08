// Emoji clipart from the shared game/data/icons.json (same file the Godot IconBank
// reads, so the two can't drift). setIcons() is called once at boot with the fetched
// data; every creature/weapon shows *something* via the fallbacks.
let ICONS = { words: {}, boons: {}, fallback: {} };

export function setIcons(data) {
  ICONS = { words: {}, boons: {}, fallback: {}, ...data };
}

export function iconFor(word) {
  return ICONS.words[String(word).toLowerCase()] || '';
}
export function creatureIcon(word) {
  return iconFor(word) || ICONS.fallback.creature || '👾';
}
export function weaponIcon(word) {
  return iconFor(word) || ICONS.fallback.weapon || '⚔️';
}
export function boonIcon(id) {
  return ICONS.boons[id] || '⭐';
}
export function tombstone() {
  return ICONS.fallback.tombstone || '🪦';
}
