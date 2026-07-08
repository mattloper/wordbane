// Holds the shared tuning/catalog data (data/rules.json) — the SAME file the
// Godot game reads. Set once at startup (Node reads the file; the browser fetches
// it). Mirrors godot_version/core/rules.gd. `RULES` is a live binding, so importers see the
// value after setRules() runs.
export let RULES = {};

export function setRules(data) {
  RULES = data || {};
}

export function section(name) {
  return RULES[name] || {};
}

export function num(sectionName, key, fallback) {
  const v = section(sectionName)[key];
  return v === undefined ? fallback : v;
}
