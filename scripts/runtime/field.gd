class_name Field
extends Node2D

## Top-down stage. Spawns enemies + the visible party (player leading,
## companions trailing). Player movement lives on the Player node;
## encounters fire EventBus signals.

const FIELD_ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/field_enemy.tscn")
const FIELD_DECORATION_SCENE: PackedScene = preload("res://scenes/decorations/field_decoration.tscn")
const FIELD_TREASURE_CHEST_SCENE: PackedScene = preload("res://scenes/objects/field_treasure_chest.tscn")
const FIELD_ITEM_DROP_SCENE: PackedScene = preload("res://scenes/objects/field_item_drop.tscn")
const FIELD_RECOVERY_ORB_SCENE: PackedScene = preload("res://scenes/objects/field_recovery_orb.tscn")
const FIELD_CAMPFIRE_SCENE: PackedScene = preload("res://scenes/objects/field_campfire.tscn")
const FIELD_SHRINE_SCENE: PackedScene = preload("res://scenes/objects/field_shrine.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const COMPANION_SCENE: PackedScene = preload("res://scenes/companion.tscn")
const SLIME_DATA: EnemyData = preload("res://data/enemies/slime.tres")
const TREE_TEXTURE: Texture2D = preload("res://assets/sprites/decorations/tree.png")

## Fixed world-map size for every field.
const FIELD_SIZE: Vector2 = Vector2(720, 405)
const TILE_SIZE: int = 16

## Field unfolds from a tight opening frame into a sprawl gradually.
## Keep the per-stage step small so stage 2 feels like a nudge, not a genre
## change.
const FIELD_SIZE_START: Vector2 = Vector2(480, 270)
const FIELD_SIZE_END: Vector2 = Vector2(1200, 675)
const FIELD_SIZE_STAGE_STEP: Vector2 = Vector2(45, 25.3125)
const SPAWN_MARGIN: float = 48.0
## Don't drop slimes within this radius of the player on stage start.
const PARTY_SAFE_RADIUS: float = 80.0
const DECOR_SAFE_RADIUS: float = 104.0
const TOWN_TILE_SAFE_RADIUS: float = 96.0
const TOWN_TILE_INSET: Vector2 = Vector2(96, 72)
const BASE_FIELD_AREA: float = FIELD_SIZE.x * FIELD_SIZE.y

@export var peaceful_start_enemies: int = 3
@export var enemies_added_per_field_area: float = 1.4
@export var small_forest_cluster_count_min: int = 3
@export var small_forest_cluster_count_max: int = 5
@export var small_forest_min_trees: int = 8
@export var small_forest_max_trees: int = 16
@export var large_forest_cluster_count_min: int = 1
@export var large_forest_cluster_count_max: int = 2
@export var large_forest_min_trees: int = 100
@export var large_forest_max_trees: int = 200
@export var scattered_tree_count: int = 8
@export var spawn_interval: float = 2.5
@export var spawn_batch_size: int = 1
@export var entry_burst_bonus: int = 0
@export var crowd_growth_per_wave: int = 1
@export var max_crowd_pressure: int = 4

## ─── Continuous time-based field intensity ──────────────────────────
## The field gets meaner over the 30-minute target, but early stages should
## climb in small, readable steps.
const SPAWN_INTERVAL_START: float = 3.2
const SPAWN_INTERVAL_END: float = 1.25
const ENEMY_CAP_TIME_BONUS_END: int = 12
const STAGE_DURATION_START: float = 25.0
const STAGE_DURATION_END: float = 75.0
const STAGE_DURATION_STEP: float = 5.0
## Town tiles are disabled while the Brotato-style wave timer drives town
## visits. Flip this true if we want walk-in town tiles back later.
const TOWN_TILE_ENABLED: bool = false
@export var treasure_kills_required_base: int = 3
@export var treasure_kills_required_stage_step: int = 1
@export var treasure_gold_base: int = 45
@export var treasure_gold_per_stage: int = 15

@onready var _background: ColorRect = $Background
@onready var _decorations_root: Node2D = $Decorations
@onready var _town_tile: FieldTownTile = $Tiles/TownTile
@onready var _treasures_root: Node2D = $Treasures
@onready var _items_root: Node2D = $Items
@onready var _enemies_root: Node2D = $Enemies
@onready var _party_root: Node2D = $Party

var _player: Player
var _decor_rng := RandomNumberGenerator.new()
var _forest_cells: Dictionary = {}
var _spawn_timer: float = 0.0
var _stage_duration: float = STAGE_DURATION_START
var _stage_time_left: float = STAGE_DURATION_START
var _crowd_pressure: int = 0
var _field_size: Vector2 = FIELD_SIZE
var _town_revealed: bool = false
var _treasure_kills: int = 0
var _treasure_spawned: bool = false
var _stage_complete: bool = false


func _ready() -> void:
	EventBus.party_changed.connect(_setup_party_visuals)
	EventBus.all_battles_resolved.connect(_check_stage_clear)
	EventBus.stage_started.connect(_on_stage_started)
	EventBus.enemy_defeated.connect(_on_enemy_defeated)
	EventBus.field_item_drop_requested.connect(_on_field_item_drop_requested)
	EventBus.field_recovery_orb_requested.connect(_on_field_recovery_orb_requested)
	# Surface the town tile to a group so HUD-side widgets (compass arrow,
	# distance readout) can find it without poking through the scene tree.
	if is_instance_valid(_town_tile):
		_town_tile.add_to_group("town_tile")
	# HUD reads timer/bounds helpers off this group without poking through
	# the scene tree.
	add_to_group("field_root")
	# Town respawn cycle — once the party leaves a town, the tile vanishes
	# and a new one fades in elsewhere 30s later.
	EventBus.town_closed.connect(_on_town_closed)
	_build_town_respawn_timer()
	# Cover the case where party was already set before this scene mounted.
	_setup_party_visuals()


func field_world_bounds() -> Rect2:
	return Rect2(global_position, _field_size)


func stage_time_left() -> float:
	return maxf(_stage_time_left, 0.0)


func stage_duration() -> float:
	return _stage_duration


## Town respawn: when the party walks out of town, hide the current tile
## and start a one-shot timer. When it fires, the tile pops back in at a
## random corner that's far from the party's current position.
const TOWN_RESPAWN_DELAY: float = 30.0
## First-ever town spawn at the start of a run is faster so the player
## sees the destination/mechanic quickly.
const FIRST_TOWN_DELAY: float = 10.0
const TOWN_RESPAWN_MIN_DISTANCE: float = 220.0
var _town_respawn_timer: Timer


func _build_town_respawn_timer() -> void:
	_town_respawn_timer = Timer.new()
	_town_respawn_timer.one_shot = true
	_town_respawn_timer.wait_time = TOWN_RESPAWN_DELAY
	_town_respawn_timer.timeout.connect(_spawn_town_tile_elsewhere)
	add_child(_town_respawn_timer)


func _on_town_closed() -> void:
	if not TOWN_TILE_ENABLED:
		return
	if not is_instance_valid(_town_tile):
		return
	# Consume the used tile: hide + clear its trigger flag so the next
	# reveal is fresh. The player ends up standing where the tile was.
	_town_revealed = false
	_town_tile.reset()
	_town_respawn_timer.start(TOWN_RESPAWN_DELAY)


## Seconds until the next town tile reveals. Used by the HUD countdown.
## Returns 0 when the timer isn't running (town is currently on the map).
func town_respawn_seconds_left() -> float:
	if not is_instance_valid(_town_respawn_timer):
		return 0.0
	if _town_respawn_timer.is_stopped():
		return 0.0
	return _town_respawn_timer.time_left


## Picks the corner farthest from the party (with a minimum-distance
## guard) so the player has to actually travel to the next town instead
## of bumping into it immediately.
func _spawn_town_tile_elsewhere() -> void:
	if not is_instance_valid(_town_tile):
		return
	var anchor: Vector2 = _player.global_position if is_instance_valid(_player) else _field_size * 0.5
	var candidates: Array[Vector2] = [
		TOWN_TILE_INSET,
		Vector2(_field_size.x - TOWN_TILE_INSET.x, TOWN_TILE_INSET.y),
		Vector2(TOWN_TILE_INSET.x, _field_size.y - TOWN_TILE_INSET.y),
		_field_size - TOWN_TILE_INSET,
	]
	candidates.shuffle()
	var picked: Vector2 = candidates[0]
	var best_distance: float = picked.distance_to(anchor)
	for candidate in candidates:
		var d: float = candidate.distance_to(anchor)
		if d >= TOWN_RESPAWN_MIN_DISTANCE:
			picked = candidate
			break
		if d > best_distance:
			picked = candidate
			best_distance = d
	_town_revealed = true
	_town_tile.position = picked
	_town_tile.reveal_with_impact()


func _process(delta: float) -> void:
	if GameState.current_stage <= 0 or GameState.is_party_wiped():
		return
	if _stage_complete:
		return
	_stage_time_left = maxf(0.0, _stage_time_left - delta)
	if _stage_time_left <= 0.0:
		_complete_stage_by_timer()
		return
	if GameState.current_stage <= 1:
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	# Cadence tightens with run intensity — spawns come fast at 30 min in.
	_spawn_timer = _current_spawn_interval()
	_grow_crowd_pressure()
	_refill_enemy_population(spawn_batch_size)


## Lerp from the gentle opening interval down to the late-run pressure
## cadence. Mirrors GameState.run_intensity() so spawn rate and enemy
## stats grow on the same clock.
func _current_spawn_interval() -> float:
	var t: float = clampf(GameState.run_intensity(), 0.0, 1.0)
	return lerpf(SPAWN_INTERVAL_START, SPAWN_INTERVAL_END, t)


func _complete_stage_by_timer() -> void:
	if _stage_complete:
		return
	_stage_complete = true
	_spawn_timer = 0.0
	EventBus.stage_cleared.emit(GameState.current_stage)


# ─── Party visuals (data-driven) ──────────────────────────────────────
## Rebuilds the visible party from GameState.party. Slot 0 = player avatar,
## slots 1..N = companions trailing each previous member like a JRPG snake.
## Mid-run recruits preserve everyone's current world position so the hero
## doesn't teleport back to spawn — the new companion just falls in at the
## tail of the trail.
func _setup_party_visuals() -> void:
	# Snapshot existing world positions so a recruit doesn't yank everyone
	# back to the field center. Index 0 = player, then companions in order.
	var cached_positions: Array[Vector2] = []
	if _player and is_instance_valid(_player):
		cached_positions.append(_player.position)
	for child in _party_root.get_children():
		if child is Companion:
			cached_positions.append((child as Node2D).position)
		child.queue_free()
	_player = null
	if GameState.party_size() == 0:
		return
	_player = PLAYER_SCENE.instantiate()
	_player.setup(GameState.party[0])
	# Restore the hero where they were standing; fresh runs start at center.
	# Done before add_child so the first frame renders at the right spot.
	if cached_positions.size() > 0:
		_player.position = cached_positions[0]
	else:
		_player.position = _field_size * 0.5
	_party_root.add_child(_player)
	# Field bounds (camera limits) MUST be applied after add_child — the
	# Camera2D ref is @onready, so it's null until the player enters the
	# tree. Player.tscn ships with default 640×480 limits; if we skip this
	# the camera freezes against those defaults instead of the real field.
	if _player.has_method("set_field_bounds"):
		_player.set_field_bounds(Vector2.ZERO, _field_size)
	var leader: Node2D = _player
	for i in range(1, GameState.party_size()):
		var comp: Companion = COMPANION_SCENE.instantiate()
		comp.setup(GameState.party[i])
		comp.leader = leader
		var is_new_recruit: bool = i >= cached_positions.size()
		if is_new_recruit:
			# Brand-new recruit — drop them on the current tail so they
			# naturally trail behind the player on the very next step.
			comp.position = leader.position
		else:
			# Existing companion — keep them right where they were.
			comp.position = cached_positions[i]
		_party_root.add_child(comp)
		if is_new_recruit:
			_play_recruit_pop(comp)
		leader = comp


## Springy scale-in for a freshly recruited companion. Mirrors the HUD
## recruit toast (TRANS_BACK overshoot) so the field-side and HUD-side
## reactions feel like one beat.
func _play_recruit_pop(comp: Node2D) -> void:
	comp.scale = Vector2(0.2, 0.2)
	comp.modulate.a = 0.0
	var pop: Tween = comp.create_tween()
	pop.set_parallel(true)
	pop.tween_property(comp, "scale", Vector2.ONE, 0.38)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	pop.tween_property(comp, "modulate:a", 1.0, 0.2)


# ─── Enemy spawning ───────────────────────────────────────────────────
func _on_stage_started(_stage_num: int) -> void:
	_decor_rng.randomize()
	_apply_stage_field_size(_stage_num)
	_stage_duration = _stage_duration_for(_stage_num)
	_stage_time_left = _stage_duration
	_treasure_kills = 0
	_treasure_spawned = false
	_stage_complete = false
	_clear_field_enemies()
	_clear_decorations()
	_clear_treasures()
	_clear_items()
	_crowd_pressure = entry_burst_bonus
	_town_revealed = false
	_town_tile.reset()
	_recenter_party()
	_scatter_decorations()
	_spawn_timer = _current_spawn_interval()
	_refill_enemy_population(_desired_enemy_count())
	# Town tiles are gated by TOWN_TILE_ENABLED while we test the pure
	# 30-min run loop. When false, the tile stays at its off-screen park
	# position forever and the HUD countdown stays at zero.
	if TOWN_TILE_ENABLED:
		_town_respawn_timer.start(FIRST_TOWN_DELAY)
	_spawn_unlocked_recruit_events()


func _stage_duration_for(stage_num: int) -> float:
	var stage_index: int = maxi(0, stage_num - 1)
	return minf(STAGE_DURATION_END, STAGE_DURATION_START + float(stage_index) * STAGE_DURATION_STEP)


## Picks a sensible spawn slot for an event tile (campfire, shrine, …) —
## somewhere on the map that isn't right next to the player or buried
## inside town/decoration guard zones. Single-shot per run.
func _spawn_event_tile(scene: PackedScene) -> void:
	if scene == null:
		return
	var party_anchor: Vector2 = _player.global_position if is_instance_valid(_player) else _field_size * 0.5
	var spawn_pos: Vector2 = _random_safe_position(party_anchor)
	var tile := scene.instantiate()
	tile.position = spawn_pos
	_decorations_root.add_child(tile)


func _spawn_unlocked_recruit_events() -> void:
	if GameState.is_system_unlocked(GameState.SYSTEM_MAGE_EVENT) and not GameState.has_party_member(&"mage"):
		_spawn_event_tile(FIELD_CAMPFIRE_SCENE)
	if GameState.is_system_unlocked(GameState.SYSTEM_PRIEST_EVENT) and not GameState.has_party_member(&"priest"):
		_spawn_event_tile(FIELD_SHRINE_SCENE)


## Teleport the whole party back to the field center for a fresh start.
## Without this, party would drift further and further from spawn each stage.
func _recenter_party() -> void:
	if _player == null:
		return
	var center: Vector2 = _field_size * 0.5
	if _player.has_method("set_field_bounds"):
		_player.set_field_bounds(Vector2.ZERO, _field_size)
	_player.position = center
	# Reset camera smoothing so it doesn't pan from the old spot.
	if _player.has_method("snap_camera"):
		_player.snap_camera()
	for child in _party_root.get_children():
		if child is Companion:
			child.position = center


func _clear_field_enemies() -> void:
	for child in _enemies_root.get_children():
		child.queue_free()


func _despawn_field_enemies() -> void:
	for child in _enemies_root.get_children():
		if child is FieldEnemy:
			(child as FieldEnemy).despawn_with_pop()
		else:
			child.queue_free()


func _clear_decorations() -> void:
	_forest_cells.clear()
	for child in _decorations_root.get_children():
		child.queue_free()


func _clear_treasures() -> void:
	for child in _treasures_root.get_children():
		child.queue_free()


func _clear_items() -> void:
	for child in _items_root.get_children():
		child.queue_free()


func _scatter_decorations() -> void:
	if not GameState.is_system_unlocked(GameState.SYSTEM_FOREST):
		return
	var safe_origin: Vector2 = _player.position if _player else _field_size * 0.5
	var occupied: Dictionary = {}
	var large_count: int = _decor_range(large_forest_cluster_count_min, large_forest_cluster_count_max)
	for i in large_count:
		_add_forest_cluster(
			safe_origin,
			occupied,
			large_forest_min_trees,
			large_forest_max_trees,
			7,
			10
		)
	var small_count: int = _decor_range(small_forest_cluster_count_min, small_forest_cluster_count_max)
	for i in small_count:
		_add_forest_cluster(
			safe_origin,
			occupied,
			small_forest_min_trees,
			small_forest_max_trees,
			2,
			4
		)
	for i in scattered_tree_count:
		var cell: Vector2i = _random_decor_cell(safe_origin, occupied)
		if cell == Vector2i(-1, -1):
			return
		_add_tree_cell(cell, occupied)


func _add_decoration(texture: Texture2D, pos: Vector2) -> void:
	var sprite := FIELD_DECORATION_SCENE.instantiate() as Sprite2D
	sprite.texture = texture
	sprite.position = pos
	sprite.scale = Vector2.ONE
	_decorations_root.add_child(sprite)


func _add_forest_cluster(
	avoid: Vector2,
	occupied: Dictionary,
	min_trees: int,
	max_trees: int,
	min_radius: int,
	max_radius: int
) -> void:
	var center: Vector2i = _random_decor_cell(avoid, occupied)
	if center == Vector2i(-1, -1):
		return
	var target_count: int = _decor_range(min_trees, max_trees)
	var radius: int = _decor_range(min_radius, max_radius)
	var cluster: Array[Vector2i] = [center]
	var cluster_set: Dictionary = { center: true }
	var attempts: int = target_count * 28
	while cluster.size() < target_count and attempts > 0:
		attempts -= 1
		var anchor: Vector2i = cluster[_decor_rng.randi_range(0, cluster.size() - 1)]
		var candidate: Vector2i = anchor + _random_forest_step()
		if cluster_set.has(candidate):
			continue
		if not _is_valid_decor_cell(candidate, avoid, occupied):
			continue
		var offset := Vector2(candidate - center)
		var distance: float = offset.length()
		var soft_radius: float = float(radius) + _decor_rng.randf_range(-0.8, 1.15)
		if distance > soft_radius:
			continue
		var keep_chance: float = clampf(1.08 - (distance / maxf(float(radius), 1.0)) * 0.58, 0.38, 0.96)
		if _decor_rng.randf() > keep_chance:
			continue
		cluster.append(candidate)
		cluster_set[candidate] = true
	for cell in cluster:
		_add_tree_cell(cell, occupied, true)


func _random_forest_step() -> Vector2i:
	var steps: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i(1, 1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(-1, -1),
	]
	return steps[_decor_rng.randi_range(0, steps.size() - 1)]


func _decor_range(min_value: int, max_value: int) -> int:
	return _decor_rng.randi_range(mini(min_value, max_value), maxi(min_value, max_value))


func _add_tree_cell(cell: Vector2i, occupied: Dictionary, is_forest: bool = false) -> void:
	occupied[cell] = true
	if is_forest:
		_forest_cells[cell] = true
	_add_decoration(TREE_TEXTURE, _cell_to_world(cell))


func _random_decor_cell(avoid: Vector2, occupied: Dictionary) -> Vector2i:
	for attempt in 80:
		var cell := Vector2i(
			_decor_rng.randi_range(_min_grid_index(), _max_grid_x()),
			_decor_rng.randi_range(_min_grid_index(), _max_grid_y())
		)
		if _is_valid_decor_cell(cell, avoid, occupied):
			return cell
	return Vector2i(-1, -1)


func _is_valid_decor_cell(cell: Vector2i, avoid: Vector2, occupied: Dictionary) -> bool:
	if occupied.has(cell):
		return false
	var pos: Vector2 = _cell_to_world(cell)
	return pos.distance_to(avoid) >= DECOR_SAFE_RADIUS and not _is_near_town_tile(pos)


func _cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE_SIZE + TILE_SIZE * 0.5, cell.y * TILE_SIZE + TILE_SIZE * 0.5)


