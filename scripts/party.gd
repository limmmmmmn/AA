class_name Party
extends Node2D
## 용사 일행 — 꼬리물기 대열. v2.0: 키보드 = 용사의 몸 (WASD 이동 + Space 범프).
## 자율 행동(사냥/귀환)은 "용사의 직감" 해금 후 ai_query가 담당.

signal bumped(node: Node2D)

const SPACING := 5          # 히스토리 점 몇 개 간격으로 따라올까 (점 간격 3px)
const HISTORY_STEP := 3.0

var frozen := false
var ai_query: Callable        # main이 제공 — 용사의 직감 (직감 없으면 null 반환)
var bounds_min := Vector2(10, 26)
var bounds_max := Vector2(630, 348)
var head_pos := Vector2.ZERO
var target_node: Node2D = null
var target_point: Variant = null   # AI용 지점 이동 (Vector2)
var manual_hold := 0.0      # 수동 입력 직후엔 자율 행동 억제
var _ai_wait := 0.0

var _history: Array[Vector2] = []
var _sprites: Array = []           # 멤버 인덱스 순 Sprite2D
var _anim_t := 0.0
var _dir_row := 0                  # 0 아래 1 왼쪽 2 오른쪽 3 위
var _moving := false
var _bob_t := 0.0

func _ready() -> void:
	Game.party_changed.connect(_rebuild_sprites)
	_rebuild_sprites()

func init_at(pos: Vector2) -> void:
	head_pos = pos
	_history.clear()
	for i in 64:
		_history.append(pos)
	position = Vector2.ZERO

func teleport(pos: Vector2) -> void:
	init_at(pos)
	target_node = null
	target_point = null
	_layout_sprites()

func _rebuild_sprites() -> void:
	for s in _sprites:
		if is_instance_valid(s):
			s.queue_free()
	_sprites = []
	for m in Game.members:
		var d: Dictionary = Game.CLASS_DEFS[m["cls"]]
		var s := Sprite2D.new()
		s.texture = load(d["tex"])
		s.hframes = 3
		s.vframes = 4
		s.frame = 1
		s.offset = Vector2(0, -float(d["frame_h"]) / 2.0)
		add_child(s)
		_sprites.append(s)

# ---------------------------------------------------------------- 이동

func _physics_process(delta: float) -> void:
	manual_hold = maxf(0.0, manual_hold - delta)
	_bob_t += delta * 4.0
	if frozen:
		_moving = false
		_layout_sprites()
		return

	# WASD / 화살표 — 용사의 몸
	var kdir := Vector2(
		(1.0 if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT) else 0.0)
		- (1.0 if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT) else 0.0),
		(1.0 if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN) else 0.0)
		- (1.0 if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP) else 0.0))
	if kdir != Vector2.ZERO:
		target_node = null
		target_point = null
		manual_hold = 2.5
		_step(kdir.normalized(), delta)
		_check_passive_bumps()
		_layout_sprites()
		return

	# 용사의 직감 — 자율 행동
	if target_node == null and target_point == null and manual_hold <= 0.0:
		_ai_wait -= delta
		if _ai_wait <= 0.0:
			_ai_wait = 1.2
			if ai_query.is_valid():
				var t = ai_query.call()
				if t is Node2D:
					target_node = t
				elif t is Vector2:
					target_point = t

	_moving = false
	if target_node != null:
		if not is_instance_valid(target_node):
			target_node = null
		else:
			var d: Vector2 = target_node.global_position - head_pos
			var arrive: float = target_node.pick_radius() if target_node.has_method("pick_radius") else 14.0
			if d.length() <= arrive:
				var n := target_node
				target_node = null
				bumped.emit(n)
			else:
				_step(d.normalized(), delta)
	elif target_point != null:
		var dp: Vector2 = (target_point as Vector2) - head_pos
		if dp.length() <= 6.0:
			target_point = null
		else:
			_step(dp.normalized(), delta)

	_check_passive_bumps()
	_layout_sprites()

func _step(dir: Vector2, delta: float) -> void:
	head_pos += dir * Game.move_speed() * delta
	head_pos = head_pos.clamp(bounds_min, bounds_max)
	_moving = true
	_dir_row = _dir_from(dir)
	if _history.is_empty() or head_pos.distance_to(_history[0]) >= HISTORY_STEP:
		_history.push_front(head_pos)
		if _history.size() > 120:
			_history.pop_back()

func _dir_from(d: Vector2) -> int:
	if absf(d.x) > absf(d.y):
		return 2 if d.x > 0 else 1
	return 0 if d.y > 0 else 3

func _check_passive_bumps() -> void:
	# 지나가다 자연 충돌 — 몬스터와 항아리류만 (건물/NPC는 Space 확정)
	for m in get_tree().get_nodes_in_group("monster"):
		if not is_instance_valid(m) or not m.is_visible_in_tree():
			continue
		if m.bump_cd <= 0.0 and head_pos.distance_to(m.global_position) < (m.pick_radius() + 4.0):
			bumped.emit(m)
			return
	for n in get_tree().get_nodes_in_group("hoverable"):
		if n is Interactable and n.passive_active() and n.is_visible_in_tree() and head_pos.distance_to(n.global_position) < n.pick_radius():
			bumped.emit(n)
			return

# ---------------------------------------------------------------- 대열 렌더링

func _layout_sprites() -> void:
	if _sprites.is_empty():
		return
	_anim_t += get_physics_process_delta_time() * 8.0
	var frame_col: int = [0, 1, 2, 1][int(_anim_t) % 4] if _moving else 1
	# 살아있는 멤버 먼저 (용사 사망 → 리더 교대), 유령은 뒤에서 둥둥
	var order: Array = []
	for i in Game.members.size():
		if not Game.members[i]["ghost"]:
			order.append(i)
	for i in Game.members.size():
		if Game.members[i]["ghost"]:
			order.append(i)
	for slot in order.size():
		var idx: int = order[slot]
		if idx >= _sprites.size():
			continue
		var s: Sprite2D = _sprites[idx]
		if not is_instance_valid(s):
			continue
		var hist_i: int = mini(slot * SPACING, _history.size() - 1)
		var p: Vector2 = _history[hist_i] if hist_i >= 0 else head_pos
		s.position = p
		s.z_index = order.size() - slot
		var ghost: bool = Game.members[idx]["ghost"]
		if ghost:
			s.modulate = Color(0.75, 0.85, 1.3, 0.5)
			s.position.y -= 3.0 + sin(_bob_t + slot) * 2.0
			s.frame_coords = Vector2i(1, _dir_row)
		else:
			s.modulate = Color(1, 1, 1, 1)
			s.frame_coords = Vector2i(frame_col, _dir_row)

func leader_pos() -> Vector2:
	return head_pos
