class_name ManualBattle
extends CanvasLayer

## DQ1-style command battle. Visually = a real auto battle_window
## (white panel, 1px black border, centered enemy sprite, log strip at
## bottom) plus a sibling COMMAND panel sitting next to it. The two
## panels read as one unit, but the command sidebar telegraphs that this
## is the *manual* path. Only ATTACK is wired through; SPELL/ITEM/RUN
## print one Easter-egg line each and return control without burning
## the enemy's turn.
##
## Active while GameState.is_manual_battle_mode() is true. While the
## window is up GameState registers the manual battle so
## is_field_combat_locked() returns true (player/companions/field
## enemies freeze) — but the field's _process keeps running so the
## stage timer and spawner still tick.

signal battle_finished

const BATTLE_PANEL_SIZE: Vector2 = Vector2(120, 80)
const COMMAND_PANEL_SIZE: Vector2 = Vector2(120, 80)
const PANEL_GAP: float = 6.0
const PANELS_TOP_Y: float = 76.0

const WINDOW_BG_COLOR: Color = Color(1, 1, 1, 1)
const WINDOW_BORDER_COLOR: Color = Color(0, 0, 0, 1)
const TEXT_COLOR: Color = Color(0, 0, 0, 1)
const FOCUS_COLOR: Color = Color(0.18, 0.36, 0.74, 1)
const HOVER_COLOR: Color = Color(0.10, 0.22, 0.56, 1)
const DISABLED_COLOR: Color = Color(0.55, 0.55, 0.55, 1)

const TEXT_MESSAGE_SECONDS: float = 1.05
const VICTORY_DELAY: float = 0.55
const DEFEAT_DELAY: float = 0.85
const ENCOUNTER_PREFIX: String = "어! "
const ENCOUNTER_SUFFIX: String = " 어피어스!"

const SPRITE_SCALE: float = 2.0
const ENEMY_ANCHOR: Vector2 = Vector2(60, 36)  ## matches battle_window.tscn

@export var hero_index: int = 0

var _enemy_data: EnemyData
var _enemy_max_hp: int
var _enemy_hp: int
var _busy: bool = false
var _ended: bool = false

var _battle_panel: Panel
var _command_panel: Panel
var _enemy_sprite: TextureRect
var _log_label: Label
var _attack_btn: Button
var _spell_btn: Button
var _item_btn: Button
var _run_btn: Button


func setup(enemy_data: EnemyData) -> void:
	_enemy_data = enemy_data
	_enemy_max_hp = GameState.scaled_enemy_max_hp(enemy_data)
	_enemy_hp = _enemy_max_hp


func _enter_tree() -> void:
	GameState.register_manual_battle()


func _exit_tree() -> void:
	GameState.unregister_manual_battle()


func _ready() -> void:
	layer = 50
	_build_ui()
	_set_command_enabled(false)
	EventBus.party_wiped.connect(_on_party_wiped)
	await _show_message(_encounter_text())
	if _ended:
		return
	_set_command_enabled(true)
	_attack_btn.grab_focus()


# ─── UI construction ──────────────────────────────────────────────────
func _build_ui() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var total_width: float = BATTLE_PANEL_SIZE.x + PANEL_GAP + COMMAND_PANEL_SIZE.x
	var origin_x: float = floor((vp.x - total_width) * 0.5)
	var origin_y: float = PANELS_TOP_Y
	_battle_panel = _build_battle_panel(Vector2(origin_x, origin_y))
	_command_panel = _build_command_panel(Vector2(origin_x + BATTLE_PANEL_SIZE.x + PANEL_GAP, origin_y))


## Mirrors scenes/battle_window.tscn layout: Background panel (white +
## 1px border), enemy sprite at the EnemyAnchor offset, LogPanel pinned
## to the bottom edge. Name/HP labels are intentionally absent — the
## auto window hides them too.
func _build_battle_panel(pos: Vector2) -> Panel:
	var panel := Panel.new()
	panel.position = pos
	panel.size = BATTLE_PANEL_SIZE
	panel.add_theme_stylebox_override("panel", _make_window_stylebox())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	_enemy_sprite = TextureRect.new()
	_enemy_sprite.texture = _enemy_data.sprite if _enemy_data else null
	_enemy_sprite.stretch_mode = TextureRect.STRETCH_SCALE
	var sprite_size: Vector2 = _enemy_sprite_size()
	_enemy_sprite.size = sprite_size
	_enemy_sprite.position = ENEMY_ANCHOR - sprite_size * 0.5
	_enemy_sprite.pivot_offset = sprite_size * 0.5
	_enemy_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_enemy_sprite)

	var log_panel := Panel.new()
	log_panel.position = Vector2(4, BATTLE_PANEL_SIZE.y - 24)
	log_panel.size = Vector2(BATTLE_PANEL_SIZE.x - 8, 20)
	log_panel.add_theme_stylebox_override("panel", _make_window_stylebox())
	log_panel.clip_contents = true
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(log_panel)

	_log_label = Label.new()
	_log_label.position = Vector2(2, 2)
	_log_label.size = log_panel.size - Vector2(4, 4)
	_log_label.add_theme_font_size_override("font_size", 7)
	_log_label.add_theme_color_override("font_color", TEXT_COLOR)
	_log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.clip_text = true
	_log_label.max_lines_visible = 1
	log_panel.add_child(_log_label)

	return panel


