class_name UnfoldField
extends Node2D

signal battle_requested(monster: Node2D)

const SLIME_MARKER_SCENE: PackedScene = preload("res://scenes/entities/slime_marker.tscn")
const GOLD_PICKUP_SCENE: PackedScene = preload("res://scenes/entities/gold_pickup.tscn")
const SWORD_PICKUP_SCENE: PackedScene = preload("res://scenes/entities/sword_pickup.tscn")
const ARMOR_PICKUP_SCENE: PackedScene = preload("res://scenes/entities/armor_pickup.tscn")
const COMPANION_PICKUP_SCENE: PackedScene = preload("res://scenes/entities/companion_pickup.tscn")
const COMPANION_FOLLOWER_SCENE: PackedScene = preload("res://scenes/entities/companion_follower.tscn")
const EQUIPMENT_PICKUP_SCENE: PackedScene = preload("res://scenes/entities/equipment_pickup.tscn")
const TILE_SIZE: float = 16.0
const CONTINUOUS_MOVE_SPEED: float = 84.0
const ENCOUNTER_RADIUS: float = 14.0
const MONSTER_PUSH_SPEED: float = 54.0
const RANDOM_DROP_MARGIN: float = 18.0
const HERO_SAFE_RADIUS: float = 34.0
const MONSTER_SPAWN_INTERVAL: float = 3.0
const MAX_SPAWNED_MONSTERS: int = 4
const MAX_SPAWNED_MONSTERS_UPGRADED: int = 8
const PICKUP_RANGE_SCALE: float = 1.7
const RANDOM_GOLD_COUNT: int = 3
const GOLD_PER_KILL: int = 2
const GOLD_DROP_STAGGER: float = 0.08
const LOOT_DROP_STAGGER: float = 0.10
const LOOT_PER_KILL: int = 1
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
var _hero_velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	_rng.randomize()
	RunState.skill_unlocked.connect(_on_skill_unlocked)
	RunState.companion_recruited_signal.connect(_on_companion_recruited)
	_apply_map_size()
	_refresh_gold_pickups()
	_refresh_item_pickups()
	_ensure_random_gold_scatter()
	_ensure_companion_pickup()
	_ensure_companion_follower()
	_refresh_monsters()
	_sync_depth_sort()


func _apply_map_size() -> void:
	const BASE_SIZE: Vector2 = Vector2(192, 128)
	const PER_UNLOCK_GROWTH: Vector2 = Vector2(4, 3)
	const INITIAL_FREE_UNLOCKS: int = 2  # movement + auto_battle (cost 0)
	var bonus_unlocks: int = maxi(0, RunState.unlocked.size() - INITIAL_FREE_UNLOCKS)
	var size_bonus: Vector2 = PER_UNLOCK_GROWTH * bonus_unlocks
	var scale_factor: float = 1.5 if RunState.is_unlocked(&"map_expand") else 1.0
	var new_size: Vector2 = (BASE_SIZE + size_bonus) * scale_factor
	background.size = new_size
	# Keep field centered in 640×360 viewport as it grows.
	background.position = Vector2(
		(640.0 - new_size.x) * 0.5,
		(360.0 - new_size.y) * 0.5
	)


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
		_hero_velocity = Vector2.ZERO
		hero.set_moving(false)
		_try_pickups()
		_try_monster_encounter()
		return
	_hero_velocity = dir * CONTINUOUS_MOVE_SPEED
	hero.set_moving(true)
	hero.face(_dir_to_facing(dir))
	hero.position = _clamp_to_field(hero.position + dir * CONTINUOUS_MOVE_SPEED * delta)
	_try_pickups()
	_try_monster_encounter()


func get_hero_velocity() -> Vector2:
	return _hero_velocity


