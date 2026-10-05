class_name GameOverScreen
extends Control

var game: Variant

var _title: Label
var _subtitle: Label
var _arena_line: Label
var _tip: Label
var _learned: Label
var _kills: Label
var _rooms: Label
var _score: Label
var _best: Label
var _chips: Label
var _unlock: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func show_stats() -> void:
	_kills.text = "Enemies defeated      %d" % GameManager.kills
	_rooms.text = "Rooms cleared         %d" % GameManager.rooms_cleared
	_score.text = "Score                 %d" % GameManager.score()
	_title.text = "YOU DIED"
	_title.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
	_subtitle.text = "%s  -  %s" % [GameManager.difficulty_name(), GameManager.character_name()]

	# The instruction, not the lore: the single thing to change on the next one.
	_tip.text = "NEXT  -  %s" % ArenaMemory.death_tip()

	# The Arena files this death by cause and reports what it observed -
	# one line of readout, not a page of it.
	_arena_line.text = ArenaMemory.death_line()

	# What the run did, compressed: the old version was five separate rows
	# that pushed the buttons off the bottom of the screen.
	var atk := "%d" % int(ArenaMemory.melee_attacks)
	if ArenaMemory.bolt_attacks > 0:
		atk += " / %d frost" % int(ArenaMemory.bolt_attacks)
	var readout := "dashes %d   heals %d   attacks %s   supers %d   damage taken %d" % [
		ArenaMemory.dashes, ArenaMemory.heals, atk,
		ArenaMemory.supers_used, int(ArenaMemory.damage_taken)]
	if ArenaMemory.record_broken:
		readout += "\nnew ceiling - room %d" % ArenaMemory.highest_room
	_learned.text = readout

	# One commit per run, taken before the lifetime number is read back for
	# the row below it. New best, higher ceiling, or neither - said plainly.
	var new_best := GameManager.commit_score()
	_best.text = "Best score              %d" % GameManager.best_score
	_chips.visible = GameManager.last_chip_gain > 0
	if GameManager.last_chip_gain > 0:
		_chips.text = "Memory chips            +%d   (bank %d)" % [
			GameManager.last_chip_gain, GameManager.chips]

	_unlock.visible = false
	_title.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
	if new_best:
		_unlock.visible = true
		_unlock.text = "NEW BEST SCORE   %d" % GameManager.best_score
		_title.text = "NEW RECORD"
		_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	elif ArenaMemory.record_broken:
		# A taller room, not a taller tally: worth saying, worth less.
		_unlock.visible = true
		_unlock.text = "NEW CEILING   room %d" % ArenaMemory.highest_room

	visible = true


func _build() -> void:
	UIKit.dim(self, Color(0.02, 0.02, 0.05, 0.85))

	# The report column stops short of the bottom strip, and the buttons live
	# in that strip - so however much text the death has to say, the two ways
	# out of it are always on screen.
	var col := UIKit.column_above(self, 8, 104.0)

	_title = UIKit.label(col, "YOU DIED", 48, Color(1.0, 0.25, 0.2))
	UIKit.outline(_title, 12)

	_subtitle = UIKit.label(col, "", 17, Color(0.7, 0.75, 0.85))
	UIKit.outline(_subtitle, 5)

	_arena_line = UIKit.label(col, "Reconstruction approved.", 18, Color(0.55, 0.9, 1.0))
	UIKit.outline(_arena_line, 6)

	# The instruction, not the lore: one line, no voice, no judgment.
	_tip = UIKit.label(col, "", 16, Color(0.85, 1.0, 0.9))
	UIKit.outline(_tip, 6)

	_spacer(col, 6)

	_kills = UIKit.label(col, "Enemies defeated      0", 24, Color(0.95, 0.95, 1.0))
	_rooms = UIKit.label(col, "Rooms cleared         0", 24, Color(0.95, 0.95, 1.0))
	_score = UIKit.label(col, "Score                 0", 28, Color(1.0, 0.85, 0.35))
	for l in [_kills, _rooms, _score]:
		UIKit.outline(l as Label, 7)

	# The lifetime number, beside the run that just fed it.
	_best = UIKit.label(col, "Best score              0", 17, Color(1.0, 0.85, 0.35))
	UIKit.outline(_best, 7)

	# What the run just paid into the bank. Hidden when the run already paid
	# out at the victory screen and this death had nothing left to add.
	_chips = UIKit.label(col, "Memory chips            +0", 20, Color(0.5, 0.95, 0.7))
	UIKit.outline(_chips, 7)
	_chips.visible = false

	# What the Arena observed about your run, on a single panel line.
	var learned_panel := UIKit.panel(Color(0.05, 0.07, 0.1, 0.92), 8, 10)
	learned_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(learned_panel)
	var learned_col := VBoxContainer.new()
	learned_col.add_theme_constant_override("separation", 2)
	learned_panel.add_child(learned_col)
	var learned_head := UIKit.small_label(learned_col, "THE ARENA OBSERVED", 13,
		Color(0.55, 0.9, 1.0))
	UIKit.outline(learned_head, 3)
	_learned = UIKit.small_label(learned_col, "", 14, Color(0.75, 0.82, 0.9),
		HORIZONTAL_ALIGNMENT_CENTER)
	UIKit.outline(_learned, 3)

	_unlock = UIKit.label(col, "???  UNLOCKED", 22, Color(1.0, 0.85, 0.25))
	UIKit.outline(_unlock, 8)
	_unlock.visible = false

	var bar := UIKit.bottom_bar(self, -92.0, -16.0)
	var buttons := UIKit.row(bar, 14)
	var retry := UIKit.button("Reconstruct", 21, Color(0.1, 0.3, 0.16),
		Color(0.14, 0.42, 0.22), Color(0.2, 0.6, 0.3), Vector2(230, 58))
	retry.pressed.connect(Callable(game, "restart"))
	buttons.add_child(retry)

	var menu := UIKit.button("Main Menu", 21, Color(0.14, 0.16, 0.24),
		Color(0.2, 0.24, 0.36), Color(0.3, 0.4, 0.7), Vector2(230, 58))
	menu.pressed.connect(Callable(game, "go_menu"))
	buttons.add_child(menu)


func _spacer(parent: Node, height: float) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	parent.add_child(s)
