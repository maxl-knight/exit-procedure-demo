class_name HUD
extends Control

const SLOT_W := 108.0
const SLOT_H := 104.0
const TOP_W := 640.0
const TOP_H := 152.0

const MULT_W := 210.0
const STATUS_W := 300.0

var player: Player

var _hp_fill: ColorRect
var _hp_text: Label
var _kills_label: Label
var _room_label: Label
var _left_label: Label
var _realm_label: Label
var _kind_label: Label
var _score_label: Label
var _slots: Array = []
var _ability_root: Control
var _banner: Label
var _voice: Label
var _voice_tween: Tween
var _vignette: ColorRect
var _banner_tween: Tween
var _flash_tween: Tween

var _enemies_left := 0

var _wing_label: Label
var _wing_fill: ColorRect

var _streak_label: Label
var _streak_tween: Tween
var _streak_shown := -1

var _toast: Label
var _toast_tween: Tween

## Off-screen threat marker: one arrow at the screen edge for the nearest
## enemy you cannot see.
var _threat: Label
var _threat_cam: Camera3D
var _threat_rooms: RoomManager

var _mult_value: Label
var _mult_rows: VBoxContainer
var _status_col: VBoxContainer
var _status_root: Control
var _status_cache := ""

## Centre reticle: a dot plus four arms. Doubles as the hit marker, so a
## connect is answered in the middle of the screen instead of only as a
## number floating off to one side.
var _reticle_root: Control
var _reticle_tween: Tween

## Floating "+N" when the tally actually moves.
var _score_pop: Label
var _score_pop_tween: Tween
var _score_pop_y := 0.0

## One line of objective under the top panel: what this room wants from you.
var _objective: Label

## Persistent low-HP layer. Separate from the damage flash so the two never
## fight over the same alpha channel.
var _crit: ColorRect
var _hp_warn: Label

## How long is left on the quick-clear bonus.
var _time_label: Label

## Small, always-on streak readout (the big pop stays a pop).
var _streak_small: Label

## The difficulty's actual numbers, written once per run.
var _diff_detail: Label

## Tutorial / one-off hints, sitting above the toast.
var _hint: Label
var _hint_tween: Tween
var _hints_shown := {}

## "LEFT 4 / 9" - the room total, and a cache so the row is not rebuilt
## every frame.
var _room_total := 0
var _left_shown := -1
var _left_total_shown := -1

## A loud event (defect, boss, realm) queues behind the banner currently on
## screen rather than silently swallowing it.
var _banner_queue: Array = []
var _banner_busy := false

## Last multiplier we drew, so a jump upward can flash. Negative until the
## first frame so a run does not open with a celebration it did not earn.
var _mult_shown := -1.0

var _boss_root: Control
var _boss_fill: ColorRect
var _boss_label: Label
var _boss_detail: Label
var _boss_watch: TheCreator = null
var current_room := 0
## What kind of room the player is standing in, set on entry by game.gd.
var room_kind := "combat"


## Display text + colour for each room type the schedule can produce.
const KIND_STYLE := {
	"combat": {"text": "COMBAT", "color": Color(0.6, 0.7, 0.85)},
	"elite": {"text": "ELITE TRIAL", "color": Color(0.9, 0.25, 0.95)},
	"upgrade": {"text": "UPGRADE CACHE", "color": Color(1.0, 0.85, 0.3)},
	"recovery": {"text": "RECOVERY BAY", "color": Color(0.4, 1.0, 0.68)},
	"memory": {"text": "MEMORY ROOM", "color": Color(0.72, 0.5, 1.0)},
	"adaptive": {"text": "ADAPTIVE TEST", "color": Color(0.35, 0.85, 1.0)},
	"milestone": {"text": "MILESTONE", "color": Color(1.0, 0.9, 0.5)},
	"boss": {"text": "BOSS ROOM", "color": Color(1.0, 0.9, 0.5)},
	"defect": {"text": "SYSTEM DEFECT", "color": Color(0.9, 0.3, 0.9)},
}


func setup(p: Player) -> void:
	player = p
	player.damaged_received.connect(flash_damage)
	player.died.connect(hide_bars)
	player.buff_added.connect(func(_id, _n): _status_cache = "")
	player.curse_added.connect(func(_id, _n): _status_cache = "")


func watch_boss(boss: TheCreator) -> void:
	_boss_watch = boss


func clear_boss() -> void:
	_boss_watch = null
	if _boss_root != null:
		_boss_root.visible = false


## Hands the HUD the live camera and room list so it can point at threats
## that have drifted off-screen.
func watch_threats(cam: Camera3D, rooms: RoomManager) -> void:
	_threat_cam = cam
	_threat_rooms = rooms


## How many enemies are still standing in the room you are in.
func set_enemies_left(n: int) -> void:
	_enemies_left = maxi(0, n)


## How many enemies the room opened with, so the counter can read
## "LEFT 4 / 9" instead of a number with no denominator.
func set_room_total(n: int) -> void:
	_room_total = maxi(0, n)


## One line saying what the current room wants. "" hides it.
func set_objective(text: String) -> void:
	if _objective == null:
		return
	_objective.text = text
	_objective.visible = text != ""


## A longer-lived instruction above the ability row, for things the player
## should know before they matter.
func show_hint(text: String, duration: float = 5.0) -> void:
	if _hint == null:
		return
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint.text = text
	_set_alpha(_hint, 1.0)
	_hint.visible = true
	_hint_tween = create_tween()
	_hint_tween.tween_interval(duration)
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 0.6)
	_hint_tween.tween_callback(_hide_hint)


## The same, but only the first time this id is seen in the run.
func show_hint_once(id: String, text: String, duration: float = 5.0) -> void:
	if _hints_shown.has(id):
		return
	_hints_shown[id] = true
	show_hint(text, duration)


func _hide_hint() -> void:
	if _hint != null:
		_hint.visible = false


