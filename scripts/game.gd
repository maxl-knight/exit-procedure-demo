extends Node3D

## Game scene root: builds the world, the player, the UI and owns the run state.

enum State { PLAYING, PAUSED, CHOOSING, VICTORY, OVER }

const MENU_SCENE := "res://scenes/main_menu.tscn"

const REALM_BANNER := {
	0: Color(1.0, 0.4, 0.25),
	1: Color(0.4, 1.0, 0.6),
	2: Color(1.0, 0.92, 0.6),
}

var state: int = State.PLAYING

var player: Player
var camera_rig: CameraRig
var room_manager: RoomManager
var hud: HUD
var pause_menu: PauseMenu
var game_over: GameOverScreen
var choice: ChoiceScreen
var victory: VictoryScreen
var ending: EndingChoice

var boss: TheCreator
var _env: Environment
var _sun: DirectionalLight3D
var _realm := -1
var _boss_started := false


func _ready() -> void:
	_build_environment()

	player = Player.new()
	player.character_type = GameManager.character
	player.position = Vector3(0, 0.2, 6)
	add_child(player)

	camera_rig = CameraRig.new()
	add_child(camera_rig)
	camera_rig.set_target(player)
	# Bigger arenas need a camera that can actually see them.
	camera_rig.distance = Room.CAMERA_DISTANCE
	player.camera = camera_rig

	room_manager = RoomManager.new()
	room_manager.player = player
	add_child(room_manager)
	room_manager.room_entered.connect(_on_room_entered)
	room_manager.room_cleared.connect(_on_room_cleared)

	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)

	hud = HUD.new()
	hud.setup(player)
	ui.add_child(hud)
	# One edge marker pointing at the nearest enemy you cannot see - rooms
	# are big enough now that "where did he go" is a real question.
	hud.watch_threats(camera_rig.camera, room_manager)

	# Room 0 has no entry edge (the run starts already standing in it), so
	# the HUD is primed by hand the same way the room manager wakes its
	# garrison by hand.
	_prime_hud_for_first_room()

	pause_menu = PauseMenu.new()
	pause_menu.game = self
	ui.add_child(pause_menu)

	game_over = GameOverScreen.new()
	game_over.game = self
	ui.add_child(game_over)

	choice = ChoiceScreen.new()
	choice.chosen.connect(_on_choice_made)
	ui.add_child(choice)

	victory = VictoryScreen.new()
	victory.descend.connect(_on_descend)
	victory.to_menu.connect(go_menu)
	ui.add_child(victory)

	ending = EndingChoice.new()
	ending.chosen.connect(_on_ending_chosen)
	ui.add_child(ending)

	player.died.connect(_on_player_died)
	ArenaMemory.voice.connect(_on_arena_voice)
	# The record is written by whichever end screen opens first; the Arena
	# only needs to know when it actually moved.
	GameManager.score_recorded.connect(_on_score_recorded)

	_realm = GameManager.realm_of_room(0)
	_apply_realm(_realm)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Sfx.set_ambience(true)
	hud.show_banner("EXIT PROCEDURE", Color(1.0, 0.85, 0.4), 2.2)
	_show_first_run_hints()


## The opening room never reports an entry, so its room tag, objective and
## enemy total are set here instead of in _on_room_entered.
func _prime_hud_for_first_room() -> void:
	var r := room_manager.room_at(0)
	if r == null:
		return
	hud.current_room = 0
	hud.set_room_kind(room_manager.kind_for(0))
	hud.set_room_total(r.enemies.size())
	hud.set_objective(_objective_for(r))
	# Room 0 has no entry edge, so it opens on its own sting here - otherwise
	# the run starts in silence while every room after it announces itself.
	Sfx.play("room_start")


## The first reconstruction ever gets three short instructions, spaced out so
## they arrive one at a time instead of as a wall of text.
func _show_first_run_hints() -> void:
	if not is_instance_valid(hud) or ArenaMemory.runs > 1:
		return
	var tree := get_tree()
	hud.show_hint_once("move", "WASD to move   -   mouse to look", 4.2)
	tree.create_timer(4.8).timeout.connect(func() -> void:
		if is_instance_valid(hud):
			hud.show_hint_once("strike", "LEFT CLICK to strike   -   they read you while you wind up", 4.6))
	tree.create_timer(9.9).timeout.connect(func() -> void:
		if is_instance_valid(hud):
			hud.show_hint_once("abilities", "SHIFT dash    Q super    E heal", 5.0))


