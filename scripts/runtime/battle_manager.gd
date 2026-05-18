class_name BattleManager
extends CanvasLayer

## Spawns BattleWindows on enemy_encountered, then lets them drift away from
## overlapping windows or the player and settle into their new screen position.
##
## CanvasLayer base = screen-space rendering. Battle windows stay locked to
## the viewport regardless of where the world camera is looking.
## Windows themselves are independent — manager only decides where they live.

const BATTLE_WINDOW_SCENE: PackedScene = preload("res://scenes/battle_window.tscn")
const MANUAL_BATTLE_SCENE: PackedScene = preload("res://scenes/manual_battle.tscn")
const DAMAGE_NUMBER_SCENE: PackedScene = preload("res://scenes/effects/damage_number.tscn")

## Fallback if no valid player-relative spawn point exists.
const SPAWN_CENTER: Vector2 = Vector2(260, 56)

const SLOT_MARGIN: float = 2.0
const HUD_RESERVED_BOTTOM: float = 8.0
const SPAWN_DISTANCE: float = 52.0
const WINDOW_PUSH_PADDING: float = 10.0
const WINDOW_PUSH_STRENGTH: float = 260.0
const PARTY_COLLISION_SIZE: Vector2 = Vector2(18.0, 24.0)
const PARTY_COLLISION_STRENGTH: float = 1800.0
const WALL_PUSH_STRENGTH: float = 900.0
const ORC_WINDOW_PUSH_MULTIPLIER: float = 0.35
const ORC_WINDOW_DRAG_SPEED_MULTIPLIER: float = 0.45
const ORC_WINDOW_DRAG_DURATION: float = 0.12
const VELOCITY_DAMPING: float = 4.6
const MAX_WINDOW_SPEED: float = 180.0
const SETTLE_SPEED: float = 10.0
const SETTLE_INTERVAL: float = 0.08
const WINDOW_COLLISION_DAMAGE_COOLDOWN: float = 1.5
const PARTY_COLLISION_DAMAGE_COOLDOWN: float = 1.2
## Max total HP that bump_blessing can heal from a single window's lifetime.
## Prevents "infinite bump-heal" sustain via repeated collisions.
const BUMP_HEAL_PER_WINDOW_CAP: int = 8
const DROP_RING_RADIUS: float = 16.0
const DROP_RING_RADIUS_STEP: float = 7.0
const DROP_RING_SLOTS: int = 8

var _window_rects: Dictionary = {}  ## BattleWindow -> Rect2 target it took
var _window_velocities: Dictionary = {}  ## BattleWindow -> Vector2 screen velocity.
var _collision_cooldowns: Dictionary = {}  ## window pair key -> remaining seconds.
var _party_collision_cooldowns: Dictionary = {}  ## battle window id -> remaining seconds.
var _bump_heal_totals: Dictionary = {}  ## battle window id -> cumulative HP healed.
var _settle_timer: float = 0.0


func _ready() -> void:
	EventBus.enemy_encountered.connect(_on_enemy_encountered)
	EventBus.battle_window_closed.connect(_on_battle_window_closed)
	EventBus.party_wiped.connect(_on_party_wiped)


func _process(delta: float) -> void:
	_purge_invalid_window_references()
	if _window_rects.is_empty():
		return
	_settle_timer += delta
	_tick_collision_cooldowns(delta)
	_tick_party_collision_cooldowns(delta)
	_apply_window_push(delta)


func active_window_count() -> int:
	_purge_invalid_window_references()
	return _window_rects.size()


# ─── Spawning ─────────────────────────────────────────────────────────
func _on_enemy_encountered(field_enemy: Node) -> void:
	if GameState.is_party_wiped() or not is_instance_valid(field_enemy):
		return
	var data: EnemyData = field_enemy.data
	if data == null:
		return
	if GameState.is_manual_battle_mode():
		_open_manual_battle(data)
		return
	var source := field_enemy as Node2D
	var enemy_count: int = _encounter_enemy_count(field_enemy)
	spawn_battle(data, source, enemy_count)
	# Echo Strike & friends: roll for bonus duplicate windows.
	var extras: int = GameState.roll_window_duplicates()
	for i in extras:
		spawn_battle(data, source, enemy_count)