## Called when the run is over: drop the ability row, banner and damage flash.
func clear_bars() -> void:
	if _ability_root != null:
		_ability_root.visible = false
	if _vignette != null:
		_vignette.color = Color(0.85, 0.05, 0.05, 0.0)
	if _crit != null:
		_crit.visible = false
	if _hp_warn != null:
		_hp_warn.visible = false
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = null
	_banner_busy = false
	_banner_queue.clear()
	if _banner != null:
		_banner.visible = false
	if _voice != null:
		_voice.visible = false
	if _toast != null:
		_toast.visible = false
	if _hint != null:
		_hint.visible = false
	if _objective != null:
		_objective.visible = false
	if _score_pop != null:
		_score_pop.visible = false
	if _streak_label != null:
		_streak_label.visible = false
	if _streak_small != null:
		_streak_small.visible = false
	if _threat != null:
		_threat.visible = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	# Combat feedback comes in through the autoload so enemies, bolts, traps
	# and the player can all raise it without holding a HUD reference.
	GameManager.hit_connected.connect(_on_hit_connected)
	GameManager.score_gained.connect(_on_score_gained)
	GameManager.super_fired.connect(_on_super_fired)


## Names the move on screen. Both super tiers fire on the same key, so the
## banner is how you tell a 100% cast from a 200% one without watching the bar.
func _on_super_fired(move_name: String, tier: int) -> void:
	var color := Color(1.0, 0.5, 0.2) if tier < 2 else Color(1.0, 0.9, 0.3)
	var text := move_name if tier < 2 else move_name + "\nOVERDRIVE"
	# The centre of the screen belongs to the room announcement: if one is up
	# this falls back to the side line rather than pushing it out of the queue.
	if _banner_busy:
		show_toast(move_name, color, 1.6)
	else:
		show_banner(text, color, 1.5)


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return

	var pct := player.health.fraction()
	_hp_fill.anchor_right = pct
	_hp_fill.color = Color(0.3, 0.95, 0.4).lerp(Color(0.95, 0.2, 0.15), 1.0 - pct)
	# keep the inset from ever exceeding the filled width (avoids a negative rect)
	var inset := minf(3.0, pct * TOP_W * 0.5)
	_hp_fill.offset_left = inset
	_hp_fill.offset_right = -inset
	_hp_text.text = "%d / %d" % [ceili(player.health.health), ceili(player.health.max_health)]
	_update_critical(pct)

	_kills_label.text = "KILLS   %d" % GameManager.kills
	_room_label.text = "ROOM   %d" % (current_room + 1)
	_score_label.text = "SCORE   %d" % GameManager.score()
	_realm_label.text = GameManager.realm_name(current_room)
	_update_left()
	_update_reticle()

	_update_multiplier()
	_update_status()
	_update_boss()
	_update_wing()
	_update_streak()
	_update_threat()
	_update_abilities()


## The counter only repaints when the count actually moves.
func _update_left() -> void:
	if _left_label == null:
		return
	if _enemies_left == _left_shown and _room_total == _left_total_shown:
		return
	_left_shown = _enemies_left
	_left_total_shown = _room_total
	if _room_total > 0:
		_left_label.text = "LEFT   %d / %d" % [_enemies_left, _room_total]
	else:
		_left_label.text = "LEFT   %d" % _enemies_left


## Below 30% the screen itself starts saying so - a slow red breath that does
## not depend on the player reading a number mid-fight.
func _update_critical(pct: float) -> void:
	var low := pct <= 0.30 and pct > 0.0 and not player.dead
	if _crit != null:
		_crit.visible = low
		if low:
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.007)
			_crit.color = Color(0.9, 0.12, 0.1,
				(0.16 + 0.14 * pulse) * (1.0 - pct / 0.30))
			_hp_fill.modulate = Color(1.0, 1.0, 1.0, 0.72 + 0.28 * pulse)
	if _hp_warn != null and _hp_warn.visible != low:
		_hp_warn.visible = low
	if not low and _hp_fill != null:
		_hp_fill.modulate = Color.WHITE


## The reticle tracks the live accessibility toggle so it can be switched
## mid-run from the pause menu.
func _update_reticle() -> void:
	if _reticle_root == null:
		return
	if _reticle_root.visible != GameManager.opt_reticle:
		_reticle_root.visible = GameManager.opt_reticle


func _update_abilities() -> void:
	var state := player.get_ability_state()
	for i in mini(_slots.size(), state.size()):
		var slot: Dictionary = _slots[i]
		var info: Dictionary = state[i]
		var fill := clampf(float(info["fill"]), 0.0, 1.0)
		# the dark overlay hangs from the top, so the bar visually "fills up"
		(slot["overlay"] as ColorRect).offset_bottom = SLOT_H * (1.0 - fill)
		var value := slot["value"] as Label
		value.text = str(info["label"])
		var tier := Color(1.0, 0.88, 0.4)
		if i == 0:
			tier = _super_tier(value)
			_label_super_move(slot)
		value.add_theme_color_override("font_color", tier)
		var col := Color(1, 1, 1, 1) if bool(info["ready"]) else Color(0.62, 0.65, 0.74, 0.92)
		(slot["root"] as Control).modulate = col
		_update_pips(slot)


## The super slot names the move the bar is holding, not the key it sits on:
## 100% and 200% cast different things and the label has to say which one is
## actually loaded. Shrinks the font rather than clipping a longer name.
func _label_super_move(slot: Dictionary) -> void:
	var label := slot["name"] as Label
	if label == null:
		return
	var text := player.super_display_name()
	# The size follows the text, so re-deriving it from the label every frame
	# would mean a theme override (and a relayout) sixty times a second.
	if str(slot.get("super_text", "")) == text:
		return
	slot["super_text"] = text
	var font := label.get_theme_font("font")
	var widest := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var size := 13
	if widest > SLOT_W - 8.0:
		size = maxi(9, int(floor(13.0 * (SLOT_W - 8.0) / maxf(widest, 1.0))))
	label.text = text
	label.add_theme_font_size_override("font_size", size)


## The super slot says which of the three tiers it is actually sitting on.
## Returns the colour the label should be.
func _super_tier(value: Label) -> Color:
	if player.super_charge >= Player.SUPER_MAX - 0.5:
		if player.health.fraction() <= 0.25:
			value.text = "DESPERATION"
			return Color(1.0, 0.3, 0.25)
		value.text = "200%  x2 DMG"
		return Color(1.0, 0.72, 0.18)
	if player.super_charge >= Player.SUPER_READY:
		value.text = "READY"
		return Color(0.45, 1.0, 0.65)
	return Color(1.0, 0.88, 0.4)


