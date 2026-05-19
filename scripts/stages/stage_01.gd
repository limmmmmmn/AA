extends Node2D

const COUNTDOWN_SECONDS: float = 10.0
const UNLOCK_TIMER_BONUS_SECONDS: float = 1.0
const BATTLE_VIEW_SCENE: PackedScene = preload("res://scenes/ui/battle_view.tscn")
const WINDOW_BASH_MIN_SPEED: float = 10.0
const WINDOW_BASH_PUSH_FACTOR: float = 0.35
const WINDOW_PUSH_RATE: float = 1.0

@onready var field: UnfoldField = $Field
@onready var ui_layer: CanvasLayer = $UI
@onready var countdown_label: Label = $UI/Countdown
@onready var clear_screen: Control = $UI/ClearScreen
@onready var gold_stat_label: Label = $UI/ClearScreen/ResultPanel/Layout/GoldStat
@onready var unfold_button: Button = $UI/ClearScreen/ResultPanel/Layout/Buttons/UnfoldButton
@onready var continue_button: Button = $UI/ClearScreen/ResultPanel/Layout/Buttons/ContinueButton
@onready var unfold_panel: Control = $UI/ClearScreen/UnfoldPanel
@onready var unfold_layout: VBoxContainer = $UI/ClearScreen/UnfoldPanel/PanelBox/PanelLayout
@onready var info_panel: Label = $UI/ClearScreen/UnfoldPanel/PanelBox/PanelLayout/InfoPanel
@onready var skill_tree: SkillTree = $UI/ClearScreen/UnfoldPanel/PanelBox/PanelLayout/SkillTree
@onready var close_button: Button = $UI/ClearScreen/UnfoldPanel/PanelBox/PanelLayout/CloseButton
var _unfold_gold_label: Label
@onready var result_layout: VBoxContainer = $UI/ClearScreen/ResultPanel/Layout
@onready var battle_view: BattleView = $UI/BattleView
@onready var debug_gold_button: Button = $UI/DebugGoldButton

var time_left: float = COUNTDOWN_SECONDS
var cleared: bool = false
var in_battle: bool = false
var active_battle_views: Array[BattleView] = []

var _run_kills: int = 0
var _run_gold_earned: int = 0
var _last_seen_gold: int = 0
var _town_label: Label
var _run_stats_label: Label
var _inventory_label: Label
var _party_stats_label: Label


