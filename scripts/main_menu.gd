extends Control

## Hub-lite main menu: the Arena's waiting room rather than a level you walk.
## The backdrop, the voice line, the unlock stations and the record all read
## the persistent save, so the menu visibly changes as you go deeper - and as
## you finish runs. Everything long-winded lives behind the bottom row.

var selected_difficulty: int = 1
var selected_character: int = 0

var _diff_group: ButtonGroup
var _char_group: ButtonGroup
var _diff_buttons: Array = []
var _diff_desc: Label
var _char_desc: Label
var _hint: Label
var _chips: Label
## Kept so the counter only rewrites its text when the bank actually moves -
## the shop opens and closes over this screen.
var _chips_shown := -1
var _voice_label: Label
var _reveal_text := ""
var _reveal_at := 0

## The hub shows the body you are about to take.
var _preview_root: Node3D
var _preview_model: Node3D
var _preview_spin := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# The arena has air in it; the hub does not need it.
	Sfx.set_ambience(false)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_start_reveal(ArenaMemory.menu_line())
	_refresh_text()


func _process(delta: float) -> void:
	if _preview_model != null and is_instance_valid(_preview_model):
		_preview_spin += delta * 0.7
		_preview_model.rotation.y = CharacterModels.FACING_Y + _preview_spin
	# Buying something in the shop behind this screen must not leave the
	# counter on the front page telling the player they still have it.
	if _chips != null and is_instance_valid(_chips) and _chips_shown != GameManager.chips:
		_chips_shown = GameManager.chips
		_chips.text = "MEMORY CHIPS   %d" % _chips_shown
	if _reveal_at >= _reveal_text.length():
		return
	_reveal_at = mini(_reveal_text.length(), _reveal_at + 1 + int(delta * 60.0))
	_voice_label.text = _reveal_text.substr(0, _reveal_at)


## The room changes colour with the record: wing reached, Core broken, door
## taken. This is the cheapest possible "the hub changed because of you".
func _hub_bg() -> Color:
	match ArenaMemory.ending:
		"escape":
			return Color(0.01, 0.05, 0.045)
		"destroy":
			return Color(0.06, 0.018, 0.02)
		"control":
			return Color(0.03, 0.03, 0.085)
	if ArenaMemory.bosses_beaten > 0:
		return Color(0.05, 0.02, 0.03)
	if ArenaMemory.highest_room >= 40:
		return Color(0.05, 0.02, 0.06)
	if ArenaMemory.highest_room >= 20:
		return Color(0.01, 0.035, 0.045)
	if ArenaMemory.highest_room >= 5:
		return Color(0.03, 0.024, 0.014)
	return Color(0.015, 0.018, 0.03)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = _hub_bg()
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# The hub grew past one screen: the column scrolls rather than clipping,
	# and still centres itself whenever it happens to fit.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var col := UIKit.centered_column(scroll, 5)
	# Anchors are meaningless under a container: let the ScrollContainer own
	# the page's rect, and let EXPAND decide fill-versus-scroll. PASS so the
	# wheel keeps bubbling out of the page and into the scrollbar.
	var page := col.get_parent() as Control
	page.anchor_right = 0.0
	page.anchor_bottom = 0.0
	page.offset_right = 0.0
	page.offset_bottom = 0.0
	page.mouse_filter = Control.MOUSE_FILTER_PASS
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# The Arena speaks first - before the title, before any choice.
	_voice_label = UIKit.label(col, "", 16, Color(0.55, 0.95, 0.8))
	UIKit.outline(_voice_label, 5)

	var title := UIKit.label(col, "EXIT PROCEDURE", 48, Color(1, 1, 1))
	UIKit.outline(title, 14, Color(0.35, 0.12, 0.05))
	var sub := UIKit.label(col,
		"Reconstruction Wing, Adaptation Field, Core Perimeter  -  then The Core.",
		16, Color(0.6, 0.68, 0.8))
	UIKit.outline(sub, 5)

	_spacer(col, 8)

	# The two choices and the body they belong to sit side by side, so the
	# hub stops growing downward every time something is added to it.
	var mid := UIKit.row(col, 24)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_child(left)

	_build_difficulty(left)
	_spacer(left, 6)
	_build_character(left)
	_build_character_preview(mid)

	_spacer(col, 8)

	var action_row := UIKit.row(col, 16)
	var play := UIKit.button("PLAY", 26, Color(0.1, 0.3, 0.16),
		Color(0.14, 0.45, 0.24), Color(0.2, 0.65, 0.32), Vector2(260, 62))
	play.pressed.connect(_on_play)
	action_row.add_child(play)

	var quit := UIKit.button("Quit", 22, Color(0.24, 0.12, 0.12),
		Color(0.36, 0.17, 0.17), Color(0.6, 0.25, 0.25), Vector2(150, 62))
	quit.pressed.connect(get_tree().quit)
	action_row.add_child(quit)

	# Unlock stations: the two things you can earn, framed as places in the hub.
	var stations := UIKit.row(col, 14)
	stations.add_child(_station_hell())
	stations.add_child(_station_admin())

	_hint = UIKit.label(col, "", 15, Color(0.6, 0.65, 0.75))
	UIKit.outline(_hint, 4)

	# What the last run left in the bank, so the shop button below it has a
	# number to point at.
	_chips = UIKit.label(col, "", 17, Color(1.0, 0.85, 0.35))
	UIKit.outline(_chips, 5)

	_spacer(col, 4)
	# Everything that used to be a wall of panels under the fold is now three
	# doors: the hub shows a choice, not a manual.
	_menu_row(col)


