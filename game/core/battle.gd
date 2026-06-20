## The turn-flow state machine — view-agnostic.
##
## Owns the two fighters and the turn sequence; mutates state via GameLogic and
## tells whatever view is attached to redraw via signals. Both the 2D scene and
## the 3D world drive a Battle the same way:
##   battle.use_item(i)     # your turn: use one of your items
##   battle.target_word(j)  # while targeting: randomize an enemy word
##   battle.new_game()
## and render from `player`, `enemy`, `state`, `pending_targets` on `changed`.
##
## It's a Node so it can run the between-turns timer and emit signals.
class_name Battle
extends Node

signal changed              ## state/fighters updated — the view should redraw
signal logged(text: String) ## a human-readable message for the log

const ST_CHOOSE := "choose"  # your turn: pick one of your items
const ST_TARGET := "target"  # picking which enemy word(s) to randomize
const ST_BUSY := "busy"      # enemy acting / between turns
const ST_OVER := "over"      # battle finished

const ENEMY_TURN_DELAY := 0.55

var player: Dictionary = {}
var enemy: Dictionary = {}
var state := ST_CHOOSE
var pending_targets := 0
var pending_label := ""

var _pools: Dictionary = {}
var _characters: Array = []
var _rng := RandomNumberGenerator.new()
var _battle_id := 0          # bumped each new_game; guards stale turn timers
var _player_msg := ""


func setup(bank: Dictionary) -> void:
	_rng.randomize()
	_pools = bank.get("pools", {})
	_characters = bank.get("characters", [])


func new_game() -> void:
	_battle_id += 1
	var enemy_t := GameLogic.pick_character(_characters, "enemy", _rng)
	var player_t := GameLogic.pick_character(_characters, "player", _rng)
	if enemy_t.is_empty() or player_t.is_empty():
		logged.emit("Word bank is missing player/enemy characters.")
		return
	enemy = GameLogic.make_fighter(enemy_t)
	player = GameLogic.make_fighter(player_t)
	state = ST_CHOOSE
	_player_msg = ""
	pending_targets = 0
	changed.emit()
	logged.emit("Your turn — use one of your items.")


## Use one of the player's items. A word-randomizer enters targeting mode;
## everything else resolves immediately and passes the turn.
func use_item(item_index: int) -> void:
	if state != ST_CHOOSE or item_index < 0:
		return
	var power := GameLogic.item_power(player.tokens, item_index)
	if power.is_empty():
		return
	if power.get("type", "") == GameLogic.WORD_ATTACK:
		pending_targets = int(power.amount)
		pending_label = GameLogic.item_label(player.tokens, item_index)
		state = ST_TARGET
		changed.emit()
		logged.emit("%s readies %s — click an enemy word to randomize it." % [
			player.name, pending_label])
		return
	var res := GameLogic.apply_item(player, enemy, item_index, _pools, _rng)
	_player_msg = CombatText.describe(player.name, res, enemy.name)
	_finish_player_action()


## Randomize a chosen enemy word (only valid while targeting).
func target_word(token_index: int) -> void:
	if state != ST_TARGET:
		return
	var r := GameLogic.scramble_one(enemy, token_index, _pools, _rng)
	if not r.get("ok", false):
		return
	pending_targets -= 1
	var note: String = "blocked by %s's ward!" % enemy.name if r.get("blocked", false) \
		else "→ randomized to '%s'." % r.get("text", "")
	changed.emit()
	if _check_end():
		return
	if pending_targets <= 0 or GameLogic.editable_indices(enemy.tokens).is_empty():
		_player_msg = "%s used %s (%s)" % [player.name, pending_label, note]
		_finish_player_action()
	else:
		logged.emit("%s  Click %d more enemy word(s)." % [note, pending_targets])


## A label describing the current phase (shared banner text).
func banner_text() -> String:
	match state:
		ST_CHOOSE: return "● YOUR TURN — use an item"
		ST_TARGET: return "◎ PICK A TARGET — click %d enemy word(s)" % pending_targets
		ST_BUSY: return "ENEMY TURN…"
		ST_OVER: return "GAME OVER"
	return ""


func _finish_player_action() -> void:
	var id := _battle_id
	logged.emit(_player_msg)
	state = ST_BUSY
	changed.emit()
	if _check_end():
		return
	await get_tree().create_timer(ENEMY_TURN_DELAY).timeout
	if id != _battle_id:
		return  # a new battle started during the pause; abandon this coroutine
	_enemy_turn()


func _enemy_turn() -> void:
	if state == ST_OVER:
		return
	var idx := GameLogic.next_item_index(enemy)
	var res := GameLogic.apply_item(enemy, player, idx, _pools, _rng)
	GameLogic.advance_cycle(enemy)
	logged.emit(_player_msg + "\n" + CombatText.describe(enemy.name, res, player.name))
	if _check_end():
		return
	state = ST_CHOOSE
	changed.emit()


func _check_end() -> bool:
	if int(enemy.hp) <= 0:
		_end("VICTORY — you defeated %s (HP 0)!" % enemy.name)
		return true
	if GameLogic.is_pacified(enemy.tokens):
		_end("VICTORY — %s is pacified: no negative words left!" % enemy.name)
		return true
	if int(player.hp) <= 0:
		_end("DEFEAT — %s knocked your HP to 0." % player.name)
		return true
	return false


func _end(msg: String) -> void:
	state = ST_OVER
	changed.emit()
	logged.emit(msg + "\nPress New Battle to play again.")