func _min_grid_index() -> int:
	return ceili(SPAWN_MARGIN / float(TILE_SIZE))


func _max_grid_x() -> int:
	return floori((_field_size.x - SPAWN_MARGIN) / float(TILE_SIZE)) - 1


func _max_grid_y() -> int:
	return floori((_field_size.y - SPAWN_MARGIN) / float(TILE_SIZE)) - 1


func _grow_crowd_pressure() -> void:
	if GameState.current_stage <= 1:
		_crowd_pressure = 0
		return
	if _enemies_root.get_child_count() <= 0:
		_crowd_pressure = 0
		return
	_crowd_pressure = mini(max_crowd_pressure, _crowd_pressure + crowd_growth_per_wave)


func _refill_enemy_population(max_to_spawn: int) -> void:
	var desired_count: int = _desired_enemy_count()
	var missing_count: int = desired_count - _enemies_root.get_child_count()
	var spawn_count: int = mini(max_to_spawn, missing_count)
	for i in spawn_count:
		_spawn_field_enemy(_enemy_data_for_stage(GameState.effective_stage()))


func _desired_enemy_count() -> int:
	if GameState.current_stage <= 1:
		return peaceful_start_enemies
	var base: int = _enemy_count_for_stage(GameState.effective_stage())
	# Time-based crowd bump on top of stage/area math. At 30 min the
	# field carries a controlled extra crowd without spiking stage 2.
	var t: float = clampf(GameState.run_intensity(), 0.0, 1.0)
	var time_bonus: int = int(round(t * float(ENEMY_CAP_TIME_BONUS_END)))
	return base + time_bonus + _crowd_pressure


