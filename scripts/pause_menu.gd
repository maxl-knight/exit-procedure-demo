class_name PauseMenu
extends Control

## Lives on the UI layer with PROCESS_MODE_ALWAYS so it can catch Esc while the
## tree is paused. It stays deliberately short: the long-form reference material
## lives behind the two buttons at the bottom.

var game: Variant

var _stat_kills: Label
var _stat_rooms: Label
var _stat_score: Label
var _stat_streak: Label
var _stat_best_streak: Label
var _stat_difficulty: Label
var _stat_character: Label
## The last set of numbers written out, so the panel is not re-laying itself
## out every frame while the tree sits paused.
var _stats_sig := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func _process(_delta: float) -> void:
	if visible:
		_refresh_stats()


## Esc is read here instead of polled in _process. Polling it meant both this
## screen and Game._unhandled_input could act on the same press in the same
## frame - open then instantly close - and a reference panel open on top had
## no way to claim the key first. One owner, one outcome per press.
func _input(event: InputEvent) -> void:
	if not visible or game == null:
		return
	if not event.is_action_pressed("pause"):
		return
	get_viewport().set_input_as_handled()
	if UIKit.overlays.is_empty():
		game.toggle_pause()
	else:
		# A settings or controls panel is on top: close it, stay paused.
		UIKit.close_overlays()


func _build() -> void:
	UIKit.dim(self)

	var col := UIKit.column_above(self, 10, 0.0)

	var title := UIKit.label(col, "PAUSED", 44, Color(1, 1, 1))
	UIKit.outline(title, 10)
	var sub := UIKit.label(col, "Take a breath.", 15, Color(0.6, 0.65, 0.75))
	UIKit.outline(sub, 4)

	_spacer(col, 6)

	var resume := UIKit.button("Resume", 22, Color(0.1, 0.3, 0.16),
		Color(0.14, 0.42, 0.22), Color(0.2, 0.6, 0.3), Vector2(320, 52))
	resume.pressed.connect(game.toggle_pause)
	col.add_child(resume)

	var restart := UIKit.button("Restart Run", 20, Color(0.14, 0.16, 0.24),
		Color(0.2, 0.24, 0.36), Color(0.3, 0.4, 0.7), Vector2(320, 46))
	restart.pressed.connect(game.restart)
	col.add_child(restart)

	var menu := UIKit.button("Main Menu", 20, Color(0.24, 0.12, 0.12),
		Color(0.36, 0.17, 0.17), Color(0.6, 0.25, 0.25), Vector2(320, 46))
	menu.pressed.connect(game.go_menu)
	col.add_child(menu)

	var hint := UIKit.label(col, "Press Esc to resume", 14, Color(0.55, 0.6, 0.7))
	UIKit.outline(hint, 4)

	var ref := UIKit.row(col, 14)
	ref.add_child(_ref_button("Controls",
		Color(0.1, 0.13, 0.2), Color(0.15, 0.19, 0.3), Color(0.25, 0.34, 0.6),
		_open_controls))
	ref.add_child(_ref_button("Settings",
		Color(0.14, 0.12, 0.2), Color(0.2, 0.18, 0.32), Color(0.38, 0.32, 0.66),
		_open_settings))

	col.add_child(_stats_panel())


func _ref_button(text: String, n: Color, h: Color, pr: Color, cb: Callable) -> Button:
	var b := UIKit.button(text, 18, n, h, pr, Vector2(210, 46))
	b.pressed.connect(cb)
	return b


func _open_controls() -> void:
	InfoScreen.open_on(self, "CONTROLS", InfoScreen.controls_lines())


func _open_settings() -> void:
	SettingsScreen.open_on(self)


func _spacer(parent: Node, height: float) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	parent.add_child(s)


## The run as it stands - read live so the numbers are honest whenever the
## pause key lands.
func _stats_panel() -> PanelContainer:
	var panel := UIKit.panel(Color(0.06, 0.085, 0.1, 0.94), 10, 12)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	panel.add_child(inner)

	var head := UIKit.small_label(inner, "CURRENT RUN", 14, Color(0.6, 0.9, 0.95))
	UIKit.outline(head, 4)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 2)
	inner.add_child(grid)

	_stat_kills = _stat_row(grid, "kills")
	_stat_rooms = _stat_row(grid, "rooms cleared")
	_stat_score = _stat_row(grid, "score")
	_stat_streak = _stat_row(grid, "streak")
	_stat_best_streak = _stat_row(grid, "best streak")
	_stat_difficulty = _stat_row(grid, "difficulty")
	_stat_character = _stat_row(grid, "character")
	_refresh_stats()
	return panel


func _stat_row(grid: GridContainer, label: String) -> Label:
	UIKit.small_label(grid, label, 14, Color(0.62, 0.68, 0.8), HORIZONTAL_ALIGNMENT_LEFT)
	var value := UIKit.small_label(grid, "-", 14, Color(0.9, 0.93, 1.0),
		HORIZONTAL_ALIGNMENT_LEFT)
	UIKit.outline(value, 3)
	return value


## Writes the values out only when one of them actually moved.
func _refresh_stats() -> void:
	var sig := "%d|%d|%d|%d|%d|%s|%s" % [
		GameManager.kills, GameManager.rooms_cleared, GameManager.score(),
		GameManager.streak, GameManager.best_streak,
		GameManager.difficulty_name(), GameManager.character_name()]
	if sig == _stats_sig:
		return
	_stats_sig = sig
	_stat_kills.text = str(GameManager.kills)
	_stat_rooms.text = str(GameManager.rooms_cleared)
	_stat_score.text = str(GameManager.score())
	_stat_streak.text = str(GameManager.streak)
	_stat_best_streak.text = str(GameManager.best_streak)
	_stat_difficulty.text = GameManager.difficulty_name()
	_stat_character.text = GameManager.character_name()