## Dash charges as pips instead of a single number - you should be able to
## see at a glance how many escapes you have left.
func _update_pips(slot: Dictionary) -> void:
	if not slot.has("pips"):
		return
	var pips: Array = slot["pips"]
	var maxc := player.dash_charges_max
	for j in pips.size():
		var p := pips[j] as ColorRect
		if p == null:
			continue
		var alive := j < maxc
		p.visible = alive
		if alive:
			p.color = Color(0.45, 0.8, 1.0) if j < player.dash_charges \
				else Color(0.15, 0.19, 0.28)


## A centre-screen crosshair flash so a connect is answered immediately.
func _on_hit_connected(color: Color) -> void:
	if _reticle_root == null or not _reticle_root.visible:
		return
	if _reticle_tween != null and _reticle_tween.is_valid():
		_reticle_tween.kill()
	_reticle_root.modulate = color
	_reticle_root.scale = Vector2(1.75, 1.75)
	_reticle_tween = create_tween()
	_reticle_tween.tween_property(_reticle_root, "scale", Vector2.ONE, 0.15) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_reticle_tween.parallel().tween_property(_reticle_root, "modulate",
		Color(1, 1, 1, 1), 0.22)


## Points rise and fade next to the score, so a kill pays visibly.
func _on_score_gained(amount: float) -> void:
	if _score_pop == null or amount <= 0.0:
		return
	if _score_pop_tween != null and _score_pop_tween.is_valid():
		_score_pop_tween.kill()
	_score_pop.text = "+%d" % int(round(amount))
	_set_alpha(_score_pop, 1.0)
	_score_pop.visible = true
	_score_pop_tween = create_tween()
	_score_pop_tween.tween_method(_rise_score_pop, 0.0, -30.0, 0.65) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_score_pop_tween.tween_interval(0.25)
	_score_pop_tween.tween_property(_score_pop, "modulate:a", 0.0, 0.3)
	_score_pop_tween.tween_callback(_hide_score_pop)


func _rise_score_pop(v: Variant) -> void:
	var dy := float(v)
	_score_pop.offset_top = _score_pop_y + dy
	_score_pop.offset_bottom = _score_pop_y + dy + 26.0


func _hide_score_pop() -> void:
	if _score_pop == null:
		return
	_score_pop.visible = false
	_score_pop.offset_top = _score_pop_y
	_score_pop.offset_bottom = _score_pop_y + 26.0


## The side panel: how much each clean, fast room is worth right now.
func _update_multiplier() -> void:
	if _mult_value == null:
		return
	var m := GameManager.multiplier()
	_mult_value.text = "x%.2f" % m
	_mult_value.modulate = Color(0.6, 0.65, 0.75).lerp(Color(1.0, 0.9, 0.3),
		clampf((m - 1.0) / 6.0, 0.0, 1.0))
	# A jump upward is worth a beat of attention; downward is just arithmetic.
	if _mult_shown >= 0.0 and m > _mult_shown + 0.005:
		_flash_multiplier()
	_mult_shown = m

	# The quick-clear window, as a countdown you can actually pace yourself to.
	if _time_label != null:
		var left := GameManager.PAR_TIME - GameManager.room_time
		if left > 0.0:
			_time_label.text = "QUICK BONUS   %ds left" % int(ceil(left))
			_time_label.add_theme_color_override("font_color", Color(0.5, 0.95, 0.7))
		else:
			_time_label.text = "QUICK BONUS   gone"
			_time_label.add_theme_color_override("font_color", Color(0.5, 0.53, 0.62))

	var base := GameManager.base_score_mult() * (1.0 + GameManager.score_bonus)
	# The "clean" factor is measured against the body you are wearing, not a
	# hard-coded 100.
	var max_hp := maxf(GameManager.run_max_hp, 10.0)
	var clean := clampf(1.0 - GameManager.room_damage / max_hp, 0.0, 1.0)
	var fast := clampf((GameManager.PAR_TIME - GameManager.room_time)
		/ GameManager.PAR_TIME, 0.0, 1.0)

	var rows := [
		["base x%.2f" % base, Color(0.7, 0.74, 0.84)],
		["no damage  +%d%%" % int(round(clean * 200.0)),
			Color(0.4, 1.0, 0.6) if clean > 0.99 else Color(0.85, 0.5, 0.4)],
		["quick clear  +%d%%" % int(round(fast * 150.0)),
			Color(0.4, 1.0, 0.6) if fast > 0.99 else Color(0.6, 0.7, 0.9)],
		["streak  +%d%%" % int(round((GameManager.streak_mult() - 1.0) * 100.0)),
			Color(1.0, 0.72, 0.25) if GameManager.streak > 1 else Color(0.5, 0.53, 0.62)],
	]
	for i in mini(_mult_rows.get_child_count(), rows.size()):
		var l := _mult_rows.get_child(i) as Label
		l.text = rows[i][0]
		l.add_theme_color_override("font_color", rows[i][1])


func _flash_multiplier() -> void:
	if _mult_value == null:
		return
	_mult_value.pivot_offset = Vector2(_mult_value.size.x * 0.5, _mult_value.size.y * 0.5)
	_mult_value.scale = Vector2(1.2, 1.2)
	var tw := create_tween()
	tw.tween_property(_mult_value, "scale", Vector2.ONE, 0.24) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_status() -> void:
	if _status_col == null or player == null:
		return
	var key := "%s|%s" % [str(player.buffs), str(player.curses)]
	if key == _status_cache:
		return
	_status_cache = key
	for child in _status_col.get_children():
		child.free()

	# An empty status board is still a board: the whole panel used to sit on
	# the right of the screen saying "no buffs yet". Nothing to report is not
	# a report.
	var has_any := not player.buffs.is_empty() or not player.curses.is_empty()
	if _status_root != null:
		_status_root.visible = has_any
	if not has_any:
		return

	for id in Content.BUFF_IDS:
		var n := player.buff_stacks(id)
		if n <= 0:
			continue
		var data: Dictionary = Content.BUFFS[id]
		# Lore names are long - the side panel shows the short tag plus what
		# it actually does, so the build is readable without a wiki.
		var l := _label(_status_col, "%s  x%d   %s" % [
				str(data.get("short", data["name"])).to_upper(), n,
				str(data.get("desc", ""))],
			13, data["color"], HORIZONTAL_ALIGNMENT_LEFT)
		l.add_theme_constant_override("outline_size", 5)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))

	var seen := {}
	for c in player.curses:
		seen[c] = int(seen.get(c, 0)) + 1
	for id in Content.CURSE_IDS:
		var n := int(seen.get(id, 0))
		if n <= 0:
			continue
		var data: Dictionary = Content.CURSES[id]
		var suffix := "" if n == 1 else "  x%d" % n
		var l := _label(_status_col, "DEFECT  %s%s   %s" % [
				str(data["name"]).to_upper(), suffix, str(data.get("desc", ""))],
			13, Color(1.0, 0.45, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
		l.add_theme_constant_override("outline_size", 5)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))