func _build_command_panel(pos: Vector2) -> Panel:
	var panel := Panel.new()
	panel.position = pos
	panel.size = COMMAND_PANEL_SIZE
	panel.add_theme_stylebox_override("panel", _make_window_stylebox())
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(panel)

	var title := Label.new()
	title.position = Vector2(2, 2)
	title.size = Vector2(COMMAND_PANEL_SIZE.x - 4, 10)
	title.text = "COMMAND"
	title.add_theme_font_size_override("font_size", 8)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var grid_top: float = 14.0
	var btn_w: float = (COMMAND_PANEL_SIZE.x - 12) * 0.5
	var btn_h: float = 28.0
	var row_gap: float = 4.0
	_attack_btn = _make_command_button("공격", Vector2(4, grid_top), btn_w, btn_h)
	_spell_btn = _make_command_button("스펠", Vector2(8 + btn_w, grid_top), btn_w, btn_h)
	_item_btn = _make_command_button("아이템", Vector2(4, grid_top + btn_h + row_gap), btn_w, btn_h)
	_run_btn = _make_command_button("런", Vector2(8 + btn_w, grid_top + btn_h + row_gap), btn_w, btn_h)
	panel.add_child(_attack_btn)
	panel.add_child(_spell_btn)
	panel.add_child(_item_btn)
	panel.add_child(_run_btn)
	# Hook focus neighbours so arrow keys land on the right cell.
	_attack_btn.focus_neighbor_right = _attack_btn.get_path_to(_spell_btn)
	_attack_btn.focus_neighbor_bottom = _attack_btn.get_path_to(_item_btn)
	_spell_btn.focus_neighbor_left = _spell_btn.get_path_to(_attack_btn)
	_spell_btn.focus_neighbor_bottom = _spell_btn.get_path_to(_run_btn)
	_item_btn.focus_neighbor_top = _item_btn.get_path_to(_attack_btn)
	_item_btn.focus_neighbor_right = _item_btn.get_path_to(_run_btn)
	_run_btn.focus_neighbor_top = _run_btn.get_path_to(_spell_btn)
	_run_btn.focus_neighbor_left = _run_btn.get_path_to(_item_btn)
	_attack_btn.pressed.connect(_on_attack_pressed)
	_spell_btn.pressed.connect(_on_spell_pressed)
	_item_btn.pressed.connect(_on_item_pressed)
	_run_btn.pressed.connect(_on_run_pressed)
	return panel


func _make_window_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = WINDOW_BG_COLOR
	sb.border_color = WINDOW_BORDER_COLOR
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	return sb


func _make_command_button(text: String, pos: Vector2, width: float, height: float) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.position = pos
	btn.size = Vector2(width, height)
	btn.add_theme_font_size_override("font_size", 10)
	btn.add_theme_color_override("font_color", TEXT_COLOR)
	btn.add_theme_color_override("font_focus_color", FOCUS_COLOR)
	btn.add_theme_color_override("font_hover_color", HOVER_COLOR)
	btn.add_theme_color_override("font_disabled_color", DISABLED_COLOR)
	btn.focus_mode = Control.FOCUS_ALL
	btn.flat = true
	return btn


func _enemy_sprite_size() -> Vector2:
	if _enemy_data == null or _enemy_data.sprite == null:
		return Vector2(32, 32)
	var native: Vector2 = _enemy_data.sprite.get_size()
	if native.x <= 0.0 or native.y <= 0.0:
		return Vector2(32, 32)
	return native * SPRITE_SCALE


# ─── Command handlers ─────────────────────────────────────────────────
func _on_attack_pressed() -> void:
	if _busy or _ended:
		return
	_busy = true
	_set_command_enabled(false)
	var hero_name: String = _hero_display_name()
	await _show_message("%s의 공격!" % hero_name)
	if _ended:
		return
	var damage: int = _calc_hero_damage()
	_enemy_hp = maxi(0, _enemy_hp - damage)
	_play_enemy_hit()
	await _show_message("%s에게 %d 데미지!" % [_enemy_display_name(), damage])
	if _ended:
		return
	if _enemy_hp <= 0:
		await _finish_victory()
		return
	await _enemy_turn()
	if _ended:
		return
	_busy = false
	_set_command_enabled(true)
	_attack_btn.grab_focus()


func _on_spell_pressed() -> void:
	await _gag_message("주문을 모른다!")


func _on_item_pressed() -> void:
	await _gag_message("도구가 없다...")


func _on_run_pressed() -> void:
	await _gag_message("도망칠 수 없다!")