func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.008, 0.01, 0.018)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.36, 0.4, 0.55)
	_env.ambient_light_energy = 0.65
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.15
	_env.glow_enabled = true
	_env.glow_intensity = 0.7
	_env.glow_bloom = 0.15
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.05, 0.06, 0.1)
	_env.fog_light_energy = 0.6
	_env.fog_density = 0.012
	world_env.environment = _env
	add_child(world_env)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-50, -35, 0)
	_sun.light_color = Color(1.0, 0.96, 0.88)
	_sun.light_energy = 1.0
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 70.0
	add_child(_sun)


func _apply_realm(realm: int) -> void:
	if not Content.REALM.has(realm):
		return
	var p: Dictionary = Content.REALM[realm]
	var sun_colors := [Color(1.0, 0.6, 0.45), Color(0.9, 1.0, 0.95), Color(1.0, 0.97, 0.85)]
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_env, "fog_light_color", p["fog"], 1.4)
	tw.tween_property(_env, "ambient_light_color", p["ambient"], 1.4)
	tw.tween_property(_env, "background_color", p["bg"], 1.4)
	tw.tween_property(_sun, "light_color", sun_colors[clampi(realm, 0, 2)], 1.4)


func _process(delta: float) -> void:
	if state == State.PLAYING:
		GameManager.room_time += delta
	if is_instance_valid(hud) and room_manager != null:
		hud.set_enemies_left(room_manager.enemies_in(room_manager.current_index))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()


# --------------------------------------------------------------- events -----

func _on_room_entered(index: int) -> void:
	GameManager.reset_room_stats()
	player.arena_heal_mult = 1.0
	hud.current_room = index
	var room := room_manager.room_at(index)
	# The HUD always shows what kind of room this is, even if the banner
	# gets stolen by something louder (defect, boss).
	hud.set_room_kind(room_manager.kind_for(index))
	hud.set_room_total(0 if room == null else room.enemies.size())
	hud.set_objective(_objective_for(room))

	var realm := GameManager.realm_of_room(index)
	var realm_changed := realm != _realm
	if realm_changed:
		_realm = realm
		_apply_realm(realm)

	if GameManager.is_boss_room(index) and not _boss_started:
		# The Core's door is the last boundary the record knows about.
		ArenaMemory.speak_final_wing()
		_spawn_boss(index)

	if state != State.PLAYING:
		return
	# Every room opens with the same low sting so a new arena announces itself
	# even when a banner is about to say something louder over the top of it.
	Sfx.play("room_start")

	# A defect is the loudest thing that can happen to you - say it plainly.
	if room_manager.is_curse_room(index):
		var id := player.apply_random_curse()
		var data: Dictionary = Content.CURSES.get(id, {})
		var curse_name := str(data.get("name", id)).to_upper()
		var desc := str(data.get("desc", ""))
		Sfx.play("curse")
		hud.show_banner("SYSTEM DEFECT INSTALLED\n%s  -  %s" % [curse_name, desc],
			Color(0.9, 0.3, 0.9), 5.0)
		return

	if room != null and room.is_boss_room:
		hud.show_banner("THE CORE PERIMETER", Color(1.0, 0.9, 0.5), 3.0)
		return
	if room != null and room.challenge != Room.Challenge.NONE:
		hud.show_banner(room.challenge_name(),
			Color(1.0, 0.3, 0.95) if room.challenge == Room.Challenge.ELITE_TRIAL
			else Color(1.0, 0.85, 0.3), 2.4)
		return
	if room != null and room.adaptive != "":
		_enter_adaptive(room)
		return
	if room != null and room.kind == "recovery":
		hud.show_banner("RECOVERY BAY\nClear the room to be reconstructed",
			Color(0.4, 1.0, 0.68), 3.2)
		return
	if room != null and room.kind == "memory":
		hud.show_banner("MEMORY ROOM", Color(0.72, 0.5, 1.0), 2.4)
		ArenaMemory.speak_fragment()
		return
	if realm_changed:
		hud.show_banner("ENTERING  %s" % GameManager.REALM_NAMES[realm],
			REALM_BANNER.get(realm, Color.WHITE), 2.6)
		return

	hud.show_banner("Room %d   -   %s" % [index + 1, GameManager.realm_name(index)],
		Color(0.6, 0.85, 1.0), 1.6)


## What the current room wants, in one line that stays put for the whole
## room instead of scrolling away with a banner.
func _objective_for(room: Room) -> String:
	if room == null:
		return ""
	if room.is_boss_room:
		return "Break its summons, then finish it"
	if room.adaptive != "":
		return "TEST   %s" % str(room.adaptive_title()).to_upper()
	if room.challenge == Room.Challenge.ELITE_TRIAL:
		return "Put the elite down"
	if room.challenge == Room.Challenge.VAULT:
		return "Clear it and the cache opens"
	if room.kind == "recovery":
		return "Clear the room to be reconstructed"
	if room.kind == "memory":
		return "Something is buried in here"
	if room.kind == "elite":
		return "An elite is waiting"
	return ""


