class_name HUD
extends CanvasLayer

## Field HUD:
##   • Top bar:   "Field N" (left) | "Gold N" (right)
##   • Bottom bar: a row of party member boxes — portrait + name on the left
##                 column, HP bar / MP bar / EXP bar / equipment slots on the right.
##
## Pure presentation node. State comes from GameState, change notifications
## come through EventBus.

const MEMBER_BOX_SCENE: PackedScene = preload("res://scenes/ui/party_member_box.tscn")
const LEVEL_UP_STAT_PANEL_SCENE: PackedScene = preload("res://scenes/ui/level_up_stat_panel.tscn")
const LEVEL_UP_PANEL_SCENE: PackedScene = preload("res://scenes/ui/level_up_panel.tscn")

@onready var _stage_label: Label = %StageLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _member_row: HBoxContainer = %MemberRow
## Built dynamically so it sits on whatever HUD scene variant is active.
var _stage_timer_label: Label
var _cheat_button_row: HBoxContainer

## Live member box references, parallel to GameState.party. Rebuilt from
## scratch on party_changed so we never have stale indices when a recruit
## or wipe shifts the party array.
var _member_boxes: Array[PartyMemberBox] = []
var _stat_panel: LevelUpStatPanel
var _level_up_panel: LevelUpPanel
var _pending_level_up_choice_rounds: int = 0
## Tracks the party level seen on the previous level-up emit so the stat
## panel can show old→new deltas for multi-level jumps.
var _previous_party_level: int = 1
## Per-frame throttle: party members now level in lockstep so the level-up
## signal fires N times in the same frame. We only want one toast + one
## reward flow, so we ignore repeated emits from the same frame.
var _last_level_up_frame: int = -1
func _ready() -> void:
	EventBus.party_changed.connect(_rebuild_member_boxes)
	EventBus.party_member_hp_changed.connect(_on_party_member_hp_changed)
	EventBus.party_member_mp_changed.connect(_on_party_member_mp_changed)
	EventBus.party_member_xp_changed.connect(_on_party_member_xp_changed)
	EventBus.party_member_leveled_up.connect(_on_party_member_leveled_up)
	EventBus.party_equipment_changed.connect(_on_party_equipment_changed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.stage_started.connect(_on_stage_started)
	EventBus.difficulty_increased.connect(_on_difficulty_increased)
	EventBus.character_recruited.connect(_on_character_recruited)
	EventBus.system_unlocked.connect(_on_system_unlocked)
	_build_stage_timer_label()
	_build_field_bump_button()
	_build_debug_level_button()
	_refresh_gold()
	_refresh_stage()
	_rebuild_member_boxes()


## Wave timer updates every frame. Pulls state from the field_root group so
## the HUD doesn't need a direct reference.
func _process(_delta: float) -> void:
	_update_stage_timer()


## Debug knobs live in the bottom-right corner so the top bar can stay
## readable during timed waves.
func _build_field_bump_button() -> void:
	var parent: HBoxContainer = _ensure_cheat_button_row()
	var btn := Button.new()
	btn.text = "▲"
	btn.tooltip_text = "필드 레벨 +1"
	btn.add_theme_font_size_override("font_size", 9)
	btn.custom_minimum_size = Vector2(18, 14)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_on_field_bump_pressed)
	parent.add_child(btn)


func _on_field_bump_pressed() -> void:
	GameState.bump_difficulty_tier()


func _build_debug_level_button() -> void:
	var parent: HBoxContainer = _ensure_cheat_button_row()
	var btn := Button.new()
	btn.text = "LV+"
	btn.tooltip_text = "테스트 레벨업"
	btn.add_theme_font_size_override("font_size", 9)
	btn.custom_minimum_size = Vector2(28, 14)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_on_debug_level_pressed)
	parent.add_child(btn)


func _on_debug_level_pressed() -> void:
	GameState.debug_level_up_party()