func _try_pickups() -> void:
	for pickup in hero.overlapping_pickups():
		if pickup is GoldPickup and RunState.is_unlocked(&"gold"):
			var gold_pos: Vector2 = (pickup as GoldPickup).position
			var amount: int = (pickup as GoldPickup).VALUE
			RunState.add_gold(amount)
			(pickup as GoldPickup).collect()
			_spawn_gold_popup(gold_pos, amount)
		elif pickup is EquipmentPickup:
			var ep: EquipmentPickup = pickup as EquipmentPickup
			var ep_pos: Vector2 = ep.position
			var ep_type: StringName = ep.loot_type
			var ep_tier_before: int = ep.tier
			var result: Dictionary = ep.collect()
			var final_tier: int = int(result.get("final_tier", ep_tier_before))
			var combined: bool = bool(result.get("combined", false))
			_spawn_loot_popup(ep_pos, ep_type, final_tier, combined)
		elif pickup is SwordPickup and RunState.is_unlocked(&"item") and not RunState.sword_collected:
			(pickup as SwordPickup).collect()
		elif pickup is ArmorPickup and RunState.is_unlocked(&"item") and not RunState.armor_collected:
			(pickup as ArmorPickup).collect()
		elif pickup is CompanionPickup and RunState.is_unlocked(&"companion") and not RunState.companion_recruited:
			(pickup as CompanionPickup).collect()


func _spawn_loot_popup(world_pos: Vector2, type: StringName, tier: int, combined: bool = false) -> void:
	var label: Label = Label.new()
	var type_name: String = EquipmentPickup.display_name_for_type(type)
	var text: String
	var font_size: int
	var start_scale: float
	var rise_distance: float
	if combined:
		var tier_name: String = RunState.LOOT_TIER_NAMES[clampi(tier, 0, RunState.LOOT_TIER_NAMES.size() - 1)]
		text = "✨ %s %s!" % [tier_name, type_name]
		font_size = 14
		start_scale = 1.7
		rise_distance = 22.0
	elif tier > 0:
		var tier_name: String = RunState.LOOT_TIER_NAMES[clampi(tier, 0, RunState.LOOT_TIER_NAMES.size() - 1)]
		text = "%s %s!" % [tier_name, type_name]
		font_size = 13
		start_scale = 1.5
		rise_distance = 19.0
	else:
		text = "+%s" % type_name
		font_size = 11
		start_scale = 1.3
		rise_distance = 16.0
	label.text = text
	var color: Color = EquipmentPickup.TIER_COLORS[clampi(tier, 0, EquipmentPickup.TIER_COLORS.size() - 1)]
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override(&"shadow_offset_x", 1)
	label.add_theme_constant_override(&"shadow_offset_y", 1)
	label.add_theme_font_size_override(&"font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 200
	label.position = world_pos + Vector2(-14, -14)
	add_child(label)

	label.scale = Vector2(start_scale, start_scale)
	var pop_tween: Tween = label.create_tween()
	pop_tween.tween_property(label, "scale", Vector2.ONE, 0.12)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)

	var move_tween: Tween = label.create_tween()
	move_tween.tween_property(label, "position:y", label.position.y - rise_distance, 0.6)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	move_tween.parallel().tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.3)
	move_tween.tween_callback(label.queue_free)


func _spawn_gold_popup(world_pos: Vector2, amount: int) -> void:
	var label: Label = Label.new()
	label.text = "+%d" % amount
	label.add_theme_color_override(&"font_color", Color(1.0, 0.82, 0.2, 1.0))
	label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override(&"shadow_offset_x", 1)
	label.add_theme_constant_override(&"shadow_offset_y", 1)
	label.add_theme_font_size_override(&"font_size", 12)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 200
	label.position = world_pos + Vector2(-6, -14)
	add_child(label)

	label.scale = Vector2(1.4, 1.4)
	var pop_tween: Tween = label.create_tween()
	pop_tween.tween_property(label, "scale", Vector2.ONE, 0.10)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)

	var move_tween: Tween = label.create_tween()
	move_tween.tween_property(label, "position:y", label.position.y - 16.0, 0.55)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	move_tween.parallel().tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.25)
	move_tween.tween_callback(label.queue_free)


