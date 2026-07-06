class_name Hud
extends CanvasLayer
## 화면 하단 고정 UI — 드퀘식 스테이터스 창 + 상시 설명창 + 메뉴 + 연출 레이어

const SLOT_SIZE := Vector2(150, 84)
const SLOT_POS := [
	Vector2(4, 22), Vector2(158, 22), Vector2(312, 22), Vector2(466, 22),
	Vector2(4, 110), Vector2(158, 110), Vector2(312, 110), Vector2(466, 110),
]
const GOLD_TARGET := Vector2(40, 16)

# 앰비언트 팝 (v3.7 §E — 상시 설명창의 후계자. 뒷문장은 항상 비껴 뜬다)
const AMBIENT_PAIRS := [
	["바람이 분다. 평화롭다.", "…일단은."],
	["어디선가 슬라임 우는 소리가 들린다.", "…조금 귀엽다."],
	["마왕은 이미 이겼다.", "그래서 뭐 어떤가."],
	["일행은 씩씩하게 걷고 있다.", "누군가는 졸면서."],
	["돌아갈 곳이 있다는 건", "좋은 일이다."],
	["마을에 서 있는 사람의 수가", "곧 진행바다."],
]

var main: Node2D

## v3.5 씬 리팩터 — 고정 UI는 scenes/hud.tscn 에디터 노드 (%유니크 네임 참조).
## 위치·크기·색은 에디터에서 수정하면 된다. 코드는 내용만 채운다.
@onready var windows_root: Control = %WindowsRoot
@onready var _party_root: Control = %PartyRoot
@onready var _fx_root: Control = %FxRoot
@onready var _menu_root: Control = %MenuRoot
@onready var _overlay_root: Control = %OverlayRoot
@onready var _top_panel: PanelContainer = %TopPanel
@onready var _top_label: Label = %TopLabel
@onready var _xp_bar: ColorRect = %XPBar
@onready var _party_bar: PanelContainer = %PartyBar
@onready var _party_vbox: VBoxContainer = %PartyVBox
@onready var _tooltip: PanelContainer = %Tooltip
@onready var _tooltip_label: Label = %TooltipLabel
@onready var _event_box: PanelContainer = %EventBox
@onready var _event_label: RichTextLabel = %EventLabel
@onready var _event_portrait: TextureRect = %EventPortrait

const MEMBER_BOX_SCENE := preload("res://scenes/member_box.tscn")

var _member_boxes: Array = []
var _casino_refs: Dictionary = {}
var _spin_active := false
var _board_tab := 0
var room_name := "기지"           # main이 설정

# 성수 게이지 — 통합 파티 바 안의 셀 (v3.7 §D)
var _holy_cell: Control = null
var _holy_bar: ColorRect = null
# 합체기 게이지 셀
var _combo_cell: Control = null
var _combo_fill: ColorRect = null

var _hover_text := ""
var _menu_kind := ""
var menu_hover := ""   # 메뉴 항목 호버 시 툴팁에 흘릴 텍스트

# 이벤트 박스 큐 (§E — 선언은 동시에 하나)
var _event_q: Array = []
var _event_showing := false
var _ambient_t := 45.0

# v3.1
var remote_open := false           # 상인의 텔레파시로 연 메뉴 — 몸 행위 행은 잠긴다
var _hover_heal_idx := -1          # 치유의 눈길 — 호버 중인 멤버 박스

func _ready() -> void:
	Game.gold_changed.connect(func(_v): _update_top())
	Game.level_changed.connect(func(_v): _update_top())
	Game.chapter_changed.connect(func(_v): _update_top())
	Game.party_changed.connect(_rebuild_members)
	Game.member_changed.connect(_update_member)
	Game.upgrades_changed.connect(func(): _update_top())
	# 텍스트 연기 이펙트 설치 (v3.7 §E)
	_event_label.install_effect(SlamFX.new())
	_event_label.install_effect(WhisperFX.new())
	_update_top()
	_rebuild_members()
	# 세이브에서 이미 태어난 UI는 연출 없이 바로 보여준다 (탄생은 최초 1회뿐)
	if Game.ui_unlocked["gold"]:
		_top_panel.visible = true
	if Game.ui_unlocked["party"]:
		_party_bar.visible = true

func _process(delta: float) -> void:
	# 툴팁 (속삭임) — 커서 추종 (v3.7 §E)
	var tip := _hover_text if _hover_text != "" else menu_hover
	if tip != "" and not _title_suppress:
		_tooltip_label.text = tip
		_tooltip.visible = true
		_tooltip.reset_size()
		var mp := get_viewport().get_mouse_position() + Vector2(12, 14)
		mp.x = clampf(mp.x, 2.0, 638.0 - _tooltip.size.x)
		mp.y = clampf(mp.y, 2.0, 358.0 - _tooltip.size.y)
		_tooltip.position = mp
	else:
		_tooltip.visible = false
	# 앰비언트 팝 — 희소해야 시가 된다 (수 분당 1회)
	if not _title_suppress and not is_menu_open():
		_ambient_t -= delta
		if _ambient_t <= 0.0:
			_ambient_t = randf_range(100.0, 190.0)
			_spawn_ambient()
	# 이벤트 박스 큐 소화
	if not _event_showing and not _event_q.is_empty():
		_show_next_event()
	# 파티 컬럼 — 우측 세로 고정 (v3.8 §B-2, FF 오마주. 자라면 아래로)
	if _party_bar.visible:
		_party_bar.position = Vector2(636.0 - _party_bar.size.x, 64.0)
	# 메뉴 스크롤 높이 — 내용에 맞추되 화면을 넘지 않게
	if _menu_sc != null and is_instance_valid(_menu_sc) and _menu_v != null and is_instance_valid(_menu_v):
		var want: float = minf(_menu_v.get_combined_minimum_size().y, 252.0)
		if absf(_menu_sc.custom_minimum_size.y - want) > 0.5:
			_menu_sc.custom_minimum_size = Vector2(312, want)
	# XP 미니바 — 다음 레벨까지의 거리
	if _top_panel.visible and is_instance_valid(_xp_bar):
		var w: float = maxf(0.0, _top_panel.size.x - 16.0)
		_xp_bar.size = Vector2(w * clampf(float(Game.exp) / maxf(1.0, float(Game.exp_to_next())), 0.0, 1.0), 2)
	# 성수 — 자동 재생 / 치유의 눈길 호버 시 소모하며 회복 (셀은 파티 바 안, v3.7 §D)
	if Game.buildings["church"]:
		if _holy_cell != null and is_instance_valid(_holy_cell) and not _holy_cell.visible:
			_holy_cell.visible = true
		var healing := false
		if _hover_heal_idx >= 0 and _hover_heal_idx < Game.members.size() and Game.holy > 0.0:
			var m: Dictionary = Game.members[_hover_heal_idx]
			if not m["ghost"] and m["hp"] < m["max_hp"]:
				Game.holy = maxf(0.0, Game.holy - delta)
				healing = true
				_heal_accum += float(m["max_hp"]) * Game.holy_heal_pct() * delta
				if _heal_accum >= 1.0:
					var amt := int(_heal_accum)
					_heal_accum -= amt
					Game.heal_member(_hover_heal_idx, amt)
		if not healing:
			Game.holy = minf(Game.holy_max(), Game.holy + Game.holy_regen_rate() * delta)
		if _holy_bar != null and is_instance_valid(_holy_bar):
			_holy_bar.size = Vector2(70.0 * clampf(Game.holy / maxf(1.0, Game.holy_max()), 0.0, 1.0), 3)
			_holy_bar.color = Color(0.9, 0.95, 1.0) if healing else Color(0.55, 0.8, 1.0)
	# 합체기 게이지 — 조합 성립 시 상시 표시 (v3.4)
	_update_combo_bar()

var _heal_accum := 0.0

# ---------------------------------------------------------------- UI 공개 스케줄 (게임이 자라는 게임)

func unlock_ui(id: String) -> void:
	if Game.ui_unlocked.get(id, false):
		return
	Game.ui_unlocked[id] = true
	Sfx.play("window", 1.2)
	var target: Control = null
	match id:
		"desc":
			pass  # v3.7: 상시 설명창 폐지 — 대사는 이벤트 박스/앰비언트가 맡는다 (플래그만 유지)
		"gold":
			target = _top_panel
			_update_top()
		"party":
			_party_bar.visible = true
			_rebuild_members()
			target = _party_bar
		"quest":
			pass  # 촌장의 부탁이 열린다 — UI가 아니라 세계(촌장)가 창구
	if target != null:
		target.visible = true
		_birth_pop(target)
	Game.save_game()

