class_name BattleView
extends Control

signal battle_finished(monster: Node2D, defeated: bool, kills: int)

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
const FALLBACK_SLIME_MAX_HP: int = 1
const HERO_MAX_HP_BASE: int = 10
const HERO_MAX_HP_ARMORED: int = 15
const HERO_MAX_MP: int = 5
const FIRE_SPELL_COST: int = 3
const FIRE_SPELL_DAMAGE: int = 3
const SLIME_ATTACK_DAMAGE: int = 1
const ENEMY_DUAL_OFFSET: float = 22.0
const ENEMY_SPRITE_Y: float = 36.0
const STATS_WINDOW_POS: Vector2 = Vector2(182, 70)
const STATS_WINDOW_SIZE: Vector2 = Vector2(92, 66)
const COMMAND_WINDOW_POS: Vector2 = Vector2(278, 70)
const COMMAND_WINDOW_SIZE: Vector2 = Vector2(180, 66)
const BATTLE_WINDOW_POS: Vector2 = Vector2(230, 140)
const BATTLE_WINDOW_SIZE: Vector2 = Vector2(180, 126)
const BATTLE_SCENE_RECT: Rect2 = Rect2(4, 4, 172, 64)
const BATTLE_LOG_RECT: Rect2 = Rect2(4, 72, 172, 50)

var _monster: Node2D
var _busy: bool = false
var _field_mode: bool = false
var _world_anchor: Vector2 = Vector2.ZERO
var _battle_side: int = 1
var _battle_window_home: Vector2 = Vector2.ZERO
var _slime_hp: int = FALLBACK_SLIME_MAX_HP
var _slime_hp_2: int = 0
var _slime_max_hp: int = FALLBACK_SLIME_MAX_HP
var _hero_hp: int = HERO_MAX_HP_BASE
var _hero_mp: int = 0
var _ending: bool = false
var _finished: bool = false
var _last_attacked_sprite: TextureRect

var _command_buttons: Array[Button] = []
var _stats_window: Panel
var _command_window: Panel
var _battle_window: Panel
var _fight_button: Button
var _spell_button: Button
var _run_button: Button
var _item_button: Button
var _stats_label: Label
var _log_label: Label
var _gold_label: Label
var _enemy_sprite: TextureRect
var _enemy_sprite_2: TextureRect
var _attack_effect: TextureRect


func _ready() -> void:
	visible = false
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	if has_node("BattleWindow"):
		_bind_ui()
	else:
		_build_ui()
	RunState.hero_attack_changed.connect(_on_hero_attack_changed)


func start(monster: Node2D, hero_global_position: Vector2 = Vector2.ZERO) -> void:
	_monster = monster
	_busy = false
	_ending = false
	_finished = false
	_field_mode = RunState.is_unlocked(&"battle_movement")
	_world_anchor = monster.global_position if is_instance_valid(monster) else Vector2.ZERO
	_battle_side = 1 if _world_anchor.x >= hero_global_position.x else -1
	_slime_max_hp = _monster_max_hp(monster)
	_slime_hp = _slime_max_hp
	_slime_hp_2 = _slime_max_hp if _initial_enemy_count() >= 2 else 0
	_last_attacked_sprite = null
	_hero_hp = _hero_max_hp()
	_hero_mp = _initial_mp()
	visible = true
	_gold_label.text = "G  %d" % RunState.gold
	_refresh_stats()
	_enemy_sprite.modulate = Color.WHITE
	_enemy_sprite.scale = Vector2.ONE
	_enemy_sprite.visible = true
	if _enemy_sprite_2 != null:
		_enemy_sprite_2.modulate = Color.WHITE
		_enemy_sprite_2.scale = Vector2.ONE
		_enemy_sprite_2.visible = (_slime_hp_2 > 0)
	_position_enemy_sprites()
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


