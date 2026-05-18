class_name UnfoldField
extends Node2D

signal battle_requested(monster: Node2D)

const SLIME_MARKER_SCENE: PackedScene = preload("res://scenes/entities/slime_marker.tscn")
const GOLD_PICKUP_SCENE: PackedScene = preload("res://scenes/entities/gold_pickup.tscn")
const SWORD_PICKUP_SCENE: PackedScene = preload("res://scenes/entities/sword_pickup.tscn")
const ARMOR_PICKUP_SCENE: PackedScene = preload("res://scenes/entities/armor_pickup.tscn")
const COMPANION_PICKUP_SCENE: PackedScene = preload("res://scenes/entities/companion_pickup.tscn")
const COMPANION_FOLLOWER_SCENE: PackedScene = preload("res://scenes/entities/companion_follower.tscn")
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
const MAX_SPAWNED_MONSTERS_UPGRADED: int = 8
const PICKUP_RANGE_MULTIPLIER: float = 1.7
const RANDOM_GOLD_COUNT: int = 3
const GOLD_PER_KILL: int = 2
const START_SLIME_COUNT: int = 2
const START_SLIME_COUNT_EXTRA: int = 2

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
	RunState.companion_recruited_signal.connect(_on_companion_recruited)
	_refresh_gold_pickups()
	_refresh_item_pickups()
	_ensure_random_gold_scatter()
	_ensure_sword_pickup()
	_ensure_armor_pickup()
	_ensure_companion_pickup()
	_ensure_companion_follower()
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
	var radius: float = _pickup_radius()
	for child in pickups_root.get_children():
		if child is GoldPickup and child.position.distance_to(hero.position) <= radius:
			RunState.add_gold(child.VALUE)
			child.collect()


func _try_item_pickup() -> void:
	var radius: float = _item_pickup_radius()
	for child in items_root.get_children():
		var node: Node2D = child as Node2D
		if node == null:
			continue
		if node.position.distance_to(hero.position) > radius:
			continue
		if child is SwordPickup and RunState.is_unlocked(&"item") and not RunState.sword_collected:
			(child as SwordPickup).collect()
		elif child is ArmorPickup and RunState.is_unlocked(&"item") and not RunState.armor_collected:
			(child as ArmorPickup).collect()
		elif child is CompanionPickup and RunState.is_unlocked(&"companion") and not RunState.companion_recruited:
			(child as CompanionPickup).collect()


func _pickup_radius() -> float:
	if RunState.is_unlocked(&"pickup_range"):
		return PICKUP_RADIUS * PICKUP_RANGE_MULTIPLIER
	return PICKUP_RADIUS


func _item_pickup_radius() -> float:
	if RunState.is_unlocked(&"pickup_range"):
		return ITEM_PICKUP_RADIUS * PICKUP_RANGE_MULTIPLIER
	return ITEM_PICKUP_RADIUS


func _max_monsters() -> int:
	if RunState.is_unlocked(&"max_enemies"):
		return MAX_SPAWNED_MONSTERS_UPGRADED
	return MAX_SPAWNED_MONSTERS


func _refresh_gold_pickups() -> void:
	var gold_visible: bool = RunState.is_unlocked(&"gold")
	for child in pickups_root.get_children():
		if child is GoldPickup:
			child.visible = gold_visible
			child.process_mode = Node.PROCESS_MODE_INHERIT if gold_visible else Node.PROCESS_MODE_DISABLED


func _refresh_item_pickups() -> void:
	var sword_visible: bool = RunState.is_unlocked(&"item") and not RunState.sword_collected
	var armor_visible: bool = RunState.is_unlocked(&"item") and not RunState.armor_collected
	var companion_visible: bool = RunState.is_unlocked(&"companion") and not RunState.companion_recruited
	for child in items_root.get_children():
		if child is SwordPickup:
			child.visible = sword_visible
			child.process_mode = Node.PROCESS_MODE_INHERIT if sword_visible else Node.PROCESS_MODE_DISABLED
		elif child is ArmorPickup:
			child.visible = armor_visible
			child.process_mode = Node.PROCESS_MODE_INHERIT if armor_visible else Node.PROCESS_MODE_DISABLED
		elif child is CompanionPickup:
			child.visible = companion_visible
			child.process_mode = Node.PROCESS_MODE_INHERIT if companion_visible else Node.PROCESS_MODE_DISABLED


func _ensure_sword_pickup() -> void:
	if not RunState.is_unlocked(&"item") or RunState.sword_collected:
		return
	for child in items_root.get_children():
		if child is SwordPickup:
			return
	_spawn_sword_pickup(_random_field_position())


