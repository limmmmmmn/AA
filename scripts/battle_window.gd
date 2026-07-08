class_name BattleWindow
extends Control
## 드퀘식 전투창 — BattleSim 하나를 구독해 그리는 뷰. 창마다 독립 턴 박자 (비동기).
## 드퀘다움: 이중 테두리 / 타자기 텍스트+블립음+▼ / 펼침 등장 / 몬스터 중앙 크게

signal golden_hover_changed(hovering: bool)
signal flee_requested
signal clicked                      # 스택 셔플용 (v3.4 §B-1)

var sim: BattleSim
var is_boss := false
var closing := false
var _linger_t := 0.0        # 바드의 여운 — 커서를 떼도 주시가 잔류
var _dust_t := 0.0          # 주시 금가루 파티클 타이머
var _flee_btn: Button = null

var _enemy_nodes: Array = []          # TextureRect
var _enemy_tex_sizes: Array = []      # 원본 텍스처 크기 (재배율용)
var _enemy_base_pos: Array = []
var _log_label: RichTextLabel
var _base_position := Vector2.ZERO
var _base_width := 120.0              # v4.1: 기본 창 폭 (큰 적 확장의 하한)
var _flash := 0.0
var _golden: TextureRect = null
var _golden_hovering := false
var _squish_cd := 0.0
var _wiggle_t := 0.0
var _t := 0.0

# 타자기 (v3.8: RichTextLabel + visible_characters — 자동 채색과 공존)
var _msg_queue: Array[String] = []
var _lines_bb: Array[String] = []   # 표시 중인 줄 (bbcode)
var _lines_plain: Array[int] = []   # 줄별 순수 글자 수 (태그 제외)
var _shown := 0.0                   # 드러난 글자 수 (float 누적)
var _type_t := 0.0
static var _strip_rx: RegEx = null

func setup(p_sim: BattleSim, p_size: Vector2, boss: bool) -> void:
	sim = p_sim
	is_boss = boss
	_base_width = p_size.x
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
	sim.enemy_acted.connect(_on_enemy_acted)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

## 타자기 속도 튜닝 (v3.5 — 인스펙터에서 조절)
@export var type_interval := 0.028       # 한 글자 간격 (초)
@export var type_interval_busy := 0.014  # 큐가 밀릴 때
@export var type_interval_rush := 0.008  # 큐 폭주 시

func _ready() -> void:
	_base_position = position
	pivot_offset = size / 2.0
	clip_contents = true
	_build_enemies()
	# v3.8: 로그 = RichTextLabel (자동 채색 + [slam] 크리 + visible_characters 타자기)
	_log_label = get_node_or_null("%LogLabel")
	if _log_label == null:
		_log_label = RichTextLabel.new()
		_log_label.bbcode_enabled = true
		_log_label.scroll_active = false
		_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_log_label.add_theme_constant_override("line_separation", -3)
		add_child(_log_label)
	_log_label.install_effect(SlamFX.new())
	_log_label.install_effect(WhisperFX.new())
	_log_label.position = Vector2(7, size.y - 28)
	_log_label.size = Vector2(size.x - 14, 26)
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
	# v3.9: 몬스터는 원본 1배수 고정. v4.1: 큰 적이 여럿이면 창을 가로로 늘려 다 담는다
	if _enemy_nodes.is_empty():
		return
	var total := 0.0
	for i in _enemy_tex_sizes.size():
		total += _enemy_tex_sizes[i].x
	total += 5.0 * (_enemy_nodes.size() - 1)
	# 필요 폭이 기본 창을 넘으면 창 자체를 확장 (박쥐 4마리 등) — 보스 창은 고정
	if not is_boss:
		var need_w := total + 16.0
		var want_w := maxf(_base_width, ceilf(need_w))
		if absf(size.x - want_w) > 0.5:
			size.x = want_w
			custom_minimum_size.x = want_w
			pivot_offset = size / 2.0
			if _log_label != null:
				_log_label.position = Vector2(7, size.y - 28)
				_log_label.size = Vector2(size.x - 14, 26)
			if _flee_btn != null and is_instance_valid(_flee_btn):
				_flee_btn.position = Vector2(size.x - 40, 4)
	var log_h := size.y / 3.0
	var area_h := size.y - log_h - 4.0
	var x := (size.x - total) / 2.0
	for i in _enemy_nodes.size():
		var tr: TextureRect = _enemy_nodes[i]
		if not is_instance_valid(tr):
			continue
		var sz: Vector2 = _enemy_tex_sizes[i]  # 1:1 원본
		tr.size = sz
		tr.pivot_offset = Vector2(sz.x / 2.0, sz.y)  # 발밑 기준 (바운스용)
		tr.position = Vector2(x, 4.0 + (area_h - sz.y) / 2.0)
		_enemy_base_pos[i] = tr.position
		x += sz.x + 5.0

func nudge_to(pos: Vector2) -> void:
	# 밀어내기 결과 위치 확정 — 피격 흔들림 복귀 지점도 함께 갱신 (v3.9 §B-4)
	position = pos
	_base_position = pos