## Called on room entry: the tag in the top bar says what kind of room this is.
func set_room_kind(kind: String) -> void:
	room_kind = kind
	if _kind_label == null:
		return
	var style: Dictionary = KIND_STYLE.get(kind, KIND_STYLE["combat"])
	_kind_label.text = str(style["text"])
	_kind_label.add_theme_color_override("font_color", style["color"])


func _update_boss() -> void:
	if _boss_root == null:
		return
	var boss := _boss_watch
	if boss == null or not is_instance_valid(boss) or boss.dead:
		_boss_root.visible = false
		return
	_boss_root.visible = true
	var pct := clampf(boss.hp / maxf(boss.max_hp, 0.001), 0.0, 1.0)
	_boss_fill.anchor_right = pct
	var inset := minf(3.0, pct * 540.0 * 0.5)
	_boss_fill.offset_left = inset
	_boss_fill.offset_right = -inset
	_boss_label.text = "THE CORE   %d / %d" % [ceili(boss.hp), ceili(boss.max_hp)]

	# Two facts you need mid-fight: what is still alive in the room with you,
	# and whether this is the moment to spend everything.
	var adds := boss.adds_alive()
	var exposed := boss.is_vulnerable()
	var detail := boss.state_label()
	if adds > 0:
		detail += "     SUMMONS   %d" % adds
	elif exposed:
		detail = "EXPOSED   " + detail
	_boss_detail.text = detail
	if exposed:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.011)
		_boss_fill.color = Color(1.0, 0.4, 0.25).lerp(Color(1.0, 0.95, 0.6), pulse)
		_boss_detail.modulate = Color(1.0, 0.45, 0.3).lerp(Color(1.0, 0.9, 0.5), pulse)
	elif boss.invulnerable:
		_boss_fill.color = Color(1.0, 0.78, 0.25)
		_boss_detail.modulate = Color(0.55, 0.6, 0.85)
	else:
		_boss_fill.color = Color(1.0, 0.78, 0.25)
		_boss_detail.modulate = Color(1.0, 0.85, 0.3)