func _max_monsters() -> int:
	if RunState.is_unlocked(&"max_enemies_2"):
		return 16
	if RunState.is_unlocked(&"max_enemies"):
		return MAX_SPAWNED_MONSTERS_UPGRADED
	return MAX_SPAWNED_MONSTERS


func _spawn_interval() -> float:
	if RunState.is_unlocked(&"spawner_fast"):
		return MONSTER_SPAWN_INTERVAL * 0.5
	return MONSTER_SPAWN_INTERVAL


func _spawn_burst_count() -> int:
	return 2 if RunState.is_unlocked(&"spawner_burst") else 1


func _refresh_gold_pickups() -> void:
	var gold_visible: bool = RunState.is_unlocked(&"gold")
	for child in pickups_root.get_children():
		if child is GoldPickup:
			child.visible = gold_visible
			child.process_mode = Node.PROCESS_MODE_INHERIT if gold_visible else Node.PROCESS_MODE_DISABLED
			_apply_pickup_area_scale(child as Node2D)


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
		_apply_pickup_area_scale(child as Node2D)


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
	if RunState.is_unlocked(&"more_slimes_2"):
		for _i in range(2):
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
		if defeated and kills > 0:
			if RunState.is_unlocked(&"gold"):
				_drop_gold_from_kills(monster.position, kills)
			if RunState.is_unlocked(&"item"):
				_drop_loot_from_kills(monster.position, kills)
		monster.queue_free()
	_encounter_locked = false


func _drop_gold_from_kills(origin: Vector2, kills: int) -> void:
	var total: int = kills * GOLD_PER_KILL
	_drop_gold_staggered(origin, total)


func _drop_loot_from_kills(origin: Vector2, kills: int) -> void:
	var total: int = kills * LOOT_PER_KILL
	_drop_loot_staggered(origin, total)


func _drop_loot_staggered(origin: Vector2, total: int) -> void:
	for i in range(total):
		var type: StringName = EquipmentPickup.ALL_TYPES[_rng.randi() % EquipmentPickup.ALL_TYPES.size()]
		var tier: int = _roll_drop_tier()
		_spawn_equipment_pickup(origin + _loot_drop_offset(i, total), type, tier)
		if i < total - 1:
			await get_tree().create_timer(LOOT_DROP_STAGGER).timeout


func _roll_drop_tier() -> int:
	var tier: int = 0
	if RunState.is_unlocked(&"drop_uncommon") and _rng.randf() < 0.60:
		tier = 1
		if RunState.is_unlocked(&"drop_rare") and _rng.randf() < 0.40:
			tier = 2
			if RunState.is_unlocked(&"drop_epic") and _rng.randf() < 0.30:
				tier = 3
				if RunState.is_unlocked(&"drop_legendary") and _rng.randf() < 0.20:
					tier = 4
	return tier


func _loot_drop_offset(index: int, total: int) -> Vector2:
	var radius: float = 24.0
	if total <= 1:
		var single_angle: float = _rng.randf_range(PI * 0.25, PI * 0.75)
		return Vector2.from_angle(single_angle) * radius
	var angle: float = TAU * float(index) / float(total) + PI * 0.5
	return Vector2.from_angle(angle) * radius


func _spawn_equipment_pickup(pos: Vector2, type: StringName, tier: int) -> void:
	var pickup: EquipmentPickup = EQUIPMENT_PICKUP_SCENE.instantiate() as EquipmentPickup
	pickup.position = _clamp_to_field(pos)
	pickup.setup(type, tier)
	pickup.scale = Vector2.ZERO
	pickups_root.add_child(pickup)
	_apply_pickup_area_scale(pickup)
	var tween: Tween = pickup.create_tween()
	tween.tween_property(pickup, "scale", Vector2(1.3, 1.3), 0.10)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(pickup, "scale", Vector2.ONE, 0.08)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)


func _drop_gold_staggered(origin: Vector2, total: int) -> void:
	for i in range(total):
		_spawn_gold_pickup(origin + _gold_drop_offset(i, total))
		if i < total - 1:
			await get_tree().create_timer(GOLD_DROP_STAGGER).timeout


