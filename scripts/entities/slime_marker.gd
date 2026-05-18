class_name SlimeMarker
extends Node2D

const WANDER_SPEED: float = 18.0
const WANDER_RADIUS: float = 36.0
const ARRIVE_DISTANCE: float = 2.0
const CHASE_SPEED: float = 12.0
const MIN_MOVE_SECONDS: float = 1.0
const MAX_MOVE_SECONDS: float = 2.2
const MIN_IDLE_SECONDS: float = 0.45
const MAX_IDLE_SECONDS: float = 1.35
const QUESTION_OFFSET: Vector2 = Vector2(-10, -25)

@export var enemy_data: EnemyData

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _home: Vector2
var _target: Vector2
var _bounds: Rect2
var _has_bounds: bool = false
var _is_idle: bool = true
var _state_time_left: float = 0.0
var _question_label: Label
var _chase_target: Node2D


func _ready() -> void:
	_rng.randomize()
	_home = position
	_target = position
	_build_question_label()
	_begin_idle()


func setup_wander(bounds: Rect2) -> void:
	_bounds = bounds
	_has_bounds = true
	_home = position
	_target = position


func set_chase_target(target: Node2D) -> void:
	_chase_target = target


func push_from(source_position: Vector2, distance: float, bounds: Rect2) -> void:
	var dir: Vector2 = position - source_position
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	position += dir.normalized() * distance
	position = Vector2(
		clampf(position.x, bounds.position.x, bounds.end.x),
		clampf(position.y, bounds.position.y, bounds.end.y)
	)
	_home = position
	_target = position
	_is_idle = true
	_state_time_left = maxf(_state_time_left, 0.18)
	set_question_visible(true)


func set_question_visible(is_visible: bool) -> void:
	if _question_label != null:
		_question_label.visible = is_visible


func gold_reward() -> int:
	if enemy_data == null:
		return 1
	return maxi(0, enemy_data.gold_reward)


func max_hp() -> int:
	if enemy_data == null:
		return 1
	return maxi(1, enemy_data.max_hp)


func _process(delta: float) -> void:
	if RunState.is_unlocked(&"monster_chase") and _chase_target != null and is_instance_valid(_chase_target):
		_chase_hero(delta)
		return

	_state_time_left -= delta
	if _is_idle:
		if _state_time_left <= 0.0:
			_begin_move()
		return

	var to_target: Vector2 = _target - position
	if to_target.length() <= ARRIVE_DISTANCE or _state_time_left <= 0.0:
		_begin_idle()
		return
	position += to_target.normalized() * WANDER_SPEED * delta


func _chase_hero(delta: float) -> void:
	var to_hero: Vector2 = _chase_target.global_position - global_position
	if to_hero.length() <= ARRIVE_DISTANCE:
		return
	var step: Vector2 = to_hero.normalized() * CHASE_SPEED * delta
	position += step
	if _has_bounds:
		position = Vector2(
			clampf(position.x, _bounds.position.x, _bounds.end.x),
			clampf(position.y, _bounds.position.y, _bounds.end.y)
		)


func _begin_idle() -> void:
	_is_idle = true
	_state_time_left = _rng.randf_range(MIN_IDLE_SECONDS, MAX_IDLE_SECONDS)


func _begin_move() -> void:
	_is_idle = false
	_state_time_left = _rng.randf_range(MIN_MOVE_SECONDS, MAX_MOVE_SECONDS)
	var angle: float = _rng.randf_range(0.0, TAU)
	var distance: float = _rng.randf_range(8.0, WANDER_RADIUS)
	_target = _home + Vector2.from_angle(angle) * distance
	if _has_bounds:
		_target = Vector2(
			clampf(_target.x, _bounds.position.x, _bounds.end.x),
			clampf(_target.y, _bounds.position.y, _bounds.end.y)
		)


func _build_question_label() -> void:
	_question_label = Label.new()
	_question_label.name = "QuestionBubble"
	_question_label.position = QUESTION_OFFSET
	_question_label.size = Vector2(20, 12)
	_question_label.text = "[?]"
	_question_label.visible = false
	_question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_question_label.add_theme_color_override(&"font_color", Color.WHITE)
	_question_label.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	_question_label.add_theme_constant_override(&"shadow_offset_x", 1)
	_question_label.add_theme_constant_override(&"shadow_offset_y", 1)
	_question_label.add_theme_font_size_override(&"font_size", 10)
	add_child(_question_label)
