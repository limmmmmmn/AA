class_name SlimeMarker
extends Node2D

const WANDER_SPEED: float = 18.0
const WANDER_RADIUS: float = 36.0
const ARRIVE_DISTANCE: float = 2.0
const MIN_MOVE_SECONDS: float = 1.0
const MAX_MOVE_SECONDS: float = 2.2
const MIN_IDLE_SECONDS: float = 0.45
const MAX_IDLE_SECONDS: float = 1.35

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _home: Vector2
var _target: Vector2
var _bounds: Rect2
var _has_bounds: bool = false
var _is_idle: bool = true
var _state_time_left: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_home = position
	_target = position
	_begin_idle()


func setup_wander(bounds: Rect2) -> void:
	_bounds = bounds
	_has_bounds = true
	_home = position
	_target = position


func _process(delta: float) -> void:
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