## The centre-screen streak pop. Fires on every clean kill from the third
## onward, then drifts away so it never sits over the fight.
func _update_streak() -> void:
	if _streak_label == null:
		return
	var n := GameManager.streak
	if n == _streak_shown:
		return
	_streak_shown = n
	_kill_streak_tween()
	if n < 3:
		_streak_label.visible = false
		_set_alpha(_streak_label, 1.0)
		return
	_streak_label.text = "STREAK  x%d" % n
	_streak_label.add_theme_color_override("font_color",
		Color(1.0, 0.78, 0.25).lerp(Color(1.0, 0.28, 0.2),
			clampf(float(n - 3) / 12.0, 0.0, 1.0)))
	_set_alpha(_streak_label, 1.0)
	_streak_label.scale = Vector2(1.5, 1.5)
	_streak_label.visible = true
	_streak_tween = create_tween()
	_streak_tween.tween_property(_streak_label, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_streak_tween.tween_interval(1.1)
	_streak_tween.tween_property(_streak_label, "modulate:a", 0.0, 0.35)
	_streak_tween.tween_callback(_hide_streak)


func _kill_streak_tween() -> void:
	if _streak_tween != null and _streak_tween.is_valid():
		_streak_tween.kill()
	_streak_tween = null


func _hide_streak() -> void:
	if _streak_label != null:
		_streak_label.visible = false


## A short-lived line above the ability row, for events the banner would
## otherwise swallow (or that do not deserve a banner at all).
func show_toast(text: String, color: Color = Color.WHITE,
		duration: float = 1.7) -> void:
	if _toast == null:
		return
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_set_alpha(_toast, 1.0)
	_toast.visible = true
	_toast_tween = create_tween()
	_toast_tween.tween_interval(duration)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(_hide_toast)


func _hide_toast() -> void:
	if _toast != null:
		_toast.visible = false


func _set_alpha(c: Control, a: float) -> void:
	var m := c.modulate
	m.a = a
	c.modulate = m


## One arrow at the edge of the screen pointing at the nearest enemy you
## cannot see. Rooms are large enough now that losing one off the side of
## the camera is routine, and that should be readable, not punishing.
func _update_threat() -> void:
	if _threat == null or _threat_cam == null or _threat_rooms == null:
		return
	if player == null or not is_instance_valid(player) or player.dead:
		_threat.visible = false
		return

	var best: Node3D = null
	var best_d := INF
	var best_elite := false
	var room := _threat_rooms.room_at(_threat_rooms.current_index)
	if room != null:
		for child in room.get_children():
			if not (child is Enemy):
				continue
			var e := child as Enemy
			if e.dead:
				continue
			var d: float = player.global_position.distance_to(e.global_position)
			if d < best_d:
				best_d = d
				best = e
				best_elite = e.elite != Enemy.Elite.NONE
	if best == null:
		_threat.visible = false
		return

	var world: Vector3 = best.global_position
	var behind := _threat_cam.is_position_behind(world)
	if not behind:
		var sp := _threat_cam.unproject_position(world)
		var m := 46.0
		if sp.x >= m and sp.x <= size.x - m and sp.y >= m and sp.y <= size.y - m:
			# On screen - the fight already tells you about this one.
			_threat.visible = false
			return
	_place_threat(world, best_d, behind, best_elite)


func _place_threat(world: Vector3, dist: float, behind: bool, elite: bool) -> void:
	var center := size * 0.5
	var sp := _threat_cam.unproject_position(world)
	if behind:
		# Mirrored so the arrow still points the right way around.
		sp = center - (sp - center)
	var dir := sp - center
	if dir.length_squared() < 4.0:
		dir = Vector2(0.0, -1.0)
	dir = dir.normalized()

	# Walk out from the centre until the marker hits the safe rectangle.
	var inset := size * 0.5 - Vector2(58.0, 78.0)
	var travel := INF
	if absf(dir.x) > 0.001:
		travel = minf(travel, maxf(inset.x, 1.0) / absf(dir.x))
	if absf(dir.y) > 0.001:
		travel = minf(travel, maxf(inset.y, 1.0) / absf(dir.y))
	if travel == INF or travel > size.x:
		travel = 120.0
	var pos := center + dir * travel

	var glyphs := ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"]
	var idx := int(round(atan2(dir.y, dir.x) / (PI / 4.0)))
	_threat.text = "%s   %dm" % [glyphs[posmod(idx, 8)], int(round(dist))]
	_threat.add_theme_color_override("font_color",
		Color(1.0, 0.35, 0.28) if elite else Color(1.0, 0.78, 0.35))
	_place(_threat, Vector2(0, 0), pos - Vector2(58.0, 14.0), Vector2(116.0, 28.0))
	_threat.visible = true


# ---------------------------------------------------------------- build -----

func _build() -> void:
	_build_top()
	_build_abilities()
	_build_multiplier()
	_build_status()
	_build_boss_bar()
	_build_reticle()

	_banner = _label(self, "", 42, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_banner, Vector2(0.5, 0.5), Vector2(-580, -80), Vector2(1160, 160))
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_banner.pivot_offset = Vector2(580, 80)
	_banner.visible = false

	# The Arena's voice: a typewriter subtitle line above the ability row.
	_voice = _label(self, "", 19, Color(0.55, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	_place(_voice, Vector2(0.5, 1), Vector2(-460, -(SLOT_H + 74.0)), Vector2(920, 36))
	_voice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_voice.add_theme_constant_override("outline_size", 7)
	_voice.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_voice.pivot_offset = Vector2(460, 18)
	_voice.visible = false

	# Streak pop: one line under the banner, only when the run is on a roll.
	_streak_label = _label(self, "", 34, Color(1.0, 0.78, 0.25),
		HORIZONTAL_ALIGNMENT_CENTER)
	_place(_streak_label, Vector2(0.5, 0.5), Vector2(-320, 92), Vector2(640, 46))
	_streak_label.add_theme_constant_override("outline_size", 9)
	_streak_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_streak_label.pivot_offset = Vector2(320, 23)
	_streak_label.visible = false

	# Small event toast above the ability row: "+1 DASH CHARGE" and friends.
	_toast = _label(self, "", 20, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	_place(_toast, Vector2(0.5, 1), Vector2(-300, -(SLOT_H + 112.0)),
		Vector2(600, 26))
	_toast.add_theme_constant_override("outline_size", 7)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_toast.visible = false

	# Off-screen threat arrow, parked out of the way until it is needed.
	_threat = _label(self, "", 21, Color(1.0, 0.78, 0.35), HORIZONTAL_ALIGNMENT_CENTER)
	_place(_threat, Vector2(0, 0), Vector2(-400, -400), Vector2(116, 28))
	_threat.visible = false

	# Points rise next to the tally, so a kill pays in front of you.
	_score_pop = _label(self, "", 20, Color(1.0, 0.9, 0.4),
		HORIZONTAL_ALIGNMENT_RIGHT)
	_score_pop_y = 16.0 + TOP_H + 8.0
	_place(_score_pop, Vector2(1, 0), Vector2(-268, _score_pop_y), Vector2(252, 26))
	_score_pop.add_theme_constant_override("outline_size", 7)
	_score_pop.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_score_pop.visible = false

	# What this room wants from you, parked under the top panel where it
	# stays true for the whole room instead of scrolling away with a banner.
	_objective = _label(self, "", 15, Color(0.35, 0.85, 1.0),
		HORIZONTAL_ALIGNMENT_LEFT)
	_place(_objective, Vector2(0, 0), Vector2(16, 16.0 + TOP_H + 8.0),
		Vector2(460, 24))
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.add_theme_constant_override("outline_size", 6)
	_objective.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_objective.visible = false

	# Longer-lived instruction, above the toast so the two never collide.
	_hint = _label(self, "", 18, Color(1.0, 0.95, 0.7),
		HORIZONTAL_ALIGNMENT_CENTER)
	_place(_hint, Vector2(0.5, 1), Vector2(-420, -(SLOT_H + 150.0)),
		Vector2(840, 30))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_constant_override("outline_size", 7)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hint.pivot_offset = Vector2(420, 15)
	_hint.visible = false

	_vignette = ColorRect.new()
	_vignette.color = Color(0.85, 0.05, 0.05, 0.0)
	_cover(_vignette)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)

	# Persistent low-HP layer, on top of the one-shot damage flash.
	_crit = ColorRect.new()
	_crit.color = Color(0.9, 0.12, 0.1, 0.0)
	_cover(_crit)
	_crit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crit.visible = false
	add_child(_crit)


## A dot and four arms at the centre of the screen. It reads as an aim point
## and doubles as the hit marker.
func _build_reticle() -> void:
	_reticle_root = Control.new()
	_place(_reticle_root, Vector2(0.5, 0.5), Vector2(-16, -16), Vector2(32, 32))
	_reticle_root.pivot_offset = Vector2(16, 16)
	_reticle_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle_root.visible = GameManager.opt_reticle
	add_child(_reticle_root)

	var arm_len := 7.0
	var arm_w := 2.0
	var gap := 7.0
	_reticle_rect(Vector2(-2.5, -2.5), Vector2(5, 5), Color(1, 1, 1, 0.95))
	_reticle_rect(Vector2(-arm_w * 0.5, -(gap + arm_len)), Vector2(arm_w, arm_len),
		Color(1, 1, 1, 0.72))
	_reticle_rect(Vector2(-arm_w * 0.5, gap), Vector2(arm_w, arm_len),
		Color(1, 1, 1, 0.72))
	_reticle_rect(Vector2(-(gap + arm_len), -arm_w * 0.5), Vector2(arm_len, arm_w),
		Color(1, 1, 1, 0.72))
	_reticle_rect(Vector2(gap, -arm_w * 0.5), Vector2(arm_len, arm_w),
		Color(1, 1, 1, 0.72))


func _reticle_rect(off: Vector2, sz: Vector2, col: Color) -> void:
	var r := ColorRect.new()
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(r, Vector2(0.5, 0.5), off, sz)
	_reticle_root.add_child(r)


## Everything the player needs to read sits in one centred block at the top.
func _build_top() -> void:
	var top := Control.new()
	_place(top, Vector2(0.5, 0), Vector2(-TOP_W / 2.0, 16), Vector2(TOP_W, TOP_H))
	add_child(top)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 5)
	top.add_child(col)

	var title_row := HBoxContainer.new()
	title_row.custom_minimum_size = Vector2(0, 17)
	title_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	title_row.add_theme_constant_override("separation", 8)
	col.add_child(title_row)

	var title := _label(title_row, "HEALTH", 15, Color(0.72, 0.77, 0.88),
		HORIZONTAL_ALIGNMENT_LEFT)
	title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	# The warning sits next to the label so it cannot be mistaken for a
	# damage number floating somewhere in the fight.
	_hp_warn = _label(title_row, "CRITICAL", 14, Color(1.0, 0.32, 0.26),
		HORIZONTAL_ALIGNMENT_RIGHT)
	_hp_warn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_warn.add_theme_constant_override("outline_size", 4)
	_hp_warn.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hp_warn.visible = false

	# --- health bar ---
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 32)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	col.add_child(bar)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 0.9)
	_cover(bg)
	bar.add_child(bg)

	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.3, 0.95, 0.4)
	_cover(_hp_fill)
	_hp_fill.offset_left = 3.0
	_hp_fill.offset_top = 3.0
	_hp_fill.offset_right = -3.0
	_hp_fill.offset_bottom = -3.0
	_hp_fill.grow_horizontal = Control.GROW_DIRECTION_END
	bar.add_child(_hp_fill)

	_hp_text = _label(bar, "100 / 100", 17, Color(1, 1, 1))
	_cover(_hp_text)
	_hp_text.add_theme_constant_override("outline_size", 5)
	_hp_text.add_theme_color_override("font_outline_color", Color(0, 0, 0))

	# --- stats row ---
	var stats_row := HBoxContainer.new()
	stats_row.custom_minimum_size = Vector2(0, 30)
	stats_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stats_row.add_theme_constant_override("separation", 8)
	col.add_child(stats_row)

	_kills_label = _label(stats_row, "KILLS   0", 18, Color(0.95, 0.95, 1.0),
		HORIZONTAL_ALIGNMENT_LEFT)
	_room_label = _label(stats_row, "ROOM   1", 18, Color(1.0, 0.85, 0.4))
	_left_label = _label(stats_row, "LEFT   0", 18, Color(0.6, 0.9, 1.0))
	_score_label = _label(stats_row, "SCORE   0", 18, Color(0.5, 1.0, 0.75),
		HORIZONTAL_ALIGNMENT_RIGHT)
	for child in stats_row.get_children():
		var l := child as Label
		if l != null:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.add_theme_constant_override("outline_size", 6)
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0))

	# --- realm + difficulty ---
	var realm_row := HBoxContainer.new()
	realm_row.custom_minimum_size = Vector2(0, 22)
	realm_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	realm_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	realm_row.add_theme_constant_override("separation", 8)
	col.add_child(realm_row)

	_realm_label = _label(realm_row, "RECONSTRUCTION WING", 14, Color(1.0, 0.5, 0.35),
		HORIZONTAL_ALIGNMENT_LEFT)
	_realm_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_kind_label = _label(realm_row, "COMBAT", 13, Color(0.6, 0.7, 0.85),
		HORIZONTAL_ALIGNMENT_CENTER)
	_kind_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_kind_label.size_flags_stretch_ratio = 1.8
	_label(realm_row, GameManager.difficulty_name().to_upper(), 15,
		Color(0.65, 0.7, 0.8), HORIZONTAL_ALIGNMENT_RIGHT)
	for child in realm_row.get_children():
		var l := child as Label
		if l != null:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.add_theme_constant_override("outline_size", 5)
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0))

	_build_wing_row(col)