func _chip(text: String, color: Color = UILib.COL_WHITE, bg_a: float = 0.82) -> PanelContainer:
	# 소형 텍스트 칩 (v3.8 §B-5) — 화면에 맨몸 텍스트 금지, 전부 패널 위에
	var c := DQPanel.new()
	c.inner_line = false
	c.bg_color = Color(0.102, 0.11, 0.173, bg_a)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UILib.make_label(text, UILib.FS, color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(l)
	return c

func _birth_pop(c: Control) -> void:
	# UI의 탄생 — 뿅
	c.pivot_offset = c.size / 2.0
	c.scale = Vector2(0.2, 0.2)
	var tw := create_tween()
	tw.tween_property(c, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

var _toasts: Array = []

func toast(text: String, dur: float = 3.0) -> void:
	# 프롤로그 등 중앙 대사 — 칩에 담아 쌓는다 (v3.8: 맨몸 텍스트 금지)
	var l := _chip(text)
	_fx_root.add_child(l)
	_toasts.append(l)
	await get_tree().process_frame
	if not is_instance_valid(l):
		return
	var idx: int = maxi(0, _toasts.find(l))
	l.position = Vector2(320 - l.size.x / 2.0, 136 + idx * 22)
	var tw := create_tween()
	tw.tween_interval(dur)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func():
		_toasts.erase(l)
		l.queue_free())

# ---------------------------------------------------------------- 말풍선 → 툴팁 (v3.7: 커서 추종으로 통합)

func show_bubble(_text: String, _screen_pos: Vector2) -> void:
	pass  # 툴팁(_hover_text)이 대신한다 — 호환용 빈 함수

func hide_bubble() -> void:
	pass

# ---------------------------------------------------------------- 상단/설명

func _update_top() -> void:
	var t := "%s   G %d   Lv %d" % [room_name, Game.gold, Game.level]
	if Game.coins > 0:
		t += "   C %d" % Game.coins
	if Game.run_count > 1:
		t += "   %d회차" % Game.run_count
	# 밤낮 시계 (v3.2 §B-5) — 숲이 열리면 해와 달이 뜬다
	if Game.clock_on():
		t += "   " + ("● 밤" if Game.is_night() else "○ 낮")
	_top_label.text = t
	_top_label.add_theme_color_override("font_color",
		Color(0.7, 0.8, 1.0) if Game.clock_on() and Game.is_night() else UILib.COL_GOLD)

func set_hover(text: String) -> void:
	_hover_text = text

# ---------------------------------------------------------------- 이벤트 박스 (v3.7 §E — "선언". 놓치는 게 불가능해야 한다)

func event(text: String, dur: float = 2.5, portrait: String = "") -> void:
	# 동시 1개 + 큐. 큐가 밀리면 오래된 것부터 버린다 (선언의 신선도)
	_event_q.append({"text": text, "dur": maxf(dur, 1.6), "portrait": portrait})
	while _event_q.size() > 5:
		_event_q.pop_front()

func _show_next_event() -> void:
	if _event_q.is_empty() or _title_suppress:
		return
	_event_showing = true
	var e: Dictionary = _event_q.pop_front()
	var text := UILib.colorize(String(e["text"]))  # v3.8: 자동 채색
	# 수중 필드 — 모든 선언이 출렁인다 (§E [wave])
	if Game.current_field == Game.HIDDEN_FIELD and not text.begins_with("["):
		text = "[wave amp=6 freq=4]%s[/wave]" % text
	_event_label.text = text
	# 초상화 슬롯 (촌장·엄마 얼굴 도트 — 임시: 스프라이트 프레임 컷)
	var tex := _portrait_tex(String(e["portrait"]))
	_event_portrait.texture = tex
	_event_portrait.visible = tex != null
	_event_box.visible = true
	_event_box.reset_size()
	# 최하단 8px 고정 — 부유 금지 (v3.8 §B-2)
	_event_box.position = Vector2(320.0 - _event_box.size.x / 2.0, 352.0 - _event_box.size.y)
	_event_box.pivot_offset = Vector2(_event_box.size.x / 2.0, _event_box.size.y)
	_event_box.scale = Vector2(1.0, 0.3)
	Sfx.play("window", 0.8)  # 등장 사운드 필수 — 놓치는 게 불가능해야 한다
	var dur: float = e["dur"] * (0.55 if not _event_q.is_empty() else 1.0)  # 밀리면 빠르게
	var tw := create_tween()
	tw.tween_property(_event_box, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(dur)
	tw.tween_property(_event_box, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func():
		_event_box.visible = false
		_event_box.modulate.a = 1.0
		_event_showing = false)

func _portrait_tex(id: String) -> Texture2D:
	if id == "":
		return null
	var path := "res://assets/NPCs/village_chief.png"
	var tex: Texture2D = load(path)
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(tex.get_width() / 3.0, 0, tex.get_width() / 3.0, tex.get_height() / 4.0)
	return atlas

# ---------------------------------------------------------------- 앰비언트 팝 (v3.7 §E — 박스에서 연기로)

func _spawn_ambient() -> void:
	var pair: Array = AMBIENT_PAIRS[randi() % AMBIENT_PAIRS.size()]
	var base := Vector2(randf_range(260.0, 460.0), randf_range(60.0, 260.0))
	var l1 := _chip(String(pair[0]), UILib.COL_WHITE, 0.75)  # 박스째로 뜬다 (§B-5)
	l1.position = base
	l1.modulate.a = 0.0
	_fx_root.add_child(l1)
	var tw1 := create_tween()
	tw1.tween_property(l1, "modulate:a", 0.9, 0.5)
	tw1.tween_interval(4.2)
	tw1.tween_property(l1, "modulate:a", 0.0, 1.2)
	tw1.tween_callback(l1.queue_free)
	# 뒷문장 — 시차를 두고, 항상 비껴 뜬다 (어긋남이 곧 뉘앙스의 연기)
	get_tree().create_timer(randf_range(0.6, 1.0)).timeout.connect(func():
		var l2 := _chip(String(pair[1]), UILib.COL_GRAY, 0.75)
		l2.position = base + Vector2(randf_range(18.0, 46.0), randf_range(16.0, 26.0))
		l2.rotation_degrees = randf_range(-3.0, 3.0)  # 연기 레이어 — 기울임 합법 (§F)
		l2.modulate.a = 0.0
		_fx_root.add_child(l2)
		var tw2 := create_tween()
		tw2.tween_property(l2, "modulate:a", 0.85, 0.5)
		tw2.tween_interval(3.6)
		tw2.tween_property(l2, "modulate:a", 0.0, 1.2)
		tw2.tween_callback(l2.queue_free))

# ---------------------------------------------------------------- 파티 스테이터스

func _rebuild_members() -> void:
	# v3.8 §B-2: 파티 컬럼 — 우측 세로 스택 (FF 오마주). 위=합체기, 아래=성수
	for c in _party_vbox.get_children():
		c.queue_free()
	_member_boxes = []
	_holy_cell = null
	_holy_bar = null
	_combo_cell = null
	_combo_fill = null
	if not Game.ui_unlocked["party"]:
		_party_bar.visible = false
		return
	_party_bar.visible = not _title_suppress
	# ① 합체기 게이지 (컬럼 최상단, 가로 바 — 조합 성립 시만)
	_combo_cell = Control.new()
	_combo_cell.custom_minimum_size = Vector2(74, 7)
	_combo_cell.visible = false
	_party_vbox.add_child(_combo_cell)
	var cbg := ColorRect.new()
	cbg.color = Color(0.15, 0.13, 0.22)
	cbg.position = Vector2(0, 1)
	cbg.size = Vector2(74, 5)
	_combo_cell.add_child(cbg)
	_combo_fill = ColorRect.new()
	_combo_fill.color = UILib.COL_GOLD
	cbg.add_child(_combo_fill)
	_sep()
	# ② 파티 카드 — 얇게 (이름 + HP바. 숫자는 호버 툴팁)
	var n := Game.members.size()
	for i in n:
		var cell: Control = MEMBER_BOX_SCENE.instantiate()
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		_party_vbox.add_child(cell)
		var mi := i
		cell.mouse_entered.connect(func():
			if Game.up["heal_eye"] > 0:
				_hover_heal_idx = mi)
		cell.mouse_exited.connect(func():
			if _hover_heal_idx == mi:
				_hover_heal_idx = -1)
		# 카드 클릭 = 스테이터스 창 (v3.4 §B-12)
		cell.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				open_status(mi))
		_member_boxes.append({
			"panel": cell,
			"name": cell.get_node("%NameLabel"),
			"bar": cell.get_node("%Bar"),
		})
		_update_member(i)
		if i < n - 1:
			_sep()
	# ③ 성수 게이지 (컬럼 최하단, 교회가 서면)
	_sep()
	_holy_cell = VBoxContainer.new()
	_holy_cell.add_theme_constant_override("separation", 2)
	_holy_cell.custom_minimum_size = Vector2(74, 18)
	_holy_cell.visible = Game.buildings["church"]
	_party_vbox.add_child(_holy_cell)
	var hl := UILib.make_label("성수", UILib.FS, UILib.COL_GOLD)
	_holy_cell.add_child(hl)
	var hbg := ColorRect.new()
	hbg.color = Color(0.1, 0.13, 0.22)
	hbg.custom_minimum_size = Vector2(70, 3)
	_holy_cell.add_child(hbg)
	_holy_bar = ColorRect.new()
	_holy_bar.color = Color(0.55, 0.8, 1.0)
	_holy_bar.size = Vector2(70, 3)
	hbg.add_child(_holy_bar)

func _sep() -> void:
	# 칸막이 — 1px 크림 라인 (가로, 테두리 소음 최소화)
	var s := ColorRect.new()
	s.color = Color(0.957, 0.941, 0.878, 0.3)
	s.custom_minimum_size = Vector2(72, 1)
	_party_vbox.add_child(s)

func _update_member(i: int) -> void:
	if i >= _member_boxes.size():
		return
	var m: Dictionary = Game.members[i]
	var b: Dictionary = _member_boxes[i]
	if not is_instance_valid(b["panel"]):
		return
	var ghost: bool = m["ghost"]
	b["name"].text = ("†" if ghost else "") + String(m["name"])
	b["name"].add_theme_color_override("font_color", UILib.COL_GRAY if ghost else UILib.COL_WHITE)
	var ratio: float = float(m["hp"]) / maxf(1.0, float(m["max_hp"]))
	b["bar"].size = Vector2(56.0 * ratio, 3)
	b["bar"].color = UILib.COL_GRAY if ghost else (UILib.COL_GREEN if ratio > 0.35 else UILib.COL_RED)
	# 유령 칸 = 반투명 + 청색 (§D). 숫자는 툴팁으로 (넘버는 원할 때만)
	b["panel"].modulate = Color(0.7, 0.8, 1.25, 0.55) if ghost else Color(1, 1, 1, 1)
	b["panel"].tooltip_text = "HP %d / %d" % [m["hp"], m["max_hp"]]

func member_box_center(i: int) -> Vector2:
	if i < _member_boxes.size() and is_instance_valid(_member_boxes[i]["panel"]):
		var p: Control = _member_boxes[i]["panel"]
		return p.global_position + p.size / 2.0
	return Vector2(520, 336)

# ---------------------------------------------------------------- 연출 (fx)

func fly_damage(from: Vector2, member_idx: int, dmg: int) -> void:
	var l := _chip(str(dmg), UILib.COL_RED)  # 파티 피격 = 빨강 (v3.8 §B-1)
	l.position = from
	_fx_root.add_child(l)
	var to := member_box_center(member_idx) + Vector2(-8, -10)
	var tw := create_tween()
	tw.tween_property(l, "position", to, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		l.queue_free()
		if member_idx < _member_boxes.size() and is_instance_valid(_member_boxes[member_idx]["panel"]):
			var p: Control = _member_boxes[member_idx]["panel"]
			p.modulate = Color(1.6, 0.5, 0.55)  # 피격 플래시 (칸 전체가 붉게)
			var tw2 := create_tween()
			tw2.tween_interval(0.15)
			tw2.tween_callback(func(): _update_member(member_idx))
	)

func coin_burst(from: Vector2, count: int) -> void:
	count = clampi(count, 1, 8)
	for i in count:
		var c := TextureRect.new()
		c.texture = load("res://assets/objects/gold.png")
		c.size = Vector2(10, 10)
		c.stretch_mode = TextureRect.STRETCH_SCALE
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.position = from + Vector2(randf_range(-14, 14), randf_range(-10, 10))
		_fx_root.add_child(c)
		var mid := c.position + Vector2(randf_range(-30, 30), randf_range(-45, -20))
		var tw := create_tween()
		tw.tween_interval(i * 0.06)
		tw.tween_property(c, "position", mid, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "position", GOLD_TARGET, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			c.queue_free()
			Sfx.play("coin", 0.9 + i * 0.06))

func popup(text: String, screen_pos: Vector2, color: Color = UILib.COL_GOLD) -> void:
	var l := _chip(text, color)  # v3.8: 칩에 담는다
	l.position = screen_pos + Vector2(-14, -22)
	l.z_index = 20
	_fx_root.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 18.0, 0.8)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)

# ---------------------------------------------------------------- 스택 뱃지 (v3.4 §B-1)

var _stack_badge: PanelContainer = null

func update_stack_badge(n: int, pos: Vector2) -> void:
	if n <= 0:
		if _stack_badge != null and is_instance_valid(_stack_badge):
			_stack_badge.queue_free()
		_stack_badge = null
		return
	if _stack_badge == null or not is_instance_valid(_stack_badge):
		_stack_badge = _chip("", UILib.COL_GOLD)
		_stack_badge.z_index = 30
		_fx_root.add_child(_stack_badge)
	_stack_badge.get_child(_stack_badge.get_child_count() - 1).text = "×%d" % n
	_stack_badge.position = pos

# ---------------------------------------------------------------- 루팅 토스트 (v3.4 §B-10 — 우상단 미니 창)

var _loot_toasts: Array = []

