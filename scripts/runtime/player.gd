class_name Player
extends CharacterBody2D

## Top-down player avatar. Conceptually = the camera = the party (README: 시스템 3).
## Owns the Camera2D and its CharacterVisual. Combat lives in battle_windows.

@export var speed: float = 80.0

const CAMERA_LIMIT_DISABLED_MIN: int = -10000000
const CAMERA_LIMIT_DISABLED_MAX: int = 10000000

@onready var _visual: CharacterVisual = $Visual
@onready var _camera: Camera2D = $Camera2D

var _pending_data: CharacterData
var _field_bounds := Rect2(Vector2.ZERO, Vector2(960, 540))


func _ready() -> void:
	# Field enemies look us up via this group. Set before anything else so
	# enemies spawned on the same frame find us.
	add_to_group("player")
	add_to_group("party_member")
	_camera.make_current()
	# Party_changed re-creates the player mid-run (e.g. after recruiting a
	# companion). Snap so the camera doesn't pan from wherever it was.
	_camera.reset_smoothing()
	if _pending_data:
		_visual.setup(_pending_data)


## Inject the character data (sprite sheet, stats). Safe to call before _ready.
func setup(data: CharacterData) -> void:
	_pending_data = data
	if is_inside_tree() and _visual:
		_visual.setup(data)


func set_field_bounds(min_pos: Vector2, max_pos: Vector2) -> void:
	_field_bounds = Rect2(min_pos, max_pos - min_pos)
	if _camera:
		var viewport_size := Vector2(
			float(ProjectSettings.get_setting("display/window/size/viewport_width")),
			float(ProjectSettings.get_setting("display/window/size/viewport_height"))
		)
		var field_size: Vector2 = max_pos - min_pos
		_camera.limit_left = int(min_pos.x) if field_size.x > viewport_size.x else CAMERA_LIMIT_DISABLED_MIN
		_camera.limit_right = int(max_pos.x) if field_size.x > viewport_size.x else CAMERA_LIMIT_DISABLED_MAX
		_camera.limit_top = int(min_pos.y) if field_size.y > viewport_size.y else CAMERA_LIMIT_DISABLED_MIN
		_camera.limit_bottom = int(max_pos.y) if field_size.y > viewport_size.y else CAMERA_LIMIT_DISABLED_MAX


func _physics_process(_delta: float) -> void:
	if GameState.is_field_combat_locked():
		velocity = Vector2.ZERO
		_visual.set_velocity(Vector2.ZERO)
		return
	var dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * GameState.effective_move_speed(speed)
	move_and_slide()
	global_position = Vector2(
		clampf(global_position.x, _field_bounds.position.x, _field_bounds.end.x),
		clampf(global_position.y, _field_bounds.position.y, _field_bounds.end.y)
	)
	_visual.set_velocity(velocity)


## Drop the camera's smoothing for one frame — used after teleporting the
## player (e.g. start of a new stage) so the camera doesn't pan from the
## old spot.
func snap_camera() -> void:
	if _camera:
		_camera.reset_smoothing()