func _on_room_cleared(index: int) -> void:
	if state != State.PLAYING:
		return
	ArenaMemory.note_room(GameManager.rooms_cleared)
	hud.set_objective("")
	var room := room_manager.room_at(index)
	if room == null or room.is_boss_room:
		return

	# What the room was worth, how long you took, and anything it banked.
	var line := "CLEARED   %.1fs   +%d" % [GameManager.room_time,
		int(round(GameManager.last_room_gain))]
	# Every clear banks a dash charge back - the arenas got much bigger.
	# Hell does not: the chair takes that one back.
	if GameManager.difficulty != GameManager.Difficulty.HELL and player.refund_dash():
		line += "    +1 DASH CHARGE"
	hud.show_toast(line, Color(0.4, 1.0, 0.55), 2.2)

	if room.challenge == Room.Challenge.VAULT:
		# The cache opens as a choice, so the handout reads the same way an
		# elite's does - name, effect, and the Arena's reason for giving it.
		_open_choice("UPGRADE CACHE", "The cache opens - take one",
			Content.random_buffs(3))
		return

	if room.had_elite:
		_open_choice("ELITE DEFEATED", "Pick one upgrade  -  all twelve stack",
			Content.random_buffs(3))
		return

	if room.adaptive != "":
		ArenaMemory.note_adaptive(room.adaptive)
		if room.adaptive == "heal":
			# The Arena concedes the point: reconstruction works again.
			player.health.heal(player.max_health_now() * 0.3)
		# The reward always counters the tested habit: proof the test had a point.
		_open_choice("SIMULATION CLEARED", "Your habit cost you - take the counter",
			Content.counter_options(room.adaptive, 3))
		return

	if room.kind == "recovery":
		# Reconstruction runs hot in here: 35% of max back on clear, plus a
		# mote left on the floor for later.
		player.health.heal(player.max_health_now() * 0.35)
		_drop_mote(room)
		hud.show_banner("RECONSTRUCTION COMPLETE\n+35% health",
			Color(0.4, 1.0, 0.68), 2.6)
		return

	if room.kind == "milestone":
		# A realm wall is the one boundary the Arena admits it lost control of.
		# It pays out, and it says so.
		ArenaMemory.speak_wing(GameManager.realm_of_room(index))
		_open_choice("WING CROSSED",
			"The Arena concedes a boundary - pick one upgrade",
			Content.random_buffs(3))
		return

	hud.show_banner("Room %d cleared" % (index + 1), Color(0.4, 1.0, 0.55), 1.7)


## A recovery mote left on the floor: the bay's own idea of a receipt.
func _drop_mote(room: Room) -> void:
	if room == null or not is_instance_valid(room):
		return
	var orb := HealthOrb.new()
	orb.player = player
	room.add_child(orb)
	orb.global_position = room.to_global(Vector3(0, 0.9, 0))


## Announce the test, switch on its modifiers, and let the Arena say why.
func _enter_adaptive(room: Room) -> void:
	player.arena_heal_mult = 0.5 if room.adaptive == "heal" else 1.0
	hud.show_banner("%s\n%s" % [room.adaptive_title(), room.adaptive_desc()],
		Color(0.35, 0.85, 1.0), 4.0)
	ArenaMemory.speak("adapt")


func _open_choice(title: String, detail: String, options: Array) -> void:
	if state != State.PLAYING or options.is_empty():
		return
	state = State.CHOOSING
	choice.open(title, detail, options, player.buffs)


func _on_choice_made(id: String) -> void:
	player.apply_buff(id)
	if state == State.CHOOSING:
		state = State.PLAYING
	var data: Dictionary = Content.BUFFS.get(id, {})
	hud.show_banner("%s  x%d" % [str(data.get("name", id)).to_upper(),
		player.buff_stacks(id)], data.get("color", Color.WHITE), 2.0)


func _on_player_died() -> void:
	if state == State.OVER:
		return
	state = State.OVER
	ArenaMemory.note_death(player.last_hit_source)
	# Show the death screen first - nothing else may get in its way.
	game_over.show_stats()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	hud.clear_bars()


# ------------------------------------------------------------------ boss ----