func _ensure_armor_pickup() -> void:
	if not RunState.is_unlocked(&"item") or RunState.armor_collected:
		return
	for child in items_root.get_children():
		if child is ArmorPickup:
			return
	_spawn_armor_pickup(_random_field_position())


func _ensure_random_gold_scatter() -> void:
	if not RunState.is_unlocked(&"gold"):
		return
	for child in pickups_root.get_children():
		if child is GoldPickup:
			return
	for i in range(RANDOM_GOLD_COUNT):
		_spawn_gold_pickup(_random_field_position())


func _ensure_companion_pickup() -> void:
	if not RunState.is_unlocked(&"companion") or RunState.companion_recruited:
		return
	for child in items_root.get_children():
		if child is CompanionPickup:
			return
	_spawn_companion_pickup(_random_field_position())


func _ensure_companion_follower() -> void:
	if not RunState.companion_recruited:
		return
	var existing: Array[CompanionFollower] = _get_followers()
	if existing.size() >= 1:
		return
	var target: Node2D = hero
	if not existing.is_empty():
		target = existing.back()
	var follower: CompanionFollower = COMPANION_FOLLOWER_SCENE.instantiate() as CompanionFollower
	follower.set_companion_type(RunState.companion_type)
	add_child(follower)
	follower.bind_target(target)


func _get_followers() -> Array[CompanionFollower]:
	var followers: Array[CompanionFollower] = []
	for child in get_children():
		if child is CompanionFollower:
			followers.append(child as CompanionFollower)
	return followers


func _refresh_monsters() -> void:
	if monsters_root.get_child_count() > 0:
		return
	for _i in range(START_SLIME_COUNT):
		_spawn_slime_marker(_random_field_position())
	if RunState.is_unlocked(&"more_slimes"):
		for _i in range(START_SLIME_COUNT_EXTRA):
			_spawn_slime_marker(_random_field_position())
	_reset_monster_spawn_timer()


func _spawn_slime_marker(pos: Vector2) -> void:
	var slime: Node2D = SLIME_MARKER_SCENE.instantiate() as Node2D
	slime.position = pos
	monsters_root.add_child(slime)
	if slime is SlimeMarker:
		var sm: SlimeMarker = slime as SlimeMarker
		sm.setup_wander(_field_bounds(RANDOM_DROP_MARGIN))
		sm.set_chase_target(hero)
	if not _is_input_enabled:
		slime.set_process(false)


func finish_battle(monster: Node2D, defeated: bool, kills: int = 0) -> void:
	if is_instance_valid(monster):
		if defeated and RunState.is_unlocked(&"gold") and kills > 0:
			_drop_gold_from_kills(monster.position, kills)
		monster.queue_free()
	_encounter_locked = false


func _drop_gold_from_kills(origin: Vector2, kills: int) -> void:
	var total: int = kills * GOLD_PER_KILL
	for i in range(total):
		_spawn_gold_pickup(origin + _gold_drop_offset(i, total))


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


func _spawn_armor_pickup(pos: Vector2) -> void:
	var pickup: ArmorPickup = ARMOR_PICKUP_SCENE.instantiate() as ArmorPickup
	pickup.position = _clamp_to_field(pos)
	pickup.visible = RunState.is_unlocked(&"item") and not RunState.armor_collected
	pickup.process_mode = Node.PROCESS_MODE_INHERIT if pickup.visible else Node.PROCESS_MODE_DISABLED
	items_root.add_child(pickup)


func _spawn_companion_pickup(pos: Vector2) -> void:
	var pickup: CompanionPickup = COMPANION_PICKUP_SCENE.instantiate() as CompanionPickup
	pickup.position = _clamp_to_field(pos)
	pickup.setup_random()
	pickup.visible = RunState.is_unlocked(&"companion") and not RunState.companion_recruited
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
	if monsters_root.get_child_count() >= _max_monsters():
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
	if skill_id == &"gold":
		_refresh_gold_pickups()
		_ensure_random_gold_scatter()
	elif skill_id == &"item":
		_refresh_item_pickups()
		_ensure_sword_pickup()
		_ensure_armor_pickup()
	elif skill_id == &"companion":
		_refresh_item_pickups()
		_ensure_companion_pickup()
	elif skill_id == &"spawner":
		_reset_monster_spawn_timer()


func _on_companion_recruited(_type: StringName) -> void:
	_refresh_item_pickups()
	_ensure_companion_follower()
