class_name Enemy
extends Node2D

## Generic enemy node. Data-driven via EnemyData.
## One scene (enemy.tscn) handles every species; the .tres swaps stats + sprite.

signal hp_changed(current: int, max_hp: int)
signal died()

const DAMAGE_NUMBER_SCENE: PackedScene = preload("res://scenes/effects/damage_number.tscn")

@export var data: EnemyData
@export var attack_lunge_pixels: float = 8.0
@export var attack_lunge_duration: float = 0.18
@export var hit_shake_pixels: float = 3.0
@export var hit_flash_duration: float = 0.12
@export var death_fade_duration: float = 0.38
@export var shadow_alpha: float = 0.34
@export var shadow_y_offset: float = 1.0

## Juicy drain feedback — yellow afterimage held briefly in the slice the
## ProgressBar just lost, then chased down and faded out. Same idea (and
## numbers) as StatBar's ghost so HP feedback reads consistently between
## the party HUD and the enemy stack.
const HP_GHOST_FLASH_COLOR: Color = Color(1.0, 0.95, 0.55, 1.0)
const HP_GHOST_HOLD_DURATION: float = 0.18
const HP_GHOST_DRAIN_DURATION: float = 0.45

@onready var _shadow: Polygon2D = $Shadow
@onready var _sprite: Sprite2D = $Sprite2D
@onready var _hp_bar: ProgressBar = $HPBar

var current_hp: int = 0
var max_hp: int = 0
var attack: int = 0
var defense: int = 0
var agility: int = 0
var gold_reward: int = 0
var _base_position: Vector2
var _base_scale: Vector2
var _hit_tween: Tween
var _attack_tween: Tween
var _death_tween: Tween
var _dying: bool = false
var _stolen_from: bool = false
var _hp_ghost: ColorRect
var _last_hp_ratio: float = 1.0
var _hp_ghost_drain_tween: Tween
var _hp_ghost_color_tween: Tween


func _ready() -> void:
	_base_position = position
	_base_scale = scale
	_build_hp_ghost()
	if data:
		_apply_data()


## Lives as a child of the ProgressBar so it occupies the exact same rect
## without us having to track size/position changes. anchor_right rides
## the slice width; z_index puts it just above the ProgressBar's fill.
func _build_hp_ghost() -> void:
	if not is_instance_valid(_hp_bar):
		return
	_hp_ghost = ColorRect.new()
	_hp_ghost.color = HP_GHOST_FLASH_COLOR
	_hp_ghost.color.a = 0.0
	_hp_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_ghost.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_hp_ghost.anchor_right = 0.0
	_hp_ghost.z_index = 1
	_hp_bar.add_child(_hp_ghost)


## Allows callers to inject data after instantiate() but before adding to tree.
func setup(enemy_data: EnemyData) -> void:
	data = enemy_data
	if is_inside_tree():
		_apply_data()


func _apply_data() -> void:
	if data == null:
		return
	max_hp = GameState.scaled_enemy_max_hp(data)
	attack = GameState.scaled_enemy_attack(data)
	defense = GameState.scaled_enemy_defense(data)
	agility = GameState.scaled_enemy_agility(data)
	gold_reward = GameState.scaled_enemy_gold_reward(data)
	current_hp = max_hp
	_dying = false
	_stolen_from = false
	position = _base_position
	scale = _base_scale
	modulate = Color.WHITE
	if data.sprite and _sprite:
		_sprite.texture = data.sprite
		_fit_shadow_to_sprite()
	_refresh_hp_bar()
	hp_changed.emit(current_hp, max_hp)


func _fit_shadow_to_sprite() -> void:
	if _shadow == null or _sprite == null or _sprite.texture == null:
		return
	var texture_size: Vector2 = _sprite.texture.get_size()
	var visual_size: Vector2 = texture_size * _sprite.scale.abs()
	var shadow_width: float = clampf(visual_size.x * 0.72, 10.0, 30.0)
	var shadow_height: float = clampf(visual_size.y * 0.18, 4.0, 9.0)
	_shadow.position.y = clampf(visual_size.y * 0.46, 6.0, 22.0) + shadow_y_offset
	if _shadow.has_method("setup_shadow"):
		_shadow.call("setup_shadow", Vector2(shadow_width, shadow_height), shadow_alpha)


func is_alive() -> bool:
	return current_hp > 0


func try_steal_gold(chance: float, amount: int) -> int:
	if _stolen_from or amount <= 0 or randf() >= chance:
		return 0
	_stolen_from = true
	return amount


func take_damage(amount: int, is_crit: bool = false, hit_effect: Texture2D = null, show_damage_number: bool = true) -> int:
	if not is_alive() or data == null:
		return 0
	var dealt: int = max(1, amount - defense)
	current_hp = max(0, current_hp - dealt)
	_refresh_hp_bar()
	hp_changed.emit(current_hp, max_hp)
	EventBus.damage_dealt.emit(self, dealt, global_position)
	_spawn_hit_effect(hit_effect, is_crit)
	if show_damage_number:
		_spawn_damage_number(dealt, is_crit)
	_play_hit_reaction(is_crit)
	if current_hp == 0:
		_die()
	return dealt


