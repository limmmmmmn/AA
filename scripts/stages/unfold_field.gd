class_name UnfoldField
extends Node2D

signal battle_requested(monster: Node2D)

const SLIME_MARKER_SCENE: PackedScene = preload("res://scenes/entities/slime_marker.tscn")
const GOLD_PICKUP_SCENE: PackedScene = preload("res://scenes/entities/gold_pickup.tscn")
const SWORD_PICKUP_SCENE: PackedScene = preload("res://scenes/entities/sword_pickup.tscn")
const TILE_SIZE: float = 16.0
const CONTINUOUS_MOVE_SPEED: float = 84.0
const PICKUP_RADIUS: float = 10.0
const ITEM_PICKUP_RADIUS: float = 12.0
const ENCOUNTER_RADIUS: float = 14.0
const MONSTER_PUSH_SPEED: float = 54.0
const RANDOM_DROP_MARGIN: float = 18.0
const HERO_SAFE_RADIUS: float = 34.0
const MONSTER_SPAWN_INTERVAL: float = 3.0
const MAX_SPAWNED_MONSTERS: int = 4
const START_SLIME_OFFSETS: Array[Vector2] = [
	Vector2(-44, -36),
	Vector2(44, -36),
]

@onready var hero: Hero = $Hero
@onready var background: ColorRect = $Background
@onready var pickups_root: Node2D = $Pickups
@onready var items_root: Node2D = $Items
@onready var monsters_root: Node2D = $Monsters

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _is_input_enabled: bool = true
var _encounter_locked: bool = false
var _monster_spawn_timer: float = MONSTER_SPAWN_INTERVAL
var _question_monster: SlimeMarker


func _ready() -> void:
	_rng.randomize()
	RunState.skill_unlocked.connect(_on_skill_unlocked)
	_refresh_gold_pickups()
	_refresh_item_pickups()
	_ensure_sword_pickup()
	_refresh_monsters()
	_sync_depth_sort()


func set_input_enabled(is_enabled: bool) -> void:
	_is_input_enabled = is_enabled
	if not _is_input_enabled:
		hero.set_moving(false)
	for child in monsters_root.get_children():
		var monster: Node = child as Node
		if monster != null:
			monster.set_process(is_enabled)


func prepare_monster_for_battle(monster: Node2D) -> void:
	if is_instance_valid(monster):
		monster.set_process(false)
		monster.visible = false


func get_hero_global_position() -> Vector2:
	return hero.global_position


func _process(delta: float) -> void:
	if not _is_input_enabled:
		hero.set_moving(false)
		return
	if RunState.is_unlocked(&"movement"):
		_move_continuous(delta)
	else:
		hero.set_moving(false)
	if _encounter_locked:
		_push_overlapping_monsters(delta)
	_process_monster_spawner(delta)
	_sync_depth_sort()


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
		_try_item_pickup()
		_try_monster_encounter()
		return
	hero.set_moving(true)
	hero.face(_dir_to_facing(dir))
	hero.position = _clamp_to_field(hero.position + dir * CONTINUOUS_MOVE_SPEED * delta)
	_try_pickup()
	_try_item_pickup()
	_try_monster_encounter()


func _try_pickup() -> void:
	if not RunState.is_unlocked(&"gold"):
		return
	for child in pickups_root.get_children():
		if child is GoldPickup and child.position.distance_to(hero.position) <= PICKUP_RADIUS:
			RunState.add_gold(child.VALUE)
			child.collect()


func _try_item_pickup() -> void:
	if not RunState.is_unlocked(&"item") or RunState.sword_collected:
		return
	for child in items_root.get_children():
		if child is SwordPickup and child.position.distance_to(hero.position) <= ITEM_PICKUP_RADIUS:
			child.collect()


func _refresh_gold_pickups() -> void:
	var gold_visible: bool = RunState.is_unlocked(&"gold")
	for child in pickups_root.get_children():
		if child is GoldPickup:
			child.visible = gold_visible
			child.process_mode = Node.PROCESS_MODE_INHERIT if gold_visible else Node.PROCESS_MODE_DISABLED


