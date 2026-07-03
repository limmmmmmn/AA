class_name Hud
extends CanvasLayer
## 화면 하단 고정 UI — 드퀘식 스테이터스 창 + 상시 설명창 + 메뉴 + 연출 레이어

const SLOT_SIZE := Vector2(150, 84)
const SLOT_POS := [
	Vector2(4, 22), Vector2(158, 22), Vector2(312, 22), Vector2(466, 22),
	Vector2(4, 110), Vector2(158, 110), Vector2(312, 110), Vector2(466, 110),
]
const GOLD_TARGET := Vector2(40, 16)

const IDLE_LINES := [
	"바람이 분다. 평화롭다. …일단은.",
	"일행은 씩씩하게 걷고 있다.",
	"마왕은 이미 이겼다. 그래서 뭐 어떤가.",
	"어디선가 슬라임 우는 소리가 들린다.",
	"돌아갈 곳이 있다는 건 좋은 일이다.",
	"몬스터에게 부딪히면 전투창이 열린다.",
	"전투창을 지켜보면 일행이 힘을 낸다.",
	"마을에 서 있는 사람 수가 곧 진행바다.",
]

var main: Node2D

var windows_root: Control
var _fx_root: Control
var _menu_root: Control
var _overlay_root: Control

var _top_label: Label
var _desc_label: Label
var _member_boxes: Array = []
var _casino_refs: Dictionary = {}
var _spin_active := false
var _board_tab := 0
var room_name := "기지"           # main이 설정
var _bubble: PanelContainer
var _bubble_label: Label
var _top_panel: PanelContainer
var _desc_panel: PanelContainer

var _hover_text := ""
var _event_text := ""
var _event_t := 0.0
var _idle_t := 0.0
var _idle_i := 0
var _menu_kind := ""
var menu_hover := ""   # 메뉴 항목 호버 시 설명창에 흘릴 텍스트

func _ready() -> void:
	layer = 10
	_build()
	Game.gold_changed.connect(func(_v): _update_top())
	Game.level_changed.connect(func(_v): _update_top())
	Game.chapter_changed.connect(func(_v): _update_top())
	Game.party_changed.connect(_rebuild_members)
	Game.member_changed.connect(_update_member)
	Game.upgrades_changed.connect(func(): _update_top())
	_update_top()
	_rebuild_members()
	# 세이브에서 이미 태어난 UI는 연출 없이 바로 보여준다 (탄생은 최초 1회뿐)
	if Game.ui_unlocked["desc"]:
		_desc_panel.visible = true
	if Game.ui_unlocked["gold"]:
		_top_panel.visible = true

func _build() -> void:
	windows_root = Control.new()
	windows_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	windows_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(windows_root)

	# 상단 정보창 — 첫 골드를 벌면 태어난다 (8px 그리드)
	_top_panel = UILib.make_panel()
	_top_panel.position = Vector2(8, 8)
	_top_panel.visible = false
	add_child(_top_panel)
	_top_label = UILib.make_label("", UILib.FS, UILib.COL_GOLD)
	_top_panel.add_child(_top_label)

	# 말풍선 (호버한 캐릭터 머리 위)
	_bubble = UILib.make_panel()
	_bubble.visible = false
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bubble)
	_bubble_label = UILib.make_label("", UILib.FS)
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_label.custom_minimum_size = Vector2(0, 0)
	_bubble_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(_bubble_label)

	# 상시 설명창 — 촌장에게 말을 걸면 태어난다 (베이스라인 y=352, 높이 40)
	_desc_panel = UILib.make_panel()
	_desc_panel.position = Vector2(8, 312)
	_desc_panel.custom_minimum_size = Vector2(240, 40)
	_desc_panel.visible = false
	add_child(_desc_panel)
	_desc_label = UILib.make_label("", UILib.FS)
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size = Vector2(224, 26)
	_desc_panel.add_child(_desc_label)

	_fx_root = Control.new()
	_fx_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fx_root)

	_menu_root = Control.new()
	_menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_menu_root)

	_overlay_root = Control.new()
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay_root)

