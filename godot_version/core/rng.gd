## A tiny seedable PRNG — mulberry32 — chosen because it ports 1:1 to JS and has a
## single 32-bit state that's trivial to serialize (so a run is reproducible and can
## be persisted/resumed). All game randomness goes through this, so the Godot game
## and any future port produce identical sequences from the same seed.
##
## JS reference (the port must match this exactly):
##   function mulberry32(a){return function(){a=a+0x6D2B79F5|0;var t=Math.imul(a^a>>>15,1|a);
##     t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296}}
class_name Rng
extends RefCounted

var state: int  # 32-bit; get/set to persist & resume a run's stream


func _init(seed: int = 0) -> void:
	state = seed & 0xffffffff


## Low 32 bits of a*b (== JS Math.imul, treated unsigned). Split into 16-bit halves
## so the product never overflows GDScript's 64-bit int.
static func _imul(a: int, b: int) -> int:
	var al := a & 0xffff
	var ah := (a >> 16) & 0xffff
	return (al * b + (((ah * b) & 0xffff) << 16)) & 0xffffffff


## Next raw 32-bit value.
func next_u32() -> int:
	state = (state + 0x6D2B79F5) & 0xffffffff
	var t := _imul(state ^ (state >> 15), 1 | state)
	t = ((t + _imul(t ^ (t >> 7), 61 | t)) & 0xffffffff) ^ t
	return (t ^ (t >> 14)) & 0xffffffff


## Float in [0, 1). (Named `next_float`, not `randf`, to avoid shadowing GDScript's
## global randf() — an unqualified internal call would otherwise hit the global RNG.)
func next_float() -> float:
	return float(next_u32()) / 4294967296.0


## Integer in [lo, hi] inclusive.
func range_int(lo: int, hi: int) -> int:
	return lo + int(next_float() * (hi - lo + 1))


## A random element of `arr`.
func pick(arr: Array):
	return arr[range_int(0, arr.size() - 1)]


## Fisher-Yates shuffle in place (the port must use this same order).
func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := range_int(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