func _spawn_field_enemy(data: EnemyData) -> void:
	var safe_origin: Vector2 = _player.position if _player else _field_size * 0.5
	var fe: FieldEnemy = FIELD_ENEMY_SCENE.instantiate()
	fe.setup(data, 1)
	fe.wander_bounds_min = Vector2.ONE * 16.0
	fe.wander_bounds_max = _field_size - Vector2.ONE * 16.0
	fe.position = _random_spawn_position_for_enemy(data, safe_origin)
	_enemies_root.add_child(fe)


func _enemy_count_for_stage(_stage: int) -> int:
	var field_area: float = _field_size.x * _field_size.y
	var area_ratio: float = field_area / BASE_FIELD_AREA
	var area_bonus: int = maxi(0, int(round((area_ratio - 1.0) * enemies_added_per_field_area)))
	var stage_bonus: int = int(floor(float(maxi(0, _stage - 1)) / 3.0))
	return peaceful_start_enemies + area_bonus + stage_bonus


func _enemy_data_for_stage(_stage: int) -> EnemyData:
	return SLIME_DATA


func _random_spawn_position_for_enemy(data: EnemyData, avoid: Vector2) -> Vector2:
	if data == SLIME_DATA:
		return _random_grassland_position(avoid)
	return _random_safe_position(avoid)


