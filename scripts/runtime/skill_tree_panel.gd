class_name SkillTreePanel
extends Control

## Unified party skill tree. One shared SP pool, one shared canvas.
##
## Layout (party slot → branch direction):
##     slot 0 (top)
##                ↑
##     slot 1 ← center → slot 2
##                ↓
##     slot 3 (bottom)
##
## Each branch carries the resident party member's job tree:
##   bump_attack (center) → primary skill → 2 secondary skills (Y-fork)
##
## Nodes are 16×16 color-coded squares (job-tinted). Hover instantly pops
## a tooltip panel above the node with name + description + state.

const NODE_SIZE: Vector2 = Vector2(16, 16)
const NODE_GAP: float = 36.0
const CENTER_PATH: String = "res://data/modifiers/prototype/bump_attack.tres"

## Each job tree: a primary skill plus a list of secondary skills (Y-fork).
## Order of `branches` is significant — first goes on the perpendicular
## positive side, second on the negative side.
const JOB_SKILLS: Dictionary = {
	&"hero": {
		"primary": "res://data/modifiers/prototype/heavy_strike.tres",
		"branches": [
			"res://data/modifiers/prototype/hoimi.tres",
			"res://data/modifiers/prototype/taunt.tres",
		],
	},
	&"mage": {
		"primary": "res://data/modifiers/prototype/fireball.tres",
		"branches": [
			"res://data/modifiers/prototype/elation.tres",
			"res://data/modifiers/prototype/fireburst.tres",
		],
	},
	&"priest": {
		"primary": "res://data/modifiers/prototype/battle_prayer.tres",
		"branches": [
			"res://data/modifiers/prototype/blessing.tres",
			"res://data/modifiers/prototype/revive.tres",
		],
	},
	&"thief": {
		"primary": "res://data/modifiers/prototype/pilfer.tres",
		"branches": [
			"res://data/modifiers/prototype/backstep.tres",
			"res://data/modifiers/prototype/speed_up.tres",
		],
	},
}

## Slot 0 → top, 1 → left, 2 → right, 3 → bottom.
const SLOT_DIRECTIONS: Array[Vector2] = [
	Vector2(0, -1),
	Vector2(-1, 0),
	Vector2(1, 0),
	Vector2(0, 1),
]

## Per-job tint. Center node gets its own neutral tone.
const JOB_COLOR: Dictionary = {
	&"hero": Color(0.93, 0.42, 0.45),     # 빨강
	&"mage": Color(0.72, 0.48, 0.95),     # 보라
	&"priest": Color(0.96, 0.86, 0.42),   # 금/노랑
	&"thief": Color(0.55, 0.85, 0.5),     # 녹색
}
const CENTER_COLOR: Color = Color(0.78, 0.78, 0.86)

## State multipliers applied to the job color so locked / affordable / maxed
## variants all read as "the same family, different status".
const LOCKED_TINT: Color = Color(0.28, 0.28, 0.32)
const PREREQ_LOCKED_TINT: Color = Color(0.18, 0.16, 0.22)
const HOVER_OUTLINE: Color = Color(1, 1, 1, 0.95)

const EDGE_UNLOCKED: Color = Color(0.32, 0.74, 0.36, 0.95)
const EDGE_LOCKED: Color = Color(0.45, 0.45, 0.5, 0.55)
const PANEL_BG: Color = Color(0.06, 0.08, 0.11, 0.92)

var _node_buttons: Dictionary = {}          ## skill_id → Button
var _node_skill_lookup: Dictionary = {}     ## skill_id → ModifierData (cache)
var _node_owner_id: Dictionary = {}         ## skill_id → owning job StringName (for color)
var _connectors: Array[Dictionary] = []
var _connector_layer: Control
var _sp_label: Label
var _tooltip: PanelContainer
var _tooltip_name: Label
var _tooltip_desc: Label
var _tooltip_status: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_chrome()
	_build_tooltip()
	_build_tree()
	_play_open_animation()
	EventBus.party_skill_points_changed.connect(_on_state_changed)
	EventBus.party_skills_changed.connect(_on_state_changed)
	EventBus.party_changed.connect(_rebuild_tree)