## Manual DQ1-style command screen. While open, GameState registers it
## so is_field_combat_locked() returns true — player/companions/field
## enemies freeze, but the field's _process keeps running so the stage
## timer and spawner still tick. Tree is NOT paused: the player should
## feel pressure during a slow manual fight.
## tree_exited handles both victory (battle_finished → queue_free) and
## defeat (party_wiped path also frees the window).
func _open_manual_battle(data: EnemyData) -> void:
	if _manual_battle != null and is_instance_valid(_manual_battle):
		return
	var window: ManualBattle = MANUAL_BATTLE_SCENE.instantiate()
	window.setup(data)
	window.tree_exited.connect(_on_manual_battle_closed)
	add_child(window)
	_manual_battle = window


func _on_manual_battle_closed() -> void:
	_manual_battle = null


## Public API. Used by enemy_encountered handler and debug helpers.
func spawn_battle(data: EnemyData, source: Node2D = null, enemy_count: int = 0) -> void:
	_spawn_window(data, source, enemy_count)


func _spawn_window(data: EnemyData, source: Node2D = null, enemy_count: int = 0) -> void:
	var window: BattleWindow = BATTLE_WINDOW_SCENE.instantiate()
	var field_drop_position: Vector2 = source.global_position if source != null and is_instance_valid(source) else Vector2.INF
	window.setup(data, field_drop_position, enemy_count)
	var window_size: Vector2 = window.get_expected_window_size()
	var spawn_position: Vector2 = _spawn_position_for_encounter(window_size, source)
	window.position = spawn_position
	_window_rects[window] = Rect2(spawn_position, window_size)
	_window_velocities[window] = Vector2.ZERO
	add_child(window)
	_apply_window_push(0.0, true)


func _encounter_enemy_count(field_enemy: Node) -> int:
	if field_enemy is FieldEnemy:
		return (field_enemy as FieldEnemy).encounter_enemy_count()
	return 0


# ─── Window drift ─────────────────────────────────────────────────────
func _spawn_position_for_encounter(window_size: Vector2, source: Node2D) -> Vector2:
	if source == null or not is_instance_valid(source):
		return _random_spawn_position(window_size)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var player_position: Vector2 = _player_screen_position()
	if player_position == Vector2.INF:
		return _clamped_position(SPAWN_CENTER, window_size, viewport_size)
	var source_position: Vector2 = source.get_global_transform_with_canvas().origin
	var direction: Vector2 = source_position - player_position
	if direction.length_squared() < 1.0:
		return _random_spawn_position(window_size)
	direction = direction.normalized()
	var half_extent: float = absf(direction.x) * window_size.x * 0.5 + absf(direction.y) * window_size.y * 0.5
	var center: Vector2 = player_position + direction * (SPAWN_DISTANCE + half_extent)
	return _clamped_position(center - window_size * 0.5, window_size, viewport_size)


func _random_spawn_position(window_size: Vector2) -> Vector2:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var player_position: Vector2 = _player_screen_position()
	if player_position == Vector2.INF:
		return _clamped_position(SPAWN_CENTER, window_size, viewport_size)
	var candidates: Array[Vector2] = [
		player_position + Vector2(-window_size.x * 0.5, -SPAWN_DISTANCE - window_size.y),
		player_position + Vector2(-window_size.x * 0.5, SPAWN_DISTANCE),
		player_position + Vector2(-SPAWN_DISTANCE - window_size.x, -window_size.y * 0.5),
		player_position + Vector2(SPAWN_DISTANCE, -window_size.y * 0.5),
	]
	candidates.shuffle()
	for candidate: Vector2 in candidates:
		if _is_spawn_position_valid(candidate, window_size, viewport_size):
			return candidate
	return _clamped_position(candidates.front(), window_size, viewport_size)