func _build_difficulty(left: Node) -> void:
	UIKit.label(left, "DIFFICULTY", 19, Color(0.75, 0.8, 0.9))

	_diff_group = ButtonGroup.new()
	_diff_buttons.clear()
	var diff_row := UIKit.row(left, 10)
	diff_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	for i in 4:
		var b := _select_button(GameManager.DIFFICULTY_NAMES[i], _diff_group, 168, 46)
		if i == GameManager.Difficulty.HELL and not GameManager.hell_unlocked:
			b.disabled = true
			b.text = "HELL locked"
		b.pressed.connect(_on_difficulty.bind(i))
		diff_row.add_child(b)
		_diff_buttons.append(b)
		if i == selected_difficulty:
			b.button_pressed = true

	# Wrapped to a fixed column so a long line can never widen the page and
	# shove the rows underneath it off screen.
	_diff_desc = UIKit.label(left, "", 16, Color(0.65, 0.7, 0.8))
	_diff_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diff_desc.custom_minimum_size = Vector2(460, 0)
	UIKit.outline(_diff_desc, 4)


func _build_character(left: Node) -> void:
	UIKit.label(left, "CHARACTER", 19, Color(0.75, 0.8, 0.9))

	_char_group = ButtonGroup.new()
	var char_row := UIKit.row(left, 12)
	char_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	for i in GameManager.CHARACTER_NAMES.size():
		var b := _select_button(GameManager.CHARACTER_NAMES[i], _char_group, 210, 50)
		b.pressed.connect(_on_character.bind(i))
		char_row.add_child(b)
		if i == selected_character:
			b.button_pressed = true

	_char_desc = UIKit.label(left, "", 16, Color(0.65, 0.7, 0.8))
	_char_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_char_desc.custom_minimum_size = Vector2(460, 0)
	UIKit.outline(_char_desc, 4)


# ------------------------------------------------------------------ hub -----