func _bind_ui() -> void:
	_stats_window = $StatsWindow as Panel
	_command_window = $CommandWindow as Panel
	_battle_window = $BattleWindow as Panel
	_battle_window_home = _battle_window.position
	_stats_label = $StatsWindow/StatsLabel as Label
	_gold_label = $StatsWindow/GoldLabel as Label
	_fight_button = $CommandWindow/FightButton as Button
	_spell_button = $CommandWindow/SpellButton as Button
	_run_button = $CommandWindow/RunButton as Button
	_item_button = $CommandWindow/ItemButton as Button
	_enemy_sprite = $BattleWindow/BattleScene/EnemySprite as TextureRect
	_attack_effect = $BattleWindow/BattleScene/AttackEffect as TextureRect
	_log_label = $BattleWindow/BattleLogWindow/LogLabel as Label

	var log_panel: Panel = $BattleWindow/BattleLogWindow as Panel
	for panel in [_stats_window, _command_window, _battle_window, log_panel]:
		(panel as Panel).add_theme_stylebox_override(&"panel", _make_style(PANEL_COLOR))
		(panel as Panel).mouse_filter = Control.MOUSE_FILTER_STOP
	_style_bound_label($StatsWindow/NameLabel as Label, 11)
	_style_bound_label(_stats_label, 10)
	_style_bound_label(_gold_label, 10)
	_style_bound_label($CommandWindow/TitleLabel as Label, 11)
	_style_bound_label(_log_label, 12)
	for button in [_fight_button, _spell_button, _run_button, _item_button]:
		_style_bound_button(button as Button)

	_enemy_sprite.texture = SLIME_TEXTURE
	_enemy_sprite.stretch_mode = TextureRect.STRETCH_KEEP
	_enemy_sprite.size = SLIME_TEXTURE.get_size()
	_enemy_sprite.pivot_offset = _enemy_sprite.size * 0.5
	_enemy_sprite_2 = _make_enemy_sprite()
	_enemy_sprite.get_parent().add_child(_enemy_sprite_2)
	_attack_effect.texture = BASIC_ATTACK_TEXTURE
	_attack_effect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_attack_effect.size = ATTACK_EFFECT_SIZE
	_attack_effect.pivot_offset = ATTACK_EFFECT_SIZE * 0.5
	_attack_effect.visible = false
	_attack_effect.modulate = Color(1, 1, 1, 0)

	_command_buttons = [_fight_button, _spell_button, _run_button, _item_button]
	_wire_command_buttons()
	_refresh_stats()


func _build_ui() -> void:
	_stats_window = _make_panel(STATS_WINDOW_POS, STATS_WINDOW_SIZE)
	_stats_window.name = "StatsWindow"
	add_child(_stats_window)
	_build_stats(_stats_window)

	_command_window = _make_panel(COMMAND_WINDOW_POS, COMMAND_WINDOW_SIZE)
	_command_window.name = "CommandWindow"
	add_child(_command_window)
	_build_commands(_command_window)

	_battle_window = _make_panel(BATTLE_WINDOW_POS, BATTLE_WINDOW_SIZE)
	_battle_window_home = _battle_window.position
	_battle_window.name = "BattleWindow"
	add_child(_battle_window)
	_build_battle_window(_battle_window)


func _apply_visibility_mode() -> void:
	_field_mode = RunState.is_unlocked(&"battle_movement")
	_stats_window.visible = false
	_command_window.visible = false
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


func _style_bound_label(label: Label, font_size: int) -> void:
	label.add_theme_color_override(&"font_color", TEXT_COLOR)
	label.add_theme_font_size_override(&"font_size", font_size)


func _style_bound_button(button: Button) -> void:
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_color_override(&"font_color", TEXT_COLOR)
	button.add_theme_color_override(&"font_hover_color", TEXT_COLOR)
	button.add_theme_color_override(&"font_focus_color", TEXT_COLOR)
	button.add_theme_font_size_override(&"font_size", 11)
	button.add_theme_stylebox_override(&"focus", _make_style(FOCUS_COLOR))
	button.add_theme_stylebox_override(&"hover", _make_style(FOCUS_COLOR))