func _ensure_cheat_button_row() -> HBoxContainer:
	if is_instance_valid(_cheat_button_row):
		return _cheat_button_row
	_cheat_button_row = HBoxContainer.new()
	_cheat_button_row.name = "CheatButtons"
	_cheat_button_row.anchor_left = 1.0
	_cheat_button_row.anchor_top = 1.0
	_cheat_button_row.anchor_right = 1.0
	_cheat_button_row.anchor_bottom = 1.0
	_cheat_button_row.offset_left = -92.0
	_cheat_button_row.offset_top = -38.0
	_cheat_button_row.offset_right = -12.0
	_cheat_button_row.offset_bottom = -10.0
	_cheat_button_row.alignment = BoxContainer.ALIGNMENT_END
	_cheat_button_row.add_theme_constant_override("separation", 5)
	add_child(_cheat_button_row)
	return _cheat_button_row


func _build_stage_timer_label() -> void:
	_stage_timer_label = Label.new()
	_stage_timer_label.name = "StageTimerLabel"
	_stage_timer_label.anchor_left = 0.5
	_stage_timer_label.anchor_top = 0.0
	_stage_timer_label.anchor_right = 0.5
	_stage_timer_label.anchor_bottom = 0.0
	_stage_timer_label.offset_left = -80.0
	_stage_timer_label.offset_top = 10.0
	_stage_timer_label.offset_right = 80.0
	_stage_timer_label.offset_bottom = 36.0
	_stage_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(_stage_label) and _stage_label.label_settings != null:
		_stage_timer_label.label_settings = _stage_label.label_settings
	else:
		_stage_timer_label.add_theme_font_size_override("font_size", 18)
		_stage_timer_label.add_theme_color_override("font_color", Color.WHITE)
		_stage_timer_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
		_stage_timer_label.add_theme_constant_override("outline_size", 3)
	add_child(_stage_timer_label)


func _update_stage_timer() -> void:
	if not is_instance_valid(_stage_timer_label):
		return
	var field: Node = get_tree().get_first_node_in_group("field_root")
	if field == null or not field.has_method("stage_time_left"):
		_stage_timer_label.visible = false
		return
	var seconds_left: int = maxi(0, int(ceil(float(field.stage_time_left()))))
	_stage_timer_label.visible = true
	_stage_timer_label.text = "%02d:%02d" % [int(seconds_left / 60), seconds_left % 60]


# ─── Bottom row ───────────────────────────────────────────────────────
func _rebuild_member_boxes() -> void:
	# Fresh party — reset throttle so the first level-up of the new run
	# still pops its banner.
	_last_level_up_frame = -1
	_previous_party_level = GameState.current_level
	for box in _member_boxes:
		if is_instance_valid(box):
			box.queue_free()
	_member_boxes.clear()
	for i in GameState.party_size():
		# Layout flags are authored on the box scene root, so each member
		# keeps its natural size and stays pinned to the bottom row.
		var box: PartyMemberBox = MEMBER_BOX_SCENE.instantiate()
		_member_row.add_child(box)
		box.setup(i, GameState.party[i])
		_member_boxes.append(box)


func _on_party_member_hp_changed(index: int, new_hp: int, max_hp: int) -> void:
	if index < 0 or index >= _member_boxes.size():
		return
	_member_boxes[index].set_hp(new_hp, max_hp)


func _on_party_member_mp_changed(index: int, new_mp: int, max_mp: int) -> void:
	if index < 0 or index >= _member_boxes.size():
		return
	_member_boxes[index].set_mp(new_mp, max_mp)


func _on_party_member_xp_changed(index: int, xp: int, xp_to_next: int, level: int) -> void:
	if index < 0 or index >= _member_boxes.size():
		return
	var ratio: float = 1.0 if level >= GameState.MAX_CHARACTER_LEVEL else clampf(float(xp) / float(maxi(1, xp_to_next)), 0.0, 1.0)
	_member_boxes[index].set_exp_ratio(ratio)
	_member_boxes[index].set_level(level)


