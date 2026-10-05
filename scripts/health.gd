class_name Health
extends Node

## Tiny reusable health component.

signal damaged(amount: float, current: float, hit_position: Vector3)
signal healed(amount: float, current: float)
signal died

var max_health: float = 100.0
var health: float = 100.0
var invulnerable := false

## Seconds of post-hit grace left. A group of enemies should be able to hurt
## you badly, not chain-stun you into a death you had no input against.
var invuln_left := 0.0

## Frames of invulnerability granted after a hit lands. One is enough to stop
## six overlapping hits from counting separately.
const HIT_GRACE := 0.6


func setup(max_hp: float) -> void:
	max_health = maxf(max_hp, 1.0)
	health = max_health


func is_dead() -> bool:
	return health <= 0.0


## Marks the body untouchable for `seconds` (longest wins). Ticks down in
## _process so it survives scene timing without needing a timer node.
func grant_invulnerability(seconds: float) -> void:
	if seconds <= 0.0:
		return
	invuln_left = maxf(invuln_left, seconds)
	invulnerable = true


func _process(delta: float) -> void:
	if invuln_left <= 0.0:
		return
	invuln_left -= delta
	if invuln_left <= 0.0:
		invuln_left = 0.0
		invulnerable = false


func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO) -> bool:
	if invulnerable or health <= 0.0:
		return false
	health = maxf(0.0, health - amount)
	# Every hit buys a short window so a pack cannot pile the same swing on
	# five times over.
	grant_invulnerability(HIT_GRACE)
	damaged.emit(amount, health, hit_position)
	if health <= 0.0:
		died.emit()
	return true


func heal(amount: float) -> void:
	if health <= 0.0 or amount <= 0.0:
		return
	var before := health
	health = minf(max_health, health + amount)
	if health > before:
		healed.emit(health - before, health)


func fraction() -> float:
	return health / maxf(max_health, 0.001)
