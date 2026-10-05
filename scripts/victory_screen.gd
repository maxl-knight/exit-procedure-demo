class_name VictoryScreen
extends Control

## Shown once you have walked through a door behind The Core: final score,
## the ending you chose, and - if you took the chair - the way to shatter
## containment and keep fighting your way back down through the wings.

signal descend
signal to_menu

var _descend_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP


func show_stats() -> void:
	for child in get_children():
		child.free()

	# One commit per run, taken before any of the record lines read it back.
	var new_best := GameManager.commit_score()

	UIKit.dim(self, Color(0.02, 0.01, 0.05, 0.86))
	var col := UIKit.centered_column(self, 14)

	var title := UIKit.small_label(col, "THE CORE FALLS", 52, Color(1.0, 0.9, 0.5))
	UIKit.outline(title, 10)

	var ending_id := ArenaMemory.ending
	var data: Dictionary = Content.ENDINGS.get(ending_id, {})
	var sub := UIKit.small_label(col,
		str(data.get("result", "The three wings are behind you. The record is yours.")),
		18, Color(0.78, 0.8, 0.9))
	UIKit.outline(sub, 5)

	var stats_box := UIKit.panel(Color(0.07, 0.08, 0.13, 0.95), 12, 20)
	col.add_child(stats_box)
	var stats_col := VBoxContainer.new()
	stats_col.add_theme_constant_override("separation", 6)
	stats_box.add_child(stats_col)
	UIKit.small_label(stats_col, "FINAL SCORE   %d" % GameManager.score(),
		32, Color(0.4, 1.0, 0.6))
	if new_best:
		var new_line := UIKit.small_label(stats_col,
			"NEW BEST SCORE   %d" % GameManager.best_score, 24,
			Color(1.0, 0.85, 0.35))
		UIKit.outline(new_line, 6)
	else:
		UIKit.small_label(stats_col, "BEST SCORE   %d" % GameManager.best_score,
			17, Color(0.62, 0.68, 0.8))
	if GameManager.last_chip_gain > 0:
		var chip_line := UIKit.small_label(stats_col,
			"MEMORY CHIPS   +%d   -  bank %d" % [
				GameManager.last_chip_gain, GameManager.chips],
			20, Color(0.5, 0.95, 0.7))
		UIKit.outline(chip_line, 5)
	UIKit.small_label(stats_col, "kills %d     rooms cleared %d     difficulty %s" % [
		GameManager.kills, GameManager.rooms_cleared, GameManager.difficulty_name()],
		17, Color(0.7, 0.74, 0.84))
	UIKit.small_label(stats_col, GameManager.combat_summary(), 15,
		Color(0.62, 0.68, 0.8))
	if data.size() > 0:
		var end_line := UIKit.small_label(stats_col,
			"ending   %s" % str(data["title"]), 17, Color(data["color"]))
		UIKit.outline(end_line, 5)

	# The record as a whole: what every door, every failure and every memory
	# room has added up to across all of them.
	var story_box := UIKit.panel(Color(0.06, 0.075, 0.1, 0.95), 12, 18)
	col.add_child(story_box)
	var story_col := VBoxContainer.new()
	story_col.add_theme_constant_override("separation", 6)
	story_box.add_child(story_col)
	var story_head := UIKit.small_label(story_col, "THE RECORD", 15,
		Color(0.6, 0.9, 0.95))
	UIKit.outline(story_head, 4)
	UIKit.small_label(story_col,
		"reconstructions %d     deaths %d     cores broken %d" % [
			ArenaMemory.runs, ArenaMemory.deaths, ArenaMemory.bosses_beaten],
		16, Color(0.74, 0.8, 0.9))
	UIKit.small_label(story_col,
		"fragments recovered %d" % ArenaMemory.fragments_seen, 16,
		Color(0.74, 0.8, 0.9))
	if data.size() > 0:
		var written := UIKit.small_label(story_col,
			"ending written   %s" % str(data["title"]), 16, Color(data["color"]))
		UIKit.outline(written, 4)

	if GameManager.announce_unlock:
		GameManager.announce_unlock = false
		var unlock := UIKit.small_label(col, "HELL MODE UNLOCKED", 26,
			Color(1.0, 0.35, 0.25))
		UIKit.outline(unlock, 7)
		UIKit.small_label(col, "Hell was sealed behind a Hard clear. It is open now.",
			15, Color(0.8, 0.6, 0.6))

	# Endless Administration is what taking the chair buys you - until then the
	# door is visible but shut, so the unlock reads as an unlock.
	if GameManager.endless_admin:
		_descend_button = UIKit.button("BREAK CONTAINMENT  -  keep fighting for score",
			20, Color(0.5, 0.1, 0.12), Color(0.7, 0.16, 0.18), Color(0.9, 0.3, 0.25),
			Vector2(520, 56))
		_descend_button.pressed.connect(_on_descend)
	else:
		_descend_button = UIKit.button(
			"BREAK CONTAINMENT  -  sealed until you TAKE CONTROL",
			17, Color(0.12, 0.13, 0.17), Color(0.15, 0.16, 0.21), Color(0.18, 0.19, 0.24),
			Vector2(520, 48))
		_descend_button.disabled = true
	col.add_child(_descend_button)

	var menu := UIKit.button("MAIN MENU", 20)
	menu.custom_minimum_size = Vector2(520, 48)
	menu.pressed.connect(func(): to_menu.emit())
	col.add_child(menu)

	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_descend() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	descend.emit()
