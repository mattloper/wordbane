// Word-bank constants + item-power resolution. Mirrors godot/core/word_bank.gd.
export const NEGATIVE = 'negative'; // enemies are built from the "negative" pools

export const KIND_FIXED = 'fixed';
export const KIND_ADJ = 'adjective';
export const KIND_CREATURE = 'creature';
export const KIND_ITEM = 'item';

export const HP_ATTACK = 'hp_attack';

export function itemToken(tokens, itemIndex) {
  for (const t of tokens) {
    if (t.kind === KIND_ITEM && (t.item_index ?? -1) === itemIndex) return t;
  }
  return {};
}

export function itemAdjectives(tokens, itemIndex) {
  const key = `item:${itemIndex}`;
  return tokens.filter((t) => t.kind === KIND_ADJ && t.attaches === key);
}

export function itemMultiplier(tokens, itemIndex) {
  let mult = 1.0;
  for (const t of itemAdjectives(tokens, itemIndex)) mult *= t.mult ?? 1.0;
  return mult;
}

// Resolve an item to {type, base, mult, amount, noun}. amount = round(base*mult), min 1.
export function itemPower(tokens, itemIndex) {
  const noun = itemToken(tokens, itemIndex);
  if (!noun.text) return {};
  const base = noun.base ?? 1;
  const mult = itemMultiplier(tokens, itemIndex);
  return {
    type: noun.item_type || HP_ATTACK,
    base,
    mult,
    amount: Math.max(1, Math.round(base * mult)),
    noun: noun.text || '',
  };
}