## Whole-panel "우웅 팍!" entrance — same TRANS_BACK overshoot family as
## the battle-window popup so the two beats feel related. Scale pivots
## around the viewport center, and we fade in the contents while we're
## at it so the panel never appears at full brightness while still tiny.
func _play_open_animation() -> void:
	var vp: Vector2 = get_viewport_rect().size
	pivot_offset = vp * 0.5
	scale = Vector2(0.65, 0.65)
	modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, 0.32)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.18)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_TAB or key == KEY_ESCAPE:
			queue_free_and_unpause()
			get_viewport().set_input_as_handled()


func queue_free_and_unpause() -> void:
	get_tree().paused = false
	queue_free()


# ─── Chrome ────────────────────────────────────────────────────────────
func _build_chrome() -> void:
	var bg := ColorRect.new()
	bg.color = PANEL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var title := Label.new()
	title.text = "스킬 트리"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98))
	title.position = Vector2(8, 6)
	add_child(title)

	_sp_label = Label.new()
	_sp_label.text = "SP %d" % GameState.skill_points()
	_sp_label.add_theme_font_size_override("font_size", 11)
	_sp_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
	_sp_label.position = Vector2(8, 22)
	add_child(_sp_label)

	var hint := Label.new()
	hint.text = "TAB/ESC 닫기"
	hint.add_theme_font_size_override("font_size", 8)
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	hint.anchor_left = 1.0
	hint.anchor_right = 1.0
	hint.offset_left = -72
	hint.offset_right = -6
	hint.offset_top = 8
	add_child(hint)

	var reset := Button.new()
	reset.text = "리셋"
	reset.anchor_left = 1.0
	reset.anchor_right = 1.0
	reset.anchor_top = 1.0
	reset.anchor_bottom = 1.0
	reset.offset_left = -60
	reset.offset_right = -6
	reset.offset_top = -22
	reset.offset_bottom = -6
	reset.add_theme_font_size_override("font_size", 9)
	reset.pressed.connect(_on_reset_pressed)
	add_child(reset)


# ─── Tooltip (instant, follows hovered node) ───────────────────────────
func _build_tooltip() -> void:
	_tooltip = PanelContainer.new()
	_tooltip.hide()
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.z_index = 100

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.09, 0.96)
	style.border_color = Color(0.5, 0.52, 0.6)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_tooltip.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	_tooltip.add_child(vbox)

	_tooltip_name = Label.new()
	_tooltip_name.add_theme_font_size_override("font_size", 9)
	_tooltip_name.add_theme_color_override("font_color", Color(1, 0.92, 0.4))
	vbox.add_child(_tooltip_name)

	_tooltip_desc = Label.new()
	_tooltip_desc.add_theme_font_size_override("font_size", 8)
	_tooltip_desc.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
	_tooltip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip_desc.custom_minimum_size = Vector2(140, 0)
	vbox.add_child(_tooltip_desc)

	_tooltip_status = Label.new()
	_tooltip_status.add_theme_font_size_override("font_size", 8)
	_tooltip_status.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	vbox.add_child(_tooltip_status)

	add_child(_tooltip)


func _show_tooltip(node_btn: Button, mod: ModifierData) -> void:
	_tooltip_name.text = mod.display_name
	_tooltip_desc.text = mod.description
	_tooltip_status.text = _tooltip_status_text(mod)
	_tooltip.show()
	_tooltip.reset_size()
	# Park above the node, centered, clamped to the viewport.
	var node_center: Vector2 = node_btn.position + node_btn.size * 0.5
	var sz: Vector2 = _tooltip.size
	var pos := Vector2(node_center.x - sz.x * 0.5, node_btn.position.y - sz.y - 4)
	var vp: Vector2 = get_viewport_rect().size
	pos.x = clampf(pos.x, 4, vp.x - sz.x - 4)
	if pos.y < 4:
		# Not enough room above — flip below the node.
		pos.y = node_btn.position.y + node_btn.size.y + 4
	pos.y = clampf(pos.y, 4, vp.y - sz.y - 4)
	_tooltip.position = pos


func _hide_tooltip() -> void:
	_tooltip.hide()


