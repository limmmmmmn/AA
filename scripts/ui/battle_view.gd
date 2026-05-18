class_name BattleView
extends Control

signal battle_finished(monster: Node2D, defeated: bool)

const SLIME_TEXTURE: Texture2D = preload("res://assets/sprites/enemies/slime.png")
const BASIC_ATTACK_TEXTURE: Texture2D = preload("res://assets/sprites/effects/basic_attack.png")

const PANEL_COLOR: Color = Color(0, 0, 0, 1)
const BORDER_COLOR: Color = Color(1, 1, 1, 1)
const TEXT_COLOR: Color = Color(1, 1, 1, 1)
const FOCUS_COLOR: Color = Color(0.28, 0.28, 0.28, 1)
const MESSAGE_SECONDS: float = 0.72
const AUTO_BATTLE_DELAY: float = 0.35
const FIELD_BATTLE_GAP: float = 16.0
const ATTACK_EFFECT_SIZE: Vector2 = Vector2(42, 42)
const SLIME_MAX_HP: int = 6

var _monster: Node2D
var _busy: bool = false
var _field_mode: bool = false
var _world_anchor: Vector2 = Vector2.ZERO
var _battle_side: int = 1
var _battle_window_home: Vector2 = Vector2.ZERO
var _slime_hp: int = SLIME_MAX_HP

var _command_buttons: Array[Button] = []
var _stats_window: Panel
var _command_window: Panel
var _battle_window: Panel
var _log_window: Panel
var _fight_button: Button
var _spell_button: Button
var _run_button: Button
var _item_button: Button
var _stats_label: Label
var _log_label: Label
var _gold_label: Label
var _enemy_sprite: TextureRect
var _attack_effect: TextureRect


func _ready() -> void:
	visible = false
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	RunState.hero_attack_changed.connect(_on_hero_attack_changed)


func start(monster: Node2D, hero_global_position: Vector2 = Vector2.ZERO) -> void:
	_monster = monster
	_busy = false
	_field_mode = RunState.is_unlocked(&"battle_movement")
	_world_anchor = monster.global_position if is_instance_valid(monster) else Vector2.ZERO
	_battle_side = 1 if _world_anchor.x >= hero_global_position.x else -1
	_slime_hp = SLIME_MAX_HP
	visible = true
	_gold_label.text = "G  %d" % RunState.gold
	_refresh_stats()
	_enemy_sprite.modulate = Color.WHITE
	_enemy_sprite.scale = Vector2.ONE
	_attack_effect.visible = false
	_apply_visibility_mode()
	_set_log("슬라임이 나타났다!")
	_fight_button.grab_focus.call_deferred()
	if RunState.is_unlocked(&"auto_battle"):
		_start_auto_battle.call_deferred()


func _process(_delta: float) -> void:
	if visible and _field_mode:
		_update_field_battle_position()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _busy:
		return
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if RunState.is_unlocked(&"battle_movement"):
		return

	match key_event.physical_keycode:
		KEY_W:
			_move_command_focus(Vector2.UP)
			_mark_input_handled()
		KEY_A:
			_move_command_focus(Vector2.LEFT)
			_mark_input_handled()
		KEY_S:
			_move_command_focus(Vector2.DOWN)
			_mark_input_handled()
		KEY_D:
			_move_command_focus(Vector2.RIGHT)
			_mark_input_handled()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_activate_focused_command()
			_mark_input_handled()


func _build_ui() -> void:
	_stats_window = _make_panel(Vector2(170, 62), Vector2(116, 74))
	_stats_window.name = "StatsWindow"
	add_child(_stats_window)
	_build_stats(_stats_window)

	_command_window = _make_panel(Vector2(286, 62), Vector2(184, 74))
	_command_window.name = "CommandWindow"
	add_child(_command_window)
	_build_commands(_command_window)

	_battle_window = _make_panel(Vector2(226, 136), Vector2(188, 100))
	_battle_window_home = _battle_window.position
	_battle_window.name = "BattleWindow"
	add_child(_battle_window)
	_build_battle_window(_battle_window)

	_log_window = _make_panel(Vector2(170, 236), Vector2(300, 70))
	_log_window.name = "BattleLogWindow"
	add_child(_log_window)
	_build_log(_log_window)


