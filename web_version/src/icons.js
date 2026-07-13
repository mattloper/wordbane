// Emoji clipart from the shared data/icons.json (same file the Godot IconBank
// reads, so the two can't drift). setIcons() is called once at boot with the fetched
// data; every creature/weapon shows *something* via the fallbacks.
let ICONS = { words: {}, boons: {}, fallback: {} };
// The generated long-tail map (shared_data/word_emoji.json): every playable word ->
// nearest emoji, produced offline by emoji_mapper/. Hand-authored ICONS always wins;
// this only fills words no human curated. Optional — the game runs fine without it.
let GENERATED = {};

export function setIcons(data) {
  ICONS = { words: {}, boons: {}, fallback: {}, ...data };
}
export function setGeneratedIcons(data) {
  GENERATED = (data && data.words) || {};
}

export function iconFor(word) {
  const w = String(word).toLowerCase();
  return ICONS.words[w] || GENERATED[w] || '';
}
export function creatureIcon(word) {
  return iconFor(word) || ICONS.fallback.creature || '👾';
}
export function weaponIcon(word) {
  return iconFor(word) || ICONS.fallback.weapon || '⚔️';
}
export function bonkIcon(word) {
  return iconFor(word) || ICONS.fallback.bonk || '💥';
}
export function boonIcon(id) {
  return ICONS.boons[id] || '⭐';
}
export function tombstone() {
  return ICONS.fallback.tombstone || '🪦';
}
