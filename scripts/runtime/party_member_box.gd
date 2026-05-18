class_name PartyMemberBox
extends Panel

## One party member panel for HUD. A pure composition of sub-scenes:
##   • CharacterPortrait   — head-crop badge driven by CharacterData
##   • StatBar × 3         — HP, MP, and EXP bars (color/alignment set on instance)
##   • EquipSlot × 6       — equipment slot placeholders (authored in scene)
##
## Stateless beyond the live values pushed in via setters. HUD (or whoever
## owns this widget) is responsible for wiring EventBus signals → setters.
## This widget never reaches into GameState on its own — except for the
## one-shot read in `_apply()` to seed initial values when a character is
## injected. That keeps it portable to non-HUD contexts (preview screens,
## etc.) where GameState's per-index data may not be relevant.

const LEVEL_UP_MARK_SCENE: PackedScene = preload("res://scenes/ui/level_up_mark.tscn")
## Reused name so a flurry of level-ups doesn't stack visible badges on the
## same portrait — one persistent "+" until the player clicks it.
const LEVEL_UP_MARK_NODE_NAME: StringName = &"LevelUpMark"
const LEVEL_UP_MARK_SIZE: Vector2 = Vector2(20, 20)
const LEVEL_UP_MARK_Y: float = -18.0

## Skill chip row sits just above the box, color-matched to the job, one
## chip per unlocked skill modifier owned by this member. Same palette as
## the skill-tree panel so the two readouts feel unified.
const SKILL_CHIP_SIZE: Vector2 = Vector2(8, 8)
const SKILL_CHIP_GAP: int = 2
const SKILL_CHIPS_OFFSET: Vector2 = Vector2(2, -11)
const JOB_COLOR: Dictionary = {
	&"hero": Color(0.93, 0.42, 0.45),
	&"mage": Color(0.72, 0.48, 0.95),
	&"priest": Color(0.96, 0.86, 0.42),
	&"thief": Color(0.55, 0.85, 0.5),
}

## Mirror of battle_window.gd's skill MP cost constants. Used to label the
## activation tween with a "-X MP" popup so the player sees the cost at the
## moment of cast. Keep in sync if the cost constants over there change.
const SKILL_MP_COST: Dictionary = {
	&"heavy_strike": 2,
	&"hoimi": 3,
	&"fireburst": 6,
	&"lightning_bolt": 4,
	&"battle_prayer": 4,
	&"holy_strike": 4,
	&"pilfer": 2,
}
const MP_POPUP_COLOR: Color = Color(0.55, 0.85, 1.0, 1.0)

signal level_up_mark_pressed(index: int)

@onready var _portrait: CharacterPortrait = %Portrait
@onready var _name_label: Label = %NameLabel
@onready var _hp_bar: StatBar = %HPBar
@onready var _mp_bar: StatBar = %MPBar
@onready var _exp_bar: StatBar = %ExpBar
@onready var _equip_row: HBoxContainer = %EquipRow

var party_index: int = -1
var character: CharacterData
var _pending_setup: bool = false
var _skill_chips_row: HBoxContainer
## Maps skill_id → its ColorRect chip so the activation tween can target
## a specific badge without rescanning the row every time.
var _chip_by_skill: Dictionary = {}


## Inject the slot's identity. Safe to call before the node is in the tree.
func setup(index: int, data: CharacterData) -> void:
	party_index = index
	character = data
	if is_inside_tree():
		_apply()
	else:
		_pending_setup = true


func _ready() -> void:
	_build_skill_chips_row()
	if _pending_setup or character != null:
		_pending_setup = false
		_apply()
	# Live-update chips whenever the shared skill pool changes. We don't
	# care which member triggered it — every box repaints itself based on
	# its own job match.
	EventBus.party_skills_changed.connect(refresh_skill_chips)
	EventBus.party_changed.connect(refresh_skill_chips)
	EventBus.party_skill_activated.connect(_on_skill_activated)


# ─── Live setters (called by the HUD root) ────────────────────────────
func set_hp(hp: int, max_hp: int) -> void:
	_hp_bar.set_label("%d/%d" % [hp, max_hp])
	_hp_bar.set_ratio(_safe_ratio(hp, max_hp))


func set_mp(mp: int, max_mp: int) -> void:
	_mp_bar.set_label("MP %d/%d" % [mp, max_mp])
	_mp_bar.set_ratio(_safe_ratio(mp, max_mp))


func set_exp_ratio(ratio: float) -> void:
	_exp_bar.set_ratio(clampf(ratio, 0.0, 1.0))


func set_level(level: int) -> void:
	_exp_bar.set_label("LV %d" % maxi(level, 1))


## Paint a specific slot (placeholder until ItemData lands). Indices outside
## the slot count are ignored so callers don't have to range-check.
func set_equip_slot_color(slot_index: int, color: Color) -> void:
	var slot: EquipSlot = _equip_slot_at(slot_index)
	if slot:
		slot.set_paint(color)


