class_name ChoiceScreen
extends Control

## Full-screen 3-choice picker used after an elite trial and for adaptive
## counter-rewards. Each card carries the upgrade's line of Arena lore.
## Pauses the tree while it is open.

signal chosen(id: String)

var _current: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP


func open(title: String, detail: String, options: Array,
		current: Dictionary = {}) -> void:
	_current = current
	for child in get_children():
		child.free()

	UIKit.dim(self)
	var col := UIKit.centered_column(self, 16)

	var box := UIKit.panel(Color(0.06, 0.07, 0.11, 0.97), 14, 24)
	col.add_child(box)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	inner.custom_minimum_size = Vector2(640, 0)
	box.add_child(inner)

	var head := UIKit.small_label(inner, title, 34, Color(1.0, 0.85, 0.35))
	UIKit.outline(head, 6)
	var sub := UIKit.small_label(inner, detail, 16, Color(0.7, 0.74, 0.84))
	UIKit.outline(sub, 4)

	var rule := ColorRect.new()
	rule.color = Color(1.0, 0.85, 0.35, 0.35)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(rule)

	for id in options:
		inner.add_child(_make_option(str(id)))

	var hint := UIKit.small_label(inner,
		"Permanent for the rest of the run, and it stacks  -  click a card to take it",
		14, Color(0.5, 0.55, 0.65))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _make_option(id: String) -> Button:
	# An upgrade or a defect - either way, the card reads the same fields.
	var data: Dictionary = Content.BUFFS.get(id, Content.CURSES.get(id, {}))
	var stacks := int(_current.get(id, 0))
	var name := str(data.get("name", id))
	var desc := str(data.get("desc", ""))
	var lore := str(data.get("lore", ""))
	var color: Color = data.get("color", Color.WHITE)

	var label := name
	if stacks > 0:
		label += "   x%d -> x%d" % [stacks, stacks + 1]

	var b := Button.new()
	# Name, effect, then the Arena's one line of lore explaining the handout.
	var body: String = "%s\n%s" % [label, desc]
	if lore != "":
		body += "\n" + lore
	b.text = body
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(0, 104 if lore != "" else 78)
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.5))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", UIKit.flat(Color(0.1, 0.12, 0.18, 0.95), 8, 12))
	b.add_theme_stylebox_override("hover", UIKit.flat(color.darkened(0.55), 8, 12))
	b.add_theme_stylebox_override("pressed", UIKit.flat(color.darkened(0.35), 8, 12))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	UIKit.soundify(b)
	b.pressed.connect(_pick.bind(id))
	return b


func _pick(id: String) -> void:
	Sfx.play("upgrade")
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	chosen.emit(id)