func _process(delta: float) -> void:
	if _event_t > 0.0:
		_event_t -= delta
		_desc_label.text = _event_text
	elif _hover_text != "":
		_desc_label.text = _hover_text
	else:
		_idle_t -= delta
		if _idle_t <= 0.0:
			_idle_t = 9.0
			_idle_i = (_idle_i + 1) % IDLE_LINES.size()
		_desc_label.text = IDLE_LINES[_idle_i]

# ---------------------------------------------------------------- UI 공개 스케줄 (게임이 자라는 게임)

func unlock_ui(id: String) -> void:
	if Game.ui_unlocked.get(id, false):
		return
	Game.ui_unlocked[id] = true
	Sfx.play("window", 1.2)
	var target: Control = null
	match id:
		"desc":
			target = _desc_panel
		"gold":
			target = _top_panel
			_update_top()
		"party":
			_rebuild_members()
			for b in _member_boxes:
				if is_instance_valid(b["panel"]):
					_birth_pop(b["panel"])
		"quest":
			pass  # 촌장의 부탁이 열린다 — UI가 아니라 세계(촌장)가 창구
	if target != null:
		target.visible = true
		_birth_pop(target)
	Game.save_game()

func _birth_pop(c: Control) -> void:
	# UI의 탄생 — 뿅
	c.pivot_offset = c.size / 2.0
	c.scale = Vector2(0.2, 0.2)
	var tw := create_tween()
	tw.tween_property(c, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

var _toasts: Array = []

func toast(text: String, dur: float = 3.0) -> void:
	# 설명창이 태어나기 전의 대사는 화면 중앙에 — 여러 개면 아래로 쌓인다
	var l := UILib.make_label(text, UILib.FS, UILib.COL_WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_root.add_child(l)
	_toasts.append(l)
	await get_tree().process_frame
	if not is_instance_valid(l):
		return
	var idx: int = maxi(0, _toasts.find(l))
	l.position = Vector2(320 - l.size.x / 2.0, 140 + idx * 14)
	var tw := create_tween()
	tw.tween_interval(dur)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func():
		_toasts.erase(l)
		l.queue_free())

# ---------------------------------------------------------------- 말풍선

func show_bubble(text: String, screen_pos: Vector2) -> void:
	_bubble_label.text = text
	_bubble_label.custom_minimum_size = Vector2(minf(150.0, text.length() * UILib.FS + 8.0), 0)
	_bubble.visible = true
	_bubble.reset_size()
	var p := screen_pos - Vector2(_bubble.size.x / 2.0, _bubble.size.y)
	p.x = clampf(p.x, 2.0, 640.0 - _bubble.size.x - 2.0)
	p.y = clampf(p.y, 2.0, 360.0 - _bubble.size.y - 2.0)
	_bubble.position = p

func hide_bubble() -> void:
	_bubble.visible = false

# ---------------------------------------------------------------- 상단/설명

func _update_top() -> void:
	var t := "%s   G %d   Lv %d" % [room_name, Game.gold, Game.level]
	if Game.coins > 0:
		t += "   C %d" % Game.coins
	if Game.run_count > 1:
		t += "   %d회차" % Game.run_count
	_top_label.text = t

func set_hover(text: String) -> void:
	_hover_text = text

func event(text: String, dur: float = 2.5) -> void:
	if not Game.ui_unlocked["desc"]:
		toast(text, dur)  # 설명창이 태어나기 전엔 중앙에
		return
	_event_text = text
	_event_t = dur

# ---------------------------------------------------------------- 파티 스테이터스

func _rebuild_members() -> void:
	for b in _member_boxes:
		if is_instance_valid(b["panel"]):
			b["panel"].queue_free()
	_member_boxes = []
	if not Game.ui_unlocked["party"]:
		return
	var n := Game.members.size()
	for i in n:
		var p := UILib.make_panel()
		# 오른쪽에서부터 채우고, 새 동료가 오면 한 칸씩 자란다 (베이스라인 y=352)
		p.position = Vector2(632 - 74 - (n - 1 - i) * 82, 312)
		p.custom_minimum_size = Vector2(74, 40)
		add_child(p)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		p.add_child(v)
		var name_l := UILib.make_label("", UILib.FS)
		v.add_child(name_l)
		var hp_l := UILib.make_label("", UILib.FS)
		v.add_child(hp_l)
		var bar_bg := ColorRect.new()
		bar_bg.color = Color(0.2, 0.2, 0.25)
		bar_bg.custom_minimum_size = Vector2(60, 2)
		v.add_child(bar_bg)
		var bar := ColorRect.new()
		bar.color = UILib.COL_GREEN
		bar.size = Vector2(60, 2)
		bar_bg.add_child(bar)
		_member_boxes.append({"panel": p, "name": name_l, "hp": hp_l, "bar": bar})
		_update_member(i)

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
	b["hp"].text = "HP %d" % m["hp"]
	b["hp"].add_theme_color_override("font_color", UILib.COL_GRAY if ghost else UILib.COL_WHITE)
	var ratio: float = float(m["hp"]) / maxf(1.0, float(m["max_hp"]))
	b["bar"].size = Vector2(60.0 * ratio, 2)
	b["bar"].color = UILib.COL_GRAY if ghost else (UILib.COL_GREEN if ratio > 0.35 else UILib.COL_RED)
	b["panel"].add_theme_stylebox_override("panel", UILib.panel_style(UILib.COL_GRAY if ghost else UILib.COL_WHITE))

func member_box_center(i: int) -> Vector2:
	if i < _member_boxes.size() and is_instance_valid(_member_boxes[i]["panel"]):
		return _member_boxes[i]["panel"].position + Vector2(37, 20)
	return Vector2(500, 332)

# ---------------------------------------------------------------- 연출 (fx)

func fly_damage(from: Vector2, member_idx: int, dmg: int) -> void:
	var l := UILib.make_label(str(dmg), UILib.FS, UILib.COL_RED)
	l.position = from
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_root.add_child(l)
	var to := member_box_center(member_idx) + Vector2(-8, -10)
	var tw := create_tween()
	tw.tween_property(l, "position", to, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		l.queue_free()
		if member_idx < _member_boxes.size() and is_instance_valid(_member_boxes[member_idx]["panel"]):
			var p: PanelContainer = _member_boxes[member_idx]["panel"]
			p.add_theme_stylebox_override("panel", UILib.panel_style(UILib.COL_RED))
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
	var l := UILib.make_label(text, UILib.FS, color)
	l.position = screen_pos + Vector2(-14, -18)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = 20
	_fx_root.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 18.0, 0.8)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)

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
	for c in _menu_root.get_children():
		c.queue_free()