func _build_stats(parent: Panel) -> void:
	var name_label: Label = _make_label(Vector2(8, 4), Vector2(76, 14), "Hero", 11)
	parent.add_child(name_label)

	_stats_label = _make_label(Vector2(8, 18), Vector2(76, 46), "", 10)
	parent.add_child(_stats_label)
	_refresh_stats()

	_gold_label = _make_label(Vector2(44, 4), Vector2(42, 14), "G  0", 10)
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parent.add_child(_gold_label)


func _build_commands(parent: Panel) -> void:
	var title: Label = _make_label(Vector2(0, 2), Vector2(parent.size.x, 14), "COMMAND", 11)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(title)

	_fight_button = _make_command_button("FIGHT", Vector2(14, 20))
	_spell_button = _make_command_button("SPELL", Vector2(98, 20))
	_run_button = _make_command_button("RUN", Vector2(14, 44))
	_item_button = _make_command_button("ITEM", Vector2(98, 44))

	parent.add_child(_fight_button)
	parent.add_child(_spell_button)
	parent.add_child(_run_button)
	parent.add_child(_item_button)

	_wire_command_buttons()


func _wire_command_buttons() -> void:
	_fight_button.focus_neighbor_right = _fight_button.get_path_to(_spell_button)
	_fight_button.focus_neighbor_bottom = _fight_button.get_path_to(_run_button)
	_spell_button.focus_neighbor_left = _spell_button.get_path_to(_fight_button)
	_spell_button.focus_neighbor_bottom = _spell_button.get_path_to(_item_button)
	_run_button.focus_neighbor_top = _run_button.get_path_to(_fight_button)
	_run_button.focus_neighbor_right = _run_button.get_path_to(_item_button)
	_item_button.focus_neighbor_top = _item_button.get_path_to(_spell_button)
	_item_button.focus_neighbor_left = _item_button.get_path_to(_run_button)

	if not _fight_button.pressed.is_connected(_on_fight_pressed):
		_fight_button.pressed.connect(_on_fight_pressed)
	if not _spell_button.pressed.is_connected(_on_spell_pressed):
		_spell_button.pressed.connect(_on_spell_pressed)
	if not _run_button.pressed.is_connected(_on_run_pressed):
		_run_button.pressed.connect(_on_run_pressed)
	if not _item_button.pressed.is_connected(_on_item_pressed):
		_item_button.pressed.connect(_on_item_pressed)


func _build_battle_window(parent: Panel) -> void:
	var battle_scene: Control = Control.new()
	battle_scene.name = "BattleScene"
	battle_scene.position = BATTLE_SCENE_RECT.position
	battle_scene.size = BATTLE_SCENE_RECT.size
	parent.add_child(battle_scene)

	var sky: ColorRect = ColorRect.new()
	sky.name = "Sky"
	sky.position = Vector2.ZERO
	sky.size = Vector2(BATTLE_SCENE_RECT.size.x, 42)
	sky.color = Color(0.35, 0.70, 1.0, 1)
	battle_scene.add_child(sky)

	var ground: ColorRect = ColorRect.new()
	ground.name = "Ground"
	ground.position = Vector2(0, 42)
	ground.size = Vector2(BATTLE_SCENE_RECT.size.x, 22)
	ground.color = Color(0.28, 0.72, 0.26, 1)
	battle_scene.add_child(ground)

	_enemy_sprite = TextureRect.new()
	_enemy_sprite.name = "EnemySprite"
	_enemy_sprite.texture = SLIME_TEXTURE
	_enemy_sprite.stretch_mode = TextureRect.STRETCH_KEEP
	_enemy_sprite.size = SLIME_TEXTURE.get_size()
	_enemy_sprite.position = Vector2((BATTLE_SCENE_RECT.size.x - _enemy_sprite.size.x) * 0.5, ENEMY_SPRITE_Y)
	_enemy_sprite.pivot_offset = _enemy_sprite.size * 0.5
	battle_scene.add_child(_enemy_sprite)

	_enemy_sprite_2 = _make_enemy_sprite()
	battle_scene.add_child(_enemy_sprite_2)

	_attack_effect = TextureRect.new()
	_attack_effect.name = "AttackEffect"
	_attack_effect.texture = BASIC_ATTACK_TEXTURE
	_attack_effect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_attack_effect.size = ATTACK_EFFECT_SIZE
	_attack_effect.pivot_offset = ATTACK_EFFECT_SIZE * 0.5
	_attack_effect.visible = false
	_attack_effect.modulate = Color(1, 1, 1, 0)
	battle_scene.add_child(_attack_effect)

	var log_panel: Panel = _make_panel(BATTLE_LOG_RECT.position, BATTLE_LOG_RECT.size)
	log_panel.name = "BattleLogWindow"
	parent.add_child(log_panel)
	_build_log(log_panel)