## On level-up: stat-delta panel immediately → member card picks.
## Frame-id throttle keeps the synced N-member emits from triggering the
## whole chain N times.
func _on_party_member_leveled_up(_index: int, new_level: int) -> void:
	var current_frame: int = Engine.get_process_frames()
	if current_frame == _last_level_up_frame:
		return
	_last_level_up_frame = current_frame
	var levels_gained: int = maxi(1, new_level - _previous_party_level)
	_previous_party_level = new_level
	if is_instance_valid(_stat_panel) or is_instance_valid(_level_up_panel):
		return
	_open_stat_panel(levels_gained)


func _open_stat_panel(levels_gained: int) -> void:
	_pending_level_up_choice_rounds = maxi(1, levels_gained)
	_stat_panel = LEVEL_UP_STAT_PANEL_SCENE.instantiate()
	_stat_panel.setup(levels_gained, GameState.last_level_up_auto_skills())
	add_child(_stat_panel)
	get_tree().paused = true
	_stat_panel.confirmed.connect(_on_stat_panel_confirmed)
	_stat_panel.tree_exited.connect(func() -> void:
		_stat_panel = null
	)


func _on_stat_panel_confirmed() -> void:
	call_deferred("_open_level_up_offer_sequence")


func _open_level_up_offer_sequence() -> void:
	if _pending_level_up_choice_rounds <= 0:
		get_tree().paused = false
		return
	_pending_level_up_choice_rounds -= 1
	var offers: Array[ModifierData] = GameState.level_up_card_offers()
	if offers.is_empty():
		call_deferred("_open_level_up_offer_sequence")
		return
	_level_up_panel = LEVEL_UP_PANEL_SCENE.instantiate()
	_level_up_panel.setup(-1, "파티", offers)
	add_child(_level_up_panel)
	get_tree().paused = true
	_level_up_panel.modifier_chosen.connect(_on_level_up_modifier_chosen)
	_level_up_panel.tree_exited.connect(func() -> void:
		_level_up_panel = null
	)


func _on_level_up_modifier_chosen(member_index: int, mod: ModifierData) -> void:
	GameState.apply_level_up_modifier(mod)
	call_deferred("_open_level_up_offer_sequence")


## Centered "레벨 업! → Lv N" banner. Lands with a TRANS_BACK punch (same
## family as the battle-window popup), holds, then fades out above the field.
func _show_level_up_toast(new_level: int) -> void:
	var toast := Label.new()
	toast.text = "레벨 업!  Lv %d" % new_level
	toast.add_theme_font_size_override("font_size", 26)
	toast.add_theme_color_override("font_color", Color(1.0, 0.92, 0.42))
	toast.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.02, 1.0))
	toast.add_theme_constant_override("outline_size", 6)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast.set_anchors_preset(Control.PRESET_FULL_RECT)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.z_index = 4096
	toast.top_level = true
	toast.modulate.a = 0.0
	# Pivot at viewport center so scale punches from the middle.
	var vp: Vector2 = get_viewport().get_visible_rect().size
	toast.pivot_offset = vp * 0.5
	toast.scale = Vector2(0.5, 0.5)
	add_child(toast)
	toast.move_to_front()

	var enter_tween: Tween = toast.create_tween()
	enter_tween.set_parallel(true)
	enter_tween.tween_property(toast, "scale", Vector2.ONE, 0.28)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	enter_tween.tween_property(toast, "modulate:a", 1.0, 0.14)

	var exit_tween: Tween = toast.create_tween()
	exit_tween.tween_interval(0.7)
	exit_tween.tween_property(toast, "modulate:a", 0.0, 0.35)
	exit_tween.tween_callback(toast.queue_free)


