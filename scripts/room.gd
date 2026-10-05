class_name Room
extends Node3D

signal cleared(room: Room)

const WIDTH := 36.0
const LENGTH := 36.0
## Nine units is roughly five player-heights: a hall rather than the bunker
## five read as. Everything in the shell is expressed as a function of this,
## so raising it scales walls, doorway and lintel together.
const HEIGHT := 9.0
const DOOR_W := 5.0
const DOOR_H := 4.0
const ENTRY_MARGIN := 3.0

## The lamp stays low even though the roof goes up: the floor was tuned
## against it and the arena is sealed, so nothing else lights the interior.
## Moving it to the ceiling would drop the floor about three times dimmer.
const FLOOR_LIGHT_Y := 5.5

## The size the original tuning (light falloff, camera) was done at. Rooms
## grew from 22 to 36 units, so anything hand-tuned gets scaled off this.
const REF_SIZE := 22.0

## The camera backs off as the arena grows, so a fight still fits in frame.
const CAMERA_DISTANCE := 6.5 + (LENGTH - REF_SIZE) * 0.15

## How far a telegraph box may reach before it counts as being through a
## wall, and the gap it keeps in front of the enemy's own body.
const WALL_PAD := 0.35
const TELEGRAPH_LEAD := 0.4

## Challenge rooms appear every 3-5 rooms: either an elite trial (which pays
## out as a 3-choice upgrade) or an upgrade cache that hands over a lasting buff.
enum Challenge { NONE, ELITE_TRIAL, VAULT }

## Hard ceiling on a room's garrison. The curve in _spawn_enemies() never
## stops climbing - it was fielding 30-odd bodies a room past room 20 - and
## past a certain point that stops being a fight and starts being a wall.
## Twelve, difficulty bonus and challenge adjustments included.
const MAX_ENEMIES := 12

## Short titles the Arena uses when it announces an adaptive test.
const ADAPTIVE_TITLES := {
	"dash": "SIMULATION ADAPTING: PREDICTIVE HAZARDS",
	"heal": "SIMULATION ADAPTING: RECONSTRUCTION SUPPRESSED",
	"melee": "SIMULATION ADAPTING: THEY KEEP THEIR DISTANCE",
	"ranged": "SIMULATION ADAPTING: THEY CLOSE THE GAP",
}

const ADAPTIVE_DESCS := {
	"dash": "Your movement was recorded. The traps no longer wait.",
	"heal": "The Arena watched how you survive. Healing is halved in here.",
	"melee": "Frontal engagement recorded. Archers will not let you close.",
	"ranged": "Ranged reliance recorded. Nothing stands at distance today.",
}

var index := 0
var enemies: Array = []
## The door logic hangs off these two: nothing spawns before the player
## walks in, and nothing opens until what spawned is dead.
var entered := false
var spawned := false
## Resolved room label (see RoomManager.kind_for): "combat", "elite",
## "upgrade", "adaptive", "recovery", "memory", "milestone", "boss" or
## "defect". Drives the floor markers, trap/enemy budget and the recovery
## payout; the HUD tag comes from kind_for() so both stay identical.
var kind := ""
var is_cleared := false
var challenge: int = Challenge.NONE
## Behaviour the Arena is testing here: "dash" / "heal" / "melee" / "ranged",
## or "" for an ordinary room. Announced on entry, rewarded on clear.
var adaptive := ""
var is_boss_room := false
var had_elite := false
## Whether this room fields an elite, decided by the schedule rather than
## rolled body by body (RoomManager.elite_for). At most one per room.
var elite_room := false
var palette := {}

var _player: Node3D
var _barrier: StaticBody3D
var _barrier_mesh: MeshInstance3D
var _back_barrier: StaticBody3D
var _back_mesh: MeshInstance3D
var _back_sealed := false
var _door_light_mat: StandardMaterial3D
var _taken_spots: Array = []
## Room-local footprints of every solid box the decor put on the floor, as
## {x, z, hx, hz}. Traps and spawns read this so nothing lands inside a
## pillar, and it doubles as the map the traversability test walks.
var _obstacles: Array = []


static func enemy_color(t: int, elite: int) -> Color:
	var base: Color
	match t:
		Enemy.Type.FAST:
			base = Color.from_hsv(0.36, 0.7, 0.85)
		Enemy.Type.BIG:
			base = Color.from_hsv(0.76, 0.5, 0.8)
		Enemy.Type.ARCHER:
			base = Color.from_hsv(0.13, 0.65, 0.9)
		_:
			base = Color.from_hsv(0.04, 0.55, 0.75)
	if elite != Enemy.Elite.NONE:
		return Color(Enemy.ELITE_DATA[elite]["color"]).lerp(base, 0.3)
	return base


