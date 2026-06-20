## Difficulty-balancing harness (dev tool, not part of the game).
##
## Auto-plays the gauntlet with PERFECT word-finding and optimal disarm order
## (always remove the deadliest weapon you can solve), to measure the damage
## economy independent of vocabulary. Use it after changing tuning constants in
## Gauntlet (START_HP / HEAL / ramp / multipliers) to see the curve.
##
##   godot --headless --script res://balance.gd
##
## Read the result as: "even a perfect player is walled at this depth by damage
## alone." Real players, limited by word-finding, end shallower — so you want this
## comfortably deeper than your target human depth.
extends SceneTree

const RUNS := 40
const DEPTH_CAP := 60


func _initialize() -> void:
	var ladder := WordLadder.load_from("res://data/dictionary.json")
	var g := Gauntlet.new()
	g.setup(GameLogic.load_bank("res://data/word_bank.json"), ladder)

	var depths: Array = []
	var dmg_by_depth: Dictionary = {}
	var fights_by_depth: Dictionary = {}
	for _run in range(RUNS):
		var hp: int = Gauntlet.START_HP
		var depth := 0
		while depth < DEPTH_CAP:
			depth += 1
			var b := LadderBattle.new()
			b.ladder = ladder
			b.begin(g.generate(depth), hp, Gauntlet.START_HP)
			var took := 0
			var safety := 0
			while b.state == LadderBattle.STATE_PLAY and safety < 40:
				safety += 1
				var weps := b.weapon_indices()
				weps.sort_custom(func(a, c): return b.weapon_damage(a) > b.weapon_damage(c))
				var moved := false
				for wi in weps:
					var word := ladder.find_transform(b.enemy.tokens[wi].text, "noun", b.used)
					if word != "":
						var before := b.player_hp
						b.try_move(wi, word)
						took += before - b.player_hp
						moved = true
						break
				if not moved:
					var before2 := b.player_hp
					b.pass_turn()
					took += before2 - b.player_hp
			dmg_by_depth[depth] = float(dmg_by_depth.get(depth, 0.0)) + took
			fights_by_depth[depth] = int(fights_by_depth.get(depth, 0)) + 1
			if b.state == LadderBattle.STATE_LOST:
				break
			hp = mini(Gauntlet.START_HP, b.player_hp + Gauntlet.HEAL)
		depths.append(depth)

	depths.sort()
	var sum := 0.0
	for d in depths:
		sum += d
	print("Tuning: START_HP=%d HEAL=%d" % [Gauntlet.START_HP, Gauntlet.HEAL])
	print("OPTIMAL-PLAY depth over %d runs: min=%d median=%d max=%d mean=%.1f" % [
		RUNS, depths[0], depths[depths.size() / 2], depths[-1], sum / depths.size()])
	print("avg damage per fight by depth:")
	for d in range(1, 13):
		if fights_by_depth.has(d):
			print("  depth %2d: %.1f" % [d, float(dmg_by_depth[d]) / float(fights_by_depth[d])])
	quit(0)
