class_name BattleWindow
extends Control
## 드퀘식 전투창 — BattleSim 하나를 구독해 그리는 뷰. 창마다 독립 턴 박자 (비동기).
## 드퀘다움: 이중 테두리 / 타자기 텍스트+블립음+▼ / 펼침 등장 / 몬스터 중앙 크게

signal golden_hover_changed(hovering: bool)
signal flee_requested

var sim: BattleSim
var is_boss := false
var closing := false
var _linger_t := 0.0        # 바드의 여운 — 커서를 떼도 주시가 잔류
var _dust_t := 0.0          # 주시 금가루 파티클 타이머
var _flee_btn: Button = null

var _enemy_nodes: Array = []          # TextureRect
var _enemy_tex_sizes: Array = []      # 원본 텍스처 크기 (재배율용)
var _enemy_base_pos: Array = []
var _log_label: Label
var _base_position := Vector2.ZERO
var _flash := 0.0
var _golden: TextureRect = null
var _golden_hovering := false
var _squish_cd := 0.0
var _wiggle_t := 0.0
var _t := 0.0

# 타자기 (메시지 큐 → 한 글자씩)
var _msg_queue: Array[String] = []
var _lines: Array[String] = []
var _typing := ""
var _typed := 0
var _type_t := 0.0

func setup(p_sim: BattleSim, p_size: Vector2, boss: bool) -> void:
	sim = p_sim
	is_boss = boss
	custom_minimum_size = p_size
	size = p_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	sim.line.connect(_on_line)
	sim.enemy_hit.connect(_on_enemy_hit)
	sim.member_hit.connect(_on_member_hit)
	sim.golden_spawned.connect(_on_golden_spawned)
	sim.golden_escaped.connect(_on_golden_escaped)
	sim.golden_captured.connect(_on_golden_captured)
	sim.victory.connect(_on_victory)
	sim.frogified.connect(_on_frogified)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _ready() -> void:
	_base_position = position
	pivot_offset = size / 2.0
	clip_contents = true
	_build_enemies()
	_log_label = UILib.make_label("", UILib.FS)
	_log_label.add_theme_constant_override("line_spacing", -3)
	_log_label.position = Vector2(8, size.y - 42)
	_log_label.size = Vector2(size.x - 16, 34)
	_log_label.clip_text = true
	add_child(_log_label)
	# 드퀘식 펼침 — 중앙에서 확장 (0.1초)
	scale = Vector2(0.05, 0.05)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	Sfx.play("window", randf_range(0.95, 1.05))
	# 몬스터 등장 바운스
	for tr in _enemy_nodes:
		if is_instance_valid(tr):
			tr.scale = Vector2(1.0, 0.4)
			var tw2 := create_tween()
			tw2.tween_interval(0.08)
			tw2.tween_property(tr, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

func _build_enemies() -> void:
	for e in sim.enemies:
		var tex: Texture2D
		if e["tex"] is String:
			tex = load(e["tex"])
		else:
			tex = e["tex"]
		var tr := TextureRect.new()
		tr.texture = tex
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if e.has("tint"):
			tr.modulate = e["tint"]
		add_child(tr)
		_enemy_nodes.append(tr)
		_enemy_tex_sizes.append(Vector2(tex.get_width(), tex.get_height()))
		_enemy_base_pos.append(Vector2.ZERO)
	_layout_enemies()

func _layout_enemies() -> void:
	# 몬스터는 검은 바탕 정중앙, 창 높이의 ~55%로 크게 (정수 배율)
	if _enemy_nodes.is_empty():
		return
	var log_h := 44.0
	var area_h := size.y - log_h - 4.0
	var target_h := size.y * 0.5
	var s := 4
	while s > 1:
		var total_w := 0.0
		var fits := true
		for i in _enemy_tex_sizes.size():
			var sc := clampi(int(target_h / _enemy_tex_sizes[i].y), 1, s)
			total_w += _enemy_tex_sizes[i].x * sc + 5.0
			if _enemy_tex_sizes[i].y * sc > area_h - 4.0:
				fits = false
		if fits and total_w - 5.0 <= size.x - 12.0:
			break
		s -= 1
	var widths: Array = []
	var total := 0.0
	for i in _enemy_tex_sizes.size():
		var sc := clampi(int(target_h / _enemy_tex_sizes[i].y), 1, s)
		widths.append(_enemy_tex_sizes[i] * sc)
		total += _enemy_tex_sizes[i].x * sc
	total += 5.0 * (_enemy_nodes.size() - 1)
	var x := (size.x - total) / 2.0
	for i in _enemy_nodes.size():
		var tr: TextureRect = _enemy_nodes[i]
		if not is_instance_valid(tr):
			continue
		var sz: Vector2 = widths[i]
		tr.size = sz
		tr.pivot_offset = Vector2(sz.x / 2.0, sz.y)  # 발밑 기준 (바운스용)
		tr.position = Vector2(x, 4.0 + (area_h - sz.y) / 2.0)
		_enemy_base_pos[i] = tr.position
		x += sz.x + 5.0

func apply_dock(pos: Vector2, sz: Vector2) -> void:
	# 창 수에 따른 반응형 도킹 — 위치는 트윈, 크기는 즉시 + 내부 재배치
	_base_position = pos
	if sz != size:
		size = sz
		custom_minimum_size = sz
		pivot_offset = sz / 2.0
		if _log_label != null:
			_log_label.position = Vector2(8, size.y - 42)
			_log_label.size = Vector2(size.x - 16, 34)
		_layout_enemies()
		if _golden != null and is_instance_valid(_golden):
			_golden.position = _golden.position.clamp(Vector2(4, 4), size - _golden.size - Vector2(4, 4))
		if _flee_btn != null and is_instance_valid(_flee_btn):
			_flee_btn.position = Vector2(size.x - 40, 4)
		queue_redraw()
	var tw := create_tween()
	tw.tween_property(self, "position", pos, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	if closing:
		return
	sim.tick(delta)
	_t += delta
	_squish_cd = maxf(0.0, _squish_cd - delta)
	_type_tick(delta)
	queue_redraw()
	if _flash > 0.0:
		_flash -= delta
	# 바드의 여운 — 커서가 떠나도 주시가 잠시 남는다
	if _linger_t > 0.0:
		_linger_t -= delta
		if _linger_t <= 0.0 and sim != null and not get_global_rect().has_point(get_global_mouse_position()):
			sim.hovered = false
			_update_flee_btn()
	# 주시 금가루 — 지켜보는 창에서 반짝임이 피어오른다 (v3.1 §B-7-1)
	if sim != null and sim.hovered:
		_dust_t -= delta
		if _dust_t <= 0.0:
			_dust_t = 0.22
			_spawn_gaze_dust()
	if _golden != null and is_instance_valid(_golden) and sim.golden_active:
		_wiggle_t += delta * (6.0 + sim.golden_gauge * 14.0)
		_golden.position.x += sin(_wiggle_t) * 0.6
		_golden.scale.y = 1.0 + sin(_wiggle_t * 2.0) * 0.08 * (1.0 + sim.golden_gauge)
		var hov := Rect2(_golden.position - Vector2(6, 6), _golden.size + Vector2(12, 12)).has_point(get_local_mouse_position())
		if hov != _golden_hovering:
			_golden_hovering = hov
			golden_hover_changed.emit(hov)

func is_golden_hovering() -> bool:
	return _golden_hovering and sim != null and sim.golden_active

# ---------------------------------------------------------------- 타자기 로그

func _on_line(text: String) -> void:
	_msg_queue.append(text)

func _type_tick(delta: float) -> void:
	# 큐 폭주 시 오래된 메시지는 즉시 커밋
	while _msg_queue.size() > 6:
		_commit_full_line(_msg_queue.pop_front())
	if _typing == "" and not _msg_queue.is_empty():
		_typing = _msg_queue.pop_front()
		_typed = 0
		_type_t = 0.0
		_lines.append("")
		while _lines.size() > 3:
			_lines.pop_front()
	if _typing == "":
		return
	# 큐가 밀릴수록 타자가 빨라진다
	var interval := 0.028
	if _msg_queue.size() >= 3:
		interval = 0.008
	elif _msg_queue.size() >= 1:
		interval = 0.014
	_type_t += delta
	while _type_t >= interval and _typed < _typing.length():
		_type_t -= interval
		_typed += 1
		if _typed % 3 == 1:
			Sfx.play("blip", randf_range(0.85, 1.15), -14.0)
	_lines[_lines.size() - 1] = _typing.substr(0, _typed)
	_update_log()
	if _typed >= _typing.length():
		_typing = ""

func _commit_full_line(text: String) -> void:
	_lines.append(text)
	while _lines.size() > 3:
		_lines.pop_front()
	_update_log()

func _update_log() -> void:
	if _log_label != null:
		_log_label.text = "\n".join(_lines)

# ---------------------------------------------------------------- draw (이중 테두리 + ▼)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UILib.COL_BG, true)
	var border := UILib.COL_WHITE
	if sim != null and sim.hovered:
		# 주시 중 — 금색 테두리가 숨쉬듯 맥동한다 (v3.1 §B-7-1)
		var pulse := 0.75 + 0.25 * sin(_t * 5.0)
		border = Color(UILib.COL_GOLD.r * pulse + 0.2, UILib.COL_GOLD.g * pulse + 0.2, UILib.COL_GOLD.b * pulse * 0.5)
	if _flash > 0.0:
		border = UILib.COL_GOLD if int(_flash * 12.0) % 2 == 0 else UILib.COL_WHITE
	# 굵은 외곽선(2px) + 1px 간격 + 얇은 안쪽 선 — 드퀘 정품 문법
	draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), border, false, 2.0)
	var inner := Color(0.6, 0.15, 0.15) if is_boss else Color(border.r, border.g, border.b, 0.85)
	draw_rect(Rect2(Vector2(5, 5), size - Vector2(10, 10)), inner, false, 1.0)
	# 대기 커서 ▼ — 할 말이 다 찍혔을 때 깜빡인다 (자동 진행이지만, 문법이니까)
	if _typing == "" and _msg_queue.is_empty() and not _lines.is_empty() and sin(_t * 6.0) > 0.0:
		var cx := size.x / 2.0
		var cy := size.y - 7.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - 4, cy), Vector2(cx + 4, cy), Vector2(cx, cy + 4)]), UILib.COL_WHITE)
	# 황금 슬라임 포획 게이지
	if _golden != null and is_instance_valid(_golden) and sim.golden_active and sim.golden_gauge > 0.01:
		var c := _golden.position + _golden.size / 2.0
		draw_arc(c, 15.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(sim.golden_gauge, 0.0, 1.0), 24, UILib.COL_GOLD, 2.0)