func loot_toast(text: String, kind: String = "medal") -> void:
	# 드퀘 미니 창 슬라이드 인 — 종류별 효과음, 연속 획득은 세로 큐
	match kind:
		"medal": Sfx.play("fanfare", 1.1)
		"small": Sfx.play("golden", 1.3)
		_: Sfx.play("chest")
	var p := UILib.make_panel(UILib.COL_GOLD)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_root.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	p.add_child(h)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.color = UILib.COL_GOLD if kind != "small" else Color(0.8, 0.8, 0.9)
	h.add_child(dot)
	var l := UILib.make_label(text, UILib.FS)
	h.add_child(l)
	_loot_toasts.append(p)
	var idx: int = _loot_toasts.find(p)
	p.position = Vector2(644, 26 + idx * 26)  # 화면 밖 우측에서 슬라이드 인
	var tw := create_tween()
	tw.tween_callback(func():
		p.position.x = 644.0 - 0.0)  # 레이아웃 확정 후
	tw.tween_property(p, "position:x", 632.0 - maxf(p.size.x, 120.0), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		_loot_toasts.erase(p)
		p.queue_free()
		# 남은 토스트 위로 당기기
		for j in _loot_toasts.size():
			if is_instance_valid(_loot_toasts[j]):
				_loot_toasts[j].position.y = 26 + j * 26)

func fly_xp(from: Vector2, count: int = 3) -> void:
	# XP = 처치 지점에서 직선 상승 + 반딧불이 잔상 (v3.2 §B-12 — 영혼의 가벼움)
	# 골드(coin_burst)는 포물선으로 튀어 흡입 — 궤적·색·소리 3중 구분
	if not Game.ui_unlocked["gold"]:
		return
	count = clampi(count, 1, 6)
	for i in count:
		var d := ColorRect.new()
		d.color = Color(0.45, 0.7, 1.0)
		d.size = Vector2(2, 2)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.position = from + Vector2(randf_range(-12, 12), randf_range(-4, 4))
		_fx_root.add_child(d)
		# 잔상 — 본체를 따라 늦게 사그라드는 꼬리
		var tail := ColorRect.new()
		tail.color = Color(0.45, 0.7, 1.0, 0.35)
		tail.size = Vector2(1, 6)
		tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tail.position = d.position + Vector2(0.5, 2)
		_fx_root.add_child(tail)
		var rise := randf_range(28, 44)
		var tw := create_tween()
		tw.tween_interval(i * 0.06)
		tw.set_parallel(true)
		tw.tween_property(d, "position:y", d.position.y - rise, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(d, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(tail, "position:y", tail.position.y - rise * 0.8, 0.8)
		tw.tween_property(tail, "modulate:a", 0.0, 0.8)
		tw.chain().tween_callback(func():
			d.queue_free()
			tail.queue_free())
	Sfx.play("blip", 1.6, -8.0)  # 샤랑 — 코인의 짤랑과 구분

func levelup_ritual(new_level: int) -> void:
	# 레벨업 의식 — 전화면 플래시 + 팡파레 + 게이트 힌트 (v3.1 §B-1)
	Sfx.play("fanfare")
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.55)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_root.add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.0, 0.5)
	tw.tween_callback(flash.queue_free)
	var msg := "%s은(는) 레벨 %d(이)가 되었다!" % [Game.hn(), new_level]
	var hint := _level_gate_hint(new_level)
	if hint != "":
		msg += "  " + hint
	event(msg, 4.0)

# ---------------------------------------------------------------- 이름 입력 (v3.2 §B-4)

func show_name_input(on_done: Callable) -> void:
	# 드퀘식 "이름을 입력하세요" — 기본값 용사 (v3.4)
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, 0.75)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_root.add_child(r)
	var p := UILib.make_panel(UILib.COL_GOLD)
	p.position = Vector2(200, 120)
	p.custom_minimum_size = Vector2(240, 0)
	r.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	v.add_child(UILib.make_label("이름을 입력하세요", UILib.FS, UILib.COL_GOLD))
	var le := LineEdit.new()
	le.text = "용사"
	le.max_length = 8
	le.add_theme_font_override("font", UILib.FONT_PX)
	le.add_theme_font_size_override("font_size", UILib.FS)
	v.add_child(le)
	v.add_child(UILib.make_label("(모두가 이 이름으로 부르게 된다)", UILib.FS, UILib.COL_GRAY))
	var done := func():
		var n := le.text.strip_edges()
		if n == "":
			n = "용사"
		Sfx.play("fanfare")
		r.queue_free()
		on_done.call(n)
	var b := UILib.make_button("이 이름으로 간다", UILib.FS)
	b.pressed.connect(done)
	v.add_child(b)
	le.text_submitted.connect(func(_t): done.call())
	le.grab_focus()
	le.select_all()

func _level_gate_hint(lv: int) -> String:
	# 다음 레벨 게이트가 뭘 여는지 슬쩍 알려준다 — 레벨업이 '열쇠'라는 감각
	if lv == 2:
		return "촌장이 게시판 이야기를 꺼낼 것 같다."
	if lv == 3 and not Game.residents.get("smithy", false):
		return "대장장이가 흥미를 보인다."
	if lv == 5 and Game.up["intuition"] == 0:
		return "촌장이 「직감」 이야기를 한다."
	if lv == 6 and not Game.residents.get("gambler", false):
		return "어디선가 주사위 소리가 들린다."
	if lv == 8:
		return "큰돈의 냄새를 맡은 자가 있다던데."
	if lv == 10 and Game.sword_rock == 1:
		return "…바위의 검이 응답할 것 같다."
	return ""

func show_cutin(text: String, tex_path: String, fallback: String, tint: Color) -> void:
	# 합체기 컷인 — 검은 띠 + 초상 + 기술명이 화면을 가로지른다 (v3.1 §B-4)
	var band := ColorRect.new()
	band.color = Color(0, 0, 0, 0.85)
	band.position = Vector2(0, 130)
	band.size = Vector2(640, 84)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_root.add_child(band)
	# 연기 레이어 — 컷인은 비스듬히 가로지르는 게 합법 (v3.7 §F)
	band.rotation_degrees = randf_range(-2.5, -1.5)
	var tex: Texture2D = load(tex_path) if ResourceLoader.exists(tex_path) else load(fallback)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.modulate = tint if not ResourceLoader.exists(tex_path) else Color(1, 1, 1)
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(64, 64)
	tr.size = Vector2(64, 64)
	tr.position = Vector2(-80, 10)
	band.add_child(tr)
	# [slam]/[shake] 태그 지원 — "…참치다."가 쿵 하고 박힌다 (v3.7 §E)
	var l := UILib.make_rich(text)
	l.add_theme_color_override("default_color", UILib.COL_GOLD)
	l.custom_minimum_size = Vector2(300, 0)
	l.position = Vector2(700, 22)
	band.add_child(l)
	Sfx.play("fanfare_big")
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(tr, "position:x", 120.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:x", 220.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(1.1)
	tw.chain().tween_property(band, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(band.queue_free)

func fade_quick(mid_callback: Callable) -> void:
	# 룸 전환용 짧은 페이드 (0.3초대)
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, 0)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_root.add_child(r)
	var tw := create_tween()
	tw.tween_property(r, "color:a", 1.0, 0.22)
	tw.tween_callback(func():
		if mid_callback.is_valid():
			mid_callback.call())
	tw.tween_interval(0.08)
	tw.tween_property(r, "color:a", 0.0, 0.22)
	tw.tween_callback(r.queue_free)

func fade_black(center_text: String, hold: float, mid_callback: Callable) -> void:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, 0)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_root.add_child(r)
	var l := UILib.make_label(center_text, UILib.FS)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.modulate.a = 0.0
	r.add_child(l)
	var tw := create_tween()
	tw.tween_property(r, "color:a", 1.0, 0.7)
	tw.tween_property(l, "modulate:a", 1.0, 0.5)
	tw.tween_interval(hold)
	tw.tween_callback(func():
		if mid_callback.is_valid():
			mid_callback.call())
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_property(r, "color:a", 0.0, 0.7)
	tw.tween_callback(r.queue_free)

# ---------------------------------------------------------------- 메뉴

func is_menu_open() -> bool:
	return _menu_kind != ""

func close_menu() -> void:
	_menu_kind = ""
	menu_hover = ""
	remote_open = false
	_menu_sc = null
	_menu_v = null
	for c in _menu_root.get_children():
		c.queue_free()