func _random_forest_position(avoid: Vector2) -> Vector2:
	var cells: Array = _forest_cells.keys()
	cells.shuffle()
	for cell: Vector2i in cells:
		var pos: Vector2 = _cell_to_world(cell)
		if _is_safe_enemy_spawn_position(pos, avoid):
			return pos
	return _random_safe_position(avoid)


func _random_grassland_position(avoid: Vector2) -> Vector2:
	for attempt in 48:
		var cell := Vector2i(
			_decor_rng.randi_range(_min_grid_index(), _max_grid_x()),
			_decor_rng.randi_range(_min_grid_index(), _max_grid_y())
		)
		if _forest_cells.has(cell):
			continue
		var pos: Vector2 = _cell_to_world(cell)
		if _is_safe_enemy_spawn_position(pos, avoid):
			return pos
	return _random_safe_position(avoid)


func _random_safe_position(avoid: Vector2) -> Vector2:
	for attempt in 24:
		var pos: Vector2 = _random_position()
		if _is_safe_enemy_spawn_position(pos, avoid):
			return pos
	return _random_position()


func _is_safe_enemy_spawn_position(pos: Vector2, avoid: Vector2) -> bool:
	return pos.distance_to(avoid) >= PARTY_SAFE_RADIUS and not _is_near_town_tile(pos)