## Generic centered banner — used by stage announcements and any future
## "big event" cue. Cool blue tint differentiates from the yellow level-up
## toast so the two read as different categories at a glance.
func _show_phase_toast(text: String) -> void:
	var toast := Label.new()
	toast.text = text
	toast.add_theme_font_size_override("font_size", 22)
	toast.add_theme_color_override("font_color", Color(0.65, 0.78, 1.0))
	toast.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.12, 1.0))
	toast.add_theme_constant_override("outline_size", 6)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast.set_anchors_preset(Control.PRESET_FULL_RECT)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.z_index = 4096
	toast.top_level = true
	toast.modulate.a = 0.0
	var vp: Vector2 = get_viewport().get_visible_rect().size
	toast.pivot_offset = vp * 0.5
	toast.scale = Vector2(0.55, 0.55)
	add_child(toast)
	toast.move_to_front()

	var enter_tween: Tween = toast.create_tween()
	enter_tween.set_parallel(true)
	enter_tween.tween_property(toast, "scale", Vector2.ONE, 0.34)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	enter_tween.tween_property(toast, "modulate:a", 1.0, 0.2)

	var exit_tween: Tween = toast.create_tween()
	exit_tween.tween_interval(1.2)
	exit_tween.tween_property(toast, "modulate:a", 0.0, 0.5)
	exit_tween.tween_callback(toast.queue_free)


func _on_system_unlocked(_system_id: StringName, display_name: String, description: String) -> void:
	_show_system_unlock_toast(display_name, description)


func _show_system_unlock_toast(display_name: String, description: String) -> void:
	var toast := VBoxContainer.new()
	toast.alignment = BoxContainer.ALIGNMENT_CENTER
	toast.set_anchors_preset(Control.PRESET_FULL_RECT)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.z_index = 4096
	toast.top_level = true
	toast.modulate.a = 0.0

	var headline := Label.new()
	headline.text = "NEW SYSTEM"
	headline.add_theme_font_size_override("font_size", 16)
	headline.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	headline.add_theme_color_override("font_outline_color", Color(0.02, 0.07, 0.1, 1.0))
	headline.add_theme_constant_override("outline_size", 5)
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(headline)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.98, 0.76))
	name_label.add_theme_color_override("font_outline_color", Color(0.06, 0.06, 0.02, 1.0))
	name_label.add_theme_constant_override("outline_size", 6)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(name_label)

	if not description.is_empty():
		var detail := Label.new()
		detail.text = description
		detail.add_theme_font_size_override("font_size", 13)
		detail.add_theme_color_override("font_color", Color.WHITE)
		detail.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.04, 1.0))
		detail.add_theme_constant_override("outline_size", 4)
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		toast.add_child(detail)

	var vp: Vector2 = get_viewport().get_visible_rect().size
	toast.pivot_offset = vp * 0.5
	toast.scale = Vector2(0.48, 0.48)
	add_child(toast)
	toast.move_to_front()

	var enter_tween: Tween = toast.create_tween()
	enter_tween.set_parallel(true)
	enter_tween.tween_property(toast, "scale", Vector2.ONE, 0.34)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	enter_tween.tween_property(toast, "modulate:a", 1.0, 0.18)

	var exit_tween: Tween = toast.create_tween()
	exit_tween.tween_interval(1.45)
	exit_tween.tween_property(toast, "modulate:a", 0.0, 0.42)
	exit_tween.tween_callback(toast.queue_free)


## Fires the moment add_recruit lands a new companion. Green banner +
## ★ glyph so it reads visually distinct from the yellow level-up toast
## and the cool blue phase toast.
func _on_character_recruited(character: CharacterData) -> void:
	if character == null:
		return
	_show_recruit_toast(character)
	_pulse_member_box_for_character(character)