func _is_spawn_position_valid(pos: Vector2, size: Vector2, viewport_size: Vector2) -> bool:
	var play_bottom: float = viewport_size.y - HUD_RESERVED_BOTTOM
	return (
		pos.x >= SLOT_MARGIN
		and pos.y >= SLOT_MARGIN
		and pos.x + size.x <= viewport_size.x - SLOT_MARGIN
		and pos.y + size.y <= play_bottom
	)


func _apply_window_push(delta: float, burst: bool = false) -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var party_positions: Array[Vector2] = _party_screen_positions()
	var window_collision_enabled: bool = GameState.battle_window_push_enabled()
	var party_collision_enabled: bool = GameState.party_window_push_enabled()
	var windows: Array[BattleWindow] = _active_windows()
	for window: BattleWindow in windows:
		if not is_instance_valid(window) or not _window_rects.has(window):
			continue
		_window_rects[window] = Rect2(window.position, _window_rects[window].size)
		var force := Vector2.ZERO
		var rect: Rect2 = _window_rects[window]
		for other: BattleWindow in windows:
			if window == other or not is_instance_valid(other) or not _window_rects.has(other):
				continue
			if window_collision_enabled:
				if window.get_instance_id() < other.get_instance_id():
					_apply_window_collision_damage(window, rect, other, _window_rects[other])
					if not is_instance_valid(window) or not is_instance_valid(other):
						break
				force += _window_overlap_push(window, rect, other, _window_rects[other])
		if not is_instance_valid(window) or not _window_rects.has(window):
			continue
		if party_collision_enabled:
			for party_position: Vector2 in party_positions:
				var party_rect := Rect2(party_position - PARTY_COLLISION_SIZE * 0.5, PARTY_COLLISION_SIZE)
				if rect.intersects(party_rect):
					_apply_party_collision_effects(window)
					if not is_instance_valid(window) or not _window_rects.has(window):
						break
					_apply_party_drag_effects(window)
				force += _party_collision_push(rect, party_position)
		if not is_instance_valid(window) or not _window_rects.has(window):
			continue
		if window_collision_enabled or party_collision_enabled:
			force += _wall_push(rect, viewport_size)
		force *= _window_push_multiplier(window)
		var velocity: Vector2 = _window_velocities.get(window, Vector2.ZERO)
		var step_delta: float = 1.0 / 60.0 if burst else delta
		velocity += force * step_delta
		velocity = velocity.limit_length(MAX_WINDOW_SPEED)
		velocity = velocity.move_toward(Vector2.ZERO, VELOCITY_DAMPING * velocity.length() * step_delta)
		var next_position: Vector2 = _clamped_position(window.position + velocity * step_delta, rect.size, viewport_size)
		_window_velocities[window] = velocity
		_window_rects[window] = Rect2(next_position, rect.size)
		if burst or velocity.length() >= SETTLE_SPEED:
			window.push_to(next_position)
		elif _settle_timer >= SETTLE_INTERVAL:
			window.settle_to(next_position)
	if _settle_timer >= SETTLE_INTERVAL:
		_settle_timer = 0.0


func _active_windows() -> Array[BattleWindow]:
	var windows: Array[BattleWindow] = []
	for raw_window in _window_rects.keys():
		if not is_instance_valid(raw_window):
			_forget_window_reference(raw_window)
			continue
		var window := raw_window as BattleWindow
		if window == null:
			_forget_window_reference(raw_window)
			continue
		windows.append(window)
	return windows


func _purge_invalid_window_references() -> void:
	for raw_window in _window_rects.keys():
		if not is_instance_valid(raw_window):
			_forget_window_reference(raw_window)