func _build_log(parent: Panel) -> void:
	_log_label = _make_label(Vector2(8, 6), Vector2(parent.size.x - 16, parent.size.y - 12), "", 12)
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
	button.size = Vector2(68, 18)
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
	if _busy or _ending:
		return
	_busy = true
	_set_commands_enabled(false)
	await _perform_hero_attack(auto_triggered)
	if _ending:
		return
	if _last_attacked_sprite != null and _is_sprite_dead_now(_last_attacked_sprite):
		await _show_message("슬라임을 쓰러뜨렸다!")
		_play_enemy_defeat(_last_attacked_sprite)
	if _ending:
		return
	if _all_enemies_dead():
		var kills: int = await _award_battle_reward()
		await _finish_battle(true, kills)
		return
	await _show_message("슬라임은 아직 버티고 있다.")
	await _perform_slime_attack()
	_resume_commands()


func _perform_hero_attack(_auto_triggered: bool) -> void:
	if _ending:
		return
	await _show_message("공격!")
	if _ending:
		return
	var target: TextureRect = _first_alive_sprite()
	_last_attacked_sprite = target
	await _play_attack_effect(target)
	if _ending:
		return
	var damage: int = RunState.hero_attack()
	_apply_damage_to_first_alive(damage)
	await _show_message("슬라임에게 %d 데미지!" % damage)


func _monster_max_hp(monster: Node2D) -> int:
	if monster is SlimeMarker:
		return (monster as SlimeMarker).max_hp()
	return FALLBACK_SLIME_MAX_HP


func _hero_max_hp() -> int:
	return HERO_MAX_HP_ARMORED if RunState.armor_collected else HERO_MAX_HP_BASE


func _initial_mp() -> int:
	return HERO_MAX_MP if RunState.is_unlocked(&"magic") else 0


func _initial_enemy_count() -> int:
	return 2 if RunState.is_unlocked(&"enemies_per_window") else 1


func _make_enemy_sprite() -> TextureRect:
	var sprite: TextureRect = TextureRect.new()
	sprite.texture = SLIME_TEXTURE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP
	sprite.size = SLIME_TEXTURE.get_size()
	sprite.pivot_offset = sprite.size * 0.5
	sprite.visible = false
	return sprite


func _position_enemy_sprites() -> void:
	var center_x: float = (BATTLE_SCENE_RECT.size.x - _enemy_sprite.size.x) * 0.5
	if _initial_enemy_count() >= 2:
		_enemy_sprite.position = Vector2(center_x - ENEMY_DUAL_OFFSET, ENEMY_SPRITE_Y)
		if _enemy_sprite_2 != null:
			_enemy_sprite_2.position = Vector2(center_x + ENEMY_DUAL_OFFSET, ENEMY_SPRITE_Y)
	else:
		_enemy_sprite.position = Vector2(center_x, ENEMY_SPRITE_Y)


func _first_alive_sprite() -> TextureRect:
	if _slime_hp > 0:
		return _enemy_sprite
	if _slime_hp_2 > 0 and _enemy_sprite_2 != null:
		return _enemy_sprite_2
	return _enemy_sprite


