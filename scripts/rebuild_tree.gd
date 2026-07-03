class_name RebuildTree
extends Control
## 마을 재건 계획도 — 촌장이 관리하는 노드 트리 (v2.0 §B-3)
## 전체화면 오버레이. 열려 있어도 게임/전투는 계속 돈다. 마우스 드래그 팬.
## 이중 열쇠: 마일스톤 → 노드가 "소문"과 함께 출현 → 골드 지불 = 구매.

## effect: "up:키" / "building:키" / "field:인덱스" / "assist:키" / "pots"
## reveal: {} 항상 / {"earned": n} / {"boss": 필드} / {"up": 키} / {"building": 키}
const NODES := [
	# ---- 전투 가지 (위)
	{"id": "win_cap",      "name": "전투창 확장", "pos": Vector2(0, -55),    "parent": "",            "levels": 5,  "base": 100, "growth": 2.2,  "effect": "up:win_cap",      "reveal": {}, "big": true,
		"desc": "동시 전투창 +1"},
	{"id": "battle_speed", "name": "전투 가속",   "pos": Vector2(-80, -78),  "parent": "win_cap",     "levels": 12, "base": 25,  "growth": 1.22, "effect": "up:battle_speed", "reveal": {},
		"desc": "전투 턴 간격 -7%"},
	{"id": "atk",          "name": "공격 단련",   "pos": Vector2(80, -78),   "parent": "win_cap",     "levels": 16, "base": 20,  "growth": 1.18, "effect": "up:atk",          "reveal": {},
		"desc": "파티 공격력 +2"},
	{"id": "density",      "name": "무리 유인",   "pos": Vector2(0, -105),   "parent": "win_cap",     "levels": 4,  "base": 120, "growth": 2.0,  "effect": "up:density",      "reveal": {"earned": 150},
		"desc": "창당 최대 적 수 +1", "rumor": "몬스터들이 떼로 몰려다닌다는 소문."},
	{"id": "max_hp",       "name": "튼튼한 몸",   "pos": Vector2(80, -130),  "parent": "atk",         "levels": 9,  "base": 30,  "growth": 1.2,  "effect": "up:max_hp",       "reveal": {},
		"desc": "전원 최대 HP +6"},
	{"id": "gold_mult",    "name": "골드 감각",   "pos": Vector2(-80, -130), "parent": "battle_speed","levels": 9,  "base": 60,  "growth": 1.25, "effect": "up:gold_mult",    "reveal": {},
		"desc": "골드 획득 +15%"},
	# ---- 원정 가지 (오른쪽)
	{"id": "speed",     "name": "이속 강화",   "pos": Vector2(85, 0),    "parent": "",       "levels": 9, "base": 25,   "growth": 1.2, "effect": "up:speed",     "reveal": {},
		"desc": "파티 이동 속도 +8%"},
	{"id": "shovel",    "name": "삽",          "pos": Vector2(160, 28),  "parent": "speed",  "levels": 1, "base": 150,  "growth": 1.0, "effect": "up:shovel",    "reveal": {"earned": 80},
		"desc": "반짝이는 땅을 판다", "rumor": "여기저기 반짝이는 땅이 있다는 소문."},
	{"id": "intuition", "name": "용사의 직감", "pos": Vector2(235, 28),  "parent": "shovel", "levels": 1, "base": 800,  "growth": 1.0, "effect": "up:intuition", "reveal": {"earned": 400}, "big": true,
		"desc": "파티가 스스로 사냥하고, 지치면 돌아온다", "rumor": "일행이 스스로 길을 찾고 싶어 하는 눈치다."},
	{"id": "radius",    "name": "행동반경",    "pos": Vector2(310, 28),  "parent": "intuition", "levels": 3, "base": 200, "growth": 2.0, "effect": "up:radius", "reveal": {"up": "intuition"},
		"desc": "직감 사냥 반경 +60"},
	{"id": "field1",    "name": "원정: 숲",    "pos": Vector2(160, -28), "parent": "speed",  "levels": 1, "base": 300,   "growth": 1.0, "effect": "field:1", "reveal": {"boss": 0}, "big": true,
		"desc": "숲 필드가 열린다 — 발굴 반짝이가 풍부하다", "rumor": "숲 너머에서 반짝이는 것을 봤다는 소문."},
	{"id": "field2",    "name": "원정: 동굴",  "pos": Vector2(235, -28), "parent": "field1", "levels": 1, "base": 1500,  "growth": 1.0, "effect": "field:2", "reveal": {"boss": 1}, "big": true,
		"desc": "동굴 필드가 열린다 — 무리 조우가 많다", "rumor": "동굴 깊은 곳에서 우글대는 소리가 들린다는 소문."},
	{"id": "field3",    "name": "원정: 설원",  "pos": Vector2(310, -28), "parent": "field2", "levels": 1, "base": 6000,  "growth": 1.0, "effect": "field:3", "reveal": {"boss": 2}, "big": true,
		"desc": "설원 필드가 열린다 — 정예와 황금 슬라임의 땅", "rumor": "눈보라 속에서 금빛이 번쩍였다는 소문."},
	{"id": "field4",    "name": "원정: 마왕성","pos": Vector2(385, -28), "parent": "field3", "levels": 1, "base": 20000, "growth": 1.0, "effect": "field:4", "reveal": {"boss": 3}, "big": true,
		"desc": "마왕성으로 가는 길 — 입장에는 서사시 완독이 필요하다", "rumor": "북쪽 성문이 흔들리고 있다…"},
	# ---- 마을 가지 (아래)
	{"id": "smith",  "name": "대장간",       "pos": Vector2(0, 55),    "parent": "",       "levels": 1, "base": 250,  "growth": 1.0, "effect": "building:smith",  "reveal": {"earned": 100}, "big": true,
		"desc": "무기를 벼릴 수 있다 (리듬 미니게임)", "rumor": "떠돌이 대장장이가 머물 곳을 찾는다."},
	{"id": "church", "name": "교회",         "pos": Vector2(-80, 78),  "parent": "smith",  "levels": 1, "base": 200,  "growth": 1.0, "effect": "building:church", "reveal": {"earned": 80}, "big": true,
		"desc": "유령을 되살릴 수 있다", "rumor": "순례자가 제단 자리를 찾고 있다."},
	{"id": "chest",  "name": "보물상자",     "pos": Vector2(80, 78),   "parent": "smith",  "levels": 1, "base": 400,  "growth": 1.0, "effect": "building:chest",  "reveal": {"earned": 250}, "big": true,
		"desc": "광장에 보물상자가 놓인다", "rumor": "커다란 상자를 끌고 오는 사람을 봤다."},
	{"id": "pots",   "name": "항아리 확충",  "pos": Vector2(0, 105),   "parent": "smith",  "levels": 2, "base": 300,  "growth": 1.8, "effect": "pots",            "reveal": {"earned": 200},
		"desc": "광장 항아리 +2", "rumor": "항아리 장수가 지나갔다는 소문."},
	{"id": "bard",   "name": "음유시인",     "pos": Vector2(-80, 130), "parent": "church", "levels": 1, "base": 800,  "growth": 1.0, "effect": "building:bard",   "reveal": {"earned": 600}, "big": true,
		"desc": "잠든 사이의 서사시를 판다", "rumor": "노래하는 자가 이야기를 모으고 있다."},
	{"id": "casino", "name": "카지노",       "pos": Vector2(80, 130),  "parent": "chest",  "levels": 1, "base": 1500, "growth": 1.0, "effect": "building:casino", "reveal": {"earned": 1200}, "big": true,
		"desc": "골드를 코인으로, 코인을 꿈으로", "rumor": "수상한 손님이 천막 칠 자리를 찾는다."},
	# ---- 조수 가지 (왼쪽)
	{"id": "monkey", "name": "원숭이",   "pos": Vector2(-85, 0),   "parent": "",       "levels": 3, "base": 600,  "growth": 2.5, "effect": "assist:monkey", "reveal": {"earned": 300},
		"desc": "마을 항아리를 자동으로 깬다", "rumor": "항아리를 노리는 원숭이가 어슬렁댄다."},
	{"id": "keeper", "name": "상자지기", "pos": Vector2(-160, -28), "parent": "monkey", "levels": 1, "base": 900,  "growth": 1.0, "effect": "assist:keeper", "reveal": {"building": "chest"},
		"desc": "보물상자를 자동으로 연다", "rumor": "상자만 바라보는 쥐돌이가 있다."},
	{"id": "pig",    "name": "꽃돼지",   "pos": Vector2(-160, 28), "parent": "monkey", "levels": 3, "base": 1200, "growth": 2.2, "effect": "assist:pig",    "reveal": {"up": "shovel"},
		"desc": "필드의 반짝이를 자동으로 판다 (일행과 동행)", "rumor": "코가 밝은 돼지가 마을 앞을 판다."},
]