func _forget_window_reference(window) -> void:
	_window_rects.erase(window)
	_window_velocities.erase(window)
	if is_instance_valid(window):
		var window_key: String = str(window.get_instance_id())
		_party_collision_cooldowns.erase(window_key)
		_bump_heal_totals.erase(window_key)


func _window_overlap_push(window: BattleWindow, rect: Rect2, other_window: BattleWindow, other: Rect2) -> Vector2:
	var padded := Rect2(rect.position - Vector2.ONE * WINDOW_PUSH_PADDING, rect.size + Vector2.ONE * WINDOW_PUSH_PADDING * 2.0)
	var other_padded := Rect2(other.position - Vector2.ONE * WINDOW_PUSH_PADDING, other.size + Vector2.ONE * WINDOW_PUSH_PADDING * 2.0)
	if not padded.intersects(other_padded):
		return Vector2.ZERO
	var delta: Vector2 = padded.get_center() - other_padded.get_center()
	if delta == Vector2.ZERO:
		delta = _stable_separation_direction(window, other_window)
	var overlap_x: float = minf(padded.end.x, other_padded.end.x) - maxf(padded.position.x, other_padded.position.x)
	var overlap_y: float = minf(padded.end.y, other_padded.end.y) - maxf(padded.position.y, other_padded.position.y)
	var push: float = maxf(0.0, minf(overlap_x, overlap_y))
	return delta.normalized() * push * WINDOW_PUSH_STRENGTH


func _window_push_multiplier(window: BattleWindow) -> float:
	if window.has_living_enemy_id(&"orc"):
		return ORC_WINDOW_PUSH_MULTIPLIER
	return 1.0


func _apply_party_drag_effects(window: BattleWindow) -> void:
	if window.has_living_enemy_id(&"orc"):
		GameState.apply_move_speed_drag(ORC_WINDOW_DRAG_SPEED_MULTIPLIER, ORC_WINDOW_DRAG_DURATION)


func _apply_window_collision_damage(window: BattleWindow, rect: Rect2, other_window: BattleWindow, other: Rect2) -> void:
	var damage_ratio: float = GameState.window_collision_damage_ratio()
	if damage_ratio <= 0.0:
		return
	if not rect.intersects(other):
		return
	var key: String = _collision_pair_key(window, other_window)
	if float(_collision_cooldowns.get(key, 0.0)) > 0.0:
		return
	var dealt: int = window.apply_window_collision_damage(damage_ratio)
	dealt += other_window.apply_window_collision_damage(damage_ratio)
	if dealt > 0:
		_collision_cooldowns[key] = WINDOW_COLLISION_DAMAGE_COOLDOWN


func _apply_party_collision_effects(window: BattleWindow) -> void:
	var damage_ratio: float = GameState.party_bump_damage_ratio()
	var heal_amount: int = GameState.window_collision_heal_amount()
	if damage_ratio <= 0.0 and heal_amount <= 0:
		return
	var key: String = str(window.get_instance_id())
	if float(_party_collision_cooldowns.get(key, 0.0)) > 0.0:
		return
	var dealt: int = 0
	var counter_damage_ratio: float = 0.0
	if damage_ratio > 0.0:
		counter_damage_ratio = window.party_bump_counter_damage_ratio()
		# Bump attack hits one random enemy in the window — a poke, not a sweep.
		# Window-on-window crashes (window_crash) still splash everyone.
		dealt = window.apply_window_collision_damage(damage_ratio, "Bump attack", true)
	var healed: int = 0
	if heal_amount > 0:
		var already_healed: int = int(_bump_heal_totals.get(key, 0))
		var allowed: int = maxi(0, BUMP_HEAL_PER_WINDOW_CAP - already_healed)
		if allowed > 0:
			healed = _apply_party_collision_heal(window, mini(heal_amount, allowed))
			if healed > 0:
				_bump_heal_totals[key] = already_healed + healed
	var countered: int = 0
	if dealt > 0 and counter_damage_ratio > 0.0:
		countered = _apply_party_bump_counter_damage(window, counter_damage_ratio)
	if dealt > 0 or healed > 0 or countered > 0:
		_party_collision_cooldowns[key] = PARTY_COLLISION_DAMAGE_COOLDOWN