func _refresh_item_pickups() -> void:
	var item_visible: bool = RunState.is_unlocked(&"item") and not RunState.sword_collected
	for child in items_root.get_children():
		if child is SwordPickup:
			child.visible = item_visible
			child.process_mode = Node.PROCESS_MODE_INHERIT if item_visible else Node.PROCESS_MODE_DISABLED


func _ensure_sword_pickup() -> void:
	if not RunState.is_unlocked(&"item") or RunState.sword_collected:
		return
	if items_root.get_child_count() > 0:
		return
	_spawn_sword_pickup(_random_field_position())


func _refresh_monsters() -> void:
	if monsters_root.get_child_count() > 0:
		return
	for offset in START_SLIME_OFFSETS:
		_spawn_slime_marker(hero.position + offset)
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
			_drop_gold_from_monster(monster)
		monster.queue_free()
	_encounter_locked = false


func _drop_gold_from_monster(monster: Node2D) -> void:
	var reward: int = 1
	if monster is SlimeMarker:
		reward = (monster as SlimeMarker).gold_reward()
	for i in range(reward):
		_spawn_gold_pickup(monster.position + _gold_drop_offset(i, reward))


func _gold_drop_offset(index: int, total: int) -> Vector2:
	if total <= 1:
		return Vector2.ZERO
	var angle: float = TAU * float(index) / float(total)
	return Vector2.from_angle(angle) * 12.0


func _spawn_gold_pickup(pos: Vector2) -> void:
	var pickup: GoldPickup = GOLD_PICKUP_SCENE.instantiate() as GoldPickup
	pickup.position = _clamp_to_field(pos)
	pickup.visible = RunState.is_unlocked(&"gold")
	pickup.process_mode = Node.PROCESS_MODE_INHERIT if pickup.visible else Node.PROCESS_MODE_DISABLED
	pickups_root.add_child(pickup)


func _spawn_sword_pickup(pos: Vector2) -> void:
	var pickup: SwordPickup = SWORD_PICKUP_SCENE.instantiate() as SwordPickup
	pickup.position = _clamp_to_field(pos)
	pickup.visible = RunState.is_unlocked(&"item") and not RunState.sword_collected
	pickup.process_mode = Node.PROCESS_MODE_INHERIT if pickup.visible else Node.PROCESS_MODE_DISABLED
	items_root.add_child(pickup)


func _try_monster_encounter() -> void:
	if _encounter_locked and not RunState.is_unlocked(&"multi_battle"):
		return
	for child in monsters_root.get_children():
		var monster: Node2D = child as Node2D
		if monster != null and monster.visible and monster.position.distance_to(hero.position) <= ENCOUNTER_RADIUS:
			_encounter_locked = true
			battle_requested.emit(monster)
			return


func _push_overlapping_monsters(delta: float) -> void:
	if RunState.is_unlocked(&"multi_battle"):
		return
	for target in hero.overlapping_body_targets():
		var monster: SlimeMarker = target as SlimeMarker
		if monster == null or not monster.visible:
			continue
		_set_question_monster(monster)
		monster.push_from(hero.position, MONSTER_PUSH_SPEED * delta, _field_bounds(RANDOM_DROP_MARGIN))


func _set_question_monster(monster: SlimeMarker) -> void:
	if _question_monster != null and is_instance_valid(_question_monster) and _question_monster != monster:
		_question_monster.set_question_visible(false)
	_question_monster = monster


func _process_monster_spawner(delta: float) -> void:
	if not RunState.is_unlocked(&"spawner"):
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


func _sync_depth_sort() -> void:
	hero.z_index = int(round(hero.position.y))
	for root in [pickups_root, items_root, monsters_root]:
		for child in (root as Node2D).get_children():
			var item: Node2D = child as Node2D
			if item != null:
				item.z_index = int(round(item.position.y))


func _on_skill_unlocked(skill_id: StringName) -> void:
	if skill_id == &"item":
		_refresh_item_pickups()
		_ensure_sword_pickup()
	elif skill_id == &"spawner":
		_reset_monster_spawn_timer()