func build(room_index: int, player: Node3D, cfg: Dictionary = {}) -> void:
	index = room_index
	_player = player
	challenge = int(cfg.get("challenge", Challenge.NONE))
	adaptive = str(cfg.get("adaptive", ""))
	elite_room = bool(cfg.get("elite", false))
	is_boss_room = bool(cfg.get("boss", false))
	# The schedule hands us a resolved label (see RoomManager.kind_for); this
	# fallback only covers hand-built rooms (tools, tests) with a bare cfg.
	kind = str(cfg.get("kind", ""))
	if kind == "":
		if is_boss_room:
			kind = "boss"
		elif challenge == Challenge.ELITE_TRIAL:
			kind = "elite"
		elif challenge == Challenge.VAULT:
			kind = "upgrade"
		elif adaptive != "":
			kind = "adaptive"
		elif index > 0 and index % GameManager.REALM_LENGTH == 0:
			kind = "milestone"
		else:
			kind = "combat"
	palette = Content.room_palette(GameManager.realm_of_room(index),
		index * 7919 + 13)

	_build_shell()
	_build_door()
	_build_back_barrier()
	_build_decor()
	if Engine.is_editor_hint():
		return
	if not is_boss_room:
		_spawn_traps()
	# The garrison stays dark until the player actually walks in - see enter().


## Called by the room manager the moment the player crosses the threshold.
## This is the only place enemies come into existence, so a room you have
## not entered is an empty room, and a room you have just entered starts fair
## (see ENTRY_GRACE) instead of already swinging at you.
func enter() -> void:
	if entered:
		return
	entered = true
	if Engine.is_editor_hint():
		return
	_spawn_enemies()
	# Safety net: a room that somehow put nothing on the floor opens at once
	# rather than soft-locking the run behind a closed door.
	if enemies.is_empty() and not is_boss_room and not is_cleared:
		_mark_cleared()


func challenge_name() -> String:
	match challenge:
		Challenge.ELITE_TRIAL:
			return "ELITE TRIAL"
		Challenge.VAULT:
			return "UPGRADE CACHE"
	return ""


func adaptive_title() -> String:
	return str(ADAPTIVE_TITLES.get(adaptive, ""))


func adaptive_desc() -> String:
	return str(ADAPTIVE_DESCS.get(adaptive, ""))


# -------------------------------------------------------------- geometry ----

func _build_shell() -> void:
	var floor_mat := Util.make_material(palette["floor"], 0.85, 0.05)
	var wall_mat := Util.make_material(palette["wall"], 0.9, 0.02)
	var ceil_mat := Util.make_material(palette["ceil"], 0.9, 0.02)

	Util.add_static_box(self, Vector3(WIDTH, 0.5, LENGTH), Vector3(0, -0.25, 0),
		floor_mat, Combat.LAYER_WORLD)
	Util.add_static_box(self, Vector3(WIDTH, 0.4, LENGTH), Vector3(0, HEIGHT + 0.2, 0),
		ceil_mat, Combat.LAYER_WORLD)

	Util.add_static_box(self, Vector3(0.5, HEIGHT, LENGTH),
		Vector3(-WIDTH / 2.0 - 0.25, HEIGHT / 2.0, 0), wall_mat, Combat.LAYER_WORLD)
	Util.add_static_box(self, Vector3(0.5, HEIGHT, LENGTH),
		Vector3(WIDTH / 2.0 + 0.25, HEIGHT / 2.0, 0), wall_mat, Combat.LAYER_WORLD)

	# The very first room is closed off behind the player.
	if index == 0:
		Util.add_static_box(self, Vector3(WIDTH, HEIGHT, 0.5),
			Vector3(0, HEIGHT / 2.0, LENGTH / 2.0 + 0.25), wall_mat, Combat.LAYER_WORLD)

	# Exit wall (with doorway) - this also serves as the next room's entry wall.
	var seg_w := (WIDTH - DOOR_W) / 2.0
	var z := -LENGTH / 2.0 - 0.25
	Util.add_static_box(self, Vector3(seg_w, HEIGHT, 0.5),
		Vector3(-(DOOR_W / 2.0 + seg_w / 2.0), HEIGHT / 2.0, z), wall_mat, Combat.LAYER_WORLD)
	Util.add_static_box(self, Vector3(seg_w, HEIGHT, 0.5),
		Vector3(DOOR_W / 2.0 + seg_w / 2.0, HEIGHT / 2.0, z), wall_mat, Combat.LAYER_WORLD)
	Util.add_static_box(self, Vector3(DOOR_W, HEIGHT - DOOR_H, 0.5),
		Vector3(0, DOOR_H + (HEIGHT - DOOR_H) / 2.0, z), wall_mat, Combat.LAYER_WORLD)


