class_name HomeBase
extends Node2D

## Suikoden-style 거점. Shown on party wipe instead of a stats panel.
## Recruited heroes mill around a small square plaza. A 출동 button at the
## bottom kicks off a fresh run. Future upgrades will place each hero on
## a specific building/post once the player builds those; for now they
## just wander loose across the plaza.

signal deploy_pressed

const PLAZA_SIZE: Vector2 = Vector2(280, 240)
const PLAZA_PADDING: float = 18.0
const PLAZA_FILL: Color = Color(0.46, 0.36, 0.24, 1.0)
const PLAZA_BORDER: Color = Color(0.26, 0.18, 0.1, 1.0)
const SCREEN_BG: Color = Color(0.16, 0.13, 0.1, 1.0)
const WANDER_SPEED: float = 14.0
const WANDER_RETARGET_MIN: float = 1.4
const WANDER_RETARGET_MAX: float = 3.6
const ARRIVAL_RADIUS: float = 3.0

## One entry per visible roster member: { visual, target, timer }.
var _walkers: Array[Dictionary] = []
var _plaza_origin: Vector2
var _viewport_size: Vector2


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_viewport_size = get_viewport_rect().size
	_plaza_origin = (_viewport_size - PLAZA_SIZE) * 0.5
	_build_camera()
	_build_background()
	_build_plaza()
	_build_chrome()
	_spawn_roster()


# ─── Camera (fixed) ────────────────────────────────────────────────────
func _build_camera() -> void:
	var cam := Camera2D.new()
	cam.position = _viewport_size * 0.5
	cam.zoom = Vector2.ONE
	add_child(cam)
	cam.make_current()


# ─── Background + plaza tile ───────────────────────────────────────────
func _build_background() -> void:
	# Full-screen dark backdrop so the plaza reads as an island of land.
	var bg := ColorRect.new()
	bg.color = SCREEN_BG
	bg.position = Vector2.ZERO
	bg.size = _viewport_size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -20
	add_child(bg)


func _build_plaza() -> void:
	# Border first (slightly larger so it shows as a 2px frame).
	var border := ColorRect.new()
	border.color = PLAZA_BORDER
	border.position = _plaza_origin - Vector2(2.0, 2.0)
	border.size = PLAZA_SIZE + Vector2(4.0, 4.0)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.z_index = -11
	add_child(border)

	var floor := ColorRect.new()
	floor.color = PLAZA_FILL
	floor.position = _plaza_origin
	floor.size = PLAZA_SIZE
	floor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor.z_index = -10
	add_child(floor)


# ─── UI chrome (title + deploy button) ─────────────────────────────────
func _build_chrome() -> void:
	var hud := CanvasLayer.new()
	hud.layer = 5
	add_child(hud)

	var title := Label.new()
	title.text = "기지"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.42))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 3)
	title.position = Vector2(8, 6)
	hud.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "동료들이 대기 중…"
	subtitle.add_theme_font_size_override("font_size", 9)
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	subtitle.position = Vector2(8, 24)
	hud.add_child(subtitle)

	var deploy := Button.new()
	deploy.text = "출동  ▶"
	deploy.add_theme_font_size_override("font_size", 12)
	deploy.anchor_left = 0.5
	deploy.anchor_right = 0.5
	deploy.anchor_top = 1.0
	deploy.anchor_bottom = 1.0
	deploy.offset_left = -64
	deploy.offset_right = 64
	deploy.offset_top = -36
	deploy.offset_bottom = -10
	deploy.pressed.connect(_on_deploy_pressed)
	hud.add_child(deploy)
	deploy.grab_focus()


# ─── Roster wandering ──────────────────────────────────────────────────
## Spawns one CharacterVisual per current party member at a random plaza
## point. Once upgrades land, this branch will instead route specific
## members to specific upgrade slots and only wander the leftovers.
func _spawn_roster() -> void:
	for member: CharacterData in GameState.party:
		if member == null:
			continue
		_spawn_walker(member)


func _spawn_walker(data: CharacterData) -> void:
	var visual := CharacterVisual.new()
	visual.position = _random_plaza_point()
	add_child(visual)
	visual.setup(data)
	_walkers.append({
		"visual": visual,
		"target": _random_plaza_point(),
		"timer": randf_range(WANDER_RETARGET_MIN, WANDER_RETARGET_MAX),
	})


func _random_plaza_point() -> Vector2:
	return _plaza_origin + Vector2(
		randf_range(PLAZA_PADDING, PLAZA_SIZE.x - PLAZA_PADDING),
		randf_range(PLAZA_PADDING, PLAZA_SIZE.y - PLAZA_PADDING),
	)


func _physics_process(delta: float) -> void:
	for entry: Dictionary in _walkers:
		var visual: CharacterVisual = entry.visual
		if not is_instance_valid(visual):
			continue
		entry.timer = float(entry.timer) - delta
		if float(entry.timer) <= 0.0 or visual.position.distance_to(entry.target) < ARRIVAL_RADIUS:
			entry.target = _random_plaza_point()
			entry.timer = randf_range(WANDER_RETARGET_MIN, WANDER_RETARGET_MAX)
		var to_target: Vector2 = (entry.target as Vector2) - visual.position
		var velocity: Vector2 = Vector2.ZERO
		if to_target.length() > 0.1:
			velocity = to_target.normalized() * WANDER_SPEED
		visual.position += velocity * delta
		visual.set_velocity(velocity)


func _on_deploy_pressed() -> void:
	deploy_pressed.emit()


# Enter / Space / Z deploys too — keeps things snappy on keyboard.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE or key == KEY_Z:
			_on_deploy_pressed()
			get_viewport().set_input_as_handled()