## How far through the current 20-room wing you are. The endless arena needs
## one piece of orientation that does not reset when a room does.
func _build_wing_row(col: VBoxContainer) -> void:
	var wing_row := HBoxContainer.new()
	wing_row.custom_minimum_size = Vector2(0, 14)
	wing_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wing_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	wing_row.add_theme_constant_override("separation", 8)
	col.add_child(wing_row)

	_wing_label = _label(wing_row, "WING  1 / 20", 12, Color(0.72, 0.77, 0.92),
		HORIZONTAL_ALIGNMENT_LEFT)
	_wing_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_wing_label.add_theme_constant_override("outline_size", 5)
	_wing_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))

	var bar := Control.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	bar.custom_minimum_size = Vector2(0, 11)
	wing_row.add_child(bar)

	var wbg := ColorRect.new()
	wbg.color = Color(0.05, 0.06, 0.1, 0.85)
	_cover(wbg)
	bar.add_child(wbg)

	_wing_fill = ColorRect.new()
	_wing_fill.color = Color(1.0, 0.8, 0.35)
	_cover(_wing_fill)
	_wing_fill.grow_horizontal = Control.GROW_DIRECTION_END
	bar.add_child(_wing_fill)

	_streak_small = _label(wing_row, "", 12, Color(1.0, 0.78, 0.25),
		HORIZONTAL_ALIGNMENT_RIGHT)
	_streak_small.size_flags_horizontal = Control.SIZE_SHRINK_END
	_streak_small.add_theme_constant_override("outline_size", 5)
	_streak_small.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_streak_small.visible = false