# Gag commands don't burn a turn — the enemy just sits there. Tutorial
# rule: only ATTACK progresses the fight.
func _gag_message(line: String) -> void:
	if _busy or _ended:
		return
	_busy = true
	_set_command_enabled(false)
	await _show_message(line)
	if _ended:
		return
	_busy = false
	_set_command_enabled(true)
	_attack_btn.grab_focus()


# ─── Combat math ──────────────────────────────────────────────────────
func _calc_hero_damage() -> int:
	if _enemy_data == null:
		return 1
	var atk: int = GameState.effective_attack(hero_index)
	var defense: int = GameState.scaled_enemy_defense(_enemy_data)
	return maxi(1, atk - defense)


func _enemy_turn() -> void:
	if _enemy_data == null:
		return
	if not GameState.is_alive(hero_index):
		return
	await _show_message("%s의 공격!" % _enemy_display_name())
	if _ended:
		return
	if GameState.roll_evade(hero_index):
		await _show_message("%s는 몸을 피했다!" % _hero_display_name())
		return
	var attack: int = GameState.scaled_enemy_attack(_enemy_data)
	var defense: int = GameState.effective_defense(hero_index)
	var dealt: int = maxi(1, attack - defense)
	GameState.damage_party_member(hero_index, dealt)
	_play_hero_hit()
	await _show_message("%s가 %d 데미지를 입었다!" % [_hero_display_name(), dealt])


func _finish_victory() -> void:
	_ended = true
	_set_command_enabled(false)
	var enemy_name: String = _enemy_display_name()
	_play_enemy_death()
	await _show_message("%s를 쓰러뜨렸다!" % enemy_name)
	var gold: int = GameState.modify_gold_reward(GameState.scaled_enemy_gold_reward(_enemy_data))
	var xp: int = GameState.scaled_enemy_xp_reward(_enemy_data)
	GameState.add_gold(gold)
	GameState.add_party_xp(xp)
	EventBus.enemy_defeated.emit(self, gold, Vector2.ZERO)
	await _show_message("+%d G  +%d EXP" % [gold, xp])
	await _pause(VICTORY_DELAY)
	battle_finished.emit()
	queue_free()


func _on_party_wiped() -> void:
	if _ended:
		return
	_ended = true
	_set_command_enabled(false)
	if _log_label:
		_log_label.text = "%s는 쓰러졌다..." % _hero_display_name()
	await _pause(DEFEAT_DELAY)
	# Don't emit battle_finished — party_wiped drives the home-base
	# transition in main.gd. The manual window just frees itself.
	queue_free()


# ─── Display helpers ──────────────────────────────────────────────────
func _show_message(text: String) -> void:
	if _ended:
		return
	if _log_label:
		_log_label.text = text
	await _pause(TEXT_MESSAGE_SECONDS)


func _pause(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _set_command_enabled(enabled: bool) -> void:
	if _attack_btn:
		_attack_btn.disabled = not enabled
	if _spell_btn:
		_spell_btn.disabled = not enabled
	if _item_btn:
		_item_btn.disabled = not enabled
	if _run_btn:
		_run_btn.disabled = not enabled


# ─── Sprite reactions ─────────────────────────────────────────────────
func _play_enemy_hit() -> void:
	if _enemy_sprite == null:
		return
	var tween: Tween = _enemy_sprite.create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_property(_enemy_sprite, "modulate", Color(1, 0.35, 0.35, 1), 0.08)
	tween.tween_property(_enemy_sprite, "modulate", Color.WHITE, 0.18)


func _play_enemy_death() -> void:
	if _enemy_sprite == null:
		return
	var tween: Tween = _enemy_sprite.create_tween().set_parallel(true)
	tween.set_ignore_time_scale(true)
	tween.tween_property(_enemy_sprite, "modulate:a", 0.0, 0.45)
	tween.tween_property(_enemy_sprite, "scale", Vector2(1.4, 0.5), 0.45)


func _play_hero_hit() -> void:
	if _battle_panel == null:
		return
	var origin: Vector2 = _battle_panel.position
	var tween: Tween = _battle_panel.create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_property(_battle_panel, "position", origin + Vector2(4, 0), 0.05)
	tween.tween_property(_battle_panel, "position", origin + Vector2(-3, 0), 0.05)
	tween.tween_property(_battle_panel, "position", origin, 0.08)


# ─── Naming ───────────────────────────────────────────────────────────
func _hero_display_name() -> String:
	if GameState.party.is_empty() or hero_index >= GameState.party.size():
		return "용사"
	var hero: CharacterData = GameState.party[hero_index]
	if hero == null or hero.display_name.is_empty():
		return "용사"
	return hero.display_name


func _enemy_display_name() -> String:
	if _enemy_data == null or _enemy_data.display_name.is_empty():
		return "적"
	return _enemy_data.display_name


func _encounter_text() -> String:
	return ENCOUNTER_PREFIX + _enemy_display_name() + ENCOUNTER_SUFFIX
