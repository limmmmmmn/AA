class_name Hud
extends CanvasLayer
## 화면 하단 고정 UI — 드퀘식 스테이터스 창 + 상시 설명창 + 메뉴 + 연출 레이어

const SLOT_SIZE := Vector2(150, 84)
const SLOT_POS := [
	Vector2(4, 22), Vector2(158, 22), Vector2(312, 22), Vector2(466, 22),
	Vector2(4, 110), Vector2(158, 110), Vector2(312, 110), Vector2(466, 110),
]
const GOLD_TARGET := Vector2(36, 10)

const DOCK_ITEMS := [
	{"id": "tree",   "label": "계획도"},
	{"id": "board",  "label": "수배"},
	{"id": "smith",  "label": "대장간"},
	{"id": "casino", "label": "카지노"},
	{"id": "bard",   "label": "서사시"},
	{"id": "medals", "label": "훈장"},
]

const IDLE_LINES := [
	"바람이 분다. 평화롭다. …일단은.",
	"일행은 씩씩하게 걷고 있다.",
	"마왕은 이미 이겼다. 그래서 뭐 어떤가.",
	"어디선가 슬라임 우는 소리가 들린다.",
	"돌아갈 곳이 있다는 건 좋은 일이다.",
	"몬스터에게 부딪히면 전투창이 열린다.",
	"전투창을 지켜보면 일행이 힘을 낸다.",
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
var _dock_btns: Dictionary = {}   # id → Button
var _dock_t := 0.0
var _board_tab := 0
var room_name := "기지"           # main이 설정

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

func _build() -> void:
	windows_root = Control.new()
	windows_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	windows_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(windows_root)

	# 상단 바
	var top := UILib.make_panel()
	top.position = Vector2(4, 2)
	add_child(top)
	_top_label = UILib.make_label("", UILib.FS, UILib.COL_GOLD)
	top.add_child(_top_label)

	# 마을 도크 — 시선 활동의 신호등 (오른쪽 세로)
	for i in DOCK_ITEMS.size():
		var item: Dictionary = DOCK_ITEMS[i]
		var b := UILib.make_button(item["label"], UILib.FS)
		b.position = Vector2(586, 176 + i * 20)
		b.size = Vector2(50, 18)
		b.visible = false
		var id: String = item["id"]
		b.pressed.connect(func(): _dock_pressed(id))
		add_child(b)
		_dock_btns[id] = b

	# 상시 설명창 (하단 왼쪽)
	var desc := UILib.make_panel()
	desc.position = Vector2(4, 318)
	desc.custom_minimum_size = Vector2(196, 38)
	add_child(desc)
	_desc_label = UILib.make_label("", UILib.FS)
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size = Vector2(184, 28)
	desc.add_child(_desc_label)

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
	# 도크 점등
	_dock_t += delta
	if fmod(_dock_t, 0.25) < delta:
		_update_dock()

# ---------------------------------------------------------------- 마을 도크

func _dock_pressed(id: String) -> void:
	if id == "tree":
		if main != null:
			main.tree_ui.toggle()
		return
	if id == "smith":
		if main != null and main.smith_ready():
			open_smith()
		else:
			Sfx.play("deny")
			event("화덕이 아직 식어 있다…")
		return
	if _menu_kind == id:
		close_menu()
		return
	match id:
		"board": open_board()
		"casino": open_casino()
		"bard": open_bard()
		"medals": open_medals()

func _update_dock() -> void:
	var vis := {
		"tree": true,
		"board": Game.buildings["board"],
		"smith": Game.buildings["smith"],
		"casino": Game.buildings["casino"],
		"bard": Game.buildings["bard"],
		"medals": Game.medals_owned.size() > 0,
	}
	var lit := {
		"tree": RebuildTree.any_affordable(),
		"board": _board_affordable(),
		"smith": main != null and main.smith_ready(),
		"casino": Game.coins >= 200,
		"bard": not Game.epic_complete() and Game.epic_verses < Game.EPIC_COSTS.size() and Game.gold >= Game.EPIC_COSTS[Game.epic_verses],
		"medals": false,
	}
	var pulse := 0.75 + 0.25 * sin(_dock_t * 6.0)
	for id in _dock_btns.keys():
		var b: Button = _dock_btns[id]
		b.visible = vis.get(id, false)
		if lit.get(id, false):
			b.modulate = Color(pulse + 0.3, pulse + 0.2, 0.5)
		else:
			b.modulate = Color(1, 1, 1)

func _board_affordable() -> bool:
	for f in 4:
		if Game.fields_unlocked[f] and Game.posters_f[f] < 3 \
				and Game.gold >= Game.poster_cost(f, Game.posters_f[f]):
			return true
	return false

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
	_event_text = text
	_event_t = dur

# ---------------------------------------------------------------- 파티 스테이터스

func _rebuild_members() -> void:
	for b in _member_boxes:
		if is_instance_valid(b["panel"]):
			b["panel"].queue_free()
	_member_boxes = []
	for i in Game.members.size():
		var p := UILib.make_panel()
		p.position = Vector2(204 + i * 76, 318)
		p.custom_minimum_size = Vector2(74, 38)
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
		return _member_boxes[i]["panel"].position + Vector2(37, 19)
	return Vector2(320, 330)

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
		main.goto_room(i)

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
	_casino_medal_row(v, "metal_crown", 300)
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