func _apply_visibility_mode() -> void:
	_field_mode = RunState.is_unlocked(&"battle_movement")
	_stats_window.visible = not _field_mode
	_command_window.visible = not _field_mode
	_log_window.visible = not _field_mode
	_battle_window.visible = true
	if _field_mode:
		_update_field_battle_position()
	else:
		_battle_window.position = _battle_window_home


func _update_field_battle_position() -> void:
	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * _world_anchor
	if _battle_side >= 0:
		_battle_window.position = screen_pos + Vector2(FIELD_BATTLE_GAP, -_battle_window.size.y * 0.5)
	else:
		_battle_window.position = screen_pos + Vector2(-FIELD_BATTLE_GAP - _battle_window.size.x, -_battle_window.size.y * 0.5)


func _make_panel(pos: Vector2, panel_size: Vector2) -> Panel:
	var panel: Panel = Panel.new()
	panel.position = pos
	panel.size = panel_size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override(&"panel", _make_style(PANEL_COLOR))
	return panel


func _make_style(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	return style


func _build_stats(parent: Panel) -> void:
	var name_label: Label = _make_label(Vector2(8, 4), Vector2(100, 16), "Hero", 12)
	parent.add_child(name_label)

	_stats_label = _make_label(Vector2(8, 18), Vector2(54, 50), "", 11)
	parent.add_child(_stats_label)
	_refresh_stats()

	_gold_label = _make_label(Vector2(58, 52), Vector2(50, 16), "G  0", 11)
	parent.add_child(_gold_label)


func _build_commands(parent: Panel) -> void:
	var title: Label = _make_label(Vector2(0, 2), Vector2(parent.size.x, 14), "COMMAND", 11)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(title)

	_fight_button = _make_command_button("FIGHT", Vector2(10, 20))
	_spell_button = _make_command_button("SPELL", Vector2(96, 20))
	_run_button = _make_command_button("RUN", Vector2(10, 46))
	_item_button = _make_command_button("ITEM", Vector2(96, 46))

	parent.add_child(_fight_button)
	parent.add_child(_spell_button)
	parent.add_child(_run_button)
	parent.add_child(_item_button)

	_fight_button.focus_neighbor_right = _fight_button.get_path_to(_spell_button)
	_fight_button.focus_neighbor_bottom = _fight_button.get_path_to(_run_button)
	_spell_button.focus_neighbor_left = _spell_button.get_path_to(_fight_button)
	_spell_button.focus_neighbor_bottom = _spell_button.get_path_to(_item_button)
	_run_button.focus_neighbor_top = _run_button.get_path_to(_fight_button)
	_run_button.focus_neighbor_right = _run_button.get_path_to(_item_button)
	_item_button.focus_neighbor_top = _item_button.get_path_to(_spell_button)
	_item_button.focus_neighbor_left = _item_button.get_path_to(_run_button)

	_fight_button.pressed.connect(_on_fight_pressed)
	_spell_button.pressed.connect(_on_spell_pressed)
	_run_button.pressed.connect(_on_run_pressed)
	_item_button.pressed.connect(_on_item_pressed)


func _build_battle_window(parent: Panel) -> void:
	var sky: ColorRect = ColorRect.new()
	sky.position = Vector2(4, 4)
	sky.size = Vector2(parent.size.x - 8, 62)
	sky.color = Color(0.35, 0.70, 1.0, 1)
	parent.add_child(sky)

	var ground: ColorRect = ColorRect.new()
	ground.position = Vector2(4, 66)
	ground.size = Vector2(parent.size.x - 8, 30)
	ground.color = Color(0.28, 0.72, 0.26, 1)
	parent.add_child(ground)

	_enemy_sprite = TextureRect.new()
	_enemy_sprite.texture = SLIME_TEXTURE
	_enemy_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_enemy_sprite.size = Vector2(42, 42)
	_enemy_sprite.position = Vector2((parent.size.x - _enemy_sprite.size.x) * 0.5, 46)
	_enemy_sprite.pivot_offset = _enemy_sprite.size * 0.5
	parent.add_child(_enemy_sprite)

	_attack_effect = TextureRect.new()
	_attack_effect.texture = BASIC_ATTACK_TEXTURE
	_attack_effect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_attack_effect.size = ATTACK_EFFECT_SIZE
	_attack_effect.pivot_offset = ATTACK_EFFECT_SIZE * 0.5
	_attack_effect.visible = false
	_attack_effect.modulate = Color(1, 1, 1, 0)
	parent.add_child(_attack_effect)


func _build_log(parent: Panel) -> void:
	_log_label = _make_label(Vector2(10, 8), Vector2(parent.size.x - 20, parent.size.y - 16), "", 13)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	parent.add_child(_log_label)


func _make_label(pos: Vector2, label_size: Vector2, text: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.position = pos
	label.size = label_size
	label.text = text
	label.add_theme_color_override(&"font_color", TEXT_COLOR)
	label.add_theme_font_size_override(&"font_size", font_size)
	return label


func _make_command_button(text: String, pos: Vector2) -> Button:
	var button: Button = Button.new()
	button.position = pos
	button.size = Vector2(78, 20)
	button.text = text
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_color_override(&"font_color", TEXT_COLOR)
	button.add_theme_color_override(&"font_hover_color", TEXT_COLOR)
	button.add_theme_color_override(&"font_focus_color", TEXT_COLOR)
	button.add_theme_font_size_override(&"font_size", 11)
	button.add_theme_stylebox_override(&"focus", _make_style(FOCUS_COLOR))
	button.add_theme_stylebox_override(&"hover", _make_style(FOCUS_COLOR))
	_command_buttons.append(button)
	return button


func _on_fight_pressed(auto_triggered: bool = false) -> void:
	if _busy:
		return
	_busy = true
	_set_commands_enabled(false)
	await _perform_hero_attack(auto_triggered)
	if _slime_hp <= 0:
		await _show_message("슬라임을 쓰러뜨렸다!")
		_play_enemy_defeat()
		await _finish_battle(true)
		return
	await _show_message("슬라임은 아직 버티고 있다.")
	_resume_commands()


func _perform_hero_attack(auto_triggered: bool) -> void:
	if auto_triggered:
		await _show_message("자동 공격!")
		await _play_auto_attack_effect()
	else:
		await _show_message("용사의 공격!")
	var damage: int = RunState.hero_attack()
	_slime_hp = maxi(0, _slime_hp - damage)
	await _show_message("슬라임에게 %d 데미지!" % damage)


func _start_auto_battle() -> void:
	if not visible or _busy:
		return
	await get_tree().create_timer(AUTO_BATTLE_DELAY).timeout
	if not visible or _busy:
		return
	await _show_message("용사는 망설임 없이 달려들었다!")
	while visible and not _busy and _slime_hp > 0:
		_busy = true
		_set_commands_enabled(false)
		await _perform_hero_attack(true)
		if _slime_hp <= 0:
			await _show_message("슬라임을 쓰러뜨렸다!")
			_play_enemy_defeat()
			await _finish_battle(true)
			return
		await _show_message("슬라임은 아직 버티고 있다.")
		_busy = false
		await get_tree().create_timer(AUTO_BATTLE_DELAY).timeout


func _on_spell_pressed() -> void:
	if _busy:
		return
	_busy = true
	_set_commands_enabled(false)
	await _show_message("아직 외운 주문이 없다.")
	_resume_commands()


func _on_item_pressed() -> void:
	if _busy:
		return
	_busy = true
	_set_commands_enabled(false)
	await _show_message("도구함은 텅 비어 있다.")
	_resume_commands()


func _on_run_pressed() -> void:
	if _busy:
		return
	_busy = true
	_set_commands_enabled(false)
	await _show_message("용사는 달아나려 했다!")
	if randf() < 0.5:
		await _show_message("무사히 도망쳤다.")
		await _finish_battle(false)
		return
	await _show_message("하지만 길이 막혔다!")
	_resume_commands()


func _resume_commands() -> void:
	_busy = false
	_set_commands_enabled(true)
	_fight_button.grab_focus.call_deferred()


func _move_command_focus(dir: Vector2) -> void:
	var current: Button = _focused_command_button()
	var next_button: Button = current
	if dir == Vector2.LEFT:
		if current == _spell_button:
			next_button = _fight_button
		elif current == _item_button:
			next_button = _run_button
	elif dir == Vector2.RIGHT:
		if current == _fight_button:
			next_button = _spell_button
		elif current == _run_button:
			next_button = _item_button
	elif dir == Vector2.UP:
		if current == _run_button:
			next_button = _fight_button
		elif current == _item_button:
			next_button = _spell_button
	elif dir == Vector2.DOWN:
		if current == _fight_button:
			next_button = _run_button
		elif current == _spell_button:
			next_button = _item_button
	next_button.grab_focus()


func _focused_command_button() -> Button:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner is Button and _command_buttons.has(focus_owner):
		return focus_owner as Button
	_fight_button.grab_focus()
	return _fight_button


func _activate_focused_command() -> void:
	var button: Button = _focused_command_button()
	if button == _fight_button:
		_on_fight_pressed()
	elif button == _spell_button:
		_on_spell_pressed()
	elif button == _run_button:
		_on_run_pressed()
	else:
		_on_item_pressed()


func _set_log(text: String) -> void:
	if _log_label != null:
		_log_label.text = text


func _refresh_stats() -> void:
	if _stats_label != null:
		_stats_label.text = "LV   1\nHP  10\nMP   0\nAT  %2d" % RunState.hero_attack()


func _on_hero_attack_changed(_amount: int) -> void:
	_refresh_stats()


func _show_message(text: String) -> void:
	_set_log(text)
	await get_tree().create_timer(MESSAGE_SECONDS).timeout


func _finish_battle(defeated: bool) -> void:
	await get_tree().create_timer(0.28).timeout
	visible = false
	battle_finished.emit(_monster, defeated)
	_monster = null
	_set_commands_enabled(true)
	_busy = false


func _set_commands_enabled(enabled: bool) -> void:
	for button in _command_buttons:
		button.disabled = not enabled


func _play_enemy_defeat() -> void:
	var tween: Tween = _enemy_sprite.create_tween()
	tween.tween_property(_enemy_sprite, "modulate:a", 0.0, 0.28)
	tween.parallel().tween_property(_enemy_sprite, "scale", Vector2(1.25, 0.65), 0.28)


func _play_auto_attack_effect() -> void:
	var enemy_center: Vector2 = _enemy_sprite.position + _enemy_sprite.size * 0.5
	_attack_effect.visible = true
	_attack_effect.position = enemy_center - ATTACK_EFFECT_SIZE * 0.5
	_attack_effect.scale = Vector2(0.92, 0.92)
	_attack_effect.rotation = 0.0
	_attack_effect.modulate = Color(1, 1, 1, 0)

	var effect_tween: Tween = create_tween()
	effect_tween.set_parallel(true)
	effect_tween.tween_property(_attack_effect, "modulate:a", 0.72, 0.04)
	effect_tween.tween_property(_attack_effect, "scale", Vector2.ONE, 0.12)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)
	effect_tween.tween_property(_attack_effect, "modulate:a", 0.0, 0.08).set_delay(0.08)

	var enemy_origin: Vector2 = _enemy_sprite.position
	var hit_tween: Tween = _enemy_sprite.create_tween()
	hit_tween.tween_property(_enemy_sprite, "position", enemy_origin + Vector2(2, 0), 0.04)
	hit_tween.tween_property(_enemy_sprite, "position", enemy_origin, 0.06)
	hit_tween.parallel().tween_property(_enemy_sprite, "modulate", Color(1.0, 0.9, 0.9, 1.0), 0.04)
	hit_tween.tween_property(_enemy_sprite, "modulate", Color.WHITE, 0.10)

	await effect_tween.finished
	_attack_effect.visible = false


func _mark_input_handled() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