## Enemy's own attack anticipation: slide toward the bottom of the battle
## window, then snap back. BattleWindow calls this before applying party damage.
func play_attack_lunge() -> void:
	if _dying:
		return
	if _attack_tween and _attack_tween.is_valid():
		_attack_tween.kill()
	position = _base_position
	_attack_tween = create_tween()
	_attack_tween.tween_property(self, "position", _base_position + Vector2(0, attack_lunge_pixels), attack_lunge_duration * 0.45)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	_attack_tween.tween_property(self, "position", _base_position, attack_lunge_duration * 0.55)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)


func _spawn_damage_number(amount: int, is_crit: bool) -> void:
	var num: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate()
	add_child(num)
	num.position = Vector2(randf_range(-4, 4), randf_range(-12, -6))
	num.setup(amount, is_crit)


func _refresh_hp_bar() -> void:
	if _hp_bar == null:
		return
	var new_ratio: float = 0.0 if max_hp <= 0 else clampf(float(current_hp) / float(max_hp), 0.0, 1.0)
	_hp_bar.value = new_ratio
	if is_instance_valid(_hp_ghost):
		if new_ratio < _last_hp_ratio:
			_start_hp_ghost_drain(_last_hp_ratio, new_ratio)
		else:
			_cancel_hp_ghost_tweens()
			_hp_ghost.anchor_right = new_ratio
			_hp_ghost.color.a = 0.0
	_last_hp_ratio = new_ratio


func _start_hp_ghost_drain(old_ratio: float, new_ratio: float) -> void:
	if not is_instance_valid(_hp_ghost):
		return
	_cancel_hp_ghost_tweens()
	_hp_ghost.anchor_right = old_ratio
	_hp_ghost.color = HP_GHOST_FLASH_COLOR

	_hp_ghost_drain_tween = create_tween()
	_hp_ghost_drain_tween.tween_interval(HP_GHOST_HOLD_DURATION)
	_hp_ghost_drain_tween.tween_property(_hp_ghost, "anchor_right", new_ratio, HP_GHOST_DRAIN_DURATION)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)

	_hp_ghost_color_tween = create_tween()
	_hp_ghost_color_tween.tween_interval(HP_GHOST_HOLD_DURATION)
	_hp_ghost_color_tween.tween_property(_hp_ghost, "color:a", 0.0, HP_GHOST_DRAIN_DURATION)


func _cancel_hp_ghost_tweens() -> void:
	if _hp_ghost_drain_tween and _hp_ghost_drain_tween.is_valid():
		_hp_ghost_drain_tween.kill()
	if _hp_ghost_color_tween and _hp_ghost_color_tween.is_valid():
		_hp_ghost_color_tween.kill()


func _spawn_hit_effect(texture: Texture2D, is_crit: bool) -> void:
	if texture == null:
		return
	var effect := Sprite2D.new()
	effect.texture = texture
	effect.centered = true
	effect.z_index = 8
	effect.position = Vector2(randf_range(-3, 3), randf_range(-5, 1))
	effect.scale = Vector2.ONE * 0.75
	effect.rotation = randf_range(-0.25, 0.25)
	effect.modulate = Color(1, 1, 1, 0.95)
	add_child(effect)
	var target_scale: Vector2 = Vector2.ONE * (1.45 if is_crit else 1.15)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(effect, "scale", target_scale, hit_flash_duration * 1.6)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(effect, "modulate:a", 0.0, hit_flash_duration * 2.0)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(effect.queue_free)


func _play_hit_reaction(is_crit: bool) -> void:
	if _dying:
		return
	if _hit_tween and _hit_tween.is_valid():
		_hit_tween.kill()
	var shake := hit_shake_pixels * (1.5 if is_crit else 1.0)
	position = _base_position
	modulate = Color(1.0, 0.95, 0.55, 1.0)
	_hit_tween = create_tween()
	_hit_tween.tween_property(self, "position", _base_position + Vector2(shake, 0), hit_flash_duration * 0.25)
	_hit_tween.tween_property(self, "position", _base_position + Vector2(-shake, 0), hit_flash_duration * 0.25)
	_hit_tween.tween_property(self, "position", _base_position, hit_flash_duration * 0.25)
	_hit_tween.tween_property(self, "modulate", Color.WHITE, hit_flash_duration * 0.25)


func _die() -> void:
	_dying = true
	if _attack_tween and _attack_tween.is_valid():
		_attack_tween.kill()
	if _hit_tween and _hit_tween.is_valid():
		_hit_tween.kill()
	if _death_tween and _death_tween.is_valid():
		_death_tween.kill()
	_death_tween = create_tween().set_parallel(true)
	_death_tween.tween_property(self, "modulate:a", 0.0, death_fade_duration)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_IN)
	_death_tween.tween_property(self, "position", _base_position + Vector2(0, 10), death_fade_duration)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_IN)
	died.emit()
	EventBus.enemy_defeated.emit(self, gold_reward, global_position)