func _barrier_material() -> StandardMaterial3D:
	var m := Util.make_material(Color(1.0, 0.15, 0.1, 0.55), 0.2, 0.0,
		Color(1.0, 0.15, 0.1), 2.4)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = false
	return m


func _build_door() -> void:
	_door_light_mat = Util.make_material(Color(0.1, 0.1, 0.12), 0.4, 0.3,
		Color(1.0, 0.15, 0.1), 2.0)
	Util.add_box(self, Vector3(DOOR_W + 0.4, 0.16, 0.6),
		Vector3(0, DOOR_H + 0.1, -LENGTH / 2.0), _door_light_mat)

	_barrier = _make_barrier(_barrier_material())
	_barrier.position = Vector3(0, 0, -LENGTH / 2.0)
	add_child(_barrier)
	_barrier_mesh = _barrier.get_node("Mesh") as MeshInstance3D


## Every room beyond the first gets a shutter behind the entry doorway. It
## slams shut the moment you step in, so you can never walk back.
func _build_back_barrier() -> void:
	if index == 0:
		return
	_back_barrier = _make_barrier(_barrier_material())
	_back_barrier.position = Vector3(0, 0, LENGTH / 2.0)
	add_child(_back_barrier)
	_back_mesh = _back_barrier.get_node("Mesh") as MeshInstance3D
	_back_mesh.visible = false
	_back_barrier.collision_layer = 0
	_set_shape_disabled(_back_barrier, true)


