// A tiny seedable PRNG — mulberry32 — mirroring game/core/rng.gd exactly, so the
// browser game and the Godot game produce identical sequences from the same seed.
// Single 32-bit state, trivial to serialize (persist/resume a run).
export class Rng {
  constructor(seed = 0) {
    this.state = seed >>> 0;
  }

  // Next raw 32-bit value (>>> 0 keeps everything unsigned, matching Godot's masks).
  nextU32() {
    this.state = (this.state + 0x6d2b79f5) >>> 0;
    let t = this.state;
    t = Math.imul(t ^ (t >>> 15), 1 | t);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return (t ^ (t >>> 14)) >>> 0;
  }

  nextFloat() {
    return this.nextU32() / 4294967296;
  }

  // Integer in [lo, hi] inclusive.
  rangeInt(lo, hi) {
    return lo + Math.floor(this.nextFloat() * (hi - lo + 1));
  }

  pick(arr) {
    return arr[this.rangeInt(0, arr.length - 1)];
  }

  // Fisher-Yates in place — same order as the Godot version.
  shuffle(arr) {
    for (let i = arr.length - 1; i > 0; i--) {
      const j = this.rangeInt(0, i);
      const tmp = arr[i];
      arr[i] = arr[j];
      arr[j] = tmp;
    }
  }
}