func _on_enemy_defeated(_enemy: Node, _gold: int, _world_position: Vector2) -> void:
	if GameState.current_stage <= 0 or _treasure_spawned:
		return
	if not GameState.is_system_unlocked(GameState.SYSTEM_TREASURE):
		return
	_treasure_kills += 1
	if _treasure_kills >= _treasure_kills_required():
		_spawn_treasure_chest()


func _treasure_kills_required() -> int:
	var stage_bonus: int = int(floor(float(maxi(0, GameState.current_stage - 1)) / 2.0)) * treasure_kills_required_stage_step
	return maxi(1, treasure_kills_required_base + stage_bonus)


func _spawn_treasure_chest() -> void:
	_treasure_spawned = true
	var chest := FIELD_TREASURE_CHEST_SCENE.instantiate() as FieldTreasureChest
	chest.gold_amount = _treasure_gold_amount()
	var safe_origin: Vector2 = _player.position if _player else _field_size * 0.5
	chest.position = _random_safe_treasure_position(safe_origin)
	_treasures_root.add_child(chest)
	chest.reveal_with_pop()


func _treasure_gold_amount() -> int:
	var stage_index: int = maxi(0, GameState.current_stage - 1)
	return treasure_gold_base + stage_index * treasure_gold_per_stage


func _random_safe_treasure_position(avoid: Vector2) -> Vector2:
	for attempt in 40:
		var pos: Vector2 = _random_safe_position(avoid)
		if pos.distance_to(avoid) >= DECOR_SAFE_RADIUS:
			return pos
	return _random_safe_position(avoid)


