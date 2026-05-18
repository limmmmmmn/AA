class_name UnfoldField
extends Node2D

signal battle_requested(monster: Node2D)

const SLIME_MARKER_SCENE: PackedScene = preload("res://scenes/entities/slime_marker.tscn")
const GOLD_PICKUP_SCENE: PackedScene = preload("res://scenes/entities/gold_pickup.tscn")
const TILE_SIZE: float = 16.0
const CONTINUOUS_MOVE_SPEED: float = 84.0
const PICKUP_RADIUS: float = 10.0
const ENCOUNTER_RADIUS: float = 14.0
const MAP_EXPAND_LINES_PER_UNLOCK: int = 2
const BATTLE_GOLD_DROPS: int = 3
const RANDOM_DROP_MARGIN: float = 18.0
const HERO_SAFE_RADIUS: float = 34.0
const MONSTER_SPAWN_INTERVAL: float = 3.0
const MAX_SPAWNED_MONSTERS: int = 4

@onready var hero: Hero = $Hero
@onready var background: ColorRect = $Background
@onready var pickups_root: Node2D = $Pickups
@onready var monsters_root: Node2D = $Monsters

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _is_input_enabled: bool = true
var _base_field_position: Vector2 = Vector2.ZERO
var _base_field_size: Vector2 = Vector2.ZERO
var _encounter_locked: bool = false
var _monster_spawn_timer: float = MONSTER_SPAWN_INTERVAL


func _ready() -> void:
	_rng.randomize()
	_base_field_position = background.position
	_base_field_size = background.size
	_apply_map_expansion()
	RunState.skill_unlocked.connect(_on_skill_unlocked)
	_refresh_gold_pickups()
	_ensure_world_gold_pickup()
	_refresh_monsters()


func set_input_enabled(is_enabled: bool) -> void:
	_is_input_enabled = is_enabled
	if not _is_input_enabled:
		hero.set_moving(false)
	for child in monsters_root.get_children():
		var monster: Node = child as Node
		if monster != null:
			monster.set_process(is_enabled)