## Pressing an unlocked station does something: Hell jumps you to the mode,
## Administration reports that the chair is yours.
func _station_hell() -> Button:
	var open := GameManager.hell_unlocked
	var b := UIKit.button(
		"STATION  -  HELL   %s" % ("OPEN" if open else "SEALED  -  beat The Core on Hard"),
		16, Color(0.26, 0.1, 0.1), Color(0.34, 0.14, 0.13), Color(0.5, 0.2, 0.18),
		Vector2(340, 38))
	b.disabled = not open
	if open:
		b.pressed.connect(_on_station_hell)
	return b


func _station_admin() -> Button:
	var open := GameManager.endless_admin
	var b := UIKit.button(
		"STATION  -  ENDLESS ADMINISTRATION   %s"
		% ("OPEN" if open else "SEALED  -  Take Control"),
		16, Color(0.1, 0.13, 0.26), Color(0.14, 0.18, 0.34), Color(0.24, 0.3, 0.6),
		Vector2(400, 38))
	b.disabled = not open
	if open:
		b.pressed.connect(_on_station_admin)
	return b


func _on_station_hell() -> void:
	_on_difficulty(GameManager.Difficulty.HELL)
	if _diff_buttons.size() > GameManager.Difficulty.HELL:
		(_diff_buttons[GameManager.Difficulty.HELL] as Button).button_pressed = true
	_start_reveal("ARENA: reconstruction wing primed. do not waste it.")


func _on_station_admin() -> void:
	_start_reveal("ARENA: the chair is yours. the Arena runs itself now.")


func _start_reveal(text: String) -> void:
	_reveal_text = text
	_reveal_at = 0
	_voice_label.text = ""


# ------------------------------------------------------------ reference -----

## Controls, upgrades, settings and the record, each behind its own door. The
## hub used to print all four on the front page; now it offers a choice.
func _menu_row(col: Node) -> void:
	var row := UIKit.row(col, 14)
	row.add_child(_screen_button("Upgrades", Color(0.1, 0.22, 0.14),
		Color(0.14, 0.3, 0.2), Color(0.24, 0.55, 0.34), _open_upgrades))
	row.add_child(_screen_button("Controls", Color(0.1, 0.13, 0.2),
		Color(0.15, 0.19, 0.3), Color(0.25, 0.34, 0.6), _open_controls))
	row.add_child(_screen_button("Settings", Color(0.14, 0.12, 0.2),
		Color(0.2, 0.18, 0.32), Color(0.38, 0.32, 0.66), _open_settings))
	row.add_child(_screen_button("Arena Log", Color(0.07, 0.15, 0.16),
		Color(0.1, 0.21, 0.23), Color(0.2, 0.45, 0.5), _open_log))


func _screen_button(text: String, n: Color, h: Color, pr: Color, cb: Callable) -> Button:
	var b := UIKit.button(text, 19, n, h, pr, Vector2(210, 48))
	b.pressed.connect(cb)
	return b


func _open_controls() -> void:
	InfoScreen.open_on(self, "CONTROLS", InfoScreen.controls_lines())


func _open_upgrades() -> void:
	UpgradeScreen.open_on(self)


func _open_settings() -> void:
	SettingsScreen.open_on(self)


func _open_log() -> void:
	InfoScreen.open_on(self, "ARENA LOG", _log_lines())


## The whole persistent record as a list of lines: the old log panel, the
## projection and the fragment archive, all read off the same save file.
func _log_lines() -> Array:
	var out: Array = []
	if GameManager.game_beaten:
		out.append("THE CORE   broken")
	out.append("best score   %d" % GameManager.best_score)
	out.append("adaptive tests survived   %d" % ArenaMemory.adaptive_total())
	out.append("reconstructions   %d" % ArenaMemory.runs)
	out.append("deaths   %d" % ArenaMemory.deaths)
	out.append("best room   %d" % ArenaMemory.highest_room)
	out.append("deaths this body   %d" % int(
		ArenaMemory.deaths_by_char.get(selected_character, 0)))
	out.append("cores broken   %d" % ArenaMemory.bosses_beaten)
	out.append("fragments   %d" % ArenaMemory.fragments_seen)

	var end_label := "unwritten"
	if Content.ENDINGS.has(ArenaMemory.ending):
		end_label = str(Content.ENDINGS[ArenaMemory.ending]["title"])
	out.append("ending   %s" % end_label)

	for cause in ArenaMemory.KNOWN_CAUSES:
		var cause_n := int(ArenaMemory.deaths_by_cause.get(cause, 0))
		if cause_n > 0:
			out.append("%s deaths   %d" % [cause, cause_n])

	out.append("")
	out.append("PROJECTION")
	out.append(ArenaMemory.menu_projection())
	out.append("")
	out.append("ARCHIVE  -  FRAGMENTS")
	var fragments := ArenaMemory.fragment_log()
	if fragments.is_empty():
		out.append("no fragments recovered")
	else:
		for frag in fragments:
			out.append(str(frag))
	return out


