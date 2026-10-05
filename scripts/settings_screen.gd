class_name SettingsScreen
extends Control

## The one settings screen. The hub and the pause menu both open it instead of
## each carrying its own copy of the same four switches, so there is a single
## place to look for them and a single place that writes them.

## One toggle wired straight through to the save file.
const TOGGLES := [["SCREEN SHAKE", "shake"], ["HIT-STOP", "hitstop"],
	["RETICLE", "reticle"], ["FULLSCREEN", "fullscreen"]]

## Kept so F11, which works from anywhere, cannot leave this box lying.
var _fullscreen_box: CheckButton = null


static func open_on(host: Control) -> void:
	if host == null:
		return
	host.add_child(SettingsScreen.new())


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

	var title := UIKit.label(col, "SETTINGS", 40, Color(1, 1, 1))
	UIKit.outline(title, 10)

	var panel := UIKit.panel(Color(0.07, 0.075, 0.11, 0.96), 12, 18)
	panel.custom_minimum_size = Vector2(440, 0)
	col.add_child(panel)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	panel.add_child(inner)

	var sens_row := UIKit.row(inner, 10)
	var sens_name := UIKit.small_label(sens_row, "MOUSE SENSITIVITY", 15,
		Color(0.78, 0.83, 0.92))
	sens_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.outline(sens_name, 3)
	var sens_value := UIKit.small_label(sens_row, "", 15, Color(1.0, 0.85, 0.35),
		HORIZONTAL_ALIGNMENT_RIGHT)
	UIKit.outline(sens_value, 3)

	var slider := HSlider.new()
	slider.min_value = 0.25
	slider.max_value = 3.0
	slider.step = 0.05
	slider.value = GameManager.opt_sensitivity
	slider.custom_minimum_size = Vector2(0, 18)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(slider)
	_show(sens_value)
	slider.value_changed.connect(_on_sensitivity.bind(sens_value))

	var vol_row := UIKit.row(inner, 10)
	var vol_name := UIKit.small_label(vol_row, "SOUND VOLUME", 15,
		Color(0.78, 0.83, 0.92))
	vol_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.outline(vol_name, 3)
	var vol_value := UIKit.small_label(vol_row, "", 15, Color(1.0, 0.85, 0.35),
		HORIZONTAL_ALIGNMENT_RIGHT)
	UIKit.outline(vol_value, 3)

	var vol := HSlider.new()
	vol.min_value = 0
	vol.max_value = 100
	vol.step = 5
	vol.value = GameManager.opt_volume
	vol.custom_minimum_size = Vector2(0, 18)
	vol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(vol)
	_show_volume(vol_value)
	vol.value_changed.connect(_on_volume.bind(vol_value))

	var rule := HSeparator.new()
	rule.add_theme_constant_override("separation", 10)
	inner.add_child(rule)

	for entry: Array in TOGGLES:
		_add_toggle(inner, str(entry[0]), _read(str(entry[1])), str(entry[1]))

	var note := UIKit.label(col, "Bindings are listed on the Controls screen.", 14,
		Color(0.55, 0.6, 0.7))
	UIKit.outline(note, 4)

	var bar := UIKit.bottom_bar(self, -88.0, -16.0)
	var row := UIKit.row(bar, 14)
	var back := UIKit.button("Back", 20, Color(0.14, 0.16, 0.24),
		Color(0.2, 0.24, 0.36), Color(0.3, 0.4, 0.7), Vector2(240, 54), "ui_back")
	back.pressed.connect(close)
	row.add_child(back)


func _read(key: String) -> bool:
	match key:
		"shake":
			return GameManager.opt_shake
		"hitstop":
			return GameManager.opt_hitstop
		"fullscreen":
			return GameManager.opt_fullscreen
	return GameManager.opt_reticle


func _add_toggle(parent: Node, text: String, value: bool, key: String) -> void:
	var b := CheckButton.new()
	b.text = text
	b.button_pressed = value
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
	b.toggled.connect(_on_toggle.bind(key))
	parent.add_child(b)
	# No generic click: _on_toggle voices the actual direction of the change.
	UIKit.soundify(b, "")
	if key == "fullscreen":
		_fullscreen_box = b


func _on_toggle(pressed: bool, key: String) -> void:
	match key:
		"shake":
			GameManager.opt_shake = pressed
		"hitstop":
			GameManager.opt_hitstop = pressed
		"reticle":
			GameManager.opt_reticle = pressed
		"fullscreen":
			# Resizes the window and writes the file itself, so a second save
			# here would just be the same ConfigFile written twice.
			GameManager.set_fullscreen(pressed)
			if GameManager.window_mode_refused:
				# It cannot happen from inside the editor's embedded window;
				# say so instead of letting the box silently snap back.
				Sfx.play("ui_error")
				return
			Sfx.play("ui_toggle_on" if pressed else "ui_toggle_off")
			return
	Sfx.play("ui_toggle_on" if pressed else "ui_toggle_off")
	GameManager.save_settings()


## F11 works from anywhere, including here, so the checkbox would otherwise
## quietly drift out of step with the window it is supposed to describe.
func _process(_delta: float) -> void:
	if _fullscreen_box == null or not is_instance_valid(_fullscreen_box):
		return
	if _fullscreen_box.button_pressed != GameManager.opt_fullscreen:
		_fullscreen_box.set_pressed_no_signal(GameManager.opt_fullscreen)


func _on_sensitivity(value: float, value_label: Label) -> void:
	GameManager.opt_sensitivity = clampf(value, 0.25, 3.0)
	_show(value_label)
	GameManager.save_settings()


## Dragging the volume bar has to be audible or it is just a number moving.
func _on_volume(value: float, value_label: Label) -> void:
	GameManager.opt_volume = clampi(int(round(value)), 0, 100)
	_show_volume(value_label)
	GameManager.save_settings()
	Sfx.apply_volume()
	Sfx.play("ui_click", -4.0, 1.08, 0.02)


## The slider reads as a percentage - nobody thinks in raw multipliers.
func _show(value_label: Label) -> void:
	value_label.text = "%d%%" % int(round(GameManager.opt_sensitivity * 100.0))


func _show_volume(value_label: Label) -> void:
	value_label.text = "%d%%" % GameManager.opt_volume