func _spawn_boss(index: int) -> void:
	var room := room_manager.room_at(index)
	if room == null or boss != null:
		return
	_boss_started = true
	boss = TheCreator.new()
	boss.target = player
	room.add_child(boss)
	boss.position = Vector3(0, 0.1, -5.5)
	Sfx.play("boss_spawn")
	boss.died.connect(_on_boss_died)
	# The Core narrates its own fight: guard, exposure, stun, the copy.
	boss.phase_changed.connect(_on_boss_phase)
	hud.watch_boss(boss)
	get_tree().create_timer(0.3).timeout.connect(func():
		# A freed instance is not null, so this one has to ask the harder
		# question: 0.3s is long enough for the scene to have been swapped.
		if is_instance_valid(hud):
			hud.show_banner("THE CORE", Color(1.0, 0.9, 0.5), 3.0)
		# The Core has watched every reconstruction: it opens with whatever
		# your death count has earned you.
		ArenaMemory.speak_boss())


## The Core narrates its own fight out loud. This used to be a dead signal.
func _on_boss_phase(label: String, detail: String) -> void:
	if not is_instance_valid(hud):
		return
	# Each phase carries its own weight: the guard coming up is neutral, the
	# stun and the exposure are the best news in the fight, phase two and the
	# copy are the moment the floor moves. One voice per event, never two.
	if label.contains("EXPOSED") or label.contains("STUNNED"):
		Sfx.play("room_clear", -3.0, 1.1, 0.02)
	elif label.contains("CLONE"):
		Sfx.play("desperation", -5.0, 1.05, 0.02)
	elif label.contains("PHASE"):
		Sfx.play("curse", -3.0, 0.92, 0.03)
	else:
		Sfx.play("ui_warn", -5.0, 0.95, 0.04)
	hud.show_banner("%s\n%s" % [label, detail],
		Color(1.0, 0.45, 0.3) if label.contains("EXPOSED") or label.contains("STUNNED")
		else Color(1.0, 0.9, 0.5), 3.0)


func _on_boss_died() -> void:
	hud.clear_boss()
	boss = null
	Sfx.play("victory")
	GameManager.add_room()
	GameManager.beat_game()
	ArenaMemory.note_boss()
	# A boss room never fires Room.cleared, so the record would otherwise stop
	# one room short of the score this run actually earned.
	ArenaMemory.note_room(GameManager.rooms_cleared)
	state = State.VICTORY
	if GameManager.endless:
		# Already took the chair once - no more doors to choose.
		victory.show_stats()
		return
	# First clear: the record opens three doors, right here in the arena.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ending.open()


func _on_ending_chosen(id: String) -> void:
	GameManager.apply_ending(id)
	victory.show_stats()


## The Arena talking: relay its reaction to the HUD subtitle bar.
func _on_arena_voice(text: String) -> void:
	if is_instance_valid(hud):
		hud.show_voice(text)


func _on_score_recorded(is_new_best: bool) -> void:
	if is_new_best:
		ArenaMemory.speak_score_record()


func _on_descend() -> void:
	GameManager.endless = true
	state = State.PLAYING
	_boss_started = false
	room_manager.descend()
	Sfx.play("boss_spawn", -3.0, 0.92, 0.03)
	hud.show_banner("YOU BREAK CONTAINMENT\nthe wings open below you",
		Color(1.0, 0.3, 0.2), 3.4)


# -------------------------------------------------------------- control -----

## The pause key lands in _unhandled_input and in PauseMenu._process in the
## same frame, so a single Esc used to fire this twice - open, then instantly
## close - and the menu never appeared. Two toggles in one frame now collapse
## into one.
var _toggle_frame := -1


func toggle_pause() -> void:
	if state == State.OVER or state == State.VICTORY or state == State.CHOOSING:
		return
	var frame := Engine.get_process_frames()
	if frame == _toggle_frame:
		return
	_toggle_frame = frame
	if state == State.PLAYING:
		state = State.PAUSED
		Sfx.play("ui_back", -4.0)
		pause_menu.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().paused = true
	else:
		# Leaving the menu takes any reference panel with it, so the run never
		# resumes underneath a settings screen that is still open.
		UIKit.close_overlays()
		state = State.PLAYING
		Sfx.play("ui_click", -4.0)
		pause_menu.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_tree().paused = false


func restart() -> void:
	get_tree().paused = false
	GameManager.start_run(GameManager.difficulty, GameManager.character)
	get_tree().reload_current_scene()


func go_menu() -> void:
	# Every way out of a run pays out, not just the two end screens: leaving
	# from the pause menu would otherwise quietly throw the score away.
	GameManager.bank_run_score()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)