func _update_wing() -> void:
	if _wing_label == null or _wing_fill == null:
		return
	var span := maxi(GameManager.REALM_LENGTH, 1)
	var pos := (current_room % span) + 1
	_wing_label.text = "WING  %d / %d" % [pos, span]
	_wing_fill.anchor_right = clampf(float(pos) / float(span), 0.0, 1.0)
	var realm := GameManager.realm_of_room(current_room)
	_wing_fill.color = [Color(1.0, 0.5, 0.35), Color(0.4, 1.0, 0.6),
		Color(1.0, 0.9, 0.5)][clampi(realm, 0, 2)]

	# The big streak pop is a moment; this is a fact you can check any time.
	if _streak_small != null:
		var n := GameManager.streak
		_streak_small.visible = n >= 1
		if n >= 1:
			_streak_small.text = "STREAK  x%d" % n
			_streak_small.add_theme_color_override("font_color",
				Color(1.0, 0.78, 0.25).lerp(Color(1.0, 0.3, 0.2),
					clampf(float(n - 3) / 12.0, 0.0, 1.0)))


func _build_multiplier() -> void:
	var panel := Control.new()
	_place(panel, Vector2(0, 0.5), Vector2(14, -96), Vector2(MULT_W, 192))
	add_child(panel)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.1, 0.82)
	_cover(bg)
	panel.add_child(bg)
	var frame := ColorRect.new()
	frame.color = Color(1.0, 0.85, 0.3, 0.35)
	frame.anchor_left = 0.0
	frame.anchor_right = 1.0
	frame.anchor_top = 0.0
	frame.anchor_bottom = 0.0
	frame.offset_left = 0.0
	frame.offset_right = 0.0
	frame.offset_top = 0.0
	frame.offset_bottom = 2.0
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(frame)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 2)
	col.offset_left = 12.0
	col.offset_right = -12.0
	col.offset_top = 10.0
	col.offset_bottom = -8.0
	panel.add_child(col)

	var head := _label(col, "SCORE MULTIPLIER", 13, Color(0.72, 0.77, 0.88),
		HORIZONTAL_ALIGNMENT_LEFT)
	head.add_theme_constant_override("outline_size", 4)
	head.add_theme_color_override("font_outline_color", Color(0, 0, 0))

	_time_label = _label(col, "QUICK BONUS", 12, Color(0.5, 0.95, 0.7),
		HORIZONTAL_ALIGNMENT_LEFT)
	_time_label.add_theme_constant_override("outline_size", 4)
	_time_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))

	_mult_value = _label(col, "x1.00", 48, Color(1.0, 0.9, 0.3),
		HORIZONTAL_ALIGNMENT_LEFT)
	_mult_value.add_theme_constant_override("outline_size", 8)
	_mult_value.add_theme_color_override("font_outline_color", Color(0, 0, 0))

	_mult_rows = VBoxContainer.new()
	_mult_rows.add_theme_constant_override("separation", 3)
	col.add_child(_mult_rows)
	for i in 4:
		var l := _label(_mult_rows, "", 13, Color(0.7, 0.74, 0.84),
			HORIZONTAL_ALIGNMENT_LEFT)
		l.add_theme_constant_override("outline_size", 4)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))


func _build_status() -> void:
	var panel := Control.new()
	_place(panel, Vector2(1, 0.5),
		Vector2(-14.0 - STATUS_W, -150), Vector2(STATUS_W, 300))
	add_child(panel)
	_status_root = panel

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.1, 0.78)
	_cover(bg)
	panel.add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 3)
	col.offset_left = 12.0
	col.offset_right = -10.0
	col.offset_top = 8.0
	col.offset_bottom = -8.0
	panel.add_child(col)

	var head := _label(col, "RUN STATUS", 13, Color(0.72, 0.77, 0.88),
		HORIZONTAL_ALIGNMENT_LEFT)
	head.add_theme_constant_override("outline_size", 4)
	head.add_theme_color_override("font_outline_color", Color(0, 0, 0))

	# The difficulty's real numbers. "Hard" means nothing until you can see
	# what it actually did to the enemies.
	var s: Dictionary = GameManager.settings()
	_diff_detail = _label(col, "%s   hp x%.1f   dmg x%.1f   cd x%.1f" % [
			GameManager.difficulty_name().to_upper(),
			float(s.get("hp_mult", 1.0)), float(s.get("dmg_mult", 1.0)),
			float(s.get("cooldown_mult", 1.0))],
		12, Color(0.55, 0.6, 0.74), HORIZONTAL_ALIGNMENT_LEFT)
	_diff_detail.add_theme_constant_override("outline_size", 4)
	_diff_detail.add_theme_color_override("font_outline_color", Color(0, 0, 0))

	_status_col = VBoxContainer.new()
	_status_col.add_theme_constant_override("separation", 2)
	col.add_child(_status_col)


func _build_boss_bar() -> void:
	_boss_root = Control.new()
	_place(_boss_root, Vector2(0.5, 0),
		Vector2(-270, 16 + TOP_H + 6), Vector2(540, 48))
	_boss_root.visible = false
	_boss_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_boss_root)

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.08, 0.9)
	_cover(bg)
	_boss_root.add_child(bg)

	_boss_fill = ColorRect.new()
	_boss_fill.color = Color(1.0, 0.78, 0.25)
	_cover(_boss_fill)
	_boss_root.add_child(_boss_fill)

	_boss_label = _label(_boss_root, "THE CORE", 17, Color(1, 1, 1))
	_place(_boss_label, Vector2(0, 0), Vector2(8, 1), Vector2(524, 24))
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_boss_label.add_theme_constant_override("outline_size", 5)
	_boss_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))

	_boss_detail = _label(_boss_root, "", 14, Color(1.0, 0.85, 0.3))
	_place(_boss_detail, Vector2(0, 0), Vector2(8, 25), Vector2(524, 20))
	_boss_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_boss_detail.add_theme_constant_override("outline_size", 5)
	_boss_detail.add_theme_color_override("font_outline_color", Color(0, 0, 0))