func _apply_damage_to_first_alive(amount: int) -> TextureRect:
	if _slime_hp > 0:
		_slime_hp = maxi(0, _slime_hp - amount)
		return _enemy_sprite
	if _slime_hp_2 > 0:
		_slime_hp_2 = maxi(0, _slime_hp_2 - amount)
		return _enemy_sprite_2
	return null


func _is_sprite_dead_now(sprite: TextureRect) -> bool:
	if sprite == _enemy_sprite:
		return _slime_hp <= 0
	if sprite == _enemy_sprite_2:
		return _slime_hp_2 <= 0
	return false


func _all_enemies_dead() -> bool:
	return _slime_hp <= 0 and _slime_hp_2 <= 0


func _alive_enemy_count() -> int:
	var count: int = 0
	if _slime_hp > 0:
		count += 1
	if _slime_hp_2 > 0:
		count += 1
	return count


func _perform_slime_attack() -> void:
	if _ending:
		return
	var alive: int = _alive_enemy_count()
	if alive <= 0:
		return
	await _show_message("슬라임의 공격!")
	await _play_slime_attack_effect()
	var damage: int = SLIME_ATTACK_DAMAGE * alive
	_hero_hp = maxi(0, _hero_hp - damage)
	_refresh_stats()
	await _show_message("%d 데미지를 받았다!" % damage)


func _start_auto_battle() -> void:
	if not visible or _busy or _ending:
		return
	await get_tree().create_timer(AUTO_BATTLE_DELAY).timeout
	if not visible or _busy or _ending:
		return
	while visible and not _busy and not _ending:
		_busy = true
		_set_commands_enabled(false)
		if _has_spell_ready():
			await _cast_fire_spell(true)
		else:
			await _perform_hero_attack(true)
		if _ending:
			return
		if _last_attacked_sprite != null and _is_sprite_dead_now(_last_attacked_sprite):
			await _show_message("슬라임을 쓰러뜨렸다!")
			_play_enemy_defeat(_last_attacked_sprite)
		if _ending:
			return
		if _all_enemies_dead():
			var kills: int = await _award_battle_reward()
			await _finish_battle(true, kills)
			return
		await _show_message("슬라임은 아직 버티고 있다.")
		await _perform_slime_attack()
		if _ending:
			return
		_busy = false
		await get_tree().create_timer(AUTO_BATTLE_DELAY).timeout


func _on_spell_pressed() -> void:
	if _busy or _ending:
		return
	_busy = true
	_set_commands_enabled(false)
	if not RunState.is_unlocked(&"magic"):
		await _show_message("아직 외운 주문이 없다.")
		_resume_commands()
		return
	if _hero_mp < FIRE_SPELL_COST:
		await _show_message("MP가 모자라다.")
		_resume_commands()
		return
	await _cast_fire_spell(false)
	if _ending:
		return
	if _last_attacked_sprite != null and _is_sprite_dead_now(_last_attacked_sprite):
		await _show_message("슬라임을 쓰러뜨렸다!")
		_play_enemy_defeat(_last_attacked_sprite)
	if _ending:
		return
	if _all_enemies_dead():
		var kills: int = await _award_battle_reward()
		await _finish_battle(true, kills)
		return
	await _show_message("슬라임은 아직 버티고 있다.")
	await _perform_slime_attack()
	_resume_commands()


func _has_spell_ready() -> bool:
	return RunState.is_unlocked(&"magic") and _hero_mp >= FIRE_SPELL_COST


func _cast_fire_spell(_auto_triggered: bool) -> void:
	if _ending:
		return
	_hero_mp = maxi(0, _hero_mp - FIRE_SPELL_COST)
	_refresh_stats()
	await _show_message("파이어!")
	if _ending:
		return
	var target: TextureRect = _first_alive_sprite()
	_last_attacked_sprite = target
	await _play_attack_effect(target)
	if _ending:
		return
	_apply_damage_to_first_alive(FIRE_SPELL_DAMAGE)
	await _show_message("슬라임에게 %d 데미지!" % FIRE_SPELL_DAMAGE)