func _gold_drop_offset(index: int, total: int) -> Vector2:
	var radius: float = 22.0
	if total <= 1:
		var single_angle: float = _rng.randf_range(0.0, TAU)
		return Vector2.from_angle(single_angle) * radius
	var angle: float = TAU * float(index) / float(total)
	return Vector2.from_angle(angle) * radius


func _spawn_gold_pickup(pos: Vector2) -> void:
	var pickup: GoldPickup = GOLD_PICKUP_SCENE.instantiate() as GoldPickup
	pickup.position = _clamp_to_field(pos)
	pickup.visible = RunState.is_unlocked(&"gold")
	pickup.process_mode = Node.PROCESS_MODE_INHERIT if pickup.visible else Node.PROCESS_MODE_DISABLED
	pickup.scale = Vector2.ZERO
	pickups_root.add_child(pickup)
	_apply_pickup_area_scale(pickup)
	var tween: Tween = pickup.create_tween()
	tween.tween_property(pickup, "scale", Vector2(1.3, 1.3), 0.10)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(pickup, "scale", Vector2.ONE, 0.08)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)


func _spawn_sword_pickup(pos: Vector2) -> void:
	var pickup: SwordPickup = SWORD_PICKUP_SCENE.instantiate() as SwordPickup
	pickup.position = _clamp_to_field(pos)
	pickup.visible = RunState.is_unlocked(&"item") and not RunState.sword_collected
	pickup.process_mode = Node.PROCESS_MODE_INHERIT if pickup.visible else Node.PROCESS_MODE_DISABLED
	items_root.add_child(pickup)
	_apply_pickup_area_scale(pickup)


func _spawn_armor_pickup(pos: Vector2) -> void:
	var pickup: ArmorPickup = ARMOR_PICKUP_SCENE.instantiate() as ArmorPickup
	pickup.position = _clamp_to_field(pos)
	pickup.visible = RunState.is_unlocked(&"item") and not RunState.armor_collected
	pickup.process_mode = Node.PROCESS_MODE_INHERIT if pickup.visible else Node.PROCESS_MODE_DISABLED
	items_root.add_child(pickup)
	_apply_pickup_area_scale(pickup)


func _spawn_companion_pickup(pos: Vector2) -> void:
	var pickup: CompanionPickup = COMPANION_PICKUP_SCENE.instantiate() as CompanionPickup
	pickup.position = _clamp_to_field(pos)
	pickup.setup_random()
	pickup.visible = RunState.is_unlocked(&"companion") and not RunState.companion_recruited
	pickup.process_mode = Node.PROCESS_MODE_INHERIT if pickup.visible else Node.PROCESS_MODE_DISABLED
	items_root.add_child(pickup)
	_apply_pickup_area_scale(pickup)


func _apply_pickup_area_scale(pickup: Node2D) -> void:
	var shape: CollisionShape2D = pickup.get_node_or_null("PickupArea/PickupShape") as CollisionShape2D
	if shape == null:
		return
	shape.scale = Vector2.ONE * (PICKUP_RANGE_SCALE if RunState.is_unlocked(&"pickup_range") else 1.0)


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
	var burst: int = _spawn_burst_count()
	for _i in range(burst):
		if monsters_root.get_child_count() >= _max_monsters():
			break
		_spawn_slime_marker(_random_field_position())
	_reset_monster_spawn_timer()


func _reset_monster_spawn_timer() -> void:
	_monster_spawn_timer = _spawn_interval()


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
	elif skill_id == &"companion":
		_refresh_item_pickups()
		_ensure_companion_pickup()
	elif skill_id == &"pickup_range":
		_refresh_gold_pickups()
		_refresh_item_pickups()
	elif skill_id == &"spawner":
		_reset_monster_spawn_timer()


func _on_companion_recruited(_type: StringName) -> void:
	_refresh_item_pickups()
	_ensure_companion_follower()
