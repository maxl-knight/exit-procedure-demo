class_name InfoScreen
extends Control

## A reference panel: a title, a scrolling body of lines, a Back button.
## Anything that used to live as permanent text on a menu now lives here, so
## the menus themselves stay short and the detail is one press away.

const BINDINGS := [
	"WASD   Move",
	"Left click   Attack",
	"Q   Super move",
	"Shift   Dash",
	"E   Heal",
	"Esc   Pause",
	"F11 or Alt+Enter   Fullscreen",
]

const SYSTEMS := [
	"Q  super - fires at 100% charge. Hold to 200% for a doubled blast.",
	"At 200% with 25% health or less it fires desperate and spends itself.",
	"Shift  dash - a cleared room banks one charge back.",
	"E  heal - cooldown, and only while you are still hurt.",
	"Streak - +5% score a clean kill, capped. One hit takes it to zero.",
]


## What every Controls screen says, wherever it is opened from.
static func controls_lines() -> Array:
	var out: Array = ["BINDINGS", ""]
	out.append_array(BINDINGS)
	out.append("")
	out.append("SYSTEMS")
	out.append_array(SYSTEMS)
	return out


static func open_on(host: Control, title: String, lines: Array) -> InfoScreen:
	var s := InfoScreen.new()
	s.title_text = title
	s.body_lines = lines.duplicate()
	if host != null:
		host.add_child(s)
	return s


var title_text := "CONTROLS"
var body_lines: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UIKit.add_overlay(self)
	_build()


func _exit_tree() -> void:
	UIKit.remove_overlay(self)


func close() -> void:
	if is_inside_tree():
		queue_free()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	UIKit.dim(self, Color(0.01, 0.01, 0.03, 0.82))

	var col := UIKit.column_above(self, 10, 104.0)

	var title := UIKit.label(col, title_text, 40, Color(1, 1, 1))
	UIKit.outline(title, 10)

	var panel := UIKit.panel(Color(0.06, 0.07, 0.11, 0.96), 12, 16)
	col.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 452)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 7)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stack)

	for line in body_lines:
		_write_line(stack, str(line))

	var bar := UIKit.bottom_bar(self, -88.0, -16.0)
	var row := UIKit.row(bar, 14)
	var back := UIKit.button("Back", 20, Color(0.14, 0.16, 0.24),
		Color(0.2, 0.24, 0.36), Color(0.3, 0.4, 0.7), Vector2(240, 54), "ui_back")
	back.pressed.connect(close)
	row.add_child(back)


## Section heads read as heads, everything else reads as a line of body.
func _write_line(parent: Node, text: String) -> void:
	var head := text == text.to_upper() and text.length() <= 24 and text.contains(" ")
	var l := UIKit.small_label(parent, text, 16 if head else 15,
		Color(0.8, 0.86, 0.98) if head else Color(0.74, 0.79, 0.9),
		HORIZONTAL_ALIGNMENT_LEFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.outline(l, 4 if head else 3)