func _menu_panel(title: String) -> VBoxContainer:
	# close_menu()가 _menu_kind/remote_open을 지우므로, 호출자가 미리 정한 값을 살려 둔다
	# (이게 안 되면 _up_row의 reopen·카지노 스핀 가드·텔레파시 잠금이 전부 오작동한다)
	var kind := _menu_kind
	var remote := remote_open
	close_menu()
	_menu_kind = kind
	remote_open = remote
	# v3.4 §B-2: 커맨드 창 = 화면 좌측 고정 슬롯 1개, 동시 개방 1개
	var p := UILib.make_panel(UILib.COL_GOLD)
	p.position = Vector2(8, 26)
	p.custom_minimum_size = Vector2(320, 0)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_root.add_child(p)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 1)
	p.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var t := UILib.make_label(title, UILib.FS, UILib.COL_GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := UILib.make_button("닫기", UILib.FS)
	x.pressed.connect(close_menu)
	head.add_child(x)
	# 긴 메뉴는 스크롤 — 화면(360px)을 뚫고 나가지 않게 (v3.1: 촌장 메뉴가 길어졌다)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(312, 0)
	outer.add_child(sc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	_menu_sc = sc
	_menu_v = v
	return v

var _menu_sc: ScrollContainer = null
var _menu_v: VBoxContainer = null

func _menu_row(v: VBoxContainer, left: String, sub: String, btn_text: String, enabled: bool, on_press: Callable) -> void:
	# 한 줄 레이아웃 — 설명(sub)은 호버 시 하단 설명창에 흐른다
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	v.add_child(h)
	var l := UILib.make_label(left, UILib.FS)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var b := UILib.make_button(btn_text, UILib.FS)
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(64, 0)
	b.pressed.connect(on_press)
	if sub != "":
		b.mouse_entered.connect(func(): menu_hover = sub)
		b.mouse_exited.connect(func(): menu_hover = "")
	h.add_child(b)

# ---------------------------------------------------------------- 성문 (필드 선택)

# ---------------------------------------------------------------- 커맨드 메뉴 (해금 문법 ① — 각 건물이 자기 영역을 판다)

func open_chief() -> void:
	_menu_kind = "chief"
	# 칭호 반영 (v3.2 §B-8) — 촌장은 당신의 습관을 알고 있다
	var title_txt := Game.current_title()
	var head_txt := "촌장 — 마을의 모든 일" if title_txt == "" else "촌장 — 「%s」이시여…" % title_txt
	var v := _menu_panel(head_txt)
	# 부탁 — 주민 영입 후보 2~3명 동시 노출 (어느 부탁부터가 곧 선택)
	v.add_child(UILib.make_label("— 부탁 (사람을 모으자) —", UILib.FS, UILib.COL_GOLD))
	var cands: Array = main.candidate_residents()
	if cands.is_empty():
		v.add_child(UILib.make_label("모두 모였다. 마을은 완성됐다.", UILib.FS, UILib.COL_GRAY))
	for r in cands:
		var c: Dictionary = r["cond"]
		var cond_txt: String = main.resident_cond_text(r)
		if c.has("gold"):
			var lv_ok: bool = not c.has("lv") or Game.level >= int(c["lv"])
			_menu_row(v, String(r["name"]), String(r["ask"]), cond_txt,
				lv_ok and Game.gold >= int(c["gold"]),
				func(): _chief_pay(r["id"]))
		else:
			_menu_row(v, String(r["name"]), String(r["ask"]), cond_txt, false, func(): pass)
	# 동료 부탁 — 객원들이 촌장을 통해 손을 내민다 (v3.1)
	var asks: Array = main.candidate_asks()
	if not asks.is_empty():
		v.add_child(UILib.make_label("— 동행을 원하는 자들 —", UILib.FS, UILib.COL_GOLD))
		for a in asks:
			var cd: Dictionary = Game.COMPANIONS[a["id"]]
			var lv_ok2: bool = int(a["lv"]) == 0 or Game.level >= int(a["lv"])
			var cost2: int = Game.price(int(a["gold"]))
			_menu_row(v, String(cd["name"]) + " (객원)", String(a["ask"]),
				"%d G" % cost2 if lv_ok2 else "Lv%d 필요" % int(a["lv"]),
				lv_ok2 and Game.gold >= cost2,
				func(): _chief_pay_companion(String(a["id"])))
	# 건설 — 게시판·항아리 (의식과 살림)
	v.add_child(UILib.make_label("— 건설 —", UILib.FS, UILib.COL_GOLD))
	if not Game.buildings["board"]:
		var bc := int(60 * pow(2.0, 0))
		_menu_row(v, "수배 게시판", "위험한 놈들을 불러들인다 (레벨 게이트: Lv 2)", "%d G" % bc,
			Game.level >= 2 and Game.gold >= bc, func(): _chief_build_board(bc))
	if Game.extra_pots < 3:
		var pc := int(30 * pow(2.2, Game.extra_pots))
		_menu_row(v, "항아리 확충 %d/3" % Game.extra_pots, "광장에 항아리 +2", "%d G" % pc,
			Game.gold >= pc, func(): _chief_add_pots(pc))
	# 전선 확대 / 원정 (분산 수치 업그레이드 — 촌장 담당분)
	v.add_child(UILib.make_label("— 전선 확대 —", UILib.FS, UILib.COL_GOLD))
	_up_row(v, "win_cap", "전투창 확장", "동시 전투창 +1", 100, 2.2, 5, 2 + Game.up["win_cap"] * 2)
	_up_row(v, "battle_speed", "전투 가속", "전투 턴 간격 -7%", 25, 1.22, 12, 0)
	# v3.4 §B-3: 무리 = 편성 인원 연동. 업글은 +1 보정만
	_up_row(v, "density", "무리 유인", "창당 최대 적 = 편성 인원. 여기에 +1 보정", 160, 1.0, 1, 4)
	if Game.clock_on():
		_up_row(v, "lantern", "등불", "밤 시야 반경 확장 (최종: 대열 전체가 빛의 뱀)", 120, 1.9, 3, 0)
	v.add_child(UILib.make_label("— 원정 —", UILib.FS, UILib.COL_GOLD))
	_up_row(v, "speed", "이속 강화", "파티 이동 속도 +8%", 25, 1.2, 9, 0)
	_up_row(v, "shovel", "삽", "반짝이는 땅을 판다", 150, 1.0, 1, 0)
	_up_row(v, "intuition", "용사의 직감", "파티가 스스로 사냥하고 돌아온다", 800, 1.0, 1, 5)
	if Game.up["intuition"] > 0:
		_up_row(v, "radius", "행동반경", "직감 사냥 반경 +80", 200, 2.0, 3, 0)
	# v3.1 — 지휘 계열
	_up_row(v, "flee", "퇴각 나팔", "주시 중인 전투창에서 도망칠 수 있다", 300, 1.0, 1, 3)
	if Game.up["intuition"] > 0:
		_up_row(v, "telepathy", "상인의 텔레파시", "멀리서도 건물 메뉴를 열 수 있다 (몸 행위는 불가)", 500, 1.0, 1, 0)

func _up_row(v: VBoxContainer, id: String, name_txt: String, desc: String, base: int, growth: float, max_lv: int, lv_gate: int) -> void:
	var lv: int = Game.up[id]
	var maxed: bool = lv >= max_lv
	var cost := Game.price(int(base * pow(growth, lv)))
	var label := name_txt + (" Lv%d" % lv if max_lv > 1 else "")
	var gated: bool = Game.level < lv_gate
	var btn := "완료" if maxed else ("Lv%d 필요" % lv_gate if gated else "%d G" % cost)
	# 어느 메뉴에서 불렸든 그 메뉴를 다시 연다 (촌장/여관/상점 공용)
	var reopen := _menu_kind
	_menu_row(v, label, desc, btn, not maxed and not gated and Game.gold >= cost,
		func(): _buy_up(id, cost, reopen))

func _buy_up(id: String, cost: int, reopen: String) -> void:
	if not Game.try_spend(cost):
		Sfx.play("deny")
		return
	Sfx.play("buy")
	main.up_effect(id)
	match reopen:
		"inn": open_inn()
		"shop": open_shop_menu()
		"church": open_church()
		"bank": open_bank()
		_: open_chief()

func _chief_pay(id: String) -> void:
	if main.try_pay_resident(id):
		close_menu()
	else:
		open_chief()

func _chief_pay_companion(id: String) -> void:
	if main.try_pay_companion(id):
		close_menu()
	else:
		open_chief()

func _chief_build_board(cost: int) -> void:
	if not Game.try_spend(cost):
		Sfx.play("deny")
		return
	Sfx.play("buy")
	main.build_board()
	close_menu()

func _chief_add_pots(cost: int) -> void:
	if not Game.try_spend(cost):
		Sfx.play("deny")
		return
	Sfx.play("buy")
	main.add_pots()
	open_chief()

func open_inn() -> void:
	_menu_kind = "inn"
	var v := _menu_panel("여관 — \"어서 오세요\"")
	var need: bool = Game.lowest_hp_ratio() < 1.0 or Game.ghost_count() > 0
	_menu_row(v, "쉬어간다", "일행의 HP를 전부 회복한다 (직접 와야 한다)", "무료" if not remote_open else "몸으로",
		need and not remote_open, _inn_rest)
	_up_row(v, "max_hp", "침구 개선", "전원 최대 HP +8%", 30, 1.2, 9, 0)
	# 작전 명령 (v3.2 §B-3 — 드퀘4 오마주. 훈장=반영구, 작전=수시 스위치)
	if Game.tactic_known:
		v.add_child(UILib.make_label("— 작전 명령 (개별 지시는 파티창 클릭) —", UILib.FS, UILib.COL_GOLD))
		_tactic_row(v, "", "따로 없음", "평소대로 싸운다")
		_tactic_row(v, "attack", "가차없이 공격", "턴 속도·데미지 상승, 대신 아프게 맞는다")
		_tactic_row(v, "life", "목숨을 소중히", "사제가 먼저 움직이고 덜 맞는다, 수입은 준다")
		_tactic_row(v, "gold", "골드를 노려라", "골드 상승, 처치는 느려진다")
	# 편성 (v3.1 §B-3 — 여관 로비가 대기소)
	if Game.companion_count() > 1:
		_menu_row(v, "파티 편성 (%d/%d)" % [Game.party_ids.size(), Game.PARTY_MAX],
			"누구와 걸을지 정한다. 편성이 곧 전략이다", "열기", true, open_formation)
	_menu_row(v, "《동료들의 서》", "만난 동료들의 기록 — 회차를 넘어 남는다", "펼치기", true, open_book)

func open_formation() -> void:
	_menu_kind = "formation"
	var v := _menu_panel("파티 편성 — 최대 %d명" % Game.PARTY_MAX)
	for id in Game.COMPANIONS.keys():
		if not Game.companions_owned.get(id, false):
			continue
		var d: Dictionary = Game.COMPANIONS[id]
		var in_party: bool = Game.party_ids.has(id)
		var tag: String = "정규" if d["regular"] else "객원"
		if id == "hero":
			_menu_row(v, "★ %s (%s)" % [d["name"], tag], String(d["pdesc"]), "고정", false, func(): pass)
		else:
			_menu_row(v, ("★ " if in_party else "・ ") + "%s (%s)" % [d["name"], tag], String(d["pdesc"]),
				"빼기" if in_party else "넣기",
				in_party or Game.party_ids.size() < Game.PARTY_MAX,
				func(): _formation_toggle(id))
	var combo: Dictionary = Game.active_combo()
	if not combo.is_empty():
		var hint_txt := "…이 편성, 뭔가 통하는 게 있다."
		if Game.combo_hint_known:
			hint_txt += " (%s)" % String(combo["name"])
		v.add_child(UILib.make_label(hint_txt, UILib.FS, UILib.COL_GOLD))

func _formation_toggle(id: String) -> void:
	if Game.toggle_party(id):
		Sfx.play("click")
		Game.save_game()
		open_formation()
	else:
		Sfx.play("deny")
		event("자리가 없다! (최대 %d명)" % Game.PARTY_MAX)

func open_book() -> void:
	_menu_kind = "book"
	var v := _menu_panel("《동료들의 서》 — %d/%d" % [Game.book_seen.size(), Game.COMPANIONS.size()])
	for id in Game.COMPANIONS.keys():
		var d: Dictionary = Game.COMPANIONS[id]
		if Game.book_seen.get(id, false):
			var tag: String = "정규" if d["regular"] else "객원"
			_menu_row(v, "%s (%s)" % [d["name"], tag], String(d["pdesc"]), "기록됨", false, func(): pass)
		else:
			_menu_row(v, "？？？", String(d["hint"]), "—", false, func(): pass)

func _tactic_row(v: VBoxContainer, id: String, name_txt: String, sub: String) -> void:
	var on: bool = Game.tactic == id
	_menu_row(v, ("▶ " if on else "・ ") + name_txt, sub, "지시 중" if on else "지시", not on,
		func():
			Game.tactic = id
			Sfx.play("click")
			Game.save_game()
			open_inn())

func _inn_rest() -> void:
	Sfx.play("heal")
	Game.add_stat("inn_rests")
	Game.heal_all_full()
	# 늦잠 훈장 — 유령까지 깨어나지만, 복귀가 늦다 (v3.2 양날형)
	if Game.medal_on("late_sleep"):
		if Game.ghost_count() > 0:
			Game.revive_all()
			event("푹 잤다. 유령까지 개운하게 일어났다! …해가 중천이다.", 4.0)
		else:
			event("푹 잤다. …해가 중천이다.", 3.5)
		if main != null:
			main.party.frozen = true
			get_tree().create_timer(3.5).timeout.connect(func():
				if main != null and not main._wipe_lock:
					main.party.frozen = false)
	elif Game.ghost_count() > 0:
		event("…늦잠은 금물. (유령은 교회에서)", 3.0)
	else:
		event("…늦잠은 금물.", 2.5)
	close_menu()

func open_church() -> void:
	_menu_kind = "church"
	var v := _menu_panel("교회 — 경건한 기운")
	var ghosts := Game.ghost_count()
	var cost := Game.revive_cost()
	_menu_row(v, "유령을 되살린다 (%d명)" % ghosts, "빛이 일행을 감싸안는다", "%d G" % cost if ghosts > 0 else "—",
		ghosts > 0 and Game.gold >= cost, _church_revive)
	# 축복 — 주시(호버)의 힘을 벼리는 곳 (v3.1 §B-7)
	v.add_child(UILib.make_label("— 축복 (주시의 힘) —", UILib.FS, UILib.COL_GOLD))
	_up_row(v, "gaze", "주시 강화", "지켜보는 창의 가속·회심이 강해진다", 120, 1.6, 5, 0)
	_up_row(v, "stack", "겹쳐보기", "전투창들이 겹쳐 정리되고, 스택 주시 = 전체 주시", 400, 1.0, 1, 0)  # v3.4 §B-1
	_up_row(v, "heal_eye", "치유의 눈길", "파티창을 바라보면 성수가 상처를 씻는다", 150, 1.8, 4, 0)
	_up_row(v, "golden_hands", "황금의 손길", "황금 슬라임을 문질러 붙잡을 수 있게 된다", 200, 1.0, 1, 0)
	if Game.up["heal_eye"] > 0 or Game.up["golden_hands"] > 0:
		_up_row(v, "holy_max", "성수 그릇", "성수 최대치 +4초", 100, 1.7, 4, 0)
		_up_row(v, "holy_regen", "샘의 축복", "성수가 차오르는 속도 +35%", 130, 1.7, 4, 0)
	# v3.3 §F: "프레스티지/회차" 금지 → "2주차 모험". 크레딧을 본 뒤에만 조용히 등장
	if Game.ending_seen:
		_menu_row(v, "%d주차 모험을 떠난다" % (Game.run_count + 1),
			"새 모험 — 훈장·도감·칭호·서사시는 남는다. 배율 따위는 없다",
			"떠난다", true, func(): main._do_prestige())

func _church_revive() -> void:
	var cost := Game.revive_cost()
	if not Game.try_spend(cost):
		Sfx.play("deny")
		return
	Sfx.play("revive")
	Game.add_stat("revives")  # 순교자의 성표로 가는 길 (v3.2)
	Game.revive_all()
	event("빛이 일행을 감싸안았다. 되살아났다!", 3.0)
	close_menu()

func open_shop_menu() -> void:
	_menu_kind = "shop"
	var v := _menu_panel("상점 — \"좋은 물건 있습니다\"")
	_up_row(v, "gold_mult", "골드 감각", "골드 획득 +15%", 60, 1.25, 9, 0)
	v.add_child(UILib.make_label("— 조수 동물 —", UILib.FS, UILib.COL_GOLD))
	_assist_row(v, "monkey", "원숭이", "마을 항아리를 자동으로 깬다", 600, 2.5, 3)
	_assist_row(v, "keeper", "상자지기", "보물상자를 자동으로 연다", 900, 1.0, 1)
	_assist_row(v, "pig", "꽃돼지", "필드의 반짝이를 자동으로 판다", 1200, 2.2, 3)

func _assist_row(v: VBoxContainer, id: String, name_txt: String, desc: String, base: int, growth: float, max_n: int) -> void:
	var n: int = Game.assistants[id]
	var maxed: bool = n >= max_n
	var cost := Game.price(int(base * pow(growth, n)))
	_menu_row(v, "%s %d/%d" % [name_txt, n, max_n], desc, "완료" if maxed else "%d G" % cost,
		not maxed and Game.gold >= cost, func(): _buy_assist(id, cost))

func _buy_assist(id: String, cost: int) -> void:
	if not Game.try_spend(cost):
		Sfx.play("deny")
		return
	Sfx.play("buy")
	Game.assistants[id] += 1
	main.spawn_assistant(id)
	event("새 조수가 마을에 도착했다!")
	Game.save_game()
	open_shop_menu()

func open_medalking() -> void:
	_menu_kind = "medalking"
	var v := _menu_panel("메달왕 — \"오오, 메달의 향기!\"")
	v.add_child(UILib.make_label("보유: 작은 메달 %d개" % Game.medals_small, UILib.FS, UILib.COL_GOLD))
	# v3.2 라인업 — 금간 항아리·왕관은 이제 플레이 습관이 준다 (도전과제식)
	_medal_trade_row(v, "sturdy_charm", 3)
	_medal_trade_row(v, "sharp_crest", 5)
	_medal_trade_row(v, "slime_incense", 6)
	_medal_trade_row(v, "aqua_regia", 8)
	_medal_trade_row(v, "spirit_party", 12)
	_menu_row(v, "훈장을 단다", "모은 훈장을 장착/해제한다", "열기", Game.medals_owned.size() > 0,
		func(): open_medals())

func _medal_trade_row(v: VBoxContainer, id: String, cost: int) -> void:
	var d: Dictionary = Game.MEDAL_DEFS[id]
	if Game.medals_owned.has(id):
		_menu_row(v, "훈장: " + d["name"], d["desc"], "교환 완료", false, func(): pass)
	else:
		_menu_row(v, "훈장: " + d["name"], d["desc"], "메달 %d개" % cost,
			Game.medals_small >= cost, func(): _medal_trade(id, cost))

func _medal_trade(id: String, cost: int) -> void:
	if Game.medals_small < cost:
		Sfx.play("deny")
		return
	Game.medals_small -= cost
	Game.medals_spent += cost
	Game.own_medal(id)
	Sfx.play("fanfare_big")
	event("메달왕: 「훌륭한 메달이다! 옜다, 「%s」!」" % Game.MEDAL_DEFS[id]["name"], 4.0)
	Game.save_game()
	open_medalking()

func open_gate() -> void:
	_menu_kind = "gate"
	var v := _menu_panel("성문 — 어디로 출격할까")
	for i in 5:
		var name_txt: String = Game.FIELD_NAMES[i]
		if Game.fields_unlocked[i]:
			var sub := ""
			match i:
				1: sub = "발굴 반짝이가 풍부하다"
				2: sub = "무리 조우가 많다"
				3: sub = "눈보라 — 정예와 황금 슬라임의 땅"
				4: sub = "지배자들의 심장부"
			if Game.bosses_defeated[i]:
				name_txt += " (해방됨)"
			if i == 4 and not (Game.epic_complete() and Game.roto_complete()):
				var lock_sub := "이야기의 끝을 알아야 들어갈 수 있다 (음유시인)" if not Game.epic_complete() \
					else "전설의 세 조각이 필요하다 (로토 세트 %d/3)" % Game.roto_count()
				_menu_row(v, name_txt, lock_sub, "닫힘", false, func(): pass)
			else:
				_menu_row(v, name_txt, sub, "출발", true, func(): _depart(i))
		else:
			_menu_row(v, "？？？", "지배자를 쓰러뜨리면 다음 길이 열린다", "—", false, func(): pass)
	# 숨겨진 행선지 — 바다의 노래를 아는 자에게만 (v3.4 §B-7)
	if Game.keys["sea"]:
		var hname := "≈ " + Game.FIELD_NAMES[Game.HIDDEN_FIELD] + (" (해방됨)" if Game.bosses_defeated[Game.HIDDEN_FIELD] else "")
		_menu_row(v, hname, "바다의 노래가 이끄는 곳 — 일행은 물고기가 된다", "잠수", true,
			func(): _depart(Game.HIDDEN_FIELD))

func _depart(i: int) -> void:
	close_menu()
	if main != null:
		main.select_field(i)
		Sfx.play("click")
		event("이정표가 %s 쪽을 가리킨다. 동쪽으로!" % Game.FIELD_NAMES[i], 3.0)

# ---------------------------------------------------------------- 대장간

# ---------------------------------------------------------------- 무기점 (v3.4 §B-5 — 플랫 성장의 주축)

func open_weaponshop() -> void:
	_menu_kind = "weaponshop"
	var v := _menu_panel("무기점 — \"골드가 곧 힘입니다\"")
	for i in Game.members.size():
		var m: Dictionary = Game.members[i]
		var cost := Game.weapon_cost(i)
		# 강화 변화량 필수 표시 (v3.4): 공격력 37 → 41
		var now := Game.member_atk(i)
		var after := int((Game.member_atk_flat(i) + 2) * Game.forge_mult(m["cls"]))
		_menu_row(v, "%s — %s" % [String(m["name"]), Game.weapon_name(i)],
			"강화하면 공격력 %d → %d" % [now, after], "%d G" % cost,
			Game.gold >= cost, func(): _buy_weapon(i, cost))

func _buy_weapon(i: int, cost: int) -> void:
	if not Game.try_spend(cost):
		Sfx.play("deny")
		return
	Sfx.play("buy")
	var cls := String(Game.members[i]["cls"])
	var lv: int = int(Game.members[i]["weapon_lv"]) + 1
	Game.set_weapon_lv(cls, lv)
	event("공격력이 올랐다! %s (공격력 %d)" % [Game.weapon_name(i), Game.member_atk(i)], 3.0)
	if lv == 5 or lv == 10:
		Sfx.play("fanfare_big")
		event("%s이(가) 다시 태어났다! — 「%s」" % [Game.members[i]["name"], Game.weapon_name(i)], 4.0)
	Game.save_game()
	open_weaponshop()

# ---------------------------------------------------------------- 대장간 (v3.4 — 벼림 % 배율, 선택적 손맛)

func open_smith() -> void:
	_menu_kind = "smith"
	var v := _menu_panel("대장간 — \"벼리면 더 강해지지\"")
	v.add_child(UILib.make_label("벼림 보정 = % 배율. 무기(플랫)가 클수록 가치가 커진다", UILib.FS, UILib.COL_GRAY))
	for i in Game.members.size():
		var m: Dictionary = Game.members[i]
		var cost := Game.forge_cost(i)
		var pts: int = int(Game.companion_forge.get(m["cls"], 0))
		var now := Game.member_atk(i)
		var after := int(Game.member_atk_flat(i) * (Game.forge_mult(m["cls"]) + 0.03))
		_menu_row(v, "%s — 벼림 +%d%%" % [String(m["name"]), pts * 3],
			"리듬 판정 +1~+3. 지금 벼리면 공격력 %d → 약 %d (직접 와야 한다)" % [now, after], "%d G" % cost,
			Game.gold >= cost and not remote_open, func(): _start_forge(i, cost))

func _start_forge(i: int, cost: int) -> void:
	if not Game.try_spend(cost):
		Sfx.play("deny")
		return
	close_menu()
	if Game.medal_on("anvil_bless"):
		# 모루의 축복 — 실패 없음, 대신 +3도 없음
		_apply_forge(i, 2)
		return
	_menu_kind = "forge"
	var fg := ForgeGame.new()
	fg.member_name = String(Game.members[i]["name"])
	_menu_root.add_child(fg)
	fg.finished.connect(func(result: int):
		_menu_kind = ""
		_apply_forge(i, result))

func _apply_forge(i: int, result: int) -> void:
	# v3.4: 대장간 = 벼림 % (무기 플랫과 별개 슬롯)
	var cls := String(Game.members[i]["cls"])
	Game.companion_forge[cls] = int(Game.companion_forge.get(cls, 0)) + result
	var pct: int = int(Game.companion_forge[cls]) * 3
	if result >= 3:
		Sfx.play("fanfare_big")
		event("회심의 필살작!! 벼림 +%d%% (공격력 %d)" % [pct, Game.member_atk(i)], 3.5)
		Game.smith_perfects += 1
		if Game.smith_perfects >= 3 and Game.own_medal("anvil_bless"):
			event("훈장 「모루의 축복」 을 손에 넣었다!", 4.0)
			_update_top()
	elif result == 2:
		Sfx.play("buy")
		event("좋은 벼림이다. +%d%% (공격력 %d)" % [pct, Game.member_atk(i)], 2.5)
	else:
		Sfx.play("bump")
		event("…뭐, 쓸 만하다. +%d%% (공격력 %d)" % [pct, Game.member_atk(i)], 2.5)
	if main != null:
		main.on_forged()
	Game.party_changed.emit()
	Game.save_game()

func open_board(tab: int = -1) -> void:
	_menu_kind = "board"
	if tab >= 0:
		_board_tab = tab
	elif Game.current_field < 4:
		_board_tab = Game.current_field  # v3.4 §B-8: 현재 필드 탭 자동 선택
	if not Game.fields_unlocked[_board_tab]:
		_board_tab = 0
	var v := _menu_panel("수배 게시판 — 정찰대 파견")
	# 필드 탭
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	v.add_child(tabs)
	for f in 4:
		if not Game.fields_unlocked[f]:
			continue
		var tb := UILib.make_button(("▶" if f == _board_tab else "") + Game.FIELD_NAMES[f], UILib.FS)
		var ff := f
		tb.pressed.connect(func(): open_board(ff))
		tabs.add_child(tb)
	var field := _board_tab
	for i in 3:
		var mon: Dictionary = Game.MONSTER_DEFS[i + 1]
		var mon_name: String = Game.FIELD_PREFIX[field] + String(mon["name"])
		var cost := Game.poster_cost(field, i)
		var bought: bool = Game.posters_f[field] > i
		var is_next: bool = Game.posters_f[field] == i
		var sub := "%s에 %s이(가) 출현하게 된다" % [Game.FIELD_NAMES[field], mon_name]
		if i == 2:
			sub += " (3장을 모으면 지배자가 깨어난다)"
		_menu_row(v, "수배서: " + mon_name, sub,
			"파견 완료" if bought else "%d G" % cost,
			is_next and Game.gold >= cost,
			func(): _buy_poster(field, i, cost))
	var g_cost := int(200 * Game.gold_scale())
	_menu_row(v, "황금 슬라임 목격 정보", "황금 슬라임이 더 자주 나타난다",
		"입수 완료" if Game.golden_info else "%d G" % g_cost,
		not Game.golden_info and Game.gold >= g_cost,
		func(): _buy_golden_info(g_cost))

func _buy_poster(field: int, i: int, cost: int) -> void:
	if Game.posters_f[field] != i or not Game.try_spend(cost):
		Sfx.play("deny")
		return
	Game.posters_f[field] += 1
	Sfx.play("buy")
	var mon: Dictionary = Game.MONSTER_DEFS[i + 1]
	event("정찰대를 보냈다. %s%s이(가) 나타나기 시작한다…" % [Game.FIELD_PREFIX[field], mon["name"]], 3.5)
	Game.save_game()
	if Game.posters_f[field] >= 3 and main != null:
		main.on_posters_complete(field)
	open_board(field)

func _buy_golden_info(cost: int) -> void:
	if not Game.try_spend(cost):
		Sfx.play("deny")
		return
	Game.golden_info = true
	Sfx.play("buy")
	event("금색으로 빛나는 것을 봤다는 소문이다…", 3.0)
	open_board()

# ---------------------------------------------------------------- 스테이터스 창 (v3.4 §B-12)

func open_status(i: int) -> void:
	if i >= Game.members.size():
		return
	_menu_kind = "status"
	var m: Dictionary = Game.members[i]
	var v := _menu_panel("스테이터스 — %s" % String(m["name"]))
	var title_txt := Game.current_title()
	if m["cls"] == "hero" and title_txt != "":
		v.add_child(UILib.make_label("칭호: 「%s」" % title_txt, UILib.FS, UILib.COL_GOLD))
	v.add_child(UILib.make_label("Lv %d    HP %d / %d" % [Game.level, m["hp"], m["max_hp"]], UILib.FS))
	var fm := Game.forge_mult(String(m["cls"]))
	v.add_child(UILib.make_label("공격력 %d  (기본 %d × 벼림 %d%%)" % [
		Game.member_atk(i), Game.member_atk_flat(i), int(fm * 100.0)], UILib.FS))
	v.add_child(UILib.make_label("무기: %s" % Game.weapon_name(i), UILib.FS))
	var pdesc: String = Game.COMPANIONS[m["cls"]]["pdesc"]
	v.add_child(UILib.make_label("패시브: %s" % pdesc.split(" — ")[0], UILib.FS, UILib.COL_GRAY))
	# v3.6: 개별 작전 — 이 동료에게만 내리는 지시 (전체 작전보다 우선)
	if Game.tactic_known:
		var g_name: String = Game.TACTIC_NAMES.get(Game.tactic, "따로 없음")
		v.add_child(UILib.make_label("— 개별 작전 (전체: %s) —" % g_name, UILib.FS, UILib.COL_GOLD))
		var cls := String(m["cls"])
		_member_tactic_row(v, i, cls, "", "전체 작전을 따른다")
		_member_tactic_row(v, i, cls, "attack", "가차없이 공격 — 세게 치고 아프게 맞는다")
		_member_tactic_row(v, i, cls, "life", "목숨을 소중히 — 이 동료만 덜 맞는다 (사제는 선행동)")
		_member_tactic_row(v, i, cls, "gold", "골드를 노려라 — 창의 골드 작전에 힘을 싣는다")
	else:
		var t_name: String = Game.TACTIC_NAMES.get(Game.tactic, "따로 없음")
		v.add_child(UILib.make_label("작전: %s" % t_name, UILib.FS))
	if Game.medals_equipped.is_empty():
		v.add_child(UILib.make_label("장착 훈장: 없음", UILib.FS, UILib.COL_GRAY))
	else:
		v.add_child(UILib.make_label("— 장착 훈장 —", UILib.FS, UILib.COL_GOLD))
		for mid in Game.medals_equipped:
			v.add_child(UILib.make_label("★ " + String(Game.MEDAL_DEFS[mid]["name"]), UILib.FS))

func _member_tactic_row(v: VBoxContainer, idx: int, cls: String, id: String, sub: String) -> void:
	var on: bool = String(Game.member_tactics.get(cls, "")) == id
	var label: String = Game.TACTIC_NAMES.get(id, "전체 따름")
	_menu_row(v, ("▶ " if on else "・ ") + label, sub, "지시 중" if on else "지시", not on,
		func():
			if id == "":
				Game.member_tactics.erase(cls)
			else:
				Game.member_tactics[cls] = id
			Sfx.play("click")
			Game.save_game()
			open_status(idx))

# ---------------------------------------------------------------- 합체기 게이지 (v3.4 §B-14 — 상시 가시성)

var _combo_full_told := false
var _combo_btn: Button = null      # v3.6: 만충 시 등장하는 필살 버튼
var _combo_spark_t := 0.0

func _update_combo_bar() -> void:
	# v3.7 §D: 게이지는 통합 파티 바의 첫 셀
	var active: bool = Game.ui_unlocked["party"] and not Game.active_combo().is_empty() and not _title_suppress
	if _combo_cell != null and is_instance_valid(_combo_cell):
		_combo_cell.visible = active
	if active and _combo_fill != null and is_instance_valid(_combo_fill):
		var g: float = clampf(Game.combo_gauge, 0.0, 1.0)
		_combo_fill.size = Vector2(74.0 * g, 5)
		_combo_fill.position = Vector2.ZERO
		if g >= 1.0:
			_combo_fill.color = UILib.COL_GOLD if sin(Time.get_ticks_msec() / 120.0) > 0.0 else UILib.COL_WHITE
			if not _combo_full_told:
				_combo_full_told = true
				loot_toast("합체기 준비 완료!", "medal")
		else:
			_combo_fill.color = UILib.COL_GOLD
			_combo_full_told = false
	elif not active:
		_combo_full_told = false
	_update_combo_btn()

func _update_combo_btn() -> void:
	# v3.6: 만충이면 필살 버튼이 태어난다 — 화려하게 반짝이며
	var combo: Dictionary = Game.active_combo()
	var ready: bool = not combo.is_empty() and Game.combo_gauge >= 1.0 and not _title_suppress \
		and Game.ui_unlocked["party"]
	if ready and _combo_btn == null:
		_combo_btn = UILib.make_button("", 12)
		_combo_btn.add_theme_color_override("font_color", UILib.COL_GOLD)
		_combo_btn.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_combo_btn.add_theme_constant_override("outline_size", 3)
		_combo_btn.z_index = 25
		_combo_btn.pressed.connect(func():
			if main != null:
				main._fire_combo())
		_party_root.add_child(_combo_btn)
		_birth_pop(_combo_btn)
		Sfx.play("golden", 0.7)
	elif not ready and _combo_btn != null:
		if is_instance_valid(_combo_btn):
			_combo_btn.queue_free()
		_combo_btn = null
	if _combo_btn != null and is_instance_valid(_combo_btn):
		var combo_name := String(combo.get("name", "합체기"))
		_combo_btn.text = "★ %s ★" % combo_name
		# 파티창 위에 떠서 두근두근 — 크기 맥동 + 무지개빛 금색
		var t := Time.get_ticks_msec() / 1000.0
		_combo_btn.reset_size()
		_combo_btn.position = Vector2(_party_bar.position.x - _combo_btn.size.x - 6.0, _party_bar.position.y)
		_combo_btn.pivot_offset = _combo_btn.size / 2.0
		_combo_btn.scale = Vector2.ONE * (1.0 + 0.07 * sin(t * 6.0))
		_combo_btn.modulate = Color(
			1.0 + 0.5 * sin(t * 5.0),
			0.9 + 0.4 * sin(t * 5.0 + 2.1),
			0.5 + 0.5 * sin(t * 5.0 + 4.2))
		# 금가루 스파클
		_combo_spark_t -= get_process_delta_time()
		if _combo_spark_t <= 0.0:
			_combo_spark_t = 0.12
			var d := ColorRect.new()
			d.color = Color(1.0, 0.9, randf_range(0.2, 0.7))
			d.size = Vector2(2, 2)
			d.mouse_filter = Control.MOUSE_FILTER_IGNORE
			d.position = _combo_btn.position + Vector2(randf_range(-6, _combo_btn.size.x + 6), randf_range(-4, _combo_btn.size.y))
			d.z_index = 26
			_party_root.add_child(d)
			var tw := create_tween()
			tw.set_parallel(true)
			tw.tween_property(d, "position:y", d.position.y - randf_range(8, 18), 0.5)
			tw.tween_property(d, "modulate:a", 0.0, 0.5)
			tw.chain().tween_callback(d.queue_free)

# ---------------------------------------------------------------- 옵션 (v3.3 §D — 이 목록이 전부다)

func open_options(in_game: bool = true) -> void:
	_menu_kind = "options"
	var v := _menu_panel("옵션")
	_opt_slider_row(v, "bgm", "BGM 음량")
	_opt_slider_row(v, "sfx", "효과음 음량")
	_menu_row(v, "전체화면: %s" % ("켬" if Game.opt["fullscreen"] else "끔"), "F11로도 전환할 수 있다", "전환", true,
		func():
			Game.opt["fullscreen"] = not Game.opt["fullscreen"]
			Game.apply_options()
			_opt_save_reopen(in_game))
	var ts_names := ["순간", "빠름", "보통"]
	_menu_row(v, "텍스트 속도: %s" % ts_names[int(Game.opt["text_speed"])], "드퀘 감성 보존용 3단", "전환", true,
		func():
			Game.opt["text_speed"] = (int(Game.opt["text_speed"]) + 1) % 3
			_opt_save_reopen(in_game))
	_menu_row(v, "화면 흔들림: %s" % ("켬" if Game.opt["shake"] else "끔"), "전투 타격감 셰이크 (접근성)", "전환", true,
		func():
			Game.opt["shake"] = not Game.opt["shake"]
			_opt_save_reopen(in_game))
	_menu_row(v, "언어: 한국어", "English — 번역 준비 중", "—", false, func(): pass)
	if in_game:
		_menu_row(v, "타이틀로 돌아간다", "지금까지는 자동 저장되어 있다", "돌아간다", true,
			func():
				Game.save_game()
				Game.save_options()
				close_menu()
				if main != null:
					main.return_to_title())

func _opt_slider_row(v: VBoxContainer, key: String, name_txt: String) -> void:
	# 0~10 슬라이더 (드퀘 창 문법 — 버튼식)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	v.add_child(h)
	var val: int = int(Game.opt[key])
	var l := UILib.make_label("%s  %s%s %d" % [name_txt, "■".repeat(val), "□".repeat(10 - val), val], UILib.FS)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var minus := UILib.make_button("-", UILib.FS)
	minus.pressed.connect(func(): _opt_vol(key, -1))
	h.add_child(minus)
	var plus := UILib.make_button("+", UILib.FS)
	plus.pressed.connect(func(): _opt_vol(key, 1))
	h.add_child(plus)

func _opt_vol(key: String, dir: int) -> void:
	Game.opt[key] = clampi(int(Game.opt[key]) + dir, 0, 10)
	Game.save_options()
	if key == "sfx":
		Sfx.play("click")
	else:
		Sfx.refresh_bgm_volume()
	# 열려 있던 맥락 유지 재오픈
	var in_game: bool = main == null or not main._title_mode
	open_options(in_game)

func _opt_save_reopen(in_game: bool) -> void:
	Game.save_options()
	Sfx.play("click")
	open_options(in_game)

# ---------------------------------------------------------------- 은행 (v3.1 §B-8)

func open_bank() -> void:
	_menu_kind = "bank"
	var v := _menu_panel("은행 — \"돈이 돈을 법니다\"")
	v.add_child(UILib.make_label("예금: %d G / 한도 %d G" % [Game.deposit, Game.bank_cap()], UILib.FS, UILib.COL_GOLD))
	v.add_child(UILib.make_label("예금은 전멸해도 빼앗기지 않는다", UILib.FS, UILib.COL_GRAY))
	var body_note := " (직접 와야 한다)" if remote_open else ""
	var half: int = maxi(1, int(Game.gold / 2.0))
	_menu_row(v, "절반을 맡긴다%s" % body_note, "지금 골드의 절반을 예금한다", "%d G" % half,
		Game.gold > 0 and Game.deposit < Game.bank_cap() and not remote_open,
		func(): _bank_do(half, true))
	_menu_row(v, "전부 맡긴다%s" % body_note, "지금 골드를 몽땅 예금한다", "%d G" % Game.gold,
		Game.gold > 0 and Game.deposit < Game.bank_cap() and not remote_open,
		func(): _bank_do(Game.gold, true))
	_menu_row(v, "전부 찾는다%s" % body_note, "예금을 몽땅 인출한다", "%d G" % Game.deposit,
		Game.deposit > 0 and not remote_open,
		func(): _bank_do(Game.deposit, false))
	v.add_child(UILib.make_label("— 창구 확장 —", UILib.FS, UILib.COL_GOLD))
	_up_row(v, "bank_cap", "금고 확장", "예금 한도 ×2.5", 400, 2.4, 5, 0)
	_up_row(v, "bank_rate", "우대 금리", "이자율 상승 (30초마다 이자)", 500, 2.2, 4, 0)

func _bank_do(amount: int, deposit_mode: bool) -> void:
	var moved: int = Game.bank_deposit(amount) if deposit_mode else Game.bank_withdraw(amount)
	if moved <= 0:
		Sfx.play("deny")
		return
	Sfx.play("coin")
	event("%s %d G — 「감사합니다」" % ["예금" if deposit_mode else "인출", moved], 2.5)
	Game.save_game()
	open_bank()

# ---------------------------------------------------------------- 카지노

const SLOT_SYMBOLS := ["slime", "pot", "bat", "gold"]
const SLOT_WEIGHTS := [0.35, 0.30, 0.20, 0.15]
const SLOT_PAYOUTS := {"slime": 8, "pot": 6, "bat": 15, "gold": 50}

func _symbol_tex(id: String) -> Texture2D:
	match id:
		"slime": return load("res://assets/enemies/slime.png")
		"bat": return load("res://assets/enemies/bat.png")
		"gold": return load("res://assets/objects/gold.png")
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/objects/pot.png")
	atlas.region = Rect2(0, 0, 14, 15)
	return atlas

func _roll_symbol() -> String:
	var r := randf()
	for i in SLOT_SYMBOLS.size():
		r -= SLOT_WEIGHTS[i]
		if r <= 0.0:
			return SLOT_SYMBOLS[i]
	return SLOT_SYMBOLS[0]

func open_casino() -> void:
	_menu_kind = "casino"
	_spin_active = false
	var v := _menu_panel("카지노 — \"인생 한 방\"")
	var coins_l := UILib.make_label("보유 코인: %d닢" % Game.coins, UILib.FS, UILib.COL_GOLD)
	v.add_child(coins_l)
	_casino_refs = {"coins": coins_l}
	var buy_cost := int(150 * Game.gold_scale())
	_menu_row(v, "코인 10닢 구매", "코인은 골드로 되팔 수 없다. 그것이 카지노다.", "%d G" % buy_cost, true,
		func(): _casino_buy_coins(buy_cost))
	# 슬롯 릴
	var reel_box := HBoxContainer.new()
	reel_box.add_theme_constant_override("separation", 10)
	reel_box.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(reel_box)
	var reels: Array = []
	for i in 3:
		var frame := UILib.make_panel()
		reel_box.add_child(frame)
		var tr := TextureRect.new()
		tr.texture = _symbol_tex(SLOT_SYMBOLS[randi() % 4])
		tr.custom_minimum_size = Vector2(32, 32)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		frame.add_child(tr)
		reels.append(tr)
	_casino_refs["reels"] = reels
	var result_l := UILib.make_label("슬롯: 같은 그림 3개를 노려라", UILib.FS, UILib.COL_GRAY)
	v.add_child(result_l)
	_casino_refs["result"] = result_l
	_menu_row(v, "슬롯을 돌린다", "같은 그림 3개 = 대박, 2개 = 본전 (직접 와야 한다)", "1 코인", not remote_open, _casino_spin)
	# 홀드 — 릴 1개 고정 (v3.2 §B-10 운 트리로 해금)
	if Game.casino_up["hold"] > 0:
		var hold_on: bool = _casino_hold
		_menu_row(v, "홀드: 첫 릴 고정 %s" % ("ON" if hold_on else "OFF"),
			"첫 번째 릴이 마지막 결과를 물고 있는다 (스핀 2코인)", "전환", true,
			func():
				_casino_hold = not _casino_hold
				Sfx.play("click")
				open_casino())
	# 운 트리 (v3.2 §B-10) — 결제는 코인 전용: 코인 벌어 코인 잘 버는 내부 루프
	v.add_child(UILib.make_label("— 행운 (코인 결제) —", UILib.FS, UILib.COL_GOLD))
	_casino_up_row(v, "jackpot", "잭팟의 예감", "같은 그림이 나올 확률이 오른다", 60, 2.2, 3)
	_casino_up_row(v, "consol", "꽝 위로금", "꽝이 나오면 코인을 조금 돌려받는다", 40, 2.0, 3)
	_casino_up_row(v, "hold", "홀드 해금", "릴 1개를 고정하는 기술 (스핀 2코인)", 150, 1.0, 1)
	# 교환소
	v.add_child(UILib.make_label("— 교환소 —", UILib.FS, UILib.COL_GOLD))
	if Game.casino_wincap == 0 and not Game.medals_owned.has("watch_eye"):
		_casino_medal_row(v, "watch_eye", 500)
	_casino_medal_row(v, "rich_seal", 200)
	_casino_medal_row(v, "improvise", 300)
	_casino_medal_row(v, "vip_card", 400)
	_casino_medal_row(v, "mimic_teeth", 300)

var _casino_hold := false
var _casino_last: Array = ["slime", "slime", "slime"]

func _casino_up_row(v: VBoxContainer, id: String, name_txt: String, sub: String, base: int, growth: float, max_lv: int) -> void:
	var lv: int = Game.casino_up[id]
	var maxed: bool = lv >= max_lv
	var cost := int(base * pow(growth, lv))
	_menu_row(v, name_txt + (" Lv%d" % lv if max_lv > 1 else ""), sub,
		"완료" if maxed else "%d 코인" % cost, not maxed and Game.coins >= cost,
		func(): _casino_buy_up(id, cost))

func _casino_buy_up(id: String, cost: int) -> void:
	if Game.coins < cost:
		Sfx.play("deny")
		return
	Game.coins -= cost
	Game.casino_up[id] += 1
	Sfx.play("buy")
	_update_top()
	Game.save_game()
	open_casino()

func _casino_medal_row(v: VBoxContainer, id: String, cost: int) -> void:
	var d: Dictionary = Game.MEDAL_DEFS[id]
	if Game.medals_owned.has(id):
		_menu_row(v, "훈장: " + d["name"], d["desc"], "보유 중", false, func(): pass)
	else:
		_menu_row(v, "훈장: " + d["name"], d["desc"], "%d 코인" % cost, Game.coins >= cost,
			func(): _casino_exchange(id, cost))

func _casino_buy_coins(cost: int) -> void:
	if not Game.try_spend(cost):
		Sfx.play("deny")
		return
	Game.coins += 10
	Sfx.play("coin")
	_update_top()
	_casino_update_coins()

func _casino_update_coins() -> void:
	if _casino_refs.has("coins") and is_instance_valid(_casino_refs["coins"]):
		_casino_refs["coins"].text = "보유 코인: %d닢" % Game.coins

func _casino_spin() -> void:
	if _spin_active or _menu_kind != "casino":
		return
	var hold_on: bool = _casino_hold and Game.casino_up["hold"] > 0
	var cost := 2 if hold_on else 1
	if Game.coins < cost:
		Sfx.play("deny")
		event("코인이 없다. …골드는 두고 가라.")
		return
	Game.coins -= cost
	_update_top()
	_casino_update_coins()
	_spin_active = true
	# 결과는 먼저 정해진다 — 연출은 거들 뿐
	var final: Array = [_roll_symbol(), _roll_symbol(), _roll_symbol()]
	if hold_on:
		final[0] = _casino_last[0]  # 홀드 — 첫 릴이 물고 있는다
	# 잭팟의 예감 — 어긋난 릴이 슬쩍 맞춰진다 (v3.2 운 트리)
	for i in [1, 2]:
		if final[i] != final[0] and randf() < 0.07 * Game.casino_up["jackpot"]:
			final[i] = final[0]
	_casino_last = final.duplicate()
	var payout := 0
	if final[0] == final[1] and final[1] == final[2]:
		payout = SLOT_PAYOUTS[final[0]]
	elif final[0] == final[1] or final[1] == final[2] or final[0] == final[2]:
		payout = 1
	# 카지노 VIP 카드 — 슬롯의 몬스터가 필드에 실체화 (v3.2 조건형)
	if Game.medal_on("vip_card") and main != null and ("slime" in final or "bat" in final):
		main.vip_spawn()
	_animate_spin(final, payout)

func _animate_spin(final: Array, payout: int) -> void:
	for step in 15:
		await get_tree().create_timer(0.07).timeout
		if _menu_kind != "casino" or not _casino_refs.has("reels"):
			break
		var reels: Array = _casino_refs["reels"]
		for r in 3:
			if not is_instance_valid(reels[r]):
				continue
			if step < 5 + r * 3:
				Sfx.play("click", randf_range(0.8, 1.2))
				reels[r].texture = _symbol_tex(_roll_symbol())
			else:
				reels[r].texture = _symbol_tex(final[r])
	_spin_active = false
	Game.coins += payout
	_update_top()
	_casino_update_coins()
	if _casino_refs.has("result") and is_instance_valid(_casino_refs["result"]):
		var l: Label = _casino_refs["result"]
		if payout >= 50:
			l.text = "대박!! +%d 코인!!" % payout
			l.add_theme_color_override("font_color", UILib.COL_GOLD)
			Sfx.play("gold_big")
		elif payout > 1:
			l.text = "맞췄다! +%d 코인!" % payout
			l.add_theme_color_override("font_color", UILib.COL_GOLD)
			Sfx.play("fanfare")
		elif payout == 1:
			l.text = "아깝다. 본전이다."
			l.add_theme_color_override("font_color", UILib.COL_WHITE)
			Sfx.play("coin")
		else:
			# 꽝 위로금 (v3.2 운 트리) — 카지노는 당신을 버리지 않는다
			var consol: int = Game.casino_up["consol"]
			if consol > 0:
				Game.coins += consol
				_update_top()
				_casino_update_coins()
				l.text = "꽝. …위로금 %d닢을 받았다." % consol
			else:
				l.text = "꽝. …다시?"
			l.add_theme_color_override("font_color", UILib.COL_GRAY)
			Sfx.play("bump")

func _casino_exchange(id: String, cost: int) -> void:
	if Game.coins < cost:
		Sfx.play("deny")
		return
	Game.coins -= cost
	if id == "wincap":
		Game.casino_wincap = 1
		event("전투창 상한이 늘었다! 카지노 만세!", 3.0)
	else:
		Game.own_medal(id)
		event("훈장 「%s」 을 손에 넣었다!" % Game.MEDAL_DEFS[id]["name"], 3.5)
	Sfx.play("fanfare_big")
	_update_top()
	Game.save_game()
	open_casino()

# ---------------------------------------------------------------- 음유시인 (서사시)

func open_bard() -> void:
	_menu_kind = "bard"
	var v := _menu_panel("음유시인 — 잠든 사이의 서사시")
	for i in Game.EPIC_VERSES.size():
		if i < Game.epic_verses:
			_menu_row(v, "제 %d절" % (i + 1), "이미 들은 이야기다", "다시 듣기", true,
				func(): _show_verse(i))
		elif i == Game.epic_verses:
			var cost: int = Game.EPIC_COSTS[i]
			_menu_row(v, "제 %d절 — 미지의 이야기" % (i + 1), "절이 열릴 때마다 세계에 무언가가 일어난다", "%d G" % cost,
				Game.gold >= cost, func(): _buy_verse(i))
		else:
			_menu_row(v, "제 %d절 — ⋯" % (i + 1), "", "—", false, func(): pass)
	if Game.epic_complete():
		v.add_child(UILib.make_label("「이야기는 끝났다. 이제, 끝을 바꿀 차례다.」", UILib.FS, UILib.COL_GOLD))

func _buy_verse(i: int) -> void:
	if not Game.buy_verse():
		Sfx.play("deny")
		return
	Sfx.play("fanfare_big")
	Game.save_game()
	_show_verse(i)
	# v3.1 — 절은 사건을 판다: 세계가 실제로 변한다
	if main != null:
		main.on_verse_bought(i)
	if Game.epic_complete():
		event("서사시가 완성되었다. …북쪽이 부른다.", 5.0)

func _show_verse(i: int) -> void:
	close_menu()
	_menu_kind = "verse"
	var p := UILib.make_panel(UILib.COL_GOLD)
	p.position = Vector2(150, 110)
	p.custom_minimum_size = Vector2(340, 0)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	v.add_child(UILib.make_label("서사시 — 제 %d절" % (i + 1), UILib.FS, UILib.COL_GOLD))
	var body := UILib.make_label(Game.EPIC_VERSES[i], UILib.FS)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(320, 0)
	v.add_child(body)
	var b := UILib.make_button("…", UILib.FS)
	b.pressed.connect(open_bard)
	v.add_child(b)

# ---------------------------------------------------------------- 훈장

func open_medals() -> void:
	_menu_kind = "medals"
	var v := _menu_panel("훈장 도감 (%d/%d 장착)" % [Game.medals_equipped.size(), Game.medal_slots()])
	# v3.2: 3계층으로 나눠 전시 — 순수/양날/조건/유령 (+v3.4 NEW 뱃지, 열람 시 해제)
	for tier in ["순수", "양날", "조건", "유령"]:
		v.add_child(UILib.make_label("— %s형 —" % tier, UILib.FS, UILib.COL_GOLD))
		for id in Game.MEDAL_DEFS.keys():
			var d: Dictionary = Game.MEDAL_DEFS[id]
			if String(d.get("tier", "")) != tier:
				continue
			if Game.medals_owned.has(id):
				var on := Game.medal_on(id)
				var badge := "[NEW] " if Game.is_new(id) else ""
				_menu_row(v, badge + ("★ " if on else "・ ") + d["name"], d["desc"],
					"해제" if on else "장착", true, func(): _toggle_medal(id))
			else:
				_menu_row(v, "・ ？？？", d["hint"], "—", false, func(): pass)
	Game.clear_new(Game.medals_owned)  # 도감을 펼쳤으니 NEW 해제

func _toggle_medal(id: String) -> void:
	if Game.toggle_medal(id):
		Sfx.play("buy" if Game.medal_on(id) else "click")
		Game.save_game()
		open_medals()
	else:
		Sfx.play("deny")
		event("훈장 슬롯이 가득 찼다! (%d개)" % Game.medal_slots())

# ---------------------------------------------------------------- 타이틀 커맨드 (v3.3 §B·C)

func title_hide(on: bool) -> void:
	# 타이틀 상태 — 마을만 보인다. HUD는 잠든다
	_title_suppress = on
	_top_panel.visible = Game.ui_unlocked["gold"] and not on
	_party_bar.visible = Game.ui_unlocked["party"] and not on
	_tooltip.visible = false
	_event_box.visible = false
	_event_q.clear()
	_event_showing = false

var _title_suppress := false

func open_title_menu() -> void:
	_menu_kind = "title"
	var v := _menu_panel("— 모험의 서 —")
	var any_slot := false
	for i in [1, 2, 3]:
		if Game.slot_meta(i).get("exists", false):
			any_slot = true
	_menu_row(v, "모험을 계속한다", "잠들어 있던 모험을 이어서", "선택", any_slot,
		func(): open_title_slots(false))
	_menu_row(v, "처음부터 시작한다", "새로운 용사가 늦잠에서 깬다", "선택", true,
		func(): open_title_slots(true))
	_menu_row(v, "옵션", "음량·화면·텍스트 속도", "열기", true,
		func(): open_options(false))

func open_title_slots(new_game: bool) -> void:
	_menu_kind = "title_slots"
	var v := _menu_panel("모험의 서 — " + ("어디에 기록할까" if new_game else "어느 서를 펼칠까"))
	for i in [1, 2, 3]:
		var m: Dictionary = Game.slot_meta(i)
		if m.get("exists", false):
			var mins := int(float(m["playtime"]) / 60.0)
			var label := "서 %d — %s Lv%d" % [i, m["name"], m["level"]]
			var sub := "%d주차 · 부흥 %d단계 · %d시간 %d분" % [m["run"], m["revival"], mins / 60, mins % 60]
			if new_game:
				_menu_row(v, label, sub + " — 여기에 새로 쓰면 지워진다!", "덮어쓴다", true,
					func(): _title_confirm_overwrite(i))
			else:
				_menu_row(v, label, sub, "계속한다", true,
					func():
						close_menu()
						main.title_continue(i))
		else:
			if new_game:
				_menu_row(v, "서 %d — (백지)" % i, "아무것도 적혀 있지 않다", "시작한다", true,
					func():
						close_menu()
						main.title_new(i))
			else:
				_menu_row(v, "서 %d — (백지)" % i, "", "—", false, func(): pass)
	_menu_row(v, "돌아간다", "", "←", true, open_title_menu)

func _title_confirm_overwrite(slot: int) -> void:
	# 드퀘식 안전장치 — 커서는 기본으로 "아니오"에 (v3.3 §C)
	_menu_kind = "title_confirm"
	var v := _menu_panel("정말로 지워도 되겠습니까?")
	v.add_child(UILib.make_label("서 %d의 모험이 영원히 사라집니다." % slot, UILib.FS, UILib.COL_RED))
	_menu_row(v, "아니오", "그럴 리가 없다", "돌아간다", true,
		func(): open_title_slots(true))
	_menu_row(v, "네", "…각오는 되어 있다", "지운다", true,
		func():
			close_menu()
			main.title_new(slot))

# ---------------------------------------------------------------- 크레딧 (v3.3 §F — 마을이 배경)

func roll_credits(lines: Array, on_done: Callable) -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_root.add_child(root)
	# 화면이 서서히 밝아지며 (얇은 새벽빛)
	var lightening := ColorRect.new()
	lightening.color = Color(1.0, 0.95, 0.85, 0.0)
	lightening.set_anchors_preset(Control.PRESET_FULL_RECT)
	lightening.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lightening)
	var tw0 := create_tween()
	tw0.tween_property(lightening, "color:a", 0.22, 8.0)
	# 텍스트 노드 트윈 — ScrollContainer 아님 (도트 폰트 유지)
	var total_t := 0.0
	for li in lines.size():
		var text: String = lines[li]
		if text == "":
			continue
		var l := UILib.make_label(text, UILib.FS, UILib.COL_GOLD if li == 0 else UILib.COL_WHITE)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override("outline_size", 3)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(l)
		await get_tree().process_frame
		l.position = Vector2(320 - l.size.x / 2.0, 372 + li * 22)
		var travel: float = l.position.y + 40.0
		var dur := travel / 26.0  # 초속 26px — 읽을 수 있는 속도
		var tw := create_tween()
		tw.tween_property(l, "position:y", -30.0, dur)
		tw.tween_callback(l.queue_free)
		total_t = maxf(total_t, dur)
	get_tree().create_timer(total_t + 0.8).timeout.connect(func():
		root.queue_free()
		on_done.call())
