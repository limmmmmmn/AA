extends Node2D

const COUNTDOWN_SECONDS: float = 2.0
const UNLOCK_TIMER_BONUS_SECONDS: float = 1.0
const GOLD_PER_CLEAR: int = 1

@onready var field: UnfoldField = $Field
@onready var countdown_label: Label = $UI/Countdown
@onready var clear_screen: Control = $UI/ClearScreen
@onready var gold_stat_label: Label = $UI/ClearScreen/ResultPanel/Layout/GoldStat
@onready var unfold_button: Button = $UI/ClearScreen/ResultPanel/Layout/Buttons/UnfoldButton
@onready var continue_button: Button = $UI/ClearScreen/ResultPanel/Layout/Buttons/ContinueButton
@onready var unfold_panel: Control = $UI/ClearScreen/UnfoldPanel
@onready var info_panel: Label = $UI/ClearScreen/UnfoldPanel/PanelBox/PanelLayout/InfoPanel
@onready var skill_tree: SkillTree = $UI/ClearScreen/UnfoldPanel/PanelBox/PanelLayout/SkillTree
@onready var close_button: Button = $UI/ClearScreen/UnfoldPanel/PanelBox/PanelLayout/CloseButton
@onready var battle_view: BattleView = $UI/BattleView
@onready var debug_gold_button: Button = $UI/DebugGoldButton

var time_left: float = COUNTDOWN_SECONDS
var cleared: bool = false
var in_battle: bool = false


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
	battle_view.battle_finished.connect(_on_battle_finished)
	RunState.gold_changed.connect(_on_gold_changed)
	RunState.skill_unlocked.connect(_on_skill_unlocked)
	_refresh_gold_stat()
	_clear_info()
	_refresh_countdown()


func _process(delta: float) -> void:
	if cleared or in_battle:
		return
	time_left = max(0.0, time_left - delta)
	_refresh_countdown()
	if time_left <= 0.0:
		_trigger_clear()


func _refresh_countdown() -> void:
	countdown_label.text = str(int(ceil(time_left)))


func _trigger_clear() -> void:
	cleared = true
	field.set_input_enabled(false)
	countdown_label.visible = false
	RunState.add_gold(GOLD_PER_CLEAR)
	_refresh_gold_stat()
	clear_screen.visible = true
	unfold_button.grab_focus.call_deferred()


func _on_unfold_pressed() -> void:
	unfold_panel.visible = true
	skill_tree.open_for_keyboard()


func _on_close_pressed() -> void:
	unfold_panel.visible = false
	unfold_button.grab_focus.call_deferred()


func _on_continue_pressed() -> void:
	get_tree().reload_current_scene()


func _on_battle_requested(monster: Node2D) -> void:
	if cleared or in_battle:
		return
	in_battle = true
	var hero_pos: Vector2 = field.get_hero_global_position()
	field.prepare_monster_for_battle(monster)
	if not RunState.is_unlocked(&"battle_movement"):
		field.set_input_enabled(false)
	battle_view.start(monster, hero_pos)


func _on_battle_finished(monster: Node2D, defeated: bool) -> void:
	field.finish_battle(monster, defeated)
	in_battle = false
	if not cleared:
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


func _on_gold_changed(_amount: int) -> void:
	_refresh_gold_stat()


func _on_debug_gold_pressed() -> void:
	RunState.add_gold(9999)


func _refresh_gold_stat() -> void:
	gold_stat_label.text = "보유 골드  %d G" % RunState.gold


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
