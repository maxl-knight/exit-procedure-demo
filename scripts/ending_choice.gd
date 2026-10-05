class_name EndingChoice
extends Control

## The three doors that open behind The Core. There is no separate 3D scene:
## the boss arena stays rendered underneath, so the doors literally stand in
## the room you just finished. Every choice is canonical and gets written into
## the record; only TAKE CONTROL opens Endless Administration.

signal chosen(id: String)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP


func open() -> void:
	for child in get_children():
		child.free()
	visible = true
	# The doors do not wait for the room: nothing may walk or swing while the
	# choice is on screen, and the cursor has to be free to point at one.
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UIKit.dim(self, Color(0.01, 0.02, 0.05, 0.9))

	var col := UIKit.centered_column(self, 14)
	var title := UIKit.small_label(col, "THE CORE IS SILENT", 46, Color(1.0, 0.9, 0.5))
	UIKit.outline(title, 9)
	var sub := UIKit.small_label(col,
		"Three doors stood behind it. One of them is yours.", 17,
		Color(0.75, 0.8, 0.92))
	UIKit.outline(sub, 5)

	var row := UIKit.row(col, 18)
	for id in Content.ENDING_IDS:
		row.add_child(_door(str(id)))

	var foot := UIKit.small_label(col,
		"Your choice is written into the record.", 13, Color(0.5, 0.55, 0.68))
	UIKit.outline(foot, 3)


## One door: a big, readable card with its title, its promise and its lore.
func _door(id: String) -> Button:
	var data: Dictionary = Content.ENDINGS[id]
	var accent := Color(data["color"])
	var b := Button.new()
	b.text = "%s\n\n%s\n\n%s" % [
		str(data["title"]), str(data["tag"]), str(data["lore"]),
	]
	b.add_theme_font_size_override("font_size", 17)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(300, 244)
	UIKit.style_button(b,
		Color(0.07, 0.08, 0.13, 0.95),
		Color(0.11, 0.13, 0.21, 0.98),
		accent.lerp(Color(0.0, 0.0, 0.0), 0.55))
	b.add_theme_color_override("font_color", accent.lerp(Color(1, 1, 1), 0.45))
	b.add_theme_color_override("font_hover_color", accent.lightened(0.25))
	UIKit.soundify(b)
	b.pressed.connect(func(): _pick(id))
	return b


func _pick(id: String) -> void:
	Sfx.play("milestone")
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	chosen.emit(id)