func _apply_party_bump_counter_damage(window: BattleWindow, ratio: float) -> int:
	var total_dealt: int = 0
	for i in GameState.party_size():
		if not GameState.is_alive(i):
			continue
		var amount: int = maxi(1, ceili(float(GameState.effective_max_hp(i)) * ratio))
		var before_hp: int = GameState.party_hp[i]
		GameState.damage_party_member(i, amount)
		var dealt: int = before_hp - GameState.party_hp[i]
		if dealt <= 0:
			continue
		total_dealt += dealt
		_spawn_party_damage_number(i, dealt)
	if total_dealt > 0:
		window.show_party_bump_counter_damage(total_dealt, ratio)
	return total_dealt


func _apply_party_collision_heal(window: BattleWindow, amount: int) -> int:
	var target_index: int = _lowest_wounded_party_index()
	if target_index == -1:
		return 0
	var before_hp: int = GameState.party_hp[target_index]
	GameState.heal_party_member(target_index, amount)
	var healed: int = GameState.party_hp[target_index] - before_hp
	if healed > 0:
		var member_name: String = GameState.party[target_index].display_name
		_spawn_party_heal_number(target_index, healed)
		window.show_window_collision_heal(member_name, healed)
	return healed


func _spawn_party_damage_number(party_index: int, amount: int) -> void:
	var target: Node2D = _party_member_node_for_index(party_index)
	if target == null:
		return
	var num: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate()
	target.add_child(num)
	num.position = Vector2(randf_range(-5.0, 5.0), -18.0 + randf_range(-2.0, 2.0))
	num.z_index = 30
	num.setup_text("-%d" % amount, Color(1.0, 0.28, 0.18, 1.0))


func _spawn_party_heal_number(party_index: int, amount: int) -> void:
	var target: Node2D = _party_member_node_for_index(party_index)
	if target == null:
		return
	var num: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate()
	target.add_child(num)
	num.position = Vector2(randf_range(-5.0, 5.0), -18.0 + randf_range(-2.0, 2.0))
	num.z_index = 30
	num.setup_heal(amount)


func _party_member_node_for_index(party_index: int) -> Node2D:
	if party_index < 0:
		return null
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return _party_member_node_from_group(party_index)
	if party_index == 0:
		return player
	var party_root: Node = player.get_parent()
	if party_root == null:
		return _party_member_node_from_group(party_index)
	var current_index: int = 0
	for child in party_root.get_children():
		if child is Node2D and child.is_in_group("party_member"):
			if current_index == party_index:
				return child as Node2D
			current_index += 1
	return _party_member_node_from_group(party_index)


func _party_member_node_from_group(party_index: int) -> Node2D:
	var current_index: int = 0
	for node in get_tree().get_nodes_in_group("party_member"):
		var member := node as Node2D
		if member == null:
			continue
		if current_index == party_index:
			return member
		current_index += 1
	return null


func _lowest_wounded_party_index() -> int:
	var best_index: int = -1
	var best_ratio: float = 1.1
	for i in GameState.party_size():
		if not GameState.is_alive(i):
			continue
		var max_hp: int = GameState.effective_max_hp(i)
		if max_hp <= 0 or GameState.party_hp[i] >= max_hp:
			continue
		var ratio: float = float(GameState.party_hp[i]) / float(max_hp)
		if ratio < best_ratio:
			best_ratio = ratio
			best_index = i
	return best_index


func _collision_pair_key(window: BattleWindow, other_window: BattleWindow) -> String:
	var a: int = int(window.get_instance_id())
	var b: int = int(other_window.get_instance_id())
	if a > b:
		var temp: int = a
		a = b
		b = temp
	return "%d:%d" % [a, b]