## Super / Dash / Heal, pinned to the bottom centre of the screen.
func _build_abilities() -> void:
	var total_w := SLOT_W * 3.0 + 20.0
	var bottom := Control.new()
	_place(bottom, Vector2(0.5, 1),
		Vector2(-total_w / 2.0, -(SLOT_H + 26.0)), Vector2(total_w, SLOT_H))
	add_child(bottom)
	_ability_root = bottom

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(row)

	for i in 3:
		var slot := _make_slot(player.ability_names[i], player.ability_keys[i])
		if i == 1:
			_add_pips(slot)
		row.add_child(slot["root"])
		_slots.append(slot)


## Six charge pips along the bottom of the dash slot. More readable than a
## number when you are deciding whether you can afford to spend one.
func _add_pips(slot: Dictionary) -> void:
	var root := slot["root"] as Control
	var pips: Array = []
	var w := 13.0
	var gap := 3.0
	var max_pips := 6
	var total := max_pips * w + (max_pips - 1) * gap
	var x0 := (SLOT_W - total) * 0.5
	for i in max_pips:
		var p := ColorRect.new()
		p.color = Color(0.15, 0.19, 0.28)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_place(p, Vector2(0, 0), Vector2(x0 + float(i) * (w + gap), 95.0),
			Vector2(w, 6.0))
		p.visible = false
		root.add_child(p)
		pips.append(p)
	slot["pips"] = pips


func _make_slot(name_text: String, key_text: String) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = Vector2(SLOT_W, SLOT_H)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.09, 0.85)
	_cover(bg)
	root.add_child(bg)

	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	overlay.anchor_left = 0.0
	overlay.anchor_right = 1.0
	overlay.anchor_top = 0.0
	overlay.anchor_bottom = 0.0
	overlay.offset_left = 0.0
	overlay.offset_right = 0.0
	overlay.offset_top = 0.0
	overlay.offset_bottom = 0.0
	overlay.grow_vertical = Control.GROW_DIRECTION_END
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)

	var outline_size := 6
	var outline_color := Color(0, 0, 0)

	var name_label := _label(root, name_text, 13, Color(0.8, 0.85, 0.95))
	_place(name_label, Vector2(0, 0), Vector2(4, 5), Vector2(SLOT_W - 8.0, 20))

	var key_label := _label(root, key_text, 30, Color(1, 1, 1))
	_place(key_label, Vector2(0, 0), Vector2(0, 27), Vector2(SLOT_W, 42))

	var value := _label(root, "", 17, Color(1.0, 0.88, 0.4))
	_place(value, Vector2(0, 0), Vector2(0, 70), Vector2(SLOT_W, 24))
	value.visible = true

	for lbl in [name_label, key_label, value]:
		var l := lbl as Label
		l.add_theme_constant_override("outline_size", outline_size)
		l.add_theme_color_override("font_outline_color", outline_color)

	return {"root": root, "overlay": overlay, "value": value, "name": name_label}


# ------------------------------------------------------------- helpers ------

func _place(c: Control, anchor: Vector2, offset: Vector2, size: Vector2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + size.x
	c.offset_bottom = offset.y + size.y
	if anchor.x >= 0.99:
		c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	elif absf(anchor.x - 0.5) < 0.01:
		c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	else:
		c.grow_horizontal = Control.GROW_DIRECTION_END
	if anchor.y >= 0.99:
		c.grow_vertical = Control.GROW_DIRECTION_BEGIN
	elif absf(anchor.y - 0.5) < 0.01:
		c.grow_vertical = Control.GROW_DIRECTION_BOTH
	else:
		c.grow_vertical = Control.GROW_DIRECTION_END


func _cover(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0


func _label(parent: Node, text: String, font_size: int, color: Color,
		align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


# ------------------------------------------------------------ feedback -------

func show_banner(text: String, color: Color = Color.WHITE, duration: float = 2.0) -> void:
	if _banner == null:
		return
	# Something loud is already on screen. Queue rather than swallow it - a
	# realm banner used to vanish the instant a defect fired.
	if _banner_busy:
		if _banner_queue.size() >= 2:
			_banner_queue.pop_front()
		_banner_queue.append({"text": text, "color": color, "duration": duration})
		return
	_start_banner(text, color, duration)


func _start_banner(text: String, color: Color, duration: float) -> void:
	_banner_busy = true
	_banner.text = text
	_banner.modulate = Color(color.r, color.g, color.b, 1.0)
	_banner.scale = Vector2(1.2, 1.2)
	_banner.visible = true
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "scale", Vector2.ONE, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(duration)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.45)
	_banner_tween.tween_callback(_hide_banner)


func _hide_banner() -> void:
	_banner.visible = false
	var m := _banner.modulate
	m.a = 1.0
	_banner.modulate = m
	_banner_busy = false
	if _banner_queue.size() > 0:
		var item: Dictionary = _banner_queue.pop_front()
		var c: Color = item.get("color", Color.WHITE)
		_start_banner(str(item.get("text", "")), c, float(item.get("duration", 2.0)))


## The Arena speaking: a typewriter subtitle above the ability row. Stacks a
## new line over the old one without interruption - the latest word wins.
func show_voice(text: String) -> void:
	if _voice == null:
		return
	if _voice_tween != null and _voice_tween.is_valid():
		_voice_tween.kill()
	_voice.text = text
	_voice.modulate = Color(1, 1, 1, 1)
	_voice.visible = true
	_voice.visible_characters = 0
	_voice_tween = create_tween()
	_voice_tween.tween_method(_set_voice_chars, 0, text.length(),
		clampf(text.length() * 0.024, 0.3, 1.4))
	_voice_tween.tween_interval(2.6)
	_voice_tween.tween_property(_voice, "modulate:a", 0.0, 0.5)
	_voice_tween.tween_callback(_hide_voice)


func _set_voice_chars(n: Variant) -> void:
	if _voice != null:
		_voice.visible_characters = int(n)


func _hide_voice() -> void:
	if _voice != null:
		_voice.visible = false
		_voice.visible_characters = -1


func flash_damage(_amount: float = 0.0) -> void:
	if _vignette == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_vignette.color = Color(0.85, 0.05, 0.05, 0.45)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_vignette, "color:a", 0.0, 0.42)


func hide_bars() -> void:
	if _vignette == null:
		return
	_vignette.color = Color(0.85, 0.05, 0.05, 0.0)