func _on_field_item_drop_requested(item: ItemData, world_position: Vector2) -> void:
	if item == null:
		return
	var drop := FIELD_ITEM_DROP_SCENE.instantiate() as FieldItemDrop
	drop.setup(item)
	drop.position = _clamp_field_position(world_position)
	_items_root.add_child(drop)
	drop.reveal_with_pop()


func _on_field_recovery_orb_requested(kind: StringName, world_position: Vector2) -> void:
	var orb := FIELD_RECOVERY_ORB_SCENE.instantiate() as FieldRecoveryOrb
	orb.setup(kind)
	orb.position = _clamp_field_position(world_position)
	_items_root.add_child(orb)
	orb.reveal_with_pop()


func _clamp_field_position(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, 16.0, _field_size.x - 16.0),
		clampf(pos.y, 16.0, _field_size.y - 16.0)
	)


func _is_near_town_tile(pos: Vector2) -> bool:
	return _town_revealed and pos.distance_to(_town_tile.position) < TOWN_TILE_SAFE_RADIUS


func _random_position() -> Vector2:
	return Vector2(
		randf_range(SPAWN_MARGIN, _field_size.x - SPAWN_MARGIN),
		randf_range(SPAWN_MARGIN, _field_size.y - SPAWN_MARGIN),
	)