var main: Node2D
var _pan := Vector2.ZERO
var _dragging := false
var _canvas: Control
var _buttons := {}   # id → Button
var _gold_label: Label

func _ready() -> void:
	position = Vector2.ZERO
	size = Vector2(640, 360)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	var title := UILib.make_panel(UILib.COL_GOLD)
	title.position = Vector2(4, 4)
	add_child(title)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 8)
	title.add_child(th)
	th.add_child(UILib.make_label("마을 재건 계획도", UILib.FS, UILib.COL_GOLD))
	_gold_label = UILib.make_label("", UILib.FS)
	th.add_child(_gold_label)
	var x := UILib.make_button("닫기 (Tab)")
	x.pressed.connect(close)
	th.add_child(x)
	Game.gold_changed.connect(func(_v):
		if visible:
			_refresh())

func open() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	_refresh()

func close() -> void:
	visible = false
	if main != null and main.hud != null:
		main.hud.menu_hover = ""

func toggle() -> void:
	if visible:
		close()
	else:
		open()

# ---------------------------------------------------------------- 상태

static func node_level(n: Dictionary) -> int:
	var parts: PackedStringArray = String(n["effect"]).split(":")
	match parts[0]:
		"up":
			return Game.up[parts[1]]
		"assist":
			return Game.assistants[parts[1]]
		"building":
			return 1 if Game.buildings[parts[1]] else 0
		"field":
			return 1 if Game.fields_unlocked[int(parts[1])] else 0
		"pots":
			return Game.extra_pots
	return 0

