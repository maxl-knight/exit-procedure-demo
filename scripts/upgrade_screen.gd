class_name UpgradeScreen
extends Control

## The hub's shop, and the whole point of banking a score: run ends convert
## the run's score into memory chips, and this screen spends them on the
## seven permanent upgrades that make the next run easier. Same overlay
## contract as SettingsScreen - modal, Esc closes it, one owner of the
## screen's lifetime.

var _chips_label: Label
## id -> {"name": Label, "effect": Label, "buy": Button}
var _rows := {}


static func open_on(host: Control) -> void:
	if host == null:
		return
	host.add_child(UpgradeScreen.new())


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
	UIKit.dim(self, Color(0.01, 0.01, 0.03, 0.84))

	var col := UIKit.column_above(self, 7, 92.0)

	var title := UIKit.label(col, "UPGRADES", 38, Color(1, 1, 1))
	UIKit.outline(title, 10)

	var chips_panel := UIKit.panel(Color(0.055, 0.1, 0.08, 0.96), 10, 10)
	chips_panel.custom_minimum_size = Vector2(440, 0)
	col.add_child(chips_panel)
	var chips_row := UIKit.row(chips_panel, 10)
	var chips_name := UIKit.small_label(chips_row, "MEMORY CHIPS", 17,
		Color(0.5, 0.95, 0.7))
	chips_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.outline(chips_name, 4)
	_chips_label = UIKit.small_label(chips_row, "0", 22, Color(1.0, 0.85, 0.35),
		HORIZONTAL_ALIGNMENT_RIGHT)
	UIKit.outline(_chips_label, 5)

	var hint := UIKit.small_label(col,
		"Your score is banked as chips when a run ends. Every level is permanent.",
		14, Color(0.55, 0.6, 0.7))
	UIKit.outline(hint, 3)

	# Fixed height so seven rows fit the window instead of pushing the Back
	# button off the bottom of a 720-tall screen.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.custom_minimum_size = Vector2(780, 396)
	col.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 7)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for id in GameManager.UPGRADES:
		list.add_child(_build_row(str(id)))

	var bar := UIKit.bottom_bar(self, -84.0, -14.0)
	var buttons := UIKit.row(bar, 14)
	var back := UIKit.button("Back", 20, Color(0.14, 0.16, 0.24),
		Color(0.2, 0.24, 0.36), Color(0.3, 0.4, 0.7), Vector2(240, 52), "ui_back")
	back.pressed.connect(close)
	buttons.add_child(back)

	_refresh()


## One upgrade as a panel: what it is, what it is currently worth, and the
## one button that can change either.
func _build_row(id: String) -> Control:
	var data: Dictionary = GameManager.UPGRADES[id]

	var panel := UIKit.panel(Color(0.07, 0.075, 0.11, 0.96), 8, 12)
	panel.custom_minimum_size = Vector2(764, 0)

	var row := UIKit.row(panel, 12)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var name_label := UIKit.small_label(info, "", 18, Color(0.9, 0.93, 1.0),
		HORIZONTAL_ALIGNMENT_LEFT)
	UIKit.outline(name_label, 4)

	var effect := UIKit.small_label(info, "", 15, Color(0.55, 0.95, 0.75),
		HORIZONTAL_ALIGNMENT_LEFT)
	UIKit.outline(effect, 3)

	var desc := UIKit.small_label(info, str(data["desc"]), 13,
		Color(0.6, 0.66, 0.78), HORIZONTAL_ALIGNMENT_LEFT)
	UIKit.outline(desc, 3)

	# The buy button voices its own outcome, so it does not also fire the
	# generic click on top of it.
	var buy := UIKit.button("BUY", 16, Color(0.1, 0.26, 0.16),
		Color(0.14, 0.38, 0.22), Color(0.2, 0.56, 0.3), Vector2(170, 48), "")
	buy.pressed.connect(_on_buy.bind(id))
	row.add_child(buy)

	_rows[id] = {"name": name_label, "effect": effect, "buy": buy}
	return panel


func _refresh() -> void:
	_chips_label.text = "%d" % GameManager.chips
	for id in _rows:
		var row: Dictionary = _rows[id]
		var data: Dictionary = GameManager.UPGRADES[id]
		var level := GameManager.upg_level(id)
		var pct := float(data["pct"])

		(row["name"] as Label).text = "%s   -   LV %d / %d" % [
			str(data["name"]), level, GameManager.CHIP_MAX_LEVEL]

		# Signed, so PLATING and CADENCE read as improvements rather than as
		# stats going backwards.
		var line := "%s   now %s%%" % [str(data["stat"]), _signed(pct * float(level))]
		if level >= GameManager.CHIP_MAX_LEVEL:
			line += "     MAXED"
		else:
			line += "     next %s%%" % _signed(pct * float(level + 1))
		(row["effect"] as Label).text = line

		var buy := row["buy"] as Button
		if level >= GameManager.CHIP_MAX_LEVEL:
			buy.text = "MAXED"
			buy.disabled = true
		else:
			var cost := GameManager.upg_cost(id)
			buy.text = "BUY   %d" % cost
			buy.disabled = GameManager.chips < cost


func _signed(v: float) -> String:
	var n := int(round(v))
	return ("+%d" % n) if n >= 0 else ("%d" % n)


func _on_buy(id: String) -> void:
	if GameManager.buy_upgrade(id):
		Sfx.play("ui_done")
	else:
		Sfx.play("ui_error")
	_refresh()
