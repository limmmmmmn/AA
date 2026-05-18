class_name BattleView
extends Control

signal battle_finished(monster: Node2D, defeated: bool)

const SLIME_TEXTURE: Texture2D = preload("res://assets/sprites/enemies/slime.png")

const PANEL_COLOR: Color = Color(0, 0, 0, 1)
const BORDER_COLOR: Color = Color(1, 1, 1, 1)
const TEXT_COLOR: Color = Color(1, 1, 1, 1)
const FOCUS_COLOR: Color = Color(0.28, 0.28, 0.28, 1)
const MESSAGE_SECONDS: float = 0.72

var _monster: Node2D
var _busy: bool = false

var _command_buttons: Array[Button] = []
var _fight_button: Button
var _spell_button: Button
var _run_button: Button
var _item_button: Button
var _log_label: Label
var _gold_label: Label
var _enemy_sprite: TextureRect


func _ready() -> void:
	visible = false
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func start(monster: Node2D) -> void:
	_monster = monster
	_busy = false
	visible = true
	_gold_label.text = "G  %d" % RunState.gold
	_enemy_sprite.modulate = Color.WHITE
	_enemy_sprite.scale = Vector2.ONE
	_set_log("슬라임이 나타났다!")
	_fight_button.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _busy:
		return
	if not (event is InputEventKey):
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
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
	var stats_window: Panel = _make_panel(Vector2(170, 62), Vector2(116, 74))
	stats_window.name = "StatsWindow"
	add_child(stats_window)
	_build_stats(stats_window)

	var command_window: Panel = _make_panel(Vector2(286, 62), Vector2(184, 74))
	command_window.name = "CommandWindow"
	add_child(command_window)
	_build_commands(command_window)

	var battle_window: Panel = _make_panel(Vector2(226, 136), Vector2(188, 100))
	battle_window.name = "BattleWindow"
	add_child(battle_window)
	_build_battle_window(battle_window)

	var log_window: Panel = _make_panel(Vector2(170, 236), Vector2(300, 70))
	log_window.name = "BattleLogWindow"
	add_child(log_window)
	_build_log(log_window)


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

	var stats: Label = _make_label(Vector2(8, 20), Vector2(46, 48), "LV   1\nHP  10\nMP   0", 11)
	parent.add_child(stats)

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


func _on_fight_pressed() -> void:
	if _busy:
		return
	_busy = true
	_set_commands_enabled(false)
	await _show_message("용사의 공격!")
	await _show_message("슬라임을 쓰러뜨렸다!")
	_play_enemy_defeat()
	await _finish_battle(true)


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


func _mark_input_handled() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