func _process(delta: float) -> void:
	if not _is_input_enabled:
		hero.set_moving(false)
		return
	if RunState.is_unlocked(&"movement"):
		_move_continuous(delta)
	else:
		hero.set_moving(false)
	_process_monster_spawner(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_input_enabled:
		return
	if not RunState.is_unlocked(&"movement"):
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if not _is_move_action(event):
		return
	get_viewport().set_input_as_handled()


func _is_move_action(event: InputEvent) -> bool:
	return event.is_action_pressed(&"move_left") \
		or event.is_action_pressed(&"move_right") \
		or event.is_action_pressed(&"move_up") \
		or event.is_action_pressed(&"move_down")


func _input_dir() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")


func _dir_to_facing(dir: Vector2) -> int:
	if absf(dir.x) >= absf(dir.y):
		return Hero.Direction.LEFT if dir.x < 0.0 else Hero.Direction.RIGHT
	if dir.y < 0.0:
		return Hero.Direction.UP
	return Hero.Direction.DOWN


func _move_continuous(delta: float) -> void:
	var dir: Vector2 = _input_dir()
	if dir == Vector2.ZERO:
		hero.set_moving(false)
		_try_monster_encounter()
		return
	hero.set_moving(true)
	hero.face(_dir_to_facing(dir))
	hero.position = _clamp_to_field(hero.position + dir * CONTINUOUS_MOVE_SPEED * delta)
	_try_pickup()
	_try_monster_encounter()


func _try_pickup() -> void:
	if not RunState.is_unlocked(&"gold"):
		return
	for child in pickups_root.get_children():
		if child is GoldPickup and child.position.distance_to(hero.position) <= PICKUP_RADIUS:
			RunState.add_gold(child.VALUE)
			child.collect()


func _refresh_gold_pickups() -> void:
	var gold_visible: bool = RunState.is_unlocked(&"gold")
	for child in pickups_root.get_children():
		if child is GoldPickup:
			child.visible = gold_visible
			child.process_mode = Node.PROCESS_MODE_INHERIT if gold_visible else Node.PROCESS_MODE_DISABLED


func _ensure_world_gold_pickup() -> void:
	if not RunState.is_unlocked(&"gold"):
		return
	if pickups_root.get_child_count() > 0:
		return
	_spawn_gold_pickup(_random_field_position())


func _refresh_monsters() -> void:
	if not RunState.is_unlocked(&"monster"):
		for child in monsters_root.get_children():
			child.queue_free()
		_encounter_locked = false
		return
	if monsters_root.get_child_count() > 0:
		return
	_spawn_slime_marker(_random_field_position())
	_reset_monster_spawn_timer()


func _spawn_slime_marker(pos: Vector2) -> void:
	var slime: Node2D = SLIME_MARKER_SCENE.instantiate() as Node2D
	slime.position = pos
	monsters_root.add_child(slime)
	if slime is SlimeMarker:
		(slime as SlimeMarker).setup_wander(_field_bounds(RANDOM_DROP_MARGIN))
	if not _is_input_enabled:
		slime.set_process(false)


func finish_battle(monster: Node2D, defeated: bool) -> void:
	if is_instance_valid(monster):
		if defeated:
			_drop_gold_from_monster(monster.position)
		monster.queue_free()
	_encounter_locked = false


func _drop_gold_from_monster(pos: Vector2) -> void:
	const OFFSETS: Array[Vector2] = [
		Vector2(-18, -10),
		Vector2(0, -22),
		Vector2(18, -10),
	]
	for i in range(BATTLE_GOLD_DROPS):
		_spawn_gold_pickup(pos + OFFSETS[i % OFFSETS.size()])


func _spawn_gold_pickup(pos: Vector2) -> void:
	var pickup: GoldPickup = GOLD_PICKUP_SCENE.instantiate() as GoldPickup
	pickup.position = _clamp_to_field(pos)
	pickup.visible = RunState.is_unlocked(&"gold")
	pickup.process_mode = Node.PROCESS_MODE_INHERIT if pickup.visible else Node.PROCESS_MODE_DISABLED
	pickups_root.add_child(pickup)


func _try_monster_encounter() -> void:
	if _encounter_locked or not RunState.is_unlocked(&"monster"):
		return
	for child in monsters_root.get_children():
		var monster: Node2D = child as Node2D
		if monster != null and monster.position.distance_to(hero.position) <= ENCOUNTER_RADIUS:
			_encounter_locked = true
			battle_requested.emit(monster)
			return


func _process_monster_spawner(delta: float) -> void:
	if not RunState.is_unlocked(&"spawner") or not RunState.is_unlocked(&"monster"):
		return
	if monsters_root.get_child_count() >= MAX_SPAWNED_MONSTERS:
		return
	_monster_spawn_timer -= delta
	if _monster_spawn_timer > 0.0:
		return
	_spawn_slime_marker(_random_field_position())
	_reset_monster_spawn_timer()


func _reset_monster_spawn_timer() -> void:
	_monster_spawn_timer = MONSTER_SPAWN_INTERVAL


func _apply_map_expansion() -> void:
	var side_expand: float = float(RunState.timer_bonus_seconds * MAP_EXPAND_LINES_PER_UNLOCK) * TILE_SIZE
	var expand: Vector2 = Vector2.ONE * side_expand
	background.position = _base_field_position - expand
	background.size = _base_field_size + expand * 2.0


func _is_in_bounds(pos: Vector2) -> bool:
	return Rect2(background.position, background.size).has_point(pos)


func _field_bounds(margin: float = 0.0) -> Rect2:
	var bounds: Rect2 = Rect2(background.position, background.size)
	return bounds.grow(-margin)


func _random_field_position() -> Vector2:
	var bounds: Rect2 = _field_bounds(RANDOM_DROP_MARGIN)
	var fallback: Vector2 = bounds.get_center()
	for _attempt in range(16):
		var pos: Vector2 = Vector2(
			_rng.randf_range(bounds.position.x, bounds.end.x),
			_rng.randf_range(bounds.position.y, bounds.end.y)
		)
		if pos.distance_to(hero.position) >= HERO_SAFE_RADIUS:
			return pos
		fallback = pos
	return fallback


func _clamp_to_field(pos: Vector2) -> Vector2:
	var bounds: Rect2 = Rect2(background.position, background.size)
	return Vector2(
		clampf(pos.x, bounds.position.x, bounds.end.x),
		clampf(pos.y, bounds.position.y, bounds.end.y)
	)


func _on_skill_unlocked(skill_id: StringName) -> void:
	_apply_map_expansion()
	if skill_id == &"gold":
		_refresh_gold_pickups()
		_ensure_world_gold_pickup()
	elif skill_id == &"monster":
		_refresh_monsters()
	elif skill_id == &"spawner":
		_reset_monster_spawn_timer()