# ---------------------------------------------------------------- battle feedback

func _on_enemy_hit(index: int, _dmg: int, crit: bool, dead: bool) -> void:
	if closing or index >= _enemy_nodes.size():
		return
	var node: TextureRect = _enemy_nodes[index]
	if not is_instance_valid(node):
		return
	Sfx.play("crit" if crit else "hit", randf_range(0.9, 1.1) * (1.15 if sim.hovered else 1.0))
	# 흰색 플래시 + 몬스터 흔들림 + 창 미세 셰이크
	var tw := create_tween()
	node.modulate = Color(6, 6, 6)
	tw.tween_property(node, "modulate", Color(1, 1, 1), 0.12)
	var base: Vector2 = _enemy_base_pos[index]
	node.position = base + Vector2(randf_range(-3, 3), randf_range(-2, 2))
	tw.parallel().tween_property(node, "position", base, 0.12)
	var tw3 := create_tween()
	position = _base_position + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
	tw3.tween_property(self, "position", _base_position, 0.08)
	_popup(str(_dmg), node.position + Vector2(node.size.x / 2.0, -4), UILib.COL_GOLD if crit else UILib.COL_WHITE, 12 if crit else 10)
	if dead:
		var tw2 := create_tween()
		tw2.tween_property(node, "modulate:a", 0.0, 0.35)
		tw2.parallel().tween_property(node, "scale", Vector2(1.2, 0.1), 0.35)