func _tooltip_status_text(mod: ModifierData) -> String:
	var level: int = GameState.modifier_level(mod.id)
	var maxed: bool = level >= mod.max_level
	var prereq_ok: bool = mod.required_modifier_id == &"" or GameState.modifier_level(mod.required_modifier_id) >= 1
	var sp_ok: bool = GameState.skill_points() > 0
	var lv_line: String = ""
	if mod.max_level > 1:
		lv_line = "Lv %d/%d" % [level, mod.max_level]
	if maxed:
		return "%s · 최대 레벨" % lv_line
	if not prereq_ok:
		var gate: ModifierData = ModifierDB.get_by_id(mod.required_modifier_id)
		var gate_name: String = gate.display_name if gate else String(mod.required_modifier_id)
		return "선행 필요: %s" % gate_name
	if not sp_ok:
		return "%s · SP 부족" % lv_line if not lv_line.is_empty() else "SP 부족"
	if level == 0:
		return "1 SP로 해금" if lv_line.is_empty() else "%s · 1 SP로 해금" % lv_line
	return "%s · 1 SP로 강화" % lv_line


# ─── Tree build ────────────────────────────────────────────────────────
func _build_tree() -> void:
	_connector_layer = ConnectorArea.new()
	_connector_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_connector_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_connector_layer)

	_node_buttons.clear()
	_node_skill_lookup.clear()
	_node_owner_id.clear()
	_connectors.clear()

	var viewport_size: Vector2 = get_viewport_rect().size
	var center: Vector2 = viewport_size * 0.5

	# Center: bump_attack — every branch ultimately prereqs it.
	var center_mod: ModifierData = load(CENTER_PATH) as ModifierData
	if center_mod != null:
		_add_node(center_mod, center, &"")

	# Per-slot branches: primary + Y-fork of two secondaries.
	for slot in GameState.party.size():
		if slot >= SLOT_DIRECTIONS.size():
			break
		var character: CharacterData = GameState.party[slot]
		if character == null or not JOB_SKILLS.has(character.id):
			continue
		var direction: Vector2 = SLOT_DIRECTIONS[slot]
		var perp: Vector2 = Vector2(-direction.y, direction.x)  # 90° CW
		var tree_data: Dictionary = JOB_SKILLS[character.id]
		var primary: ModifierData = load(tree_data.primary) as ModifierData
		if primary == null:
			continue
		var primary_pos: Vector2 = center + direction * NODE_GAP * 2.0
		_add_node(primary, primary_pos, character.id)
		_add_connector(center, primary_pos, primary.id)
		var branches: Array = tree_data.branches
		for b in branches.size():
			var branch_mod: ModifierData = load(branches[b]) as ModifierData
			if branch_mod == null:
				continue
			var side: float = 1.0 if b == 0 else -1.0
			var branch_pos: Vector2 = primary_pos + direction * NODE_GAP + perp * NODE_GAP * side
			_add_node(branch_mod, branch_pos, character.id)
			_add_connector(primary_pos, branch_pos, branch_mod.id)

	(_connector_layer as ConnectorArea).connectors = _connectors
	_connector_layer.queue_redraw()


func _add_node(mod: ModifierData, pos: Vector2, owner_job: StringName) -> void:
	var btn := _make_skill_node(mod, owner_job)
	btn.position = pos - NODE_SIZE * 0.5
	add_child(btn)
	_node_buttons[mod.id] = btn
	_node_skill_lookup[mod.id] = mod
	_node_owner_id[mod.id] = owner_job


func _add_connector(from_pos: Vector2, to_pos: Vector2, skill_id: StringName) -> void:
	_connectors.append({"from": from_pos, "to": to_pos, "skill_id": skill_id})


func _rebuild_tree() -> void:
	for btn in _node_buttons.values():
		if is_instance_valid(btn):
			btn.queue_free()
	if is_instance_valid(_connector_layer):
		_connector_layer.queue_free()
	_node_buttons.clear()
	_node_skill_lookup.clear()
	_node_owner_id.clear()
	_hide_tooltip()
	_build_tree()


# ─── Skill node ────────────────────────────────────────────────────────
func _make_skill_node(mod: ModifierData, owner_job: StringName) -> Button:
	var btn := Button.new()
	btn.size = NODE_SIZE
	btn.custom_minimum_size = NODE_SIZE
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = ""
	btn.pressed.connect(_on_skill_pressed.bind(mod))
	btn.mouse_entered.connect(_show_tooltip.bind(btn, mod))
	btn.mouse_exited.connect(_hide_tooltip)
	_paint_skill_node(btn, mod, owner_job)
	return btn