func _on_item_pressed() -> void:
	if _busy or _ending:
		return
	_busy = true
	_set_commands_enabled(false)
	await _show_message("도구함은 텅 비어 있다.")
	_resume_commands()


func _on_run_pressed() -> void:
	if _busy or _ending:
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
		_stats_label.text = "LV   1\nHP  %2d\nMP  %2d\nAT  %2d" % [_hero_hp, _hero_mp, RunState.hero_attack()]


func _on_hero_attack_changed(_amount: int) -> void:
	_refresh_stats()


func _show_message(text: String) -> void:
	_set_log(text)
	await get_tree().create_timer(MESSAGE_SECONDS).timeout


func force_timeout_escape() -> void:
	if not visible or _ending:
		return
	_ending = true
	_busy = true
	_set_commands_enabled(false)
	await _show_message("슬라임이 도망갔다!")
	await _finish_battle(false)


func _finish_battle(defeated: bool, kills: int = 0) -> void:
	if not visible or _finished:
		return
	_finished = true
	_ending = true
	await get_tree().create_timer(0.28).timeout
	visible = false
	battle_finished.emit(_monster, defeated, kills)
	_monster = null
	_set_commands_enabled(true)
	_busy = false


func _award_battle_reward() -> int:
	var kills: int = _initial_enemy_count()
	if not RunState.is_unlocked(&"gold"):
		RunState.add_gold(kills)
		await _show_message("골드 획득 +%d" % kills)
	return kills


func _set_commands_enabled(enabled: bool) -> void:
	for button in _command_buttons:
		button.disabled = not enabled


func _play_enemy_defeat(sprite: TextureRect) -> void:
	if sprite == null:
		return
	var tween: Tween = sprite.create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 0.28)
	tween.parallel().tween_property(sprite, "scale", Vector2(1.25, 0.65), 0.28)


func _play_attack_effect(target_sprite: TextureRect) -> void:
	if target_sprite == null:
		return
	var enemy_center: Vector2 = target_sprite.position + target_sprite.size * 0.5
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

	var enemy_origin: Vector2 = target_sprite.position
	var hit_tween: Tween = target_sprite.create_tween()
	hit_tween.tween_property(target_sprite, "position", enemy_origin + Vector2(2, 0), 0.04)
	hit_tween.tween_property(target_sprite, "position", enemy_origin, 0.06)
	hit_tween.parallel().tween_property(target_sprite, "modulate", Color(1.0, 0.9, 0.9, 1.0), 0.04)
	hit_tween.tween_property(target_sprite, "modulate", Color.WHITE, 0.10)

	await effect_tween.finished
	_attack_effect.visible = false


func _play_slime_attack_effect() -> void:
	var await_tween: Tween = null
	if _slime_hp > 0:
		await_tween = _animate_slime_attack(_enemy_sprite)
	if _slime_hp_2 > 0 and _enemy_sprite_2 != null:
		var t2: Tween = _animate_slime_attack(_enemy_sprite_2)
		if await_tween == null:
			await_tween = t2
	if await_tween != null:
		await await_tween.finished


func _animate_slime_attack(sprite: TextureRect) -> Tween:
	var origin: Vector2 = sprite.position
	var tween: Tween = sprite.create_tween()
	tween.tween_property(sprite, "position", origin + Vector2(0, 12), 0.10)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(sprite, "scale", Vector2(1.12, 0.88), 0.10)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(sprite, "modulate", Color(1.0, 0.95, 0.95, 1.0), 0.08)
	tween.tween_property(sprite, "position", origin, 0.14)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(sprite, "scale", Vector2.ONE, 0.14)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(sprite, "modulate", Color.WHITE, 0.12)
	return tween


func _mark_input_handled() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