func _menu_panel(title: String) -> VBoxContainer:
	close_menu()
	var p := UILib.make_panel(UILib.COL_GOLD)
	p.position = Vector2(160, 14)
	p.custom_minimum_size = Vector2(320, 0)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	p.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UILib.make_label(title, UILib.FS, UILib.COL_GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x := UILib.make_button("닫기", UILib.FS)
	x.pressed.connect(close_menu)
	head.add_child(x)
	return v

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
	var v := _menu_panel("촌장 — 마을의 모든 일")
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
	_up_row(v, "density", "무리 유인", "창당 최대 적 수 +1", 120, 2.0, 4, 4)
	v.add_child(UILib.make_label("— 원정 —", UILib.FS, UILib.COL_GOLD))
	_up_row(v, "speed", "이속 강화", "파티 이동 속도 +8%", 25, 1.2, 9, 0)
	_up_row(v, "shovel", "삽", "반짝이는 땅을 판다", 150, 1.0, 1, 0)
	_up_row(v, "intuition", "용사의 직감", "파티가 스스로 사냥하고 돌아온다", 800, 1.0, 1, 5)
	if Game.up["intuition"] > 0:
		_up_row(v, "radius", "행동반경", "직감 사냥 반경 +80", 200, 2.0, 3, 0)

func _up_row(v: VBoxContainer, id: String, name_txt: String, desc: String, base: int, growth: float, max_lv: int, lv_gate: int) -> void:
	var lv: int = Game.up[id]
	var maxed: bool = lv >= max_lv
	var cost := int(base * pow(growth, lv))
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
		_: open_chief()

func _chief_pay(id: String) -> void:
	if main.try_pay_resident(id):
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
	_menu_row(v, "쉬어간다", "일행의 HP를 전부 회복한다", "무료", need, _inn_rest)
	_up_row(v, "max_hp", "침구 개선", "전원 최대 HP +6", 30, 1.2, 9, 0)

func _inn_rest() -> void:
	Sfx.play("heal")
	Game.heal_all_full()
	if Game.ghost_count() > 0:
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
	_menu_row(v, "모험의 서에 기록한다", "다음 회차로 — 훈장·서사시는 남는다",
		"기록" if Game.bosses_defeated[4] or Game.ending_seen else "마왕 처치 후",
		Game.bosses_defeated[4] or Game.ending_seen,
		func(): main._do_prestige())

func _church_revive() -> void:
	var cost := Game.revive_cost()
	if not Game.try_spend(cost):
		Sfx.play("deny")
		return
	Sfx.play("revive")
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
	var cost := int(base * pow(growth, n))
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
	_medal_trade_row(v, "cracked_pot", 3)
	_medal_trade_row(v, "metal_crown", 8)
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
				3: sub = "정예와 황금 슬라임의 땅"
				4: sub = "지배자들의 심장부"
			if Game.bosses_defeated[i]:
				name_txt += " (해방됨)"
			if i == 4 and not Game.epic_complete():
				_menu_row(v, name_txt, "이야기의 끝을 알아야 들어갈 수 있다 (음유시인)", "닫힘", false, func(): pass)
			else:
				_menu_row(v, name_txt, sub, "출발", true, func(): _depart(i))
		else:
			_menu_row(v, "？？？", "재건 계획도의 원정 가지에서 길을 열 수 있다", "—", false, func(): pass)

func _depart(i: int) -> void:
	close_menu()
	if main != null:
		main.select_field(i)
		Sfx.play("click")
		event("이정표가 %s 쪽을 가리킨다. 동쪽으로!" % Game.FIELD_NAMES[i], 3.0)

# ---------------------------------------------------------------- 대장간

func open_smith() -> void:
	_menu_kind = "smith"
	var v := _menu_panel("대장간 — \"이번엔 누굴 벼릴까\"")
	for i in Game.members.size():
		var m: Dictionary = Game.members[i]
		if m["cls"] == "hero":
			_menu_row(v, Game.weapon_name(i), "전설의 검은 돈으로 벼릴 수 없다 (음유시인에게)", "—", false, func(): pass)
			continue
		var cost := Game.weapon_cost(i)
		_menu_row(v, Game.weapon_name(i), "리듬에 맞춰 두들긴다 — 판정에 따라 +1/+2/+3", "%d G" % cost,
			Game.gold >= cost, func(): _start_forge(i, cost))

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
	Game.members[i]["weapon_lv"] += result
	var lv: int = Game.members[i]["weapon_lv"]
	if result >= 3:
		Sfx.play("fanfare_big")
		event("회심의 필살작!! %s" % Game.weapon_name(i), 3.5)
		Game.smith_perfects += 1
		if Game.smith_perfects >= 3 and Game.own_medal("anvil_bless"):
			event("훈장 「모루의 축복」 을 손에 넣었다!", 4.0)
			_update_top()
	elif result == 2:
		Sfx.play("buy")
		event("좋은 물건이다. %s" % Game.weapon_name(i), 2.5)
	else:
		Sfx.play("bump")
		event("…뭐, 쓸 만하다. %s" % Game.weapon_name(i), 2.5)
	if (lv >= 5 and lv - result < 5) or (lv >= 10 and lv - result < 10):
		Sfx.play("fanfare_big")
		event("%s이(가) 다시 태어났다!" % Game.weapon_name(i), 3.5)
	if main != null:
		main.on_forged()
	Game.save_game()

func open_board(tab: int = -1) -> void:
	_menu_kind = "board"
	if tab >= 0:
		_board_tab = tab
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
	_menu_row(v, "슬롯을 돌린다", "같은 그림 3개 = 대박, 2개 = 본전", "1 코인", true, _casino_spin)
	# 교환소
	v.add_child(UILib.make_label("— 교환소 —", UILib.FS, UILib.COL_GOLD))
	if Game.casino_wincap == 0:
		_menu_row(v, "전투창 상한 +1", "카지노에서만 구할 수 있는 힘", "500 코인", Game.coins >= 500,
			func(): _casino_exchange("wincap", 500))
	else:
		_menu_row(v, "전투창 상한 +1", "", "교환 완료", false, func(): pass)
	_casino_medal_row(v, "mimic_teeth", 300)
	_casino_medal_row(v, "slime_incense", 200)

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
	if Game.coins < 1:
		Sfx.play("deny")
		event("코인이 없다. …골드는 두고 가라.")
		return
	Game.coins -= 1
	_update_top()
	_casino_update_coins()
	_spin_active = true
	# 결과는 먼저 정해진다 — 연출은 거들 뿐
	var final: Array = [_roll_symbol(), _roll_symbol(), _roll_symbol()]
	var payout := 0
	if final[0] == final[1] and final[1] == final[2]:
		payout = SLOT_PAYOUTS[final[0]]
	elif final[0] == final[1] or final[1] == final[2] or final[0] == final[2]:
		payout = 1
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
			_menu_row(v, "제 %d절 — 미지의 이야기" % (i + 1), "전설의 검은 이야기를 먹고 자란다", "%d G" % cost,
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
	if Game.epic_complete():
		event("서사시가 완성되었다. …북쪽이 부른다.", 5.0)
	else:
		event("용사의 검이 희미하게 빛난다… (%s)" % Game.weapon_name(0), 3.5)

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
	for id in Game.MEDAL_DEFS.keys():
		var d: Dictionary = Game.MEDAL_DEFS[id]
		if Game.medals_owned.has(id):
			var on := Game.medal_on(id)
			_menu_row(v, ("★ " if on else "・ ") + d["name"], d["desc"],
				"해제" if on else "장착", true, func(): _toggle_medal(id))
		else:
			_menu_row(v, "・ ？？？", d["hint"], "—", false, func(): pass)

func _toggle_medal(id: String) -> void:
	if Game.toggle_medal(id):
		Sfx.play("buy" if Game.medal_on(id) else "click")
		Game.save_game()
		open_medals()
	else:
		Sfx.play("deny")
		event("훈장 슬롯이 가득 찼다! (%d개)" % Game.medal_slots())

# ---------------------------------------------------------------- 엔딩

func show_ending(on_prestige: Callable, on_continue: Callable) -> void:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, 0)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_root.add_child(r)
	var tw := create_tween()
	tw.tween_property(r, "color:a", 0.85, 1.5)
	tw.tween_callback(func():
		var p := UILib.make_panel(UILib.COL_GOLD)
		p.position = Vector2(160, 100)
		p.custom_minimum_size = Vector2(320, 0)
		r.add_child(p)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		p.add_child(v)
		v.add_child(UILib.make_label("마왕은 쓰러졌다.", UILib.FS))
		v.add_child(UILib.make_label("세계에 아침이 왔다.", UILib.FS))
		v.add_child(UILib.make_label("…용사는 내일도 늦잠을 잘 것이다.", UILib.FS, UILib.COL_GRAY))
		var b1 := UILib.make_button("모험의 서에 기록한다 (다음 회차로)", UILib.FS)
		b1.pressed.connect(func():
			r.queue_free()
			on_prestige.call())
		v.add_child(b1)
		var b2 := UILib.make_button("조금 더 논다", UILib.FS)
		b2.pressed.connect(func():
			r.queue_free()
			on_continue.call())
		v.add_child(b2)
	)