func _make_barrier(mat: StandardMaterial3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Combat.LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(DOOR_W, DOOR_H, 0.35)
	cs.shape = shape
	cs.position = Vector3(0, DOOR_H / 2.0, 0)
	body.add_child(cs)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(DOOR_W, DOOR_H, 0.35)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(0, DOOR_H / 2.0, 0)
	body.add_child(mi)
	return body


## Called by the room manager as soon as the player crosses into this room.
func seal_back() -> void:
	if index == 0 or _back_barrier == null or _back_sealed:
		return
	_back_sealed = true
	_back_barrier.collision_layer = Combat.LAYER_WORLD
	call_deferred("_enable_shape", _back_barrier)
	_back_mesh.visible = true
	Sfx.play_at("door_close", to_global(Vector3(0, 1.5, LENGTH / 2.0)), -4.0)
	FX.burst(get_tree().current_scene, to_global(Vector3(0, 1.5, LENGTH / 2.0)),
		Color(1.0, 0.2, 0.1), 22, 0.12, 0.5, 5.0)
	_back_mesh.scale = Vector3(1.0, 0.05, 1.0)
	var tw := create_tween()
	tw.tween_property(_back_mesh, "scale", Vector3.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func is_back_sealed() -> bool:
	return _back_sealed


func back_solid() -> bool:
	if _back_barrier == null:
		return index == 0
	return _back_barrier.collision_layer == Combat.LAYER_WORLD


func _enable_shape(body: StaticBody3D) -> void:
	if body == null or not is_instance_valid(body):
		return
	_set_shape_disabled(body, false)


func _set_shape_disabled(body: StaticBody3D, disabled: bool) -> void:
	for child in body.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred("disabled", disabled)


## Longest attack telegraph (a box of half-width `half_width` running from
## `from` along `dir`) that still fits inside this room's interior.
##
## Depth testing already hides a box behind solid geometry, but the doorway
## and the (transparent, non depth-writing) barrier are genuine holes - so an
## archer's 13-unit lane used to be visible in the next room. Clamping the
## box to the interior closes that gap for good.
func clamp_attack_box(from: Vector3, dir: Vector3, max_len: float,
		half_width: float) -> float:
	var hx := WIDTH * 0.5 - WALL_PAD
	var hz := LENGTH * 0.5 - WALL_PAD
	var p := to_local(from)
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.0001:
		return max_len
	d = d.normalized()
	# Rooms are never rotated, so local == world for directions.
	var r := Vector3(-d.z, 0.0, d.x)
	var sides := [-half_width, half_width]
	var best := max_len
	for i in 2:
		var t := float(sides[i])
		# The far edge sits TELEGRAPH_LEAD + len ahead of the enemy origin.
		var ax: float = p.x + d.x * TELEGRAPH_LEAD + r.x * t
		var az: float = p.z + d.z * TELEGRAPH_LEAD + r.z * t
		best = minf(best, _axis_room_limit(ax, d.x, hx))
		best = minf(best, _axis_room_limit(az, d.z, hz))
		if best <= 0.0:
			return 0.0
	return clampf(best, 0.0, max_len)


## Largest `len >= 0` keeping `a + v * len` inside `[-limit, limit]`.
func _axis_room_limit(a: float, v: float, limit: float) -> float:
	if absf(v) < 0.0001:
		# Moving parallel to this wall: either it never constrains us or no
		# length can fix it.
		return INF if absf(a) <= limit else 0.0
	return (limit - a) / v if v > 0.0 else (-limit - a) / v


func _build_decor() -> void:
	var light := OmniLight3D.new()
	# The lamp does not follow the roof up: the floor was tuned against it at
	# its old height and the arena is sealed, so nothing else lights the
	# interior. It creeps up a little with the new headroom instead, and the
	# range stretches with the ceiling so the corners still get reached.
	light.position = Vector3(0, minf(HEIGHT - 0.7, FLOOR_LIGHT_Y), 0)
	# Falloff was tuned on 22-unit rooms; scale it (range faster than energy)
	# so a 36-unit arena still reaches its corners without blowing out.
	var grow := maxf(maxf(WIDTH, LENGTH) / REF_SIZE, 0.5)
	light.omni_range = randf_range(15.0, 19.0) * grow + (HEIGHT - 5.0) * 0.6
	light.light_energy = randf_range(1.3, 1.9) * sqrt(grow)
	light.light_color = palette["light"]
	light.shadow_enabled = false
	add_child(light)

	var pillar_mat := Util.make_material(palette["pillar"], 0.75, 0.1)
	var accent_mat := Util.make_material(palette["accent"], 0.4, 0.2,
		palette["accent"], 2.2)

	_apply_mood(light)
	_build_floor_layout(int(palette["decor"]), pillar_mat, accent_mat)
	_build_ceiling_fixture(int(palette.get("ceiling", 0)), pillar_mat, accent_mat)

	if challenge != Challenge.NONE:
		_build_challenge_marker()
	elif adaptive != "":
		_build_adaptive_marker()
	elif kind == "recovery":
		_build_ring_marker(Color(0.4, 1.0, 0.68))
	elif kind == "memory":
		_build_ring_marker(Color(0.72, 0.5, 1.0))


## One lamp or five, cold or warm: the same arena under a different lamp
## reads as a different room, and it costs almost nothing to roll one.
func _apply_mood(light: OmniLight3D) -> void:
	var color: Color = palette["light"]
	match int(palette.get("mood", 0)):
		1:
			# POOLS: a lower, softer wash plus two accent pools out by the
			# walls, so the middle of the floor is the brightest place.
			light.light_energy *= 0.78
			light.omni_range *= 0.85
			for i in 2:
				var pool := OmniLight3D.new()
				var sx := -1.0 if i == 0 else 1.0
				pool.position = Vector3(sx * (WIDTH / 2.0 - 7.0), 3.0,
					sx * (LENGTH / 2.0 - 10.0))
				pool.omni_range = 13.0
				pool.light_energy = 0.9
				pool.light_color = color
				pool.shadow_enabled = false
				add_child(pool)
		2:
			# COLD
			color = color.lerp(Color(0.6, 0.8, 1.0), 0.55)
		3:
			# WARM
			color = color.lerp(Color(1.0, 0.7, 0.42), 0.55)
			light.light_energy *= 1.05
		4:
			# DARK: half the lamp, same telegraphs - the emissive furniture
			# (trim, door, traps) does all the reading in here.
			light.light_energy *= 0.6
			light.omni_range *= 0.9
	light.light_color = color


## The lanes that have to stay empty: where you come in and where you get
## out. There is no jump in this game, so a solid box dropped across either
## one is not a difficulty spike, it is a run-ender.
func _keep_clear() -> Array:
	return [
		{"x": 0.0, "z": LENGTH / 2.0 - 5.0, "hx": 5.0, "hz": 5.0},
		{"x": 0.0, "z": -LENGTH / 2.0 + 4.0, "hx": 5.0, "hz": 4.0},
	]


func _box_hit(c: Vector2, hx: float, hz: float, o: Dictionary,
		pad: float = 0.0) -> bool:
	return absf(c.x - float(o["x"])) < hx + float(o["hx"]) + pad \
		and absf(c.y - float(o["z"])) < hz + float(o["hz"]) + pad


## A solid piece of decor: registers its footprint first, builds the collider
## second. Anything that would fence off an entry or exit lane is dropped
## rather than built, and nothing else is allowed to overlap it.
func _add_obstacle(size: Vector3, pos: Vector3, mat: Material, outline: float) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var c := Vector2(pos.x, pos.z)
	for k in _keep_clear():
		if _box_hit(c, hx, hz, k):
			return
	for o in _obstacles:
		if _box_hit(c, hx, hz, o):
			return
	_obstacles.append({"x": c.x, "z": c.y, "hx": hx, "hz": hz})
	Util.add_static_box(self, size, pos, mat, Combat.LAYER_WORLD, outline)


## Room-local point p sits inside a solid decor box (with `margin` to spare).
func _in_obstacle(p: Vector3, margin: float) -> bool:
	var c := Vector2(p.x, p.z)
	for o in _obstacles:
		if _box_hit(c, 0.0, 0.0, o, margin):
			return true
	return false


## Twelve floor plans. The first four are the originals - kept exactly as they
## were, only their pillars turned into real cover. Everything after that puts
## genuine mass into the play space so the arena is not always the same empty
## box you clear by running a circle round the outside.
func _build_floor_layout(id: int, pillar_mat: Material, accent_mat: Material) -> void:
	match id:
		0:
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_add_obstacle(Vector3(1.0, HEIGHT, 1.0),
						Vector3(sx * (WIDTH / 2.0 - 0.75), HEIGHT / 2.0,
							sz * (LENGTH / 2.0 - 0.75)), pillar_mat, 0.05)
		1:
			# Glowing floor trim instead of pillars - keeps the arena open.
			for sx in [-1.0, 1.0]:
				Util.add_box(self, Vector3(0.18, 0.06, LENGTH - 3.0),
					Vector3(sx * (WIDTH / 2.0 - 1.1), 0.03, 0), accent_mat, 0.0)
				Util.add_box(self, Vector3(0.14, 1.4, LENGTH - 3.0),
					Vector3(sx * (WIDTH / 2.0 - 0.4), HEIGHT - 1.0, 0), pillar_mat, 0.04)
		2:
			for sx in [-1.0, 1.0]:
				for sz in [-3.5, 3.5]:
					_add_obstacle(Vector3(1.2, HEIGHT, 1.2),
						Vector3(sx * (WIDTH / 2.0 - 1.0), HEIGHT / 2.0, sz),
						pillar_mat, 0.05)
		3:
			for sx in [-1.0, 1.0]:
				_add_obstacle(Vector3(0.8, HEIGHT, 0.8),
					Vector3(sx * (WIDTH / 2.0 - 0.7), HEIGHT / 2.0,
						LENGTH / 2.0 - 0.7), pillar_mat, 0.05)
			Util.add_box(self, Vector3(WIDTH - 2.0, 0.3, 0.8),
				Vector3(0, HEIGHT - 0.4, -2.5), pillar_mat, 0.04)
			Util.add_box(self, Vector3(WIDTH - 2.0, 0.3, 0.8),
				Vector3(0, HEIGHT - 0.4, 2.5), pillar_mat, 0.04)
		4:
			# Twin columns: mass off the centreline, the lanes stay open.
			for sx in [-1.0, 1.0]:
				_add_obstacle(Vector3(1.6, HEIGHT, 1.6),
					Vector3(sx * 7.0, HEIGHT / 2.0, 0.0), pillar_mat, 0.05)
		5:
			# One monolith, deliberately off centre: it splits the room
			# without owning it.
			_add_obstacle(Vector3(3.0, HEIGHT, 3.0),
				Vector3(5.5, HEIGHT / 2.0, -3.5), pillar_mat, 0.06)
		6:
			# Four buttresses at the third points - wide gaps between them.
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_add_obstacle(Vector3(1.8, HEIGHT, 1.8),
						Vector3(sx * 12.0, HEIGHT / 2.0, sz * 12.0),
						pillar_mat, 0.05)
		7:
			# Colonnade down one side: a wall to fight around.
			for sz in [-10.0, 0.0, 10.0]:
				_add_obstacle(Vector3(1.5, HEIGHT, 1.5),
					Vector3(-13.0, HEIGHT / 2.0, sz), pillar_mat, 0.05)
		8:
			# L-shaped block cluster in the near corner.
			_add_obstacle(Vector3(3.0, HEIGHT, 3.0),
				Vector3(11.0, HEIGHT / 2.0, 11.0), pillar_mat, 0.05)
			_add_obstacle(Vector3(3.0, HEIGHT, 3.0),
				Vector3(14.5, HEIGHT / 2.0, 11.0), pillar_mat, 0.05)
			_add_obstacle(Vector3(3.0, HEIGHT, 3.0),
				Vector3(11.0, HEIGHT / 2.0, 14.5), pillar_mat, 0.05)
		9:
			# Low plinths at the corners: cover you go around, never over.
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_add_obstacle(Vector3(2.4, 2.4, 2.4),
						Vector3(sx * 15.5, 1.2, sz * 15.5), pillar_mat, 0.05)
			for sz in [-1.0, 1.0]:
				Util.add_box(self, Vector3(WIDTH - 6.0, 0.2, 0.5),
					Vector3(0, HEIGHT - 1.4, sz * 7.0), accent_mat, 0.0)
		10:
			# The open one: wall ribs and trim, nothing on the floor.
			for sx in [-1.0, 1.0]:
				for sz in [-6.0, 6.0]:
					Util.add_box(self, Vector3(0.5, HEIGHT - 1.0, 0.5),
						Vector3(sx * (WIDTH / 2.0 - 0.6), (HEIGHT - 1.0) / 2.0, sz),
						pillar_mat, 0.05)
				Util.add_box(self, Vector3(0.18, 0.06, LENGTH - 4.0),
					Vector3(sx * (WIDTH / 2.0 - 1.4), 0.03, 0), accent_mat, 0.0)
		_:
			# Inlays plus a pair of corner pillars.
			for sx in [-1.0, 1.0]:
				_add_obstacle(Vector3(1.1, HEIGHT, 1.1),
					Vector3(sx * (WIDTH / 2.0 - 0.9), HEIGHT / 2.0,
						-(LENGTH / 2.0 - 0.9)), pillar_mat, 0.05)
			for sz in [-1.0, 1.0]:
				Util.add_box(self, Vector3(WIDTH - 8.0, 0.05, 0.22),
					Vector3(0, 0.04, sz * 5.0), accent_mat, 0.0)


## The roof was only worth looking at once the ceiling went up. All visual,
## all parked well above anything that can reach them (nothing in this game
## jumps), so they are scenery rather than surprise collision.
func _build_ceiling_fixture(id: int, pillar_mat: Material, accent_mat: Material) -> void:
	match id:
		1:
			# Roof trusses.
			for z in [-12.0, -4.0, 4.0, 12.0]:
				Util.add_box(self, Vector3(WIDTH - 1.5, 0.5, 0.7),
					Vector3(0, HEIGHT - 0.6, z), pillar_mat, 0.04)
				for sx in [-1.0, 1.0]:
					Util.add_box(self, Vector3(0.4, 1.3, 0.4),
						Vector3(sx * (WIDTH / 2.0 - 1.6), HEIGHT - 1.1, z),
						pillar_mat, 0.03)
		2:
			# A catwalk running the length of one wall.
			var side := -1.0 if int(palette["seed"]) % 2 == 0 else 1.0
			Util.add_box(self, Vector3(3.0, 0.35, LENGTH - 5.0),
				Vector3(side * (WIDTH / 2.0 - 4.0), HEIGHT - 1.9, 0),
				pillar_mat, 0.05)
			for z in [-10.0, 0.0, 10.0]:
				Util.add_box(self, Vector3(0.3, 1.4, 0.3),
					Vector3(side * (WIDTH / 2.0 - 4.0), HEIGHT - 1.1, z),
					pillar_mat, 0.03)
		3:
			# Pendant lamps: emissive, so the roof still reads in a DARK room.
			var lamp_mat := Util.make_material(Color(1.0, 0.95, 0.8), 0.3, 0.0,
				Color(1.0, 0.9, 0.66), 3.4)
			for p in [Vector2(-9.0, -9.0), Vector2(9.0, -3.0),
					Vector2(-4.0, 8.0), Vector2(10.0, 10.0)]:
				Util.add_box(self, Vector3(0.12, 2.2, 0.12),
					Vector3(p.x, HEIGHT - 1.7, p.y), pillar_mat, 0.0)
				Util.add_box(self, Vector3(1.1, 0.5, 1.1),
					Vector3(p.x, HEIGHT - 0.7, p.y), lamp_mat, 0.04)
		4:
			# Duct runs down the length of the room.
			for sx in [-1.0, 1.0]:
				Util.add_box(self, Vector3(1.6, 1.1, LENGTH - 4.0),
					Vector3(sx * 7.5, HEIGHT - 1.1, 0), pillar_mat, 0.04)
				Util.add_box(self, Vector3(2.4, 0.3, LENGTH - 4.0),
					Vector3(sx * 7.5, HEIGHT - 1.8, 0), accent_mat, 0.0)


## Shared floor ring + beacon so any special room reads at a glance.
func _build_ring_marker(col: Color) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 3.0
	torus.outer_radius = 3.3
	ring.mesh = torus
	ring.material_override = Util.make_material(col, 0.3, 0.0, col, 3.0)
	ring.position = Vector3(0, 0.08, 0)
	ring.rotation.x = PI / 2.0
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

	var beacon := OmniLight3D.new()
	beacon.position = Vector3(0, 2.2, 0)
	beacon.omni_range = 13.0 * maxf(maxf(WIDTH, LENGTH) / REF_SIZE, 0.5)
	beacon.light_color = col
	beacon.light_energy = 1.4
	beacon.shadow_enabled = false
	add_child(beacon)


## A cyan ring + cool beacon: the adaptive test reads as "the system is
## watching this one" rather than the gold/violet of a reward challenge.
func _build_adaptive_marker() -> void:
	_build_ring_marker(Color(0.35, 0.85, 1.0))


## A floor ring + banner light so a challenge room is obvious at a glance.
func _build_challenge_marker() -> void:
	var gold := challenge == Challenge.VAULT
	_build_ring_marker(Color(1.0, 0.85, 0.3) if gold else Color(0.9, 0.25, 0.95))


# ------------------------------------------------------------- spawning -----

func _spawn_traps() -> void:
	# A recovery bay is where you catch your breath - no spikes in there.
	if kind == "recovery":
		return
	# The minefield scaled with the floor too (22 -> 36 units): same shape,
	# steeper climb and a higher ceiling, with a wider berth around the door.
	var count := clampi(1 + index / 2, 1, 7)
	if GameManager.difficulty >= GameManager.Difficulty.HARD:
		count += 1
	# The dash test: reflexive movement gets punished with a faster cycle.
	var haste := 1.6 if adaptive == "dash" else 1.0
	if adaptive == "dash":
		count = mini(count + 1, 8)
	var trap_dmg := 12.0 * float(GameManager.settings()["dmg_mult"])
	for i in count:
		var spot := _find_spot(2.6, Vector3(0, 0, LENGTH / 2.0 - ENTRY_MARGIN), 7.0, 4.5)
		var trap := SpikeTrap.new()
		trap.damage = trap_dmg
		trap.haste = haste
		trap.position = spot
		add_child(trap)


## Mix of enemy types, unlocked gradually so the first rooms stay readable.
func _pick_type() -> int:
	var roll := randf()
	if index >= 3 and roll < 0.16:
		return Enemy.Type.BIG
	if index >= 2 and roll < 0.40:
		return Enemy.Type.ARCHER
	if index >= 1 and roll < 0.66:
		return Enemy.Type.FAST
	return Enemy.Type.GRUNT


## Adaptive rooms counter the behavior they are testing: the melee test
## fills the room with archers (they refuse to let you close), the ranged
## test floods it with runners (nothing stays at distance).
func _pick_adaptive_type() -> int:
	match adaptive:
		"melee":
			return Enemy.Type.ARCHER if randf() < 0.7 else Enemy.Type.GRUNT
		"ranged":
			return Enemy.Type.FAST if randf() < 0.7 else Enemy.Type.BIG
		"heal":
			# High single hits make every heal decision expensive.
			return Enemy.Type.BIG if randf() < 0.45 else _pick_type()
	return _pick_type()


## How many bodies this room fields, before a single one of them exists.
## Split out from the spawn itself so the schedule can be counted without
## building an arena.
##
## The garrison grew with the arena: 36 units of floor needs more bodies
## than 22 did, so past the opening pair every room fields one extra body
## and climbs a little steeper. The opening rooms still field exactly one,
## and 1 stays the floor - but the climb stops at MAX_ENEMIES, because an
## unbounded curve turns the back half of a run into a spawn screen.
func enemy_count_for(settings: Dictionary) -> int:
	var count := 1
	if index > 1:
		count = 2 + floori((index - 1) * 1.05)
	count = maxi(1, count + int(settings["enemy_bonus"]))
	match challenge:
		Challenge.ELITE_TRIAL:
			count = maxi(3, count - 1)
		Challenge.VAULT:
			count = maxi(1, count - 2)
	# Recovery is a breather: half the fight, never zero (0 would soft-lock).
	if kind == "recovery":
		count = maxi(1, count / 2)
	# Applied last, so every bonus - difficulty, challenge, recovery - is
	# capped by the same number.
	return mini(count, MAX_ENEMIES)


func _spawn_enemies() -> void:
	if is_boss_room:
		return
	spawned = true
	var count := enemy_count_for(GameManager.settings())

	# One elite, decided once for the whole room. Hand-built rooms (tools,
	# tests) pass a bare cfg, so an elite trial still fields its own there.
	var elite_slot := Enemy.Elite.NONE
	if count > 0 and (elite_room or challenge == Challenge.ELITE_TRIAL):
		elite_slot = Enemy.ELITE_KINDS[randi() % Enemy.ELITE_KINDS.size()]

	for i in count:
		var t := _pick_adaptive_type() if adaptive != "" else _pick_type()
		var elite := Enemy.Elite.NONE
		if i == 0:
			elite = elite_slot
			if elite != Enemy.Elite.NONE:
				had_elite = true

		if elite == Enemy.Elite.HEXMASTER:
			t = Enemy.Type.ARCHER
		elif elite == Enemy.Elite.JUGGERNAUT:
			t = Enemy.Type.BIG

		var data: Dictionary = Enemy.TYPE_DATA[t]
		var scale_v := float(data["scale"]) * (1.35 if elite != Enemy.Elite.NONE else 1.0)
		var spot := _find_spot(3.2 * scale_v,
			Vector3(0, 0, LENGTH / 2.0 - ENTRY_MARGIN), 7.5, 2.0 * scale_v)

		var cfg := EnemyFactory.room_cfg(t, elite, index,
			1.2 if challenge == Challenge.ELITE_TRIAL else 1.0)
		# `spot` is room-local, EnemyFactory.spawn() expects world space.
		var enemy := EnemyFactory.spawn(self, _player,
			to_global(spot + Vector3(0, 0.8 * scale_v, 0)), cfg)
		enemies.append(enemy)
		enemy.died.connect(_on_enemy_died)
		# Materialise instead of ambush: a beat before the fight starts.
		enemy.grace = Enemy.ENTRY_GRACE
		if elite != Enemy.Elite.NONE:
			Sfx.play_at("elite_spawn", enemy.global_position, -4.0)
		FX.burst(get_tree().current_scene, enemy.global_position,
			Color(0.65, 0.85, 1.0), 26, 0.13, 0.45, 5.5)


## Picks a local XZ position with margins, away from `away_from` and other spawns.
func _find_spot(margin: float, away_from: Vector3, min_dist: float,
		min_between: float) -> Vector3:
	var limit_x := WIDTH / 2.0 - margin
	var limit_z := LENGTH / 2.0 - margin
	var best := Vector3.ZERO
	var best_score := -1.0
	var found := false
	for attempt in 24:
		var p := Vector3(randf_range(-limit_x, limit_x), 0.0, randf_range(-limit_z, limit_z))
		# Out of every solid box the decor put down: a spike inside a pillar
		# is invisible, and a body spawned inside one never comes out.
		if _in_obstacle(p, margin):
			continue
		var d_away := Vector2(p.x - away_from.x, p.z - away_from.z).length()
		if d_away < min_dist:
			continue
		var too_close := false
		for other in _taken_spots:
			if Vector2(p.x - other.x, p.z - other.z).length() < min_between:
				too_close = true
				break
		if too_close:
			continue
		_taken_spots.append(p)
		return p
	# Fallback: the furliest open point we sampled.
	for attempt in 24:
		var p := Vector3(randf_range(-limit_x, limit_x), 0.0, randf_range(-limit_z, limit_z))
		if _in_obstacle(p, margin):
			continue
		var d := Vector2(p.x - away_from.x, p.z - away_from.z).length()
		if d > best_score:
			best_score = d
			best = p
			found = true
	# Every sample blocked: fall back to the exit lane, which by construction
	# can never hold an obstacle.
	var pick := best if found else Vector3(0.0, 0.0, -LENGTH / 2.0 + 4.0)
	_taken_spots.append(pick)
	return pick


# -------------------------------------------------------------- cleared -----

func _on_enemy_died(enemy: Enemy) -> void:
	enemies.erase(enemy)
	if enemies.is_empty() and not is_cleared:
		_mark_cleared()


func _mark_cleared() -> void:
	# The next door only unlocks once this room has been entered and every
	# enemy it put on the floor is dead. Never earlier, never twice.
	if is_cleared or not entered or not spawned:
		return
	if not enemies.is_empty():
		return
	is_cleared = true
	Sfx.play_at("room_clear", to_global(Vector3.ZERO))
	_open_barrier()
	cleared.emit(self)


func _open_barrier() -> void:
	Sfx.play_at("door_open", to_global(Vector3(0, 1.5, -LENGTH / 2.0)))
	_door_light_mat.emission = Color(0.2, 1.0, 0.45)
	_door_light_mat.emission_energy_multiplier = 3.0
	if _barrier != null:
		_barrier.collision_layer = 0
		call_deferred("_disable_barrier_collision")
	var tw := create_tween()
	tw.tween_property(_barrier_mesh, "position:y", -1.2, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_barrier_mesh, "scale", Vector3(1.0, 0.3, 1.0), 0.35)
	tw.tween_callback(_hide_barrier)


func _disable_barrier_collision() -> void:
	if _barrier != null and is_instance_valid(_barrier) and _barrier.collision_layer == 0:
		_set_shape_disabled(_barrier, true)


func _hide_barrier() -> void:
	if _barrier != null and is_instance_valid(_barrier):
		_barrier.visible = false