func _apply_stage_field_size(stage_num: int) -> void:
	_field_size = _field_size_for_stage(stage_num)
	_background.size = _field_size
	_town_tile.position = _hidden_town_tile_position()
	if _player and _player.has_method("set_field_bounds"):
		_player.set_field_bounds(Vector2.ZERO, _field_size)


func _field_size_for_stage(stage_num: int) -> Vector2:
	var stage_index: int = maxi(0, stage_num - 1)
	var size: Vector2 = FIELD_SIZE_START + FIELD_SIZE_STAGE_STEP * float(stage_index)
	return Vector2(minf(size.x, FIELD_SIZE_END.x), minf(size.y, FIELD_SIZE_END.y))


func _place_start_town_tile() -> void:
	_town_revealed = true
	_town_tile.position = _town_tile_corner_position()
	_town_tile.reveal_with_impact()


func _reveal_town_tile() -> void:
	if _town_revealed:
		return
	_town_revealed = true
	_town_tile.position = _town_tile_corner_position()
	_town_tile.reveal_with_impact()


func _town_tile_corner_position() -> Vector2:
	var candidates: Array[Vector2] = [
		TOWN_TILE_INSET,
		Vector2(_field_size.x - TOWN_TILE_INSET.x, TOWN_TILE_INSET.y),
		Vector2(TOWN_TILE_INSET.x, _field_size.y - TOWN_TILE_INSET.y),
		_field_size - TOWN_TILE_INSET,
	]
	return candidates.pick_random()


func _hidden_town_tile_position() -> Vector2:
	return Vector2(_field_size.x + 256.0, _field_size.y + 256.0)


## All windows closed AND the field is empty → stage clear.
## Echo Strike can keep extra windows running after the last field enemy is
## consumed, so we listen to all_battles_resolved (not battle_window_closed)
## and combine with the field-empty check.
func _check_stage_clear() -> void:
	if _stage_complete:
		return
	if GameState.current_stage <= 1:
		return
	if not _town_revealed and _enemies_root.get_child_count() == 0:
		_refill_enemy_population(spawn_batch_size)