func _on_member_hit(_idx: int, _dmg: int, fell: bool) -> void:
	if closing:
		return
	Sfx.play("hurt", randf_range(0.9, 1.05))
	if fell:
		Sfx.play("ghost")
	# 창 흔들림 — "여기서 맞았다"
	var tw := create_tween()
	position = _base_position + Vector2(randf_range(-3, 3), randf_range(-3, 3))
	tw.tween_property(self, "position", _base_position, 0.15)

func _popup(text: String, at: Vector2, color: Color, fsize: int = 10) -> void:
	var l := UILib.make_label(text, fsize, color)
	l.position = at + Vector2(-10, -10)
	l.z_index = 5
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 14.0, 0.5)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)

func _on_victory(_gold: int, _exp: int) -> void:
	_flash = 0.8
	Sfx.play("fanfare", randf_range(0.92, 1.08))

# ---------------------------------------------------------------- hover (주시)

func _on_mouse_entered() -> void:
	if sim != null:
		sim.hovered = true
	_linger_t = 0.0
	Sfx.gaze_loop(true)
	_update_flee_btn()
	queue_redraw()

func _on_mouse_exited() -> void:
	if sim != null:
		if Game.passive_on("linger"):
			_linger_t = 2.5  # 바드의 여운
		else:
			sim.hovered = false
	Sfx.gaze_loop(false)
	_update_flee_btn()
	if _golden_hovering:
		_golden_hovering = false
		golden_hover_changed.emit(false)
	queue_redraw()