static func node_cost(n: Dictionary) -> int:
	return int(n["base"] * pow(n["growth"], node_level(n)))

static func reveal_met(n: Dictionary) -> bool:
	var r: Dictionary = n["reveal"]
	if r.has("earned") and Game.total_earned < int(r["earned"]):
		return false
	if r.has("boss") and not Game.bosses_defeated[int(r["boss"])]:
		return false
	if r.has("up") and Game.up[r["up"]] == 0:
		return false
	if r.has("building") and not Game.buildings[r["building"]]:
		return false
	return true

static func is_visible_node(n: Dictionary) -> bool:
	return node_level(n) > 0 or Game.tree_revealed.get(n["id"], false)

static func any_affordable() -> bool:
	# 도크 점등용 — 소문 난 노드 중 살 수 있는 것이 있는가
	for n in NODES:
		if is_visible_node(n) and node_level(n) < int(n["levels"]) and Game.gold >= node_cost(n):
			return true
	return false

# ---------------------------------------------------------------- UI

func _center() -> Vector2:
	return Vector2(320, 190) + _pan

func _refresh() -> void:
	_gold_label.text = "G %d" % Game.gold
	for c in _canvas.get_children():
		c.queue_free()
	_buttons = {}
	_canvas.queue_redraw()
	# 중앙 광장 노드
	var hub := UILib.make_panel(UILib.COL_GOLD)
	hub.position = _center() - Vector2(24, 12)
	_canvas.add_child(hub)
	hub.add_child(UILib.make_label("광 장", UILib.FS, UILib.COL_GOLD))
	# 노드들
	for n in NODES:
		if not is_visible_node(n):
			continue
		var lv := node_level(n)
		var maxed: bool = lv >= int(n["levels"])
		var cost := node_cost(n)
		var b := UILib.make_button("", UILib.FS)
		var label: String = n["name"]
		if int(n["levels"]) > 1:
			label += " %d/%d" % [lv, n["levels"]]
		b.text = label + ("" if maxed else "\n%d G" % cost)
		var big: bool = n.get("big", false)
		b.custom_minimum_size = Vector2(78 if big else 66, 30)
		b.position = _center() + n["pos"] - b.custom_minimum_size / 2.0
		b.disabled = maxed or Game.gold < cost
		if maxed:
			b.modulate = Color(0.6, 0.65, 0.6)
		elif Game.gold >= cost:
			b.modulate = Color(1.1, 1.05, 0.85)
		var id: String = n["id"]
		b.pressed.connect(func(): buy_node(id))
		var hover_text: String = n["name"] + " — " + String(n["desc"])
		if not maxed:
			hover_text += "  (%d G)" % cost
		b.mouse_entered.connect(func():
			if main != null:
				main.hud.menu_hover = hover_text)
		b.mouse_exited.connect(func():
			if main != null:
				main.hud.menu_hover = "")
		_canvas.add_child(b)
		_buttons[id] = b