func apply_dock(pos: Vector2, sz: Vector2) -> void:
	# 창 수에 따른 반응형 도킹 — 위치는 트윈, 크기는 즉시 + 내부 재배치
	_base_position = pos
	if sz != size:
		size = sz
		custom_minimum_size = sz
		pivot_offset = sz / 2.0
		if _log_label != null:
			_log_label.position = Vector2(7, size.y - 28)
			_log_label.size = Vector2(size.x - 14, 22)
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
	_msg_queue.append(UILib.colorize(text))  # v3.8 §B-1: 자동 채색은 시스템의 일

func _plain_len(bb: String) -> int:
	if _strip_rx == null:
		_strip_rx = RegEx.new()
		_strip_rx.compile(r"\[.*?\]")
	return _strip_rx.sub(bb, "", true).length()

func _total_plain() -> int:
	var t := 0
	for pl in _lines_plain:
		t += pl
	return t + maxi(0, _lines_plain.size() - 1)  # 줄바꿈도 한 글자

func _commit_line(bb: String) -> void:
	# 두 줄만 산다 — 앞줄이 밀려나면 드러난 글자 수도 함께 이사
	if _lines_bb.size() >= 2:
		_shown = maxf(0.0, _shown - float(_lines_plain[0] + 1))
		_lines_bb.pop_front()
		_lines_plain.pop_front()
	_lines_bb.append(bb)
	_lines_plain.append(_plain_len(bb))
	if _log_label != null:
		_log_label.text = "\n".join(_lines_bb)

func _type_tick(delta: float) -> void:
	# 큐 폭주 시 오래된 메시지는 즉시 커밋 (드러난 채로)
	while _msg_queue.size() > 6:
		_commit_line(_msg_queue.pop_front())
		_shown = float(_total_plain())
	var total := _total_plain()
	if int(_shown) >= total and not _msg_queue.is_empty():
		_commit_line(_msg_queue.pop_front())
		total = _total_plain()
		_type_t = 0.0
	if int(_shown) >= total:
		if _log_label != null:
			_log_label.visible_characters = -1
		return
	# 텍스트 속도 옵션: 순간 = 즉시 (v3.3 §D)
	var tmult: float = Game.opt_type_mult()
	if tmult <= 0.0:
		_shown = float(total)
		_log_label.visible_characters = -1
		return
	# 큐가 밀릴수록 타자가 빨라진다 (@export 튜닝)
	var interval := type_interval * tmult
	if _msg_queue.size() >= 3:
		interval = type_interval_rush * tmult
	elif _msg_queue.size() >= 1:
		interval = type_interval_busy * tmult
	_type_t += delta
	while _type_t >= interval and int(_shown) < total:
		_type_t -= interval
		_shown += 1.0
		if int(_shown) % 3 == 1:
			Sfx.play("blip", randf_range(0.85, 1.15), -14.0)
	_log_label.visible_characters = int(_shown)

# ---------------------------------------------------------------- draw (v3.7: 무테 유색 카드 — 드퀘1 고증)

var _card_sb: StyleBoxFlat = null
var _frame_sb: StyleBoxFlat = null

func _card_color() -> Color:
	# 몬스터 계열색 (§B) — 보스는 살짝 어둡게 눌러 위압감
	var fam := "slime"
	if sim != null and not sim.enemies.is_empty():
		fam = String(sim.enemies[0].get("family", "slime"))
	var c := UILib.family_color(fam)
	if is_boss:
		c = c.darkened(0.25)
	if Game.is_night():
		c = c.darkened(0.15)
	return c