func _spawn_gaze_dust() -> void:
	# 창 안 아무 데서나 금가루가 떠오른다
	var d := ColorRect.new()
	d.color = Color(1.0, 0.85, 0.3, 0.9)
	d.size = Vector2(2, 2)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.position = Vector2(randf_range(8, size.x - 10), randf_range(size.y * 0.4, size.y - 46))
	d.z_index = 3
	add_child(d)
	var tw := create_tween()
	tw.tween_property(d, "position:y", d.position.y - randf_range(10, 20), 0.7)
	tw.parallel().tween_property(d, "modulate:a", 0.0, 0.7)
	tw.tween_callback(d.queue_free)

func _update_flee_btn() -> void:
	# 도망 버튼 — 퇴각 나팔 해금 후, 주시 중인 창 구석에만 (v3.1 §B-7-6)
	var want: bool = sim != null and sim.hovered and not closing and Game.up["flee"] > 0 and not is_boss
	if want and _flee_btn == null:
		_flee_btn = UILib.make_button("도망", UILib.FS)
		_flee_btn.position = Vector2(size.x - 40, 4)
		_flee_btn.z_index = 6
		_flee_btn.pressed.connect(func():
			Sfx.play("flee")
			flee_requested.emit())
		add_child(_flee_btn)
	elif not want and _flee_btn != null:
		if is_instance_valid(_flee_btn):
			_flee_btn.queue_free()
		_flee_btn = null

func _on_frogified() -> void:
	# 개구리의 왈츠 — 몬스터들이 초록으로 물들어 꿈틀거린다
	Sfx.play("squish", 0.7)
	for tr in _enemy_nodes:
		if is_instance_valid(tr):
			tr.modulate = Color(0.5, 1.3, 0.5)
			var tw := create_tween()
			tw.set_loops(4)
			tw.tween_property(tr, "scale", Vector2(1.15, 0.85), 0.12)
			tw.tween_property(tr, "scale", Vector2.ONE, 0.12)

# ---------------------------------------------------------------- 황금 슬라임

func _on_golden_spawned() -> void:
	Sfx.play("golden")
	_golden = TextureRect.new()
	_golden.texture = load("res://assets/enemies/slime.png")
	_golden.stretch_mode = TextureRect.STRETCH_SCALE
	_golden.size = Vector2(15, 17)
	_golden.modulate = Color(3.4, 2.3, 0.3)  # 파란 슬라임을 빛나는 금색으로
	_golden.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_golden.pivot_offset = _golden.size / 2.0
	_golden.position = Vector2(randf_range(16, size.x - 34), randf_range(12, size.y - (UILib.FS * 3.0 + 36.0)))
	_golden.z_index = 4
	add_child(_golden)

func _gui_input(event: InputEvent) -> void:
	if sim == null or not sim.golden_active or _golden == null:
		return
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		var rect := Rect2(_golden.position - Vector2(6, 6), _golden.size + Vector2(12, 12))
		if rect.has_point(event.position):
			sim.rub_golden(event.relative.length() / 300.0)
			accept_event()
			# rub_golden으로 포획이 완성되면 _on_golden_captured가 _golden을 null로 만든다
			if _golden == null or not is_instance_valid(_golden):
				return
			if _squish_cd <= 0.0:
				_squish_cd = 0.1
				Sfx.play("squish", 0.9 + sim.golden_gauge * 0.9)
				var tw := create_tween()
				_golden.scale = Vector2(1.25, 0.75)
				tw.tween_property(_golden, "scale", Vector2.ONE, 0.12)

func _on_golden_escaped() -> void:
	Sfx.play("flee")
	if _golden != null and is_instance_valid(_golden):
		var tw := create_tween()
		tw.tween_property(_golden, "position", Vector2(size.x + 40, -40), 0.5)
		tw.parallel().tween_property(_golden, "modulate:a", 0.0, 0.5)
		tw.tween_callback(_golden.queue_free)
	_golden = null
	if _golden_hovering:
		_golden_hovering = false
		golden_hover_changed.emit(false)

func _on_golden_captured(_reward: int) -> void:
	Sfx.play("capture")
	if _golden != null and is_instance_valid(_golden):
		var tw := create_tween()
		tw.tween_property(_golden, "scale", Vector2(1.6, 1.6), 0.2)
		tw.parallel().tween_property(_golden, "modulate:a", 0.0, 0.3)
		tw.tween_callback(_golden.queue_free)
	_golden = null
	if _golden_hovering:
		_golden_hovering = false
		golden_hover_changed.emit(false)

# ---------------------------------------------------------------- close

func close_after(delay: float) -> void:
	if closing:
		return
	closing = true
	if sim != null and sim.hovered:
		Sfx.gaze_loop(false)
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(self, "scale", Vector2(0.85, 0.85), 0.12)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.12)
	tw.tween_callback(queue_free)
