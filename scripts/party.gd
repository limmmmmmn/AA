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
var _charm_sprites: Array = []     # 매혹된 몬스터 (장식 추종자)
var _mount_sprite: Sprite2D = null # 탈것 (v3.2 §B-2 — 용사 밑에서 뜀박질)
var _anim_t := 0.0
var _dir_row := 0                  # 0 아래 1 왼쪽 2 오른쪽 3 위
var _slot_dir_cache := {}          # v4.1: 멤버별 마지막 시선 (정지 시 깜빡임 방지)
var _moving := false
var _bob_t := 0.0
var combo_glow := false            # 합체기 준비 완료 — 파티 발광
var underwater := false            # 수중 필드 — 물고기화 (v3.2 §B-1)
var _vel := Vector2.ZERO           # 수중 관성

func set_underwater(v: bool) -> void:
	if underwater == v:
		return
	underwater = v
	_vel = Vector2.ZERO
	_rebuild_sprites()

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
		if underwater:
			# 물고기화 (v3.2 §B-1 — "일행은 물고기가 되었다!") 임시: 물고기 도트는 png 교체 예정
			s.texture = load("res://assets/enemies/slime_fly.png")
			s.offset = Vector2(0, -float(s.texture.get_height()) / 2.0)
		else:
			s.texture = load(d["tex"])
			s.hframes = 3
			s.vframes = 4
			s.frame = 1
			s.offset = Vector2(0, -float(d["frame_h"]) / 2.0)
		add_child(s)
		_sprites.append(s)
	# 탈것 — 이속 트리의 끝 (v3.2 §B-2). 임시: 금빛 새 실루엣
	if _mount_sprite != null and is_instance_valid(_mount_sprite):
		_mount_sprite.queue_free()
	_mount_sprite = null
	if Game.mounted() and not underwater:
		_mount_sprite = Sprite2D.new()
		_mount_sprite.texture = load("res://assets/enemies/bat.png")
		_mount_sprite.modulate = Color(1.6, 1.3, 0.5)
		_mount_sprite.offset = Vector2(0, -4)
		add_child(_mount_sprite)
	_rebuild_charmed()

func _rebuild_charmed() -> void:
	# 매혹된 몬스터 — 대열 꽁무니를 따라오는 장식 (v3.1 드루이드/서사시)
	for c in _charm_sprites:
		if is_instance_valid(c):
			c.queue_free()
	_charm_sprites = []
	for mid in Game.charmed:
		var def := {}
		for md in Game.MONSTER_DEFS:
			if md["id"] == mid:
				def = md
				break
		if def.is_empty():
			continue
		var s := Sprite2D.new()
		s.texture = load(def["tex"])
		s.modulate = Color(1.0, 0.85, 1.0)  # 홀린 기색
		add_child(s)
		_charm_sprites.append(s)

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
	elif underwater and _vel.length() > 8.0:
		# 수중 관성 — 손을 떼도 잠깐 미끄러진다 (v3.2 §B-1)
		_vel = _vel.lerp(Vector2.ZERO, minf(1.0, 2.5 * delta))
		head_pos = (head_pos + _vel * delta).clamp(bounds_min, bounds_max)
		_moving = true
		if _history.is_empty() or head_pos.distance_to(_history[0]) >= HISTORY_STEP:
			_history.push_front(head_pos)
			if _history.size() > 120:
				_history.pop_back()
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
	if underwater:
		# 8방향 부유 + 가벼운 관성
		_vel = _vel.lerp(dir * Game.move_speed(), minf(1.0, 5.0 * delta))
		head_pos += _vel * delta
	else:
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
		# v4.1: 팔로워는 자기 궤적의 접선으로 시선을 잡는다 — 리더가 꺾여도 뒤로 걷지 않는다
		var slot_dir: int = _dir_row
		if slot > 0 and _moving:
			var ahead: int = maxi(0, hist_i - SPACING)     # 궤적 상 앞(더 새 위치)
			var move_vec: Vector2 = _history[ahead] - p
			if move_vec.length() > 0.5:
				slot_dir = _dir_from(move_vec)
			else:
				slot_dir = _slot_dir_cache.get(idx, _dir_row)
		_slot_dir_cache[idx] = slot_dir
		var ghost: bool = Game.members[idx]["ghost"]
		if ghost:
			s.modulate = Color(0.75, 0.85, 1.3, 0.5)
			s.position.y -= 3.0 + sin(_bob_t + slot) * 2.0
			if not underwater:
				s.frame_coords = Vector2i(1, slot_dir)
		else:
			var tint: Color = Game.COMPANIONS[Game.members[idx]["cls"]].get("tint", Color(1, 1, 1))
			if Game.members[idx]["cls"] == "hero" and Game.roto_count() > 0:
				# 로토 세트 단계 변신 (v3.2 §B-7 — 임시: 점점 금빛으로. 도트 3단은 png 교체 예정)
				var rc := float(Game.roto_count())
				tint = Color(tint.r + 0.12 * rc, tint.g + 0.09 * rc, tint.b - 0.05 * rc)
			if combo_glow:
				# 합체기 준비 완료 — 온몸이 은은하게 빛난다
				var g := 1.0 + 0.35 * (0.5 + 0.5 * sin(_bob_t * 2.5))
				tint = Color(tint.r * g, tint.g * g, tint.b * g)
			s.modulate = tint
			if underwater:
				s.position.y -= 2.0 + sin(_bob_t * 1.6 + slot * 0.7) * 2.5  # 부유
				s.flip_h = slot_dir == 1
			else:
				s.frame_coords = Vector2i(frame_col, slot_dir)
	# 탈것 — 용사 발밑에서 함께 달린다
	if _mount_sprite != null and is_instance_valid(_mount_sprite) and not _sprites.is_empty() and is_instance_valid(_sprites[0]):
		_mount_sprite.position = _sprites[0].position + Vector2(0, 1)
		_mount_sprite.position.y += sin(_bob_t * 6.0) * (1.5 if _moving else 0.5)
		_mount_sprite.z_index = _sprites[0].z_index - 1
		_mount_sprite.flip_h = _dir_row == 1
	# 매혹된 몬스터는 대열 맨 뒤에서 통통
	for ci in _charm_sprites.size():
		var cs: Sprite2D = _charm_sprites[ci]
		if not is_instance_valid(cs):
			continue
		var hist_c: int = mini((order.size() + ci) * SPACING, _history.size() - 1)
		cs.position = _history[hist_c] if hist_c >= 0 else head_pos
		cs.position.y -= absf(sin(_bob_t * 1.5 + ci)) * 3.0
		cs.z_index = 0

func refresh_charmed() -> void:
	_rebuild_charmed()

func leader_pos() -> Vector2:
	return head_pos