## Resolve fill color: job tint, plus lightness shift by state.
func _resolve_node_color(mod: ModifierData, owner_job: StringName) -> Color:
	var base: Color = JOB_COLOR.get(owner_job, CENTER_COLOR) if owner_job != &"" else CENTER_COLOR
	var level: int = GameState.modifier_level(mod.id)
	var maxed: bool = level >= mod.max_level
	var prereq_ok: bool = mod.required_modifier_id == &"" or GameState.modifier_level(mod.required_modifier_id) >= 1
	var sp_ok: bool = GameState.skill_points() > 0
	if maxed:
		return base.darkened(0.2)
	if not prereq_ok:
		return PREREQ_LOCKED_TINT
	if level >= 1:
		return base
	if sp_ok:
		return base.darkened(0.45)
	return LOCKED_TINT


func _paint_skill_node(btn: Button, mod: ModifierData, owner_job: StringName) -> void:
	var level: int = GameState.modifier_level(mod.id)
	var maxed: bool = level >= mod.max_level
	var prereq_ok: bool = mod.required_modifier_id == &"" or GameState.modifier_level(mod.required_modifier_id) >= 1
	var sp_ok: bool = GameState.skill_points() > 0
	# Disabled when there's nothing the click can do — either maxed,
	# prereq-blocked, or out of SP.
	btn.disabled = maxed or not prereq_ok or not sp_ok

	var fill: Color = _resolve_node_color(mod, owner_job)
	var normal := StyleBoxFlat.new()
	normal.bg_color = fill
	normal.border_color = fill.darkened(0.35)
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.border_width_top = 1
	normal.border_width_bottom = 1
	normal.content_margin_left = 0
	normal.content_margin_right = 0
	normal.content_margin_top = 0
	normal.content_margin_bottom = 0

	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = fill.lightened(0.18)
	hover.border_color = HOVER_OUTLINE
	hover.border_width_left = 2
	hover.border_width_right = 2
	hover.border_width_top = 2
	hover.border_width_bottom = 2

	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = fill.darkened(0.12)

	var focus: StyleBoxFlat = hover.duplicate()

	var disabled: StyleBoxFlat = normal.duplicate()
	# Slightly desaturate disabled so it reads as inactive without changing hue.
	disabled.bg_color = fill.darkened(0.18)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", focus)
	btn.add_theme_stylebox_override("disabled", disabled)


# ─── Actions ───────────────────────────────────────────────────────────
func _on_skill_pressed(mod: ModifierData) -> void:
	GameState.unlock_skill(mod)


func _on_reset_pressed() -> void:
	GameState.reset_skills()


func _on_state_changed(_a = null) -> void:
	_refresh_all()


func _refresh_all() -> void:
	if is_instance_valid(_sp_label):
		_sp_label.text = "SP %d" % GameState.skill_points()
	for skill_id in _node_buttons:
		var btn: Button = _node_buttons[skill_id]
		var mod: ModifierData = _node_skill_lookup.get(skill_id, null)
		var owner: StringName = _node_owner_id.get(skill_id, &"")
		if is_instance_valid(btn) and mod != null:
			_paint_skill_node(btn, mod, owner)
	if is_instance_valid(_connector_layer):
		_connector_layer.queue_redraw()
	# Refresh the hovered tooltip if it's still showing (SP just changed,
	# the "1 SP로 강화" line should update).
	if _tooltip.visible:
		_refresh_visible_tooltip()


func _refresh_visible_tooltip() -> void:
	# Find which button the mouse is currently over and re-issue the show.
	var mouse_pos: Vector2 = get_global_mouse_position()
	for skill_id in _node_buttons:
		var btn: Button = _node_buttons[skill_id]
		if not is_instance_valid(btn):
			continue
		var rect: Rect2 = Rect2(btn.global_position, btn.size)
		if rect.has_point(mouse_pos):
			var mod: ModifierData = _node_skill_lookup[skill_id]
			_show_tooltip(btn, mod)
			return
	_hide_tooltip()


# ─── Inner layer: connector lines under the buttons ────────────────────
class ConnectorArea extends Control:
	var connectors: Array = []

	func _draw() -> void:
		for conn in connectors:
			var skill_id: StringName = conn.skill_id
			var level: int = GameState.modifier_level(skill_id)
			var color: Color = (
				SkillTreePanel.EDGE_UNLOCKED if level >= 1
				else SkillTreePanel.EDGE_LOCKED
			)
			draw_line(conn.from, conn.to, color, 1.5, true)
