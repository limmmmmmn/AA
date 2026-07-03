class_name BattleWindow
extends Control
## 드퀘식 전투창 — BattleSim 하나를 구독해 그리는 뷰. 창마다 독립 턴 박자 (비동기).

signal golden_hover_changed(hovering: bool)

var sim: BattleSim
var is_boss := false
var closing := false

var _enemy_nodes: Array = []          # TextureRect
var _enemy_base_pos: Array = []
var _log_lines: Array[String] = []
var _log_label: Label
var _base_position := Vector2.ZERO
var _flash := 0.0
var _golden: TextureRect = null
var _golden_hovering := false
var _squish_cd := 0.0
var _wiggle_t := 0.0

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
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _ready() -> void:
	_base_position = position
	pivot_offset = size / 2.0
	_build_enemies()
	clip_contents = true
	_log_label = UILib.make_label("\n".join(_log_lines), UILib.FS)
	_log_label.position = Vector2(6, size.y - (UILib.FS * 3 + 10))
	_log_label.size = Vector2(size.x - 12, UILib.FS * 3 + 6)
	_log_label.clip_text = true
	add_child(_log_label)
	# 팝 연출
	scale = Vector2(0.6, 0.6)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("window", randf_range(0.95, 1.05))

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
		tr.size = Vector2(tex.get_width(), tex.get_height()) * float(e["scale"])
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.pivot_offset = tr.size / 2.0
		if e.has("tint"):
			tr.modulate = e["tint"]
		add_child(tr)
		_enemy_nodes.append(tr)
		_enemy_base_pos.append(Vector2.ZERO)
	_layout_enemies()

func _layout_enemies() -> void:
	var total_w := 0.0
	for tr in _enemy_nodes:
		total_w += tr.size.x
	total_w += 5.0 * (_enemy_nodes.size() - 1)
	var x := (size.x - total_w) / 2.0
	var bottom_y := size.y - (UILib.FS * 3.0 + 16.0)
	for i in _enemy_nodes.size():
		var tr: TextureRect = _enemy_nodes[i]
		if not is_instance_valid(tr):
			continue
		tr.position = Vector2(x, bottom_y - tr.size.y)
		_enemy_base_pos[i] = tr.position
		x += tr.size.x + 5.0

func apply_dock(pos: Vector2, sz: Vector2) -> void:
	# 창 수에 따른 반응형 도킹 — 위치는 트윈, 크기는 즉시 + 내부 재배치
	_base_position = pos
	if sz != size:
		size = sz
		custom_minimum_size = sz
		pivot_offset = sz / 2.0
		if _log_label != null:
			_log_label.position = Vector2(6, size.y - (UILib.FS * 3 + 10))
			_log_label.size = Vector2(size.x - 12, UILib.FS * 3 + 6)
		_layout_enemies()
		if _golden != null and is_instance_valid(_golden):
			_golden.position = _golden.position.clamp(Vector2(4, 4), size - _golden.size - Vector2(4, 4))
		queue_redraw()
	var tw := create_tween()
	tw.tween_property(self, "position", pos, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	if closing:
		return
	sim.tick(delta)
	_squish_cd = maxf(0.0, _squish_cd - delta)
	if _flash > 0.0:
		_flash -= delta
		queue_redraw()
	if _golden != null and is_instance_valid(_golden) and sim.golden_active:
		_wiggle_t += delta * (6.0 + sim.golden_gauge * 14.0)
		_golden.position.x += sin(_wiggle_t) * 0.6
		_golden.scale.y = 1.0 + sin(_wiggle_t * 2.0) * 0.08 * (1.0 + sim.golden_gauge)
		var hov := Rect2(_golden.position - Vector2(6, 6), _golden.size + Vector2(12, 12)).has_point(get_local_mouse_position())
		if hov != _golden_hovering:
			_golden_hovering = hov
			golden_hover_changed.emit(hov)
		queue_redraw()

func is_golden_hovering() -> bool:
	return _golden_hovering and sim != null and sim.golden_active

# ---------------------------------------------------------------- draw

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UILib.COL_BG, true)
	var border := UILib.COL_WHITE
	if sim != null and sim.hovered:
		border = UILib.COL_GOLD
	if _flash > 0.0:
		border = UILib.COL_GOLD if int(_flash * 12.0) % 2 == 0 else UILib.COL_WHITE
	if is_boss:
		draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)).abs(), Color(0.6, 0.15, 0.15), false, 2.0)
	draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), border, false, 2.0)
	# 황금 슬라임 포획 게이지
	if _golden != null and is_instance_valid(_golden) and sim.golden_active and sim.golden_gauge > 0.01:
		var c := _golden.position + _golden.size / 2.0
		draw_arc(c, 15.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(sim.golden_gauge, 0.0, 1.0), 24, UILib.COL_GOLD, 2.0)

# ---------------------------------------------------------------- log

func _on_line(text: String) -> void:
	_log_lines.append(text)
	while _log_lines.size() > 3:
		_log_lines.pop_front()
	if _log_label != null:
		_log_label.text = "\n".join(_log_lines)

# ---------------------------------------------------------------- battle feedback

func _on_enemy_hit(index: int, _dmg: int, crit: bool, dead: bool) -> void:
	if closing or index >= _enemy_nodes.size():
		return
	var node: TextureRect = _enemy_nodes[index]
	if not is_instance_valid(node):
		return
	Sfx.play("crit" if crit else "hit", randf_range(0.9, 1.1) * (1.15 if sim.hovered else 1.0))
	# 피격 플래시 + 흔들림
	var tw := create_tween()
	node.modulate = Color(4, 4, 4)
	tw.tween_property(node, "modulate", Color(1, 1, 1), 0.18)
	var base: Vector2 = _enemy_base_pos[index]
	node.position = base + Vector2(randf_range(-3, 3), randf_range(-2, 2))
	tw.parallel().tween_property(node, "position", base, 0.12)
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
	queue_redraw()

func _on_mouse_exited() -> void:
	if sim != null:
		sim.hovered = false
	if _golden_hovering:
		_golden_hovering = false
		golden_hover_changed.emit(false)
	queue_redraw()

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
			if _squish_cd <= 0.0:
				_squish_cd = 0.1
				Sfx.play("squish", 0.9 + sim.golden_gauge * 0.9)
				var tw := create_tween()
				_golden.scale = Vector2(1.25, 0.75)
				tw.tween_property(_golden, "scale", Vector2.ONE, 0.12)
			accept_event()

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
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(self, "scale", Vector2(0.85, 0.85), 0.12)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.12)
	tw.tween_callback(queue_free)