func _tick_collision_cooldowns(delta: float) -> void:
	for key: String in _collision_cooldowns.keys():
		var remaining: float = float(_collision_cooldowns[key]) - delta
		if remaining <= 0.0:
			_collision_cooldowns.erase(key)
		else:
			_collision_cooldowns[key] = remaining


func _tick_party_collision_cooldowns(delta: float) -> void:
	for key: String in _party_collision_cooldowns.keys():
		var remaining: float = float(_party_collision_cooldowns[key]) - delta
		if remaining <= 0.0:
			_party_collision_cooldowns.erase(key)
		else:
			_party_collision_cooldowns[key] = remaining


func _stable_separation_direction(window: BattleWindow, other_window: BattleWindow) -> Vector2:
	var pair_hash: int = int(window.get_instance_id() + other_window.get_instance_id())
	var angle: float = float(pair_hash % 360) * TAU / 360.0
	var direction := Vector2(cos(angle), sin(angle))
	if window.get_instance_id() < other_window.get_instance_id():
		return direction
	return -direction


func _party_collision_push(rect: Rect2, party_position: Vector2) -> Vector2:
	var party_rect := Rect2(party_position - PARTY_COLLISION_SIZE * 0.5, PARTY_COLLISION_SIZE)
	if not rect.intersects(party_rect):
		return Vector2.ZERO
	var delta: Vector2 = rect.get_center() - party_position
	if delta == Vector2.ZERO:
		delta = Vector2.UP
	var overlap_x: float = minf(rect.end.x, party_rect.end.x) - maxf(rect.position.x, party_rect.position.x)
	var overlap_y: float = minf(rect.end.y, party_rect.end.y) - maxf(rect.position.y, party_rect.position.y)
	var penetration: float = maxf(1.0, minf(overlap_x, overlap_y))
	return delta.normalized() * penetration * PARTY_COLLISION_STRENGTH


func _wall_push(rect: Rect2, viewport_size: Vector2) -> Vector2:
	var play_bottom: float = viewport_size.y - HUD_RESERVED_BOTTOM
	var force := Vector2.ZERO
	if rect.position.x < SLOT_MARGIN:
		force.x += (SLOT_MARGIN - rect.position.x) * WALL_PUSH_STRENGTH
	if rect.end.x > viewport_size.x - SLOT_MARGIN:
		force.x -= (rect.end.x - viewport_size.x + SLOT_MARGIN) * WALL_PUSH_STRENGTH
	if rect.position.y < SLOT_MARGIN:
		force.y += (SLOT_MARGIN - rect.position.y) * WALL_PUSH_STRENGTH
	if rect.end.y > play_bottom:
		force.y -= (rect.end.y - play_bottom) * WALL_PUSH_STRENGTH
	return force


func _clamped_position(pos: Vector2, size: Vector2, viewport_size: Vector2) -> Vector2:
	var play_bottom: float = viewport_size.y - HUD_RESERVED_BOTTOM
	return Vector2(
		clampf(pos.x, SLOT_MARGIN, maxf(SLOT_MARGIN, viewport_size.x - SLOT_MARGIN - size.x)),
		clampf(pos.y, SLOT_MARGIN, maxf(SLOT_MARGIN, play_bottom - size.y))
	)


func _player_screen_position() -> Vector2:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty() or not players[0] is Node2D:
		return Vector2.INF
	return (players[0] as Node2D).get_global_transform_with_canvas().origin


func _party_screen_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for member: Node in get_tree().get_nodes_in_group("party_member"):
		if member is Node2D:
			positions.append((member as Node2D).get_global_transform_with_canvas().origin)
	return positions