func _select_button(text: String, group: ButtonGroup, w: float, h: float) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", 19)
	UIKit.style_button(b, Color(0.1, 0.12, 0.18), Color(0.16, 0.2, 0.3),
		Color(0.24, 0.42, 0.85), Color(0.08, 0.09, 0.12, 0.7))
	UIKit.soundify(b, "ui_select")
	return b


func _spacer(parent: Node, height: float) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	parent.add_child(s)


# ------------------------------------------------------------- handlers ------

func _on_difficulty(index: int) -> void:
	selected_difficulty = index
	_refresh_text()


## Who you are about to play, in the flesh: the same rigged model the arena
## uses, lit and turning on the hub floor so a click on the name actually
## shows you the swap.
func _build_character_preview(col: Control) -> void:
	var frame := SubViewportContainer.new()
	frame.stretch = true
	frame.custom_minimum_size = Vector2(320.0, 300.0)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(frame)

	var view := SubViewport.new()
	view.transparent_bg = true
	view.own_world_3d = true
	frame.add_child(view)

	var root := Node3D.new()
	view.add_child(root)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, -40.0, 0.0)
	key.light_energy = 1.5
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24.0, 140.0, 0.0)
	fill.light_energy = 0.55
	root.add_child(fill)

	# Close enough to fill the frame with a 1.76-unit body, far enough back
	# that a greatsword tip stays inside it.
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.0, -3.6)
	cam.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	cam.fov = 32.0
	root.add_child(cam)
	cam.current = true

	_preview_root = root
	_swap_preview()


## Swapping bodies: the old one goes, the new one drops into the same spot
## and starts its idle clip.
func _swap_preview() -> void:
	if _preview_root == null:
		return
	if _preview_model != null and is_instance_valid(_preview_model):
		_preview_model.free()
	_preview_model = CharacterModels.build(_preview_root, selected_character)
	_preview_spin = 0.0
	if _preview_model == null:
		return
	var anim := CharacterModels.animation_player(_preview_model)
	if anim != null:
		CharacterModels.prime(anim)
		anim.play("Idle")


func _on_character(index: int) -> void:
	selected_character = index
	_refresh_text()
	_swap_preview()


func _refresh_text() -> void:
	_diff_desc.text = str(GameManager.DIFFICULTY_SETTINGS[selected_difficulty]["desc"])
	_char_desc.text = str(Player.DATA[selected_character]["desc"])
	_chips_shown = GameManager.chips
	_chips.text = "MEMORY CHIPS   %d" % _chips_shown
	if GameManager.hell_unlocked:
		_hint.text = "Hell is open  -  you beat The Core on Hard."
		_hint.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))
	else:
		_hint.text = "Defeat The Core on Hard to unlock Hell mode."
		_hint.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))


func _on_play() -> void:
	# A last "confirmed" over the top of the button's own click, so starting a
	# run sounds like a decision rather than like opening a panel.
	Sfx.play("ui_done")
	GameManager.start_run(selected_difficulty, selected_character)
	get_tree().change_scene_to_file("res://scenes/game.tscn")
