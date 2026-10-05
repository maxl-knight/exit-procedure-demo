class_name EnemyFactory
extends RefCounted

## One place that turns a stat dictionary into a live Enemy, so rooms and the
## boss build identical creatures.
##
## `at` is a WORLD position: the caller converts from its own local space
## (rooms use `to_global()`) so enemies always land where they look like they do.


static func spawn(parent: Node, target: Node3D, at: Vector3, cfg: Dictionary) -> Enemy:
	var e := Enemy.new()
	e.configure(
		target,
		float(cfg.get("hp", 40.0)),
		float(cfg.get("dmg", 8.0)),
		float(cfg.get("spd", 3.4)),
		cfg.get("color", Color(0.7, 0.25, 0.25)),
		int(cfg.get("type", Enemy.Type.GRUNT)),
		int(cfg.get("elite", Enemy.Elite.NONE)))
	parent.add_child(e)
	e.global_position = at
	e.position.y = at.y
	return e


## Standard stat block for a room enemy, difficulty and room depth already
## folded in. `elite` multipliers are applied later by Enemy.configure().
static func room_cfg(type: int, elite: int, index: int, hp_scale: float = 1.0) -> Dictionary:
	var settings: Dictionary = GameManager.settings()
	var td: Dictionary = Enemy.TYPE_DATA[type]
	var hp_v: float = 40.0 * float(td["hp_mult"]) * float(settings["hp_mult"]) \
		* (1.0 + index * 0.14) * hp_scale
	var dmg: float = 8.0 * float(td["dmg_mult"]) * float(settings["dmg_mult"]) \
		* (1.0 + index * 0.05)
	var spd: float = minf(3.4 * float(td["spd_mult"]) * float(settings["speed_mult"]), 8.5)
	return {
		"hp": hp_v, "dmg": dmg, "spd": spd,
		"color": Room.enemy_color(type, elite),
		"type": type, "elite": elite,
	}