func _on_battle_window_closed(window: Node) -> void:
	if not _window_rects.has(window):
		return
	# Snapshot the window's screen rect *before* erasing — we need it to
	# anchor drop positions at the window the player was just fighting in,
	# not at the player's body.
	var window_rect: Rect2 = _window_rects[window]
	_window_rects.erase(window)
	_window_velocities.erase(window)
	var battle_window := window as BattleWindow
	if battle_window:
		var xp_reward: int = battle_window.claim_xp_reward()
		if xp_reward > 0:
			GameState.add_party_xp(xp_reward)
		_drop_rewards_from_window(battle_window, window_rect)
	# Tell anyone who cares (Field, etc.) when the last fight ends. This is
	# the gate Field uses before declaring stage_cleared — Echo Strike means
	# the *first* window closing is rarely the last one.
	if _window_rects.is_empty():
		EventBus.all_battles_resolved.emit()


func _drop_rewards_from_window(window: BattleWindow, window_rect: Rect2) -> void:
	var drops: Array[ItemData] = window.claim_item_drops()
	var orb_count: int = window.claim_recovery_orb_count()
	var total_count: int = drops.size() + orb_count
	if total_count <= 0:
		return
	var base_pos: Vector2 = _world_position_for_window_rect(window_rect)
	var slot_index: int = 0
	for i in drops.size():
		EventBus.field_item_drop_requested.emit(drops[i], _drop_slot_position(base_pos, slot_index, total_count))
		slot_index += 1
	for i in orb_count:
		var kind: StringName = GameState.RECOVERY_ORB_HP if randf() < 0.5 else GameState.RECOVERY_ORB_MP
		EventBus.field_recovery_orb_requested.emit(kind, _drop_slot_position(base_pos, slot_index, total_count))
		slot_index += 1


func _drop_slot_position(base_pos: Vector2, index: int, total_count: int) -> Vector2:
	if total_count <= 1:
		return base_pos
	var ring: int = int(floor(float(index) / float(DROP_RING_SLOTS)))
	var slot: int = index % DROP_RING_SLOTS
	var slots_in_ring: int = mini(DROP_RING_SLOTS, total_count - ring * DROP_RING_SLOTS)
	var angle_offset: float = 0.35 * float(ring)
	var angle: float = TAU * float(slot) / float(maxi(1, slots_in_ring)) + angle_offset
	var radius: float = DROP_RING_RADIUS + DROP_RING_RADIUS_STEP * float(ring)
	return base_pos + Vector2(cos(angle), sin(angle)) * radius


## Translate a battle window's on-screen rect into a world coordinate so
## the drops land *under the window the player was just fighting in*,
## not at the player's feet. Falls back to the player's world position if
## the camera isn't ready yet.
func _world_position_for_window_rect(window_rect: Rect2) -> Vector2:
	var fallback_pos: Vector2 = Vector2.ZERO
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		fallback_pos = player.global_position
	if window_rect.size == Vector2.ZERO:
		return fallback_pos
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return fallback_pos
	# Anchor the drop slightly above the bottom of the window so loot
	# spawns under the enemy stack rather than over the action log.
	var screen_anchor: Vector2 = window_rect.position + Vector2(window_rect.size.x * 0.5, window_rect.size.y * 0.65)
	var camera_world_center: Vector2 = camera.get_screen_center_position()
	var screen_offset: Vector2 = screen_anchor - viewport_size * 0.5
	return camera_world_center + screen_offset


# ─── Run-over cleanup ─────────────────────────────────────────────────
func _on_party_wiped() -> void:
	abort_all_battles()


## Force-close every active battle window. No gold, no signals, no log —
## the run is dead. Used on party_wipe and (later) explicit run resets.
func abort_all_battles() -> void:
	for window: Node in _window_rects.keys():
		if is_instance_valid(window):
			window.queue_free()
	_window_rects.clear()
	_window_velocities.clear()
	_collision_cooldowns.clear()
	_party_collision_cooldowns.clear()
	_bump_heal_totals.clear()