func _show_recruit_toast(character: CharacterData) -> void:
	var toast := VBoxContainer.new()
	toast.alignment = BoxContainer.ALIGNMENT_CENTER
	toast.set_anchors_preset(Control.PRESET_FULL_RECT)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.z_index = 4096
	toast.top_level = true
	toast.modulate.a = 0.0

	var headline := Label.new()
	headline.text = "★ 동료 합류! ★"
	headline.add_theme_font_size_override("font_size", 22)
	headline.add_theme_color_override("font_color", Color(0.62, 1.0, 0.58))
	headline.add_theme_color_override("font_outline_color", Color(0.04, 0.12, 0.04, 1.0))
	headline.add_theme_constant_override("outline_size", 6)
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(headline)

	var name_label := Label.new()
	name_label.text = character.display_name
	name_label.add_theme_font_size_override("font_size", 32)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.98, 0.78))
	name_label.add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.03, 1.0))
	name_label.add_theme_constant_override("outline_size", 7)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(name_label)

	var vp: Vector2 = get_viewport().get_visible_rect().size
	toast.pivot_offset = vp * 0.5
	toast.scale = Vector2(0.4, 0.4)
	add_child(toast)
	toast.move_to_front()

	# Punchy spring-in (TRANS_BACK over-shoot) to sell the recruit moment.
	var enter_tween: Tween = toast.create_tween()
	enter_tween.set_parallel(true)
	enter_tween.tween_property(toast, "scale", Vector2.ONE, 0.36)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	enter_tween.tween_property(toast, "modulate:a", 1.0, 0.18)

	# Gentle hold then fade — same exit curve as the level-up toast so the
	# overall pacing of all three toasts feels consistent.
	var exit_tween: Tween = toast.create_tween()
	exit_tween.tween_interval(1.3)
	exit_tween.tween_property(toast, "modulate:a", 0.0, 0.45)
	exit_tween.tween_callback(toast.queue_free)


## Quick bounce on the new member's HUD box so the eye knows where to look
## after the toast clears.
func _pulse_member_box_for_character(character: CharacterData) -> void:
	for i in GameState.party_size():
		if i >= _member_boxes.size():
			return
		if GameState.party[i] != null and GameState.party[i].id == character.id:
			var box: PartyMemberBox = _member_boxes[i]
			if box == null:
				return
			box.pivot_offset = box.size * 0.5
			var pulse: Tween = box.create_tween()
			pulse.tween_property(box, "scale", Vector2(1.18, 1.18), 0.16)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			pulse.tween_property(box, "scale", Vector2.ONE, 0.28)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			return


func _refresh_member_box(index: int) -> void:
	if index < 0 or index >= _member_boxes.size():
		return
	var box: PartyMemberBox = _member_boxes[index]
	var max_hp: int = GameState.effective_max_hp(index)
	box.set_hp(GameState.party_hp[index], max_hp)
	box.set_mp(GameState.party_mp[index], GameState.effective_max_mp(index))
	box.set_exp_ratio(GameState.party_xp_ratio(index))
	box.set_level(GameState.party_level(index))


func _on_party_equipment_changed(index: int) -> void:
	if index < 0 or index >= _member_boxes.size():
		return
	_member_boxes[index].set_equipment(GameState.equipment_for_member(index))


# ─── Top bar ──────────────────────────────────────────────────────────
func _on_gold_changed(_new_gold: int) -> void:
	_refresh_gold()


func _on_stage_started(stage_num: int) -> void:
	_refresh_stage()
	# Stage 2+ banner — Stage 1 fires once on game start, the toast there
	# would just be noise on top of the title screen flow.
	if stage_num >= 2:
		_show_phase_toast("Stage %d" % stage_num)


## Time-based difficulty just crossed another 30s tick. The corner label
## auto-rolls to the new Field number; the toast announces it.
func _on_difficulty_increased(_tier: int) -> void:
	_refresh_stage()
	_show_phase_toast("Threat %d" % GameState.current_difficulty_tier())


func _refresh_gold() -> void:
	_gold_label.text = "Gold %d" % GameState.gold


func _refresh_stage() -> void:
	_stage_label.text = "Field %d" % maxi(GameState.current_stage, 1)