func _ready() -> void:
	time_left = COUNTDOWN_SECONDS + float(RunState.timer_bonus_seconds)
	clear_screen.visible = false
	unfold_panel.visible = false
	unfold_button.pressed.connect(_on_unfold_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	close_button.pressed.connect(_on_continue_pressed)
	debug_gold_button.pressed.connect(_on_debug_gold_pressed)
	skill_tree.node_hovered_signal.connect(_on_skill_hovered)
	skill_tree.node_exited_signal.connect(_on_skill_exited)
	skill_tree.exit_requested.connect(_on_skill_tree_exit_requested)
	field.battle_requested.connect(_on_battle_requested)
	battle_view.battle_finished.connect(_on_battle_finished.bind(battle_view))
	RunState.gold_changed.connect(_on_gold_changed)
	RunState.skill_unlocked.connect(_on_skill_unlocked)
	_setup_unfold_gold_label()
	_setup_settlement_panel()
	_last_seen_gold = RunState.gold
	_refresh_gold_stat()
	_clear_info()
	_refresh_countdown()


func _setup_settlement_panel() -> void:
	_town_label = _make_settlement_label("", 14, Color(1.0, 0.88, 0.5, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	result_layout.add_child(_town_label)
	result_layout.move_child(_town_label, 1)

	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 14)
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_layout.add_child(columns)
	result_layout.move_child(columns, 2)

	var left_column: VBoxContainer = VBoxContainer.new()
	left_column.add_theme_constant_override(&"separation", 4)
	left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_column.custom_minimum_size = Vector2(190, 0)
	columns.add_child(left_column)

	var right_column: VBoxContainer = VBoxContainer.new()
	right_column.add_theme_constant_override(&"separation", 4)
	right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_column.custom_minimum_size = Vector2(190, 0)
	columns.add_child(right_column)

	var party_header: Label = _make_settlement_label("━ 일행 ━", 12, Color(0.95, 0.95, 0.95, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	left_column.add_child(party_header)
	_party_stats_label = _make_settlement_label("", 12, Color(0.78, 0.93, 1.0, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	left_column.add_child(_party_stats_label)

	var settle_header: Label = _make_settlement_label("━ 정산 ━", 12, Color(0.95, 0.95, 0.95, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	right_column.add_child(settle_header)
	_run_stats_label = _make_settlement_label("", 12, Color(1, 1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	right_column.add_child(_run_stats_label)
	_inventory_label = _make_settlement_label("", 11, Color(1.0, 0.88, 0.5, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	right_column.add_child(_inventory_label)


func _make_settlement_label(text: String, font_size: int, color: Color, align: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override(&"shadow_offset_x", 1)
	label.add_theme_constant_override(&"shadow_offset_y", 1)
	return label


func _setup_unfold_gold_label() -> void:
	_unfold_gold_label = Label.new()
	_unfold_gold_label.text = "0 G"
	_unfold_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_unfold_gold_label.add_theme_font_size_override(&"font_size", 14)
	_unfold_gold_label.add_theme_color_override(&"font_color", Color(1.0, 0.82, 0.2, 1.0))
	_unfold_gold_label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 1))
	_unfold_gold_label.add_theme_constant_override(&"shadow_offset_x", 1)
	_unfold_gold_label.add_theme_constant_override(&"shadow_offset_y", 1)
	unfold_layout.add_child(_unfold_gold_label)
	unfold_layout.move_child(_unfold_gold_label, 1)


func _process(delta: float) -> void:
	if cleared:
		return
	if in_battle and not RunState.is_unlocked(&"battle_movement"):
		return
	time_left = max(0.0, time_left - delta)
	_refresh_countdown()
	if time_left <= 0.0:
		_trigger_clear()
	_check_window_push(delta)
	_check_window_bash()


func _check_window_push(delta: float) -> void:
	if not RunState.is_unlocked(&"window_push"):
		return
	if not RunState.is_unlocked(&"battle_movement"):
		return
	if active_battle_views.is_empty():
		return
	var velocity: Vector2 = field.get_hero_velocity()
	if velocity.length() < 1.0:
		return
	var hero_pos: Vector2 = field.get_hero_global_position()
	var step: Vector2 = velocity * delta * WINDOW_PUSH_RATE
	for view in active_battle_views:
		if not is_instance_valid(view):
			continue
		var rect: Rect2 = view.get_bash_world_rect()
		if rect.size == Vector2.ZERO:
			continue
		if rect.has_point(hero_pos):
			view.apply_push(step)


func _check_window_bash() -> void:
	if not RunState.is_unlocked(&"window_bash"):
		return
	if not RunState.is_unlocked(&"battle_movement"):
		return
	if active_battle_views.is_empty():
		return
	var velocity: Vector2 = field.get_hero_velocity()
	if velocity.length() < WINDOW_BASH_MIN_SPEED:
		return
	var hero_pos: Vector2 = field.get_hero_global_position()
	for view in active_battle_views:
		if not is_instance_valid(view):
			continue
		if view.is_bash_locked():
			continue
		var rect: Rect2 = view.get_bash_world_rect()
		if rect.size == Vector2.ZERO:
			continue
		if rect.has_point(hero_pos):
			var push: Vector2 = velocity * WINDOW_BASH_PUSH_FACTOR
			view.bash_window(push, RunState.hero_attack())


func _refresh_countdown() -> void:
	countdown_label.text = str(int(ceil(time_left)))


func _trigger_clear() -> void:
	cleared = true
	field.set_input_enabled(false)
	await _close_active_battles_with_timeout(1.0)
	_force_close_all_battles()
	countdown_label.visible = false
	_refresh_gold_stat()
	_refresh_settlement_summary()
	clear_screen.visible = true
	unfold_button.grab_focus.call_deferred()


func _close_active_battles_with_timeout(timeout_secs: float) -> void:
	var pending: Array[BattleView] = active_battle_views.duplicate()
	for view in pending:
		if is_instance_valid(view) and view.visible:
			view.force_timeout_escape()
	var deadline_timer: SceneTreeTimer = get_tree().create_timer(timeout_secs)
	while deadline_timer.time_left > 0.0:
		var any_active: bool = false
		for view in pending:
			if is_instance_valid(view) and view.visible:
				any_active = true
				break
		if not any_active:
			return
		await get_tree().process_frame


func _force_close_all_battles() -> void:
	for view in active_battle_views.duplicate():
		if is_instance_valid(view):
			view.visible = false
			if view != battle_view:
				view.queue_free()
	active_battle_views.clear()
	in_battle = false


func _refresh_settlement_summary() -> void:
	if _town_label != null:
		var town: String = _town_name_for_gold(_run_gold_earned)
		_town_label.text = "— %s 에서 돌아옴 —" % town
	if _run_stats_label != null:
		var items_count: int = _run_items()
		var items_str: String = "%d 개" % items_count if items_count > 0 else "없음"
		_run_stats_label.text = "처치한 몬스터  %d\n얻은 경험치  %d\n주운 골드  %d G\n주운 장비  %s" % [_run_kills, RunState.experience, _run_gold_earned, items_str]
	if _inventory_label != null:
		_inventory_label.text = _inventory_text()
	if _party_stats_label != null:
		_party_stats_label.text = _party_stats_text()


func _inventory_text() -> String:
	var inv: Array = RunState.loot_inventory
	if inv.is_empty():
		return "전리품 없음"
	var grouped: Dictionary = RunState.loot_count_by_tier_type()
	var lines: Array[String] = ["━ 전리품 ━"]
	var tiers: Array = grouped.keys()
	tiers.sort()
	for tier in tiers:
		var tier_name: String = RunState.LOOT_TIER_NAMES[clampi(int(tier), 0, RunState.LOOT_TIER_NAMES.size() - 1)]
		var by_type: Dictionary = grouped[tier]
		var parts: Array[String] = []
		for type in EquipmentPickup.ALL_TYPES:
			if by_type.has(type):
				parts.append("%s ×%d" % [EquipmentPickup.display_name_for_type(type), int(by_type[type])])
		lines.append("%s — %s" % [tier_name, ", ".join(parts)])
	var base_value: int = RunState.loot_sell_base_value()
	var mult: float = RunState.loot_sell_multiplier()
	var sell_value: int = RunState.loot_sell_value()
	if mult > 1.001:
		lines.append("판매가  %d × %s = %d G" % [base_value, _format_mult(mult), sell_value])
	else:
		lines.append("판매가  %d G" % sell_value)
	return "\n".join(lines)


func _format_mult(mult: float) -> String:
	if absf(mult - round(mult)) < 0.01:
		return "%d.0배" % int(round(mult))
	return "%.1f배" % mult


func _town_name_for_gold(gold: int) -> String:
	if gold < 5:
		return "작은 마을 앞 초원"
	if gold < 15:
		return "마을 어귀 숲"
	if gold < 35:
		return "깊은 숲"
	if gold < 70:
		return "험준한 산길"
	if gold < 130:
		return "고대 유적"
	if gold < 250:
		return "용의 둥지"
	return "왕성 앞 평원"


func _run_items() -> int:
	return RunState.loot_inventory.size()


func _equipped_label_for(item: Dictionary) -> String:
	if item.is_empty():
		return "-"
	var t: int = clampi(int(item.get("tier", 0)), 0, RunState.LOOT_TIER_NAMES.size() - 1)
	var type_name: String = EquipmentPickup.display_name_for_type(item.get("type", &"sword"))
	return "%s %s" % [RunState.LOOT_TIER_NAMES[t], type_name]


func _party_stats_text() -> String:
	var lines: Array[String] = []
	var hero_hp_max: int = RunState.hero_max_hp()
	var hero_atk: int = RunState.hero_attack()
	var weapon_label: String = _equipped_label_for(RunState.hero_equipped_weapon())
	var body_label: String = _equipped_label_for(RunState.hero_equipped_body())
	lines.append("⚔ 용사    HP %2d   AT %2d   MP  0" % [hero_hp_max, hero_atk])
	lines.append("   무기:  %s" % weapon_label)
	lines.append("   방어:  %s" % body_label)

	if RunState.companion_recruited:
		var c_names: Dictionary = {&"mage": "메이지", &"thief": "씨프", &"knight": "나이트"}
		var c_name: String = c_names.get(RunState.companion_type, "동료")
		lines.append("✨ %s    HP  -    AT  -    MP  -" % c_name)
		lines.append("   장비:  -")

	return "\n".join(lines)


func _on_unfold_pressed() -> void:
	unfold_panel.visible = true
	skill_tree.open_for_keyboard()


func _on_close_pressed() -> void:
	unfold_panel.visible = false
	unfold_button.grab_focus.call_deferred()


func _on_continue_pressed() -> void:
	var sell_value: int = RunState.loot_sell_value()
	if sell_value > 0:
		RunState.add_gold(sell_value)
	RunState.reset_run_inventory()
	get_tree().reload_current_scene()


func _on_battle_requested(monster: Node2D) -> void:
	if cleared:
		return
	if in_battle and not RunState.is_unlocked(&"multi_battle"):
		return
	in_battle = true
	var hero_pos: Vector2 = field.get_hero_global_position()
	field.prepare_monster_for_battle(monster)
	if not RunState.is_unlocked(&"battle_movement"):
		field.set_input_enabled(false)
	var view: BattleView = _claim_battle_view()
	active_battle_views.append(view)
	view.start(monster, hero_pos)


func _claim_battle_view() -> BattleView:
	if not battle_view.visible and not active_battle_views.has(battle_view):
		return battle_view
	var view: BattleView = BATTLE_VIEW_SCENE.instantiate() as BattleView
	ui_layer.add_child(view)
	view.battle_finished.connect(_on_battle_finished.bind(view))
	return view


func _on_battle_finished(monster: Node2D, defeated: bool, kills: int, view: BattleView) -> void:
	if defeated:
		_run_kills += kills
	field.finish_battle(monster, defeated, kills)
	active_battle_views.erase(view)
	if view != battle_view:
		view.queue_free()
	in_battle = not active_battle_views.is_empty()
	if not cleared and not in_battle:
		field.set_input_enabled(true)


func _unhandled_input(event: InputEvent) -> void:
	if not cleared:
		return
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if unfold_panel.visible:
		if key_event.physical_keycode == KEY_ESCAPE:
			_mark_input_handled()
			_on_close_pressed()
			return
		if close_button.has_focus():
			match key_event.physical_keycode:
				KEY_UP, KEY_W:
					_mark_input_handled()
					skill_tree.open_for_keyboard()
					return
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
					_mark_input_handled()
					_on_continue_pressed()
					return
				KEY_LEFT, KEY_RIGHT, KEY_DOWN, KEY_A, KEY_D, KEY_S:
					_mark_input_handled()
					return
		if skill_tree.handle_keyboard_event(key_event):
			_mark_input_handled()
			return
		return

	match key_event.physical_keycode:
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_A, KEY_D, KEY_W, KEY_S:
			_toggle_result_focus()
			_mark_input_handled()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_mark_input_handled()
			_activate_result_focus()


func _on_skill_hovered(node: SkillNode) -> void:
	if node.is_empty():
		if node.skill_name.is_empty() or node.skill_name == "???":
			info_panel.text = "???   [선택 불가]"
			info_panel.tooltip_text = "다음 노드가 들어설 자리"
		else:
			info_panel.text = "%s   [선택 불가]" % node.skill_name
			info_panel.tooltip_text = node.description
		return
	var status: String
	if RunState.is_unlocked(node.skill_id):
		status = "[해금됨]"
	elif node.cost <= 0:
		status = "[무료]"
	elif RunState.can_afford(node.cost):
		status = "[비용 %d G]" % node.cost
	else:
		status = "[비용 %d G - 부족]" % node.cost
	info_panel.text = "%s   %s" % [node.skill_name, status]
	info_panel.tooltip_text = node.description


func _on_skill_exited(_node: SkillNode) -> void:
	_clear_info()


func _on_skill_tree_exit_requested(direction: Vector2) -> void:
	if direction == Vector2.DOWN:
		close_button.grab_focus()


func _on_skill_unlocked(_skill_id: StringName) -> void:
	if not cleared:
		time_left += UNLOCK_TIMER_BONUS_SECONDS
		_refresh_countdown()


func _on_gold_changed(amount: int) -> void:
	var delta: int = amount - _last_seen_gold
	_last_seen_gold = amount
	if delta > 0:
		_run_gold_earned += delta
	_refresh_gold_stat()


func _on_debug_gold_pressed() -> void:
	RunState.add_gold(9999)


func _refresh_gold_stat() -> void:
	gold_stat_label.text = "보유 골드  %d G" % RunState.gold
	if _unfold_gold_label != null:
		_unfold_gold_label.text = "보유 %d G" % RunState.gold


func _clear_info() -> void:
	info_panel.text = "방향키/WASD: 노드 선택   Enter: 해금"
	info_panel.tooltip_text = ""


func _toggle_result_focus() -> void:
	if unfold_button.has_focus():
		continue_button.grab_focus()
	else:
		unfold_button.grab_focus()


func _activate_result_focus() -> void:
	if continue_button.has_focus():
		_on_continue_pressed()
	else:
		_on_unfold_pressed()


func _mark_input_handled() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