func set_equipment(items: Array) -> void:
	for i in _equip_row.get_child_count():
		var slot: EquipSlot = _equip_slot_at(i)
		if slot:
			slot.set_item(items[i] if i < items.size() else null)


## Reset every equipment slot to the empty state.
func clear_equip_slots() -> void:
	for child in _equip_row.get_children():
		if child is EquipSlot:
			(child as EquipSlot).clear()


## Spawn (or surface the existing) persistent level-up badge over the
## portrait. Returns the mark so callers can connect `dismissed` for
## follow-up UI (e.g. opening a stat-allocation panel) without this widget
## needing to know about that flow.
func show_level_up_mark() -> LevelUpMark:
	var existing: Node = _portrait.get_node_or_null(NodePath(String(LEVEL_UP_MARK_NODE_NAME)))
	if existing:
		_position_level_up_mark(existing as LevelUpMark)
		return existing as LevelUpMark
	var mark: LevelUpMark = LEVEL_UP_MARK_SCENE.instantiate()
	mark.name = LEVEL_UP_MARK_NODE_NAME
	mark.mode = LevelUpMark.Mode.PERSISTENT
	_position_level_up_mark(mark)
	_portrait.add_child(mark)
	mark.dismissed.connect(_on_level_up_mark_dismissed)
	call_deferred("_position_level_up_mark", mark)
	return mark


func set_level_up_mark_visible(is_visible: bool) -> void:
	var existing: Node = _portrait.get_node_or_null(NodePath(String(LEVEL_UP_MARK_NODE_NAME)))
	if existing:
		existing.visible = is_visible


func clear_level_up_mark() -> void:
	var existing: Node = _portrait.get_node_or_null(NodePath(String(LEVEL_UP_MARK_NODE_NAME)))
	if existing:
		existing.queue_free()


# ─── Internal ─────────────────────────────────────────────────────────
func _on_level_up_mark_dismissed() -> void:
	level_up_mark_pressed.emit(party_index)


func _position_level_up_mark(mark: LevelUpMark) -> void:
	if not is_instance_valid(mark):
		return
	mark.set_anchors_preset(Control.PRESET_TOP_LEFT)
	mark.custom_minimum_size = LEVEL_UP_MARK_SIZE
	mark.size = LEVEL_UP_MARK_SIZE
	mark.position = Vector2((_portrait.size.x - LEVEL_UP_MARK_SIZE.x) * 0.5, LEVEL_UP_MARK_Y)
	mark.z_index = 20


func _apply() -> void:
	if character == null:
		_name_label.text = "—"
		_portrait.clear()
		set_hp(0, 1)
		set_mp(0, 1)
		set_exp_ratio(0.0)
		set_level(1)
		refresh_skill_chips()
		return
	_name_label.text = character.display_name
	_portrait.set_character(character)
	var max_hp: int = _resolve_max_hp()
	var hp: int = _resolve_current_hp(max_hp)
	set_hp(hp, max_hp)
	var max_mp: int = _resolve_max_mp()
	var mp: int = _resolve_current_mp(max_mp)
	set_mp(mp, max_mp)
	set_exp_ratio(GameState.party_xp_ratio(party_index))
	set_level(GameState.party_level(party_index))
	set_equipment(GameState.equipment_for_member(party_index))
	refresh_skill_chips()


func _resolve_max_hp() -> int:
	if party_index < 0 or party_index >= GameState.party_size():
		return character.max_hp
	return GameState.effective_max_hp(party_index)


func _resolve_current_hp(max_hp: int) -> int:
	if party_index < 0 or party_index >= GameState.party_hp.size():
		return max_hp
	return GameState.party_hp[party_index]


func _resolve_max_mp() -> int:
	if party_index < 0 or party_index >= GameState.party_size():
		return character.max_mp
	return GameState.effective_max_mp(party_index)


func _resolve_current_mp(max_mp: int) -> int:
	if party_index < 0 or party_index >= GameState.party_mp.size():
		return max_mp
	return GameState.party_mp[party_index]


func _equip_slot_at(slot_index: int) -> EquipSlot:
	if slot_index < 0 or slot_index >= _equip_row.get_child_count():
		return null
	return _equip_row.get_child(slot_index) as EquipSlot


func _safe_ratio(value: int, max_value: int) -> float:
	if max_value <= 0:
		return 0.0
	return clampf(float(value) / float(max_value), 0.0, 1.0)


# ─── Skill chips (above the box, job-tinted) ───────────────────────────
func _build_skill_chips_row() -> void:
	if is_instance_valid(_skill_chips_row):
		return
	_skill_chips_row = HBoxContainer.new()
	_skill_chips_row.add_theme_constant_override("separation", SKILL_CHIP_GAP)
	_skill_chips_row.position = SKILL_CHIPS_OFFSET
	_skill_chips_row.size_flags_horizontal = 0
	_skill_chips_row.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_skill_chips_row)