func _draw() -> void:
	# 무테 유색 카드 — 라운드 + 하단 그림자 (필드 위에 떠 있는 카드)
	if _card_sb == null:
		# v3.8 §B-3: "색종이 → 떠 있는 카드" — 1px 남색 아웃라인 + 하단 드롭섀도
		_card_sb = StyleBoxFlat.new()
		_card_sb.set_corner_radius_all(2)
		_card_sb.set_border_width_all(1)
		_card_sb.border_color = Color("1a1c2c")
		_card_sb.shadow_color = Color(0.102, 0.11, 0.173, 0.55)
		_card_sb.shadow_size = 2
		_card_sb.shadow_offset = Vector2(0, 2)
	_card_sb.bg_color = _card_color()
	draw_style_box(_card_sb, Rect2(Vector2.ZERO, size))
	# 텍스트 존 — 하단 1/3에 반투명 남색 띠 (어느 계열색 위에서도 읽히게)
	var strip_h := size.y / 3.0
	draw_rect(Rect2(Vector2(0, size.y - strip_h), Vector2(size.x, strip_h)), Color(0.102, 0.11, 0.173, 0.78), true)
	# 상태 오버레이 (정보 레이어 — §C)
	if _frame_sb == null:
		_frame_sb = StyleBoxFlat.new()
		_frame_sb.draw_center = false
		_frame_sb.set_corner_radius_all(2)
		_frame_sb.set_border_width_all(2)
	var frame_col := Color(0, 0, 0, 0)
	if sim != null and sim.golden_active:
		# 황금/은빛 슬라임 = 금/은 특수 프레임
		frame_col = Color(0.75, 0.78, 0.85) if sim.golden_silver else UILib.COL_GOLD
		frame_col.a = 0.8 + 0.2 * sin(_t * 7.0)
	elif sim != null and sim.hovered:
		# 호버 = 금테가 "생긴다" — 무테→유테 전환이 곧 시선의 시각화
		var pulse := 0.8 + 0.2 * sin(_t * 5.0)
		frame_col = Color(UILib.COL_GOLD.r, UILib.COL_GOLD.g, UILib.COL_GOLD.b, pulse)
	elif Game.lowest_hp_ratio() < 0.3 and sim != null and not sim.finished:
		# 위험 — 파티가 밀리는 중, 가장자리 적색 점멸
		if sin(_t * 8.0) > 0.0:
			frame_col = UILib.COL_RED
	if _flash > 0.0:
		frame_col = UILib.COL_GOLD if int(_flash * 12.0) % 2 == 0 else UILib.COL_WHITE
	if frame_col.a > 0.01:
		_frame_sb.border_color = frame_col
		draw_style_box(_frame_sb, Rect2(Vector2.ZERO, size))
	# 대기 커서 ▼ — 할 말이 다 찍혔을 때 깜빡인다 (자동 진행이지만, 문법이니까)
	if int(_shown) >= _total_plain() and _msg_queue.is_empty() and not _lines_bb.is_empty() and sin(_t * 6.0) > 0.0:
		var cx := size.x / 2.0
		var cy := size.y - 7.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - 4, cy), Vector2(cx + 4, cy), Vector2(cx, cy + 4)]), UILib.COL_WHITE)
	# 황금 슬라임 포획 게이지
	if _golden != null and is_instance_valid(_golden) and sim.golden_active and sim.golden_gauge > 0.01:
		var c := _golden.position + _golden.size / 2.0
		draw_arc(c, 15.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(sim.golden_gauge, 0.0, 1.0), 24, UILib.COL_GOLD, 2.0)
	# 적 미니 HP바 — 12×2px, "어느 창이 곧 끝나나" 판단 재료 (v3.4 §B-11)
	if sim != null:
		for i in mini(_enemy_nodes.size(), sim.enemies.size()):
			var e: Dictionary = sim.enemies[i]
			if e["dead"]:
				continue
			var node: TextureRect = _enemy_nodes[i]
			if not is_instance_valid(node):
				continue
			var bx := node.position.x + node.size.x / 2.0 - 6.0
			var by := node.position.y + node.size.y + 2.0
			var ratio := clampf(float(e["hp"]) / maxf(1.0, float(e["max_hp"])), 0.0, 1.0)
			draw_rect(Rect2(bx, by, 12, 2), Color(0.15, 0.15, 0.2), true)
			draw_rect(Rect2(bx, by, 12.0 * ratio, 2), UILib.COL_GREEN if ratio > 0.35 else UILib.COL_RED, true)

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
	if Game.opt["shake"]:
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
	# 창 흔들림 — "여기서 맞았다" (접근성 옵션으로 끌 수 있다)
	if Game.opt["shake"]:
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
		if Game.up["linger"] > 0:
			_linger_t = 2.5  # 노래의 여운 (축복 업글, v3.9)
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

func _on_enemy_acted(index: int) -> void:
	# 액션 강조 — 공격 주체가 한 발 앞으로 튀는 스텝 (v3.4 §B-11)
	if closing or index >= _enemy_nodes.size():
		return
	var node: TextureRect = _enemy_nodes[index]
	if not is_instance_valid(node) or index >= _enemy_base_pos.size():
		return
	var base: Vector2 = _enemy_base_pos[index]
	node.position = base + Vector2(0, 4)
	var tw := create_tween()
	tw.tween_property(node, "position", base, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

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
	Sfx.play("golden_silver" if sim.golden_silver else "golden")  # J4: 은빛 = 반음계 변형
	_golden = TextureRect.new()
	_golden.texture = load("res://assets/enemies/slime.png")
	_golden.stretch_mode = TextureRect.STRETCH_SCALE
	_golden.size = Vector2(15, 17)
	# 낮=금빛, 밤=은빛 (v3.2 §B-5)
	_golden.modulate = Color(2.2, 2.4, 2.8) if sim.golden_silver else Color(3.4, 2.3, 0.3)
	_golden.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_golden.pivot_offset = _golden.size / 2.0
	_golden.position = Vector2(randf_range(16, size.x - 34), randf_range(12, size.y - (UILib.FS * 3.0 + 36.0)))
	_golden.z_index = 4
	add_child(_golden)

func _gui_input(event: InputEvent) -> void:
	# 좌클릭 = 스택 셔플 신호 (황금 슬라임 문지르기와 별개, v3.4)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and not is_golden_hovering():
		clicked.emit()
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