func _draw() -> void:
	if not visible:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.06, 0.88), true)
	# 연결선
	for n in NODES:
		if not is_visible_node(n):
			continue
		var from := _center()
		var pid: String = n.get("parent", "")
		if pid != "":
			for p in NODES:
				if p["id"] == pid:
					from = _center() + p["pos"]
					break
		var to: Vector2 = _center() + n["pos"]
		var col := Color(0.5, 0.45, 0.25, 0.7) if node_level(n) > 0 else Color(0.3, 0.3, 0.4, 0.6)
		draw_line(from, to, col, 1.5)

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

# ---------------------------------------------------------------- 입력 (드래그 팬)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_pan += event.relative
		_pan = _pan.clamp(Vector2(-420, -220), Vector2(300, 220))
		_reposition()
		accept_event()

func _reposition() -> void:
	# 팬 이동 — 버튼 재배치 (재생성 없이)
	for n in NODES:
		if _buttons.has(n["id"]):
			var b: Button = _buttons[n["id"]]
			if is_instance_valid(b):
				b.position = _center() + n["pos"] - b.custom_minimum_size / 2.0
	for c in _canvas.get_children():
		if c is PanelContainer:
			c.position = _center() - Vector2(24, 12)
	queue_redraw()

# ---------------------------------------------------------------- 구매

func buy_node(id: String) -> bool:
	var n: Dictionary = {}
	for nd in NODES:
		if nd["id"] == id:
			n = nd
			break
	if n.is_empty():
		return false
	var lv := node_level(n)
	if lv >= int(n["levels"]) or not reveal_met(n) and not Game.tree_revealed.get(id, false):
		return false
	var cost := node_cost(n)
	if not Game.try_spend(cost):
		Sfx.play("deny")
		return false
	Sfx.play("buy")
	if main != null:
		main.tree_effect(n["effect"])
	# 클러스터 완성 보너스
	if node_level(n) >= int(n["levels"]) and int(n["levels"]) > 1:
		Sfx.play("fanfare")
		if main != null:
			main.hud.event("「%s」 계획 완성! 마을이 조금 더 살아났다." % n["name"], 3.0)
	Game.save_game()
	if visible:
		_refresh()
	return true