## Re-walks active_modifiers, picks the ones tagged to this member's job
## and flagged level_up_only (= tree-unlocked skills + synergy / risk cards),
## and re-stages one chip per distinct id. Stacking is shown as brightness
## bumps on the same chip rather than duplicate chips so the row stays tidy.
func refresh_skill_chips() -> void:
	if not is_instance_valid(_skill_chips_row):
		return
	for child in _skill_chips_row.get_children():
		child.queue_free()
	_chip_by_skill.clear()
	if character == null:
		return
	var member_id: StringName = character.id
	var seen: Dictionary = {}
	for mod: ModifierData in GameState.active_modifiers:
		if mod == null:
			continue
		if mod.required_party_member_id != member_id:
			continue
		if not mod.level_up_only:
			continue
		if seen.has(mod.id):
			continue
		seen[mod.id] = true
		var chip := _make_skill_chip(mod)
		_skill_chips_row.add_child(chip)
		_chip_by_skill[mod.id] = chip


func _make_skill_chip(mod: ModifierData) -> ColorRect:
	var chip := ColorRect.new()
	chip.custom_minimum_size = SKILL_CHIP_SIZE
	chip.size = SKILL_CHIP_SIZE
	# Brightness bumps per stack so leveled-up skills read as "filled in".
	var base: Color = JOB_COLOR.get(character.id, Color.WHITE)
	var level: int = GameState.modifier_level(mod.id)
	var max_level: int = maxi(1, mod.max_level)
	var brightness_step: float = 0.12
	var brightness: float = clampf(float(level - 1) * brightness_step, 0.0, 0.36)
	chip.color = base.lightened(brightness)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	# Pivot at center so the activation punch radiates from the chip's
	# middle instead of scaling out the bottom-right corner.
	chip.pivot_offset = SKILL_CHIP_SIZE * 0.5
	var lvl_suffix: String = " (Lv %d/%d)" % [level, max_level] if max_level > 1 else ""
	chip.tooltip_text = "%s%s\n%s" % [mod.display_name, lvl_suffix, mod.description]
	return chip


# ─── Activation feedback ───────────────────────────────────────────────
## EventBus hook: only fire the punch animation when *this* member is the
## one casting and we own a chip for that skill. The MP popup floats up
## from above the chip so the player sees both *which* skill fired and
## *how much* it cost without taking eyes off the chip row.
func _on_skill_activated(member_index: int, skill_id: StringName) -> void:
	if member_index != party_index:
		return
	_punch_chip(skill_id)
	var cost: int = int(SKILL_MP_COST.get(skill_id, 0))
	if cost > 0:
		_show_mp_cost_popup(skill_id, cost)


## Quick "꿀렁!" feedback: an oversized scale snap-back combined with a
## brief brightness flash so the player can immediately tell *which* chip
## just fired. Both tweens run in parallel on their own Tween so they
## don't fight each other, and they each target only the one chip.
func _punch_chip(skill_id: StringName) -> void:
	var chip: ColorRect = _chip_by_skill.get(skill_id, null)
	if not is_instance_valid(chip):
		return
	var base_color: Color = chip.color
	var flash_color: Color = base_color.lightened(0.55)
	chip.scale = Vector2.ONE
	chip.color = base_color

	var scale_tween: Tween = chip.create_tween()
	scale_tween.tween_property(chip, "scale", Vector2(1.9, 1.9), 0.08)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	scale_tween.tween_property(chip, "scale", Vector2.ONE, 0.32)\
		.set_trans(Tween.TRANS_ELASTIC)\
		.set_ease(Tween.EASE_OUT)

	var color_tween: Tween = chip.create_tween()
	color_tween.tween_property(chip, "color", flash_color, 0.06)
	color_tween.tween_property(chip, "color", base_color, 0.26)


## Spawns a short-lived label above the chip that floats up and fades —
## the same beat as a damage number, just for the casting cost. Attached
## to the box (not the chip) so the label keeps drifting even after the
## chip's elastic snap finishes scaling.
func _show_mp_cost_popup(skill_id: StringName, amount: int) -> void:
	var chip: ColorRect = _chip_by_skill.get(skill_id, null)
	if not is_instance_valid(chip):
		return
	var label := Label.new()
	label.text = "-%d MP" % amount
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", MP_POPUP_COLOR)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 2)
	label.size = Vector2(28, 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 30
	# Box-local origin = chip's row position + chip's slot position, then
	# center the label horizontally on the chip and place it just above.
	var chip_origin: Vector2 = _skill_chips_row.position + chip.position
	var start_pos: Vector2 = chip_origin + Vector2(SKILL_CHIP_SIZE.x * 0.5 - label.size.x * 0.5, -label.size.y - 1)
	label.position = start_pos
	label.modulate.a = 0.0
	add_child(label)

	var tween: Tween = label.create_tween()
	tween.set_parallel(true)
	# Quick fade-in, slow drift up, fade-out at the tail.
	tween.tween_property(label, "modulate:a", 1.0, 0.06)
	tween.tween_property(label, "position", start_pos + Vector2(0, -12), 0.7)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(label, "modulate:a", 0.0, 0.22)
	tween.chain().tween_callback(label.queue_free)
