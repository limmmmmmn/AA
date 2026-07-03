extends Node2D
## v3.0 메인 오케스트레이터 — "A whole JRPG. One screen."
## 한 화면 고정 (640×360, 카메라 없음): 마을(좌⅓) + 필드(우⅔) + 최심부 지배자.
## 모든 해금은 세계의 변화로만 표현된다. 해금 전용 UI는 존재하지 않는다.

const ROOM := Vector2(640, 360)
const VILLAGE_W := 216.0          # 마을 = 좌 약 ⅓ (팔레트에 물들지 않는다)
const WIN_L := Vector2(150, 84)
const WIN_S := Vector2(126, 72)

const BOSS_TEX := [
	"res://assets/enemies/slime_fly.png",
	"res://assets/enemies/bat.png",
	"res://assets/enemies/slime_chaser.png",
	"res://assets/enemies/slime_fly.png",
	"res://assets/enemies/bat.png",
]
const BUILD_POS := {
	"inn": Vector2(44, 92), "church": Vector2(172, 92),
	"smith": Vector2(44, 198), "shop": Vector2(172, 198),
	"casino": Vector2(108, 300), "bard": Vector2(196, 148),
	"medalking": Vector2(20, 148), "board": Vector2(142, 132),
}
const POT_SPOTS := [
	Vector2(84, 168), Vector2(132, 168), Vector2(84, 248), Vector2(132, 248),
	Vector2(60, 120), Vector2(160, 120), Vector2(60, 280), Vector2(160, 280),
]

## 주민 = 시설의 화신. 영입 조건 = 해금 문법 6종 중 하나 (v3.0 §B-2~B-3)
## cond: {"kill": id, "n": N} 자동 / {"boss": f} 자동 / {"medal": N} 자동 / {"gold": N, "lv": N} 촌장 부탁에서 지불
const RESIDENTS := [
	{"id": "innkeep",  "name": "여관 주인", "building": "inn",       "cond": {"kill": "slime", "n": 5},
		"ask": "슬라임이 무서워 길을 못 떠나요. 5마리만…", "join": "여관 주인이 마을에 정착했다!"},
	{"id": "smithy",   "name": "대장장이", "building": "smith",     "cond": {"gold": 250, "lv": 3},
		"ask": "화덕 지을 돈이 필요하오. (Lv 3부터)", "join": "대장장이가 화덕에 불을 붙였다!"},
	{"id": "father",   "name": "신부",     "building": "church",    "cond": {"kill": "bat", "n": 6},
		"ask": "박쥐 떼가 성물을 노립니다. 6마리를…", "join": "신부가 제단을 세웠다!"},
	{"id": "merchant", "name": "상인",     "building": "shop",      "cond": {"gold": 400},
		"ask": "밑천만 있으면 뭐든 팔아 보이죠.", "join": "상인이 좌판을 폈다!"},
	{"id": "bard_r",   "name": "음유시인", "building": "bard",      "cond": {"boss": 0},
		"ask": "초원의 지배자가 사라지면 노래하러 오겠소.", "join": "음유시인이 광장에 앉았다!"},
	{"id": "medalist", "name": "메달왕",   "building": "medalking", "cond": {"medal": 3},
		"ask": "작은 메달을 3개 모은 자에게 가겠노라.", "join": "메달왕이 행차했다!"},
	{"id": "gambler",  "name": "도박사",   "building": "casino",    "cond": {"gold": 1500, "lv": 6},
		"ask": "판돈이 모이는 곳에 내가 있지. (Lv 6부터)", "join": "도박사가 천막을 쳤다!"},
]
const REVIVAL_STEPS := [3, 6]   # 주민 수 임계 → 마을 물리 확장

var base_root: Node2D        # 마을 (불변 영역)
var field_root: Node2D       # 필드 (우⅔ — 이정표로 통째 교체)
var party: Party
var hud: Hud

var last_field := 0
var base_nodes := {}
var boss_node: FieldMonster = null
var boss_fighting := false
var boss_field := 0
var windows: Array = []

var _monster_timer := 0.0
var _sparkle_timer := 5.0
var _golden_timer := 90.0
var _save_timer := 20.0
var _flag_timer := 1.0
var _hover_node: Node2D = null
var _wipe_lock := false
var _swapping := false
var _full_msg_cd := 0.0
var _chief_wiped := false

# ================================================================ setup

func _ready() -> void:
	base_root = Node2D.new()
	add_child(base_root)
	field_root = Node2D.new()
	add_child(field_root)

	_build_village()

	party = Party.new()
	party.init_at(Vector2(140, 220))
	party.bounds_min = Vector2(10, 26)
	party.bounds_max = Vector2(630, 348)
	party.bumped.connect(_on_bump)
	party.ai_query = Callable(self, "_ai_pick")
	add_child(party)

	_build_field(last_field)  # 파티 생성 후 (스폰 거리 체크가 파티를 본다)

	hud = Hud.new()
	hud.main = self
	add_child(hud)

	Game.party_wiped.connect(_on_wipe)
	Game.gold_changed.connect(func(v: int):
		if v > 0 and not Game.ui_unlocked["gold"]:
			hud.unlock_ui("gold"))

	for kind in Game.assistants.keys():
		for i in Game.assistants[kind]:
			spawn_assistant(kind)

	_golden_timer = 90.0 if not Game.golden_first_done else randf_range(150.0, 300.0)
	UILib.set_cursor("point")
	hud._update_top()
	_prologue()

	if OS.get_environment("AAA_SMOKE") == "1":
		var smoke: Node = load("res://scripts/dev_smoke.gd").new()
		smoke.set("main", self)
		add_child(smoke)

func _prologue() -> void:
	if Game.total_earned > 0 or Game.level > 1:
		return
	hud.toast("『일어나렴, 용사야.』", 3.0)
	get_tree().create_timer(3.4).timeout.connect(func():
		hud.toast("용사는 일어났다. 그러나, 너무 늦었다.", 3.6))
	get_tree().create_timer(7.6).timeout.connect(func():
		if not Game.ui_unlocked["desc"]:
			hud.toast("WASD — 촌장에게 가 보자. (Space)", 4.0))

# ================================================================ 마을 (좌⅓ — 주민 수가 곧 진행바)

func _build_village() -> void:
	for c in base_root.get_children():
		c.queue_free()
	base_nodes.erase("chief")
	var stage := _revival_stage()
	# 마을 바닥 — 부흥 단계에 따라 광장이 자란다
	_repeat_sprite(base_root, "res://assets/Tiles/Grass_Middle.png", Rect2(0, 0, VILLAGE_W, ROOM.y), Vector2.ZERO, Color(1, 1, 1))
	var plaza := Rect2(56, 116, 108, 160)
	if stage >= 1:
		plaza = Rect2(24, 72, 172, 236)
	if stage >= 2:
		plaza = Rect2(12, 48, 196, 276)
	_repeat_sprite(base_root, "res://assets/Tiles/Path_Middle.png", Rect2(0, 0, plaza.size.x, plaza.size.y), plaza.position, Color(1, 1, 1))
	if stage >= 2:
		# 성벽 (임시 도형)
		var wall := Line2D.new()
		wall.points = PackedVector2Array([Vector2(6, 40), Vector2(6, 340), Vector2(210, 340)])
		wall.width = 3.0
		wall.default_color = Color("6a5a40")
		base_root.add_child(wall)
	for p in [Vector2(28, 40), Vector2(190, 320)]:
		_decor(base_root, "res://assets/objects/forest.png", p, Color(1, 1, 1))
	# 시작 멤버: 촌장 + 항아리 둘 + "보이는데 못 여는 것" (잠긴 창고·붉은 상자)
	base_nodes["chief"] = _add_thing(base_root, "chief", Vector2(100, 148))
	_add_thing(base_root, "warehouse", Vector2(40, 48))
	_add_thing(base_root, "redchest", Vector2(186, 48))
	var pot_n: int = mini(2 + Game.extra_pots * 2, POT_SPOTS.size())
	for i in pot_n:
		_add_thing(base_root, "pot", POT_SPOTS[i])
	if stage >= 2:
		_add_thing(base_root, "fountain", Vector2(108, 74))
	# 영입된 주민들의 시설 + 주민 본인
	for r in RESIDENTS:
		if Game.residents.get(r["id"], false):
			_place_resident(r, false)
	if Game.buildings.get("board", false):
		base_nodes["board"] = _add_thing(base_root, "board", BUILD_POS["board"])
	if Game.buildings.get("chest", false):
		_add_thing(base_root, "chest", Vector2(160, 300))

func _place_resident(r: Dictionary, pop: bool) -> void:
	var b: String = r["building"]
	var node := _add_thing(base_root, b, BUILD_POS[b])
	base_nodes[b] = node
	if pop:
		node.spawn_pop()
	# 시설 옆에 서 있는 사람 — 마을에 서 있는 사람 수가 곧 진행바
	if b != "bard" and b != "medalking":  # NPC형 시설은 본인이 곧 시설
		var npc := _add_thing(base_root, "resident", BUILD_POS[b] + Vector2(24, 12))
		npc.resident_name = r["name"]

func _revival_stage() -> int:
	var n := Game.resident_count()
	var s := 0
	for t in REVIVAL_STEPS:
		if n >= t:
			s += 1
	return s

func _repeat_sprite(root: Node2D, tex_path: String, region: Rect2, pos: Vector2, tint: Color) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load(tex_path)
	s.centered = false
	s.region_enabled = true
	s.region_rect = region
	s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	s.position = pos
	s.modulate = tint
	root.add_child(s)
	return s

func _decor(root: Node2D, tex_path: String, pos: Vector2, tint: Color) -> void:
	var s := Sprite2D.new()
	s.texture = load(tex_path)
	s.offset = Vector2(0, -s.texture.get_height() / 2.0)
	s.position = pos
	s.modulate = tint
	root.add_child(s)

func _add_thing(root: Node2D, kind: String, pos: Vector2, recruit_cls: String = "") -> Interactable:
	var n := Interactable.new()
	n.setup(kind, recruit_cls)
	n.position = pos
	root.add_child(n)
	return n

# ================================================================ 필드 (우⅔ — 이정표로 내용물만 교체)

func _build_field(f: int) -> void:
	for c in field_root.get_children():
		c.queue_free()
	boss_node = null
	last_field = f
	var tint: Color = Game.FIELD_TINTS[f]
	_repeat_sprite(field_root, "res://assets/Tiles/Grass_Middle.png", Rect2(0, 0, ROOM.x - VILLAGE_W, ROOM.y), Vector2(VILLAGE_W, 0), tint)
	var decor_tex := "res://assets/objects/forest.png" if f <= 1 else "res://assets/objects/hill.png"
	var decor_n := 10 if f == 1 else 5
	if f == 4:
		decor_tex = "res://assets/objects/tower.png"
		decor_n = 4
	for i in decor_n:
		_decor(field_root, decor_tex, Vector2(randf_range(260, 560), randf_range(48, 316)), tint)
	# 행선지 이정표 — 첫 지배자를 쓰러뜨리면 나타난다
	if Game.signpost_seen:
		base_nodes["signpost"] = _add_thing(field_root, "signpost", Vector2(228, 190))
	_spawn_boss(f)
	for i in 7:
		_spawn_monster(f)
	if f == 1:
		for i in 3:
			_spawn_sparkle()

func swap_field(f: int) -> void:
	# 필드 스왑 — 우⅔만 페이드 교체. 마을은 그대로
	if _swapping or boss_fighting or f == last_field:
		return
	_swapping = true
	Sfx.play("warp")
	var tw := create_tween()
	tw.tween_property(field_root, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func():
		_build_field(f)
		if party.head_pos.x > VILLAGE_W + 4.0:
			party.teleport(Vector2(VILLAGE_W - 20, party.head_pos.y))
		hud._update_top())
	tw.tween_property(field_root, "modulate:a", 1.0, 0.25)
	tw.tween_callback(func(): _swapping = false)

func select_field(f: int) -> void:
	swap_field(f)

func world_to_screen(p: Vector2) -> Vector2:
	return p  # 카메라 없음 — 월드 = 스크린

# ================================================================ loop

func _process(delta: float) -> void:
	_full_msg_cd = maxf(0.0, _full_msg_cd - delta)
	_update_hover()
	if _wipe_lock:
		return

	_monster_timer -= delta
	if _monster_timer <= 0.0:
		_monster_timer = 0.9
		var pop := 0
		for m in get_tree().get_nodes_in_group("monster"):
			if is_instance_valid(m) and not m.is_boss:
				pop += 1
		var target: int = 7 + (last_field + 1) * 2 + (4 if last_field == 2 else 0)
		if pop < target:
			_spawn_monster(last_field)
	_sparkle_timer -= delta
	if _sparkle_timer <= 0.0:
		_sparkle_timer = 4.0 if last_field == 1 else 10.0
		var count := 0
		for n in get_tree().get_nodes_in_group("hoverable"):
			if n is Interactable and n.kind == "sparkle":
				count += 1
		if count < 5:
			_spawn_sparkle()

	_golden_timer -= delta * (2.0 if last_field == 3 else 1.0)
	if _golden_timer <= 0.0:
		_try_spawn_golden()

	_flag_timer -= delta
	if _flag_timer <= 0.0:
		_flag_timer = 1.0
		_check_residents_auto()
		_check_recruits()
		_update_chief_alert()

	_save_timer -= delta
	if _save_timer <= 0.0:
		_save_timer = 20.0
		Game.save_game()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Game.save_game()

# ================================================================ input (몸=Space / 시선=클릭)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				hud.close_menu()
			KEY_SPACE:
				_space_interact()
			KEY_F11:
				var mode := DisplayServer.window_get_mode()
				if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				else:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_gaze_click(get_global_mouse_position())

func _space_interact() -> void:
	if _wipe_lock:
		return
	if hud.is_menu_open():
		hud.close_menu()
		return
	party.manual_hold = 4.0
	var best: Node2D = null
	var best_d := 1e9
	for n in get_tree().get_nodes_in_group("hoverable"):
		if not is_instance_valid(n) or not n.is_visible_in_tree():
			continue
		var d: float = party.head_pos.distance_to(n.global_position)
		if d < n.pick_radius() + 10.0 and d < best_d:
			best_d = d
			best = n
	if best != null:
		_on_bump(best)
	else:
		Sfx.play("bump", 0.8)

func _gaze_click(pos: Vector2) -> void:
	# 시선(클릭) — 파티 위치와 무관: 대장간 불·카지노 (한 화면이라 도크가 필요 없다)
	if _wipe_lock or hud.is_menu_open():
		return
	var node := _pick_at(pos)
	if node == null or not (node is Interactable):
		return
	var it := node as Interactable
	match it.kind:
		"smith":
			if it.is_ready:
				Sfx.play("click")
				hud.open_smith()
			else:
				hud.event("화덕이 아직 식어 있다…")
		"casino":
			Sfx.play("click")
			hud.open_casino()

# ================================================================ hover (시선) + 말풍선

func _update_hover() -> void:
	if _wipe_lock:
		UILib.set_cursor("point")
		hud.hide_bubble()
		return
	var ctrl := get_viewport().gui_get_hovered_control()
	if ctrl != null:
		var bw := _find_battle_window(ctrl)
		if bw != null:
			UILib.set_cursor("hand" if bw.is_golden_hovering() else "eye")
			if bw.is_golden_hovering():
				hud.set_hover("쓰다듬어 주기를 바라는 것 같다.")
			else:
				hud.set_hover("당신이 지켜보고 있다. 일행이 힘을 낸다!")
		elif ctrl is ForgeGame:
			UILib.set_cursor("hand")
			hud.set_hover("리듬에 맞춰… 지금이다!")
		else:
			UILib.set_cursor("point")
			hud.set_hover(hud.menu_hover)
		_set_hover_node(null)
		hud.hide_bubble()
		return
	var node := _pick_at(get_global_mouse_position())
	_set_hover_node(node)
	if node != null:
		UILib.set_cursor("hand" if _is_gaze_target(node) else "point")
		var key: String = node.kind_key()
		var text := "?????"
		if Game.discovered.get(key, false):
			text = node.flavor()
		hud.set_hover(text)
		hud.show_bubble(text, node.global_position + Vector2(0, -26))
	else:
		UILib.set_cursor("point")
		hud.set_hover("")
		hud.hide_bubble()

func _is_gaze_target(n: Node2D) -> bool:
	return n is Interactable and ((n.kind == "smith" and n.is_ready) or n.kind == "casino")

func _pick_at(pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := 1e9
	for n in get_tree().get_nodes_in_group("hoverable"):
		if not is_instance_valid(n) or not n.is_visible_in_tree():
			continue
		var d: float = pos.distance_to(n.global_position)
		var r: float = n.pick_radius() + 5.0
		if d < r and d < best_d:
			best_d = d
			best = n
	return best

func _find_battle_window(ctrl: Control) -> BattleWindow:
	var c: Node = ctrl
	while c != null:
		if c is BattleWindow:
			return c
		c = c.get_parent()
	return null

func _set_hover_node(node: Node2D) -> void:
	if node == _hover_node:
		return
	if _hover_node != null and is_instance_valid(_hover_node):
		_hover_node.scale = Vector2.ONE
	_hover_node = node
	if _hover_node != null:
		_hover_node.scale = Vector2(1.07, 1.07)

# ================================================================ bump (몸)

func _on_bump(node: Node2D) -> void:
	if _wipe_lock or not is_instance_valid(node):
		return
	if node is FieldMonster:
		_bump_monster(node)
		return
	var it := node as Interactable
	if it == null:
		return
	Game.discovered[it.kind_key()] = true
	match it.kind:
		"pot":
			_bump_pot(it)
		"chest":
			_bump_chest(it)
		"sparkle":
			_bump_sparkle(it)
		"inn":
			Sfx.play("bump")
			hud.open_inn()
		"church":
			Sfx.play("bump")
			hud.open_church()
		"shop":
			Sfx.play("bump")
			hud.open_shop_menu()
		"smith":
			if not it.is_ready:
				hud.event("화덕이 아직 식어 있다… 조금 기다리자.")
				return
			Sfx.play("bump")
			hud.open_smith()
		"board":
			Sfx.play("bump")
			hud.open_board()
		"casino":
			Sfx.play("bump")
			hud.open_casino()
		"bard":
			Sfx.play("bump")
			hud.open_bard()
		"medalking":
			Sfx.play("bump")
			hud.open_medalking()
		"chief":
			_bump_chief()
		"signpost":
			Sfx.play("bump")
			hud.open_gate()
		"warehouse":
			_bump_warehouse(it)
		"redchest":
			_bump_redchest(it)
		"fountain":
			hud.event("분수다. 물소리가 마을을 채운다.")
		"resident":
			Sfx.play("bump")
			hud.event("%s: 「좋은 마을이 되어 가는군요.」" % it.resident_name)
		"recruit":
			_bump_recruit(it)

func _bump_chief() -> void:
	Sfx.play("bump")
	# 공개 스케줄 1: 첫 대화 = 설명창의 탄생
	if not Game.ui_unlocked["desc"]:
		hud.unlock_ui("desc")
		hud.event("촌장: 「마왕은 이미 세계를 손에 넣었습니다. …그래도, 하시겠습니까?」", 6.0)
		return
	if _chief_wiped:
		_chief_wiped = false
		hud.event("촌장: 「…괜찮습니다. 다들 그렇게 시작합니다.」", 4.0)
		return
	# 공개 스케줄 2: 골드 50 → 부탁(주민 영입)이 열린다
	if not Game.ui_unlocked["quest"]:
		if Game.gold >= 50:
			hud.unlock_ui("quest")
			Sfx.play("fanfare_big")
			hud.event("촌장: 「마을을 되살려 주십시오. …사람이 필요합니다.」", 5.0)
			hud.open_chief()
		else:
			hud.event("촌장: 「골드를 조금 모아 오시면… 부탁드릴 일이 있습니다.」", 4.0)
		return
	hud.open_chief()

func _update_chief_alert() -> void:
	if base_nodes.has("chief") and is_instance_valid(base_nodes["chief"]):
		base_nodes["chief"].show_alert = (not Game.ui_unlocked["desc"]) \
			or (not Game.ui_unlocked["quest"] and Game.gold >= 50)

func _bump_warehouse(it: Interactable) -> void:
	if Game.opened["warehouse"]:
		hud.event("창고는 이제 텅 비었다.")
		return
	if Game.keys["thief"]:
		Game.opened["warehouse"] = true
		Sfx.play("chest")
		var g := int(300 * Game.gold_scale())
		Game.add_gold(g)
		Game.medals_small += 2
		hud.popup("+%d G" % g, it.global_position)
		hud.coin_burst(it.global_position, 5)
		hud.event("도둑의 열쇠로 창고를 열었다! 작은 메달 2개도 들어 있었다!", 4.5)
		it.queue_redraw()
		Game.save_game()
	else:
		Sfx.play("deny")
		hud.event("굳게 잠겨 있다. …도둑의 열쇠가 필요해 보인다.")

func _bump_redchest(it: Interactable) -> void:
	if Game.opened["redchest"]:
		hud.event("붉은 상자는 이미 열었다.")
		return
	if Game.keys["magic"]:
		Game.opened["redchest"] = true
		Sfx.play("fanfare_big")
		var g := int(1000 * Game.gold_scale())
		Game.add_gold(g)
		hud.coin_burst(it.global_position, 6)
		if Game.own_medal("sticky_gloves"):
			hud.event("붉은 상자에서 훈장 「끈끈이 장갑」 을 손에 넣었다!", 4.5)
		else:
			hud.event("붉은 상자에서 %d G를 손에 넣었다!" % g, 4.0)
		it.queue_redraw()
		Game.save_game()
	else:
		Sfx.play("deny")
		hud.event("붉게 빛나며 잠겨 있다. …마법의 열쇠가 필요해 보인다.")

func _bump_monster(m: FieldMonster) -> void:
	if m.is_boss:
		_start_boss_battle(m)
		return
	if _windows_full():
		m.bump_cd = 1.5
		if _full_msg_cd <= 0.0:
			_full_msg_cd = 1.2
			Sfx.play("deny")
			hud.event("전투창이 가득 찼다!")
		return
	Sfx.play("bump")
	var count := randi_range(1, Game.max_enemies_per_window())
	if last_field == 2:
		count = maxi(count, randi_range(1, Game.max_enemies_per_window()))
	elif last_field == 3:
		count = 1
	var defs: Array = []
	for i in count:
		defs.append(m.def)
	m.queue_free()
	_open_battle(defs, false)

func _bump_pot(it: Interactable) -> void:
	if not it.is_ready:
		return
	var cracked := Game.medal_on("cracked_pot")
	var g := maxi(1, int(randi_range(3, 8) * Game.gold_scale() * Game.gold_multiplier() * (0.5 if cracked else 1.0)))
	_gain_gold(g, it.global_position, "pot", 2)
	_maybe_drop_medal(it.global_position, 0.03)
	it.start_cooldown(12.5 if cracked else 25.0)

func _bump_chest(it: Interactable) -> void:
	if not it.is_ready:
		hud.event("텅 빈 상자다.")
		return
	it.start_cooldown(120.0)
	var teeth := Game.medal_on("mimic_teeth")
	var mimic_roll: bool = teeth or (Game.progress_tier() >= 2 and randf() < 0.18)
	if mimic_roll and not _windows_full():
		Sfx.play("boss")
		hud.event("보물상자가… 이빨을 드러냈다!", 3.0)
		var atlas := AtlasTexture.new()
		atlas.atlas = load("res://assets/objects/chest_1.png")
		atlas.region = Rect2(16, 0, 16, 18)
		var t := Game.progress_tier()
		var def := {
			"id": "mimic", "name": "미믹",
			"hp": int(24 * Game.tier_stat(t)), "atk": int(6 * Game.tier_atk(t)),
			"gold": int(130 * Game.tier_gold(t) * (3.0 if teeth else 1.0)),
			"exp": int(25 * Game.tier_exp(t)),
			"tex": atlas, "scale": 1.0, "tint": Color(1, 0.85, 0.85),
		}
		_open_battle([def], false)
		return
	var g := maxi(1, int(40 * Game.gold_scale() * Game.gold_multiplier()))
	_gain_gold(g, it.global_position, "chest", 4)
	_maybe_drop_medal(it.global_position, 0.15)

func _bump_sparkle(it: Interactable) -> void:
	if Game.up["shovel"] == 0:
		hud.event("뭔가 묻혀 있는 것 같다… (삽이 필요하다)")
		return
	_dig_sparkle(it)

func _dig_sparkle(it: Interactable) -> void:
	var g := maxi(1, int(randi_range(8, 20) * Game.gold_scale() * Game.gold_multiplier()))
	_gain_gold(g, it.global_position, "dig", 2)
	_maybe_drop_medal(it.global_position, 0.10)
	it.queue_free()

func _gain_gold(g: int, world_pos: Vector2, sfx_name: String, coins_n: int) -> void:
	Game.add_gold(g)
	Sfx.play(sfx_name, randf_range(0.9, 1.1))
	hud.popup("+%d G" % g, world_pos)
	hud.coin_burst(world_pos, coins_n)

func _maybe_drop_medal(world_pos: Vector2, chance: float) -> void:
	# 작은 메달 — 골드로 못 사는 수집품. 메달왕이 기다린다 (해금 문법 ⑥)
	if randf() < chance:
		Game.medals_small += 1
		Sfx.play("golden", 1.3)
		hud.popup("작은 메달!", world_pos + Vector2(0, -12), UILib.COL_GOLD)

func _bump_recruit(it: Interactable) -> void:
	var cls := it.recruit_cls
	Game.recruit(cls)
	Sfx.play("fanfare_big")
	hud.event("%s이(가) 일행에 합류했다!" % Game.CLASS_DEFS[cls]["name"], 3.5)
	it.queue_free()
	Game.save_game()

# ================================================================ 주민 영입 (해금 문법의 심장)

func resident_cond_text(r: Dictionary) -> String:
	var c: Dictionary = r["cond"]
	if c.has("kill"):
		var base_name := ""
		for md in Game.MONSTER_DEFS:
			if md["id"] == c["kill"]:
				base_name = md["name"]
		var have: int = Game.kill_counts.get(c["kill"], 0)
		return "%s %d/%d마리" % [base_name, mini(have, c["n"]), c["n"]]
	if c.has("boss"):
		return "%s 처치" % Game.BOSS_NAMES[c["boss"]]
	if c.has("medal"):
		return "작은 메달 %d/%d" % [mini(Game.medals_small, c["medal"]), c["medal"]]
	if c.has("gold"):
		var t := "%d G" % c["gold"]
		if c.has("lv"):
			t += " (Lv %d)" % c["lv"]
		return t
	return "?"

func resident_cond_auto_met(r: Dictionary) -> bool:
	var c: Dictionary = r["cond"]
	if c.has("kill"):
		return int(Game.kill_counts.get(c["kill"], 0)) >= int(c["n"])
	if c.has("boss"):
		return Game.bosses_defeated[c["boss"]]
	if c.has("medal"):
		return Game.medals_small >= int(c["medal"])
	return false  # gold형은 촌장 부탁 메뉴에서 지불

func candidate_residents() -> Array:
	# 촌장 부탁 메뉴의 후보 2~3명 — 어느 부탁부터 해결하느냐가 곧 선택
	var out: Array = []
	for r in RESIDENTS:
		if not Game.residents.get(r["id"], false):
			out.append(r)
			if out.size() >= 3:
				break
	return out

func _check_residents_auto() -> void:
	if not Game.ui_unlocked["quest"] or _wipe_lock:
		return
	for r in candidate_residents():
		if resident_cond_auto_met(r):
			join_resident(r)
			return  # 해금 하나당 새 개념 하나 — 동시 두 개 금지

func try_pay_resident(id: String) -> bool:
	for r in RESIDENTS:
		if r["id"] != id or Game.residents.get(id, false):
			continue
		var c: Dictionary = r["cond"]
		if not c.has("gold"):
			return false
		if c.has("lv") and Game.level < int(c["lv"]):
			Sfx.play("deny")
			hud.event("아직 이르다. (Lv %d 필요)" % c["lv"])
			return false
		if not Game.try_spend(int(c["gold"])):
			Sfx.play("deny")
			return false
		join_resident(r)
		return true
	return false

func join_resident(r: Dictionary) -> void:
	# 조건이 뭐든 결과는 하나 — 사람이 마을에 걸어 들어온다
	Game.residents[r["id"]] = true
	Game.buildings[r["building"]] = true
	var walker := Sprite2D.new()
	walker.texture = load("res://assets/NPCs/village_chief.png")
	walker.modulate = Color(randf_range(0.7, 1.0), randf_range(0.7, 1.0), randf_range(0.7, 1.0))
	walker.position = Vector2(108, 352)
	walker.offset = Vector2(0, -13)
	base_root.add_child(walker)
	hud.event("누군가 마을로 걸어 들어온다…", 2.5)
	var tw := create_tween()
	tw.tween_property(walker, "position", BUILD_POS[r["building"]], 2.2)
	tw.tween_callback(func():
		walker.queue_free()
		_place_resident(r, true)
		Sfx.play("build")
		hud.event(r["join"], 4.0)
		_check_revival()
		Game.save_game())

func _check_revival() -> void:
	# 주민 수 임계점 → 마을이 물리적으로 확장된다
	var n := Game.resident_count()
	if n in REVIVAL_STEPS:
		Sfx.play("palette")
		get_tree().create_timer(1.2).timeout.connect(func():
			_build_village()
			Sfx.play("fanfare_big")
			if n == REVIVAL_STEPS[0]:
				hud.event("마을이 살아나기 시작했다! 광장이 넓어졌다.", 5.0)
			else:
				hud.event("마을에 분수가 솟았다! 성벽도 올라간다.", 5.0))

# ================================================================ 전투창 (도킹)

func _windows_full() -> bool:
	var n := 0
	for w in windows:
		if is_instance_valid(w) and not w.closing and not w.is_boss:
			n += 1
	return n >= Game.max_windows()

func _open_battle(defs: Array, boss: bool) -> void:
	var sim := BattleSim.new()
	sim.setup(defs, boss)
	var w := BattleWindow.new()
	if boss:
		w.setup(sim, Vector2(224, 128), true)
		w.position = Vector2(208, 56)
		party.frozen = true
		boss_fighting = true
		boss_field = last_field
	else:
		w.setup(sim, WIN_L, false)
		w.position = Vector2(8 + windows.size() * 158, 40)
	hud.windows_root.add_child(w)
	windows.append(w)
	w.tree_exiting.connect(_on_window_gone.bind(w))
	sim.victory.connect(_on_victory.bind(w, boss))
	sim.member_hit.connect(_on_member_hit_fx.bind(w))
	sim.golden_captured.connect(_on_golden_captured.bind(w))
	_relayout_windows()
	# 공개 스케줄 3: 첫 전투창 → 파티 스테이터스 창의 탄생
	if not Game.ui_unlocked["party"]:
		hud.unlock_ui("party")

func _relayout_windows() -> void:
	var docked: Array = []
	for w in windows:
		if is_instance_valid(w) and not w.is_boss and not w.closing:
			docked.append(w)
	var n := docked.size()
	var big: bool = n <= 4
	var sz := WIN_L if big else WIN_S
	for i in n:
		var pos: Vector2
		if big:
			pos = Vector2(8 + i * 158, 40)
		else:
			pos = Vector2(8 + (i % 4) * 134, 40 + int(i / 4.0) * 80)
		docked[i].apply_dock(pos, sz)

func _on_window_gone(w: BattleWindow) -> void:
	windows.erase(w)
	_relayout_windows()

func _on_victory(gold_reward: int, exp_reward: int, w: BattleWindow, boss: bool) -> void:
	Game.add_gold(gold_reward)
	if is_instance_valid(w):
		hud.coin_burst(w.position + w.size / 2.0, clampi(2 + gold_reward / 25, 2, 7))
		w.close_after(1.1)
	if Game.add_exp(exp_reward):
		Sfx.play("levelup")
		hud.event("일행은 레벨 %d이(가) 되었다!" % Game.level, 3.0)
	if boss:
		boss_fighting = false
		party.frozen = false
		_on_boss_defeated(boss_field)

func _on_member_hit_fx(idx: int, dmg: int, _fell: bool, w: BattleWindow) -> void:
	if is_instance_valid(w):
		hud.fly_damage(w.position + Vector2(randf_range(20, w.size.x - 20), w.size.y - 30), idx, dmg)

func _on_golden_captured(reward: int, w: BattleWindow) -> void:
	Game.add_gold(reward)
	Sfx.play("gold_big")
	if is_instance_valid(w):
		hud.coin_burst(w.position + w.size / 2.0, 8)
	hud.event("황금 슬라임을 붙잡았다! +%d G!" % reward, 3.5)

func _close_all_windows() -> void:
	for w in windows.duplicate():
		if is_instance_valid(w):
			w.close_after(0.0)

func _try_spawn_golden() -> void:
	var incense := Game.medal_on("slime_incense")
	var candidates: Array = []
	for w in windows:
		if is_instance_valid(w) and not w.closing and not w.is_boss and w.sim != null \
				and not w.sim.finished and not w.sim.golden_active:
			if incense and not w.sim.hovered:
				continue
			candidates.append(w)
	if candidates.is_empty():
		_golden_timer = 12.0 if not incense else 6.0
		return
	var w: BattleWindow = candidates[randi() % candidates.size()]
	var dur := 16.0 if not Game.golden_first_done else 8.0
	if Game.medal_on("metal_crown"):
		dur *= 0.6
	if Game.medal_on("sticky_gloves"):
		dur += 2.0
	w.sim.spawn_golden(dur)
	Game.golden_first_done = true
	var interval := randf_range(150.0, 300.0) * (0.5 if Game.golden_info else 1.0)
	if Game.medal_on("metal_crown"):
		interval *= 0.4
	_golden_timer = interval

# ================================================================ 몬스터 스폰 (필드 좌→우 = 위험도)

func _field_def(field: int, mtier: int, x: float) -> Dictionary:
	var base: Dictionary = Game.MONSTER_DEFS[mtier]
	var t := field + 1
	var xf := 0.75 + ((x - VILLAGE_W) / (ROOM.x - VILLAGE_W)) * 0.6
	var elite: bool = field == 3
	return {
		"id": base["id"],
		"name": Game.FIELD_PREFIX[field] + String(base["name"]),
		"hp": int(base["hp"] * Game.tier_stat(t) * xf * (1.6 if elite else 1.0)),
		"atk": int(maxf(1.0, base["atk"] * Game.tier_atk(t) * xf * (1.3 if elite else 1.0))),
		"gold": int(base["gold"] * Game.tier_gold(t) * xf * (1.8 if elite else 1.0) * (1.0 + 0.4 * int(field == 2))),
		"exp": int(maxf(1.0, base["exp"] * Game.tier_exp(t) * xf)),
		"tex": base["tex"], "scale": 1.0,
		"tint": Game.FIELD_TINTS[field],
	}

func _spawn_monster(f: int) -> void:
	var pos := Vector2(randf_range(250, 570), randf_range(44, 320))
	if pos.distance_to(party.head_pos) < 80.0:
		return
	var unlocked: int = Game.posters_f[f] if f < 4 else 3
	var frac := (pos.x - VILLAGE_W) / (ROOM.x - VILLAGE_W)
	var max_tier: int = clampi(int(frac * (unlocked + 1.6)), 0, unlocked)
	var mtier := randi_range(0, max_tier)
	var m := FieldMonster.new()
	m.setup(_field_def(f, mtier, pos.x), f + 1)
	m.position = pos
	field_root.add_child(m)

func _spawn_sparkle() -> void:
	var sp := _add_thing(field_root, "sparkle", Vector2(randf_range(250, 590), randf_range(48, 320)))
	sp.passive = true

# ================================================================ 지배자 (최심부 — 결계 속 실루엣)

func _spawn_boss(f: int) -> void:
	if Game.bosses_defeated[f]:
		boss_node = null
		return
	var t := f + 1
	var def := {
		"id": "boss", "name": Game.BOSS_NAMES[f],
		"hp": int(300 * Game.tier_stat(t)),
		"atk": int(12 * Game.tier_atk(t)),
		"gold": int(500 * Game.tier_gold(t)),
		"exp": int(80 * Game.tier_exp(t)),
		"tex": BOSS_TEX[f], "scale": 1.0,
		"tint": Color(0.55, 0.35, 0.75) if f >= 4 else Color(1.1, 0.65, 0.65),
	}
	boss_node = FieldMonster.new()
	boss_node.setup(def, t, true, Game.BOSS_NAMES[f])
	boss_node.asleep = f < 4 and Game.posters_f[f] < 3
	boss_node.position = Vector2(608, 185)
	field_root.add_child(boss_node)

func on_posters_complete(field: int) -> void:
	Sfx.play("boss")
	if last_field == field and boss_node != null and is_instance_valid(boss_node) and boss_node.asleep:
		boss_node.wake_up()
		hud.event("결계가 깨졌다. 최심부에서 지배자가 깨어난다…", 4.0)
	else:
		hud.event("%s의 지배자가 깨어났다는 소문이다…" % Game.FIELD_NAMES[field], 4.0)

func _start_boss_battle(m: FieldMonster) -> void:
	if boss_fighting:
		return
	if m.asleep:
		hud.event("결계가 지배자를 지키고 있다. 수배서를 모으자.", 3.5)
		m.bump_cd = 2.0
		return
	if last_field >= 4 and not Game.epic_complete():
		Sfx.play("deny")
		hud.event("마왕 앞에 보이지 않는 벽이 있다. …이야기의 끝을 알아야 한다. (음유시인)", 4.5)
		m.bump_cd = 3.0
		return
	m.visible = false
	m.bump_cd = 9999.0
	Sfx.play("boss")
	hud.event("%s이(가) 나타났다! 모두가 지켜보는 결전이다!" % m.boss_name, 3.0)
	_open_battle([m.def], true)

func _on_boss_defeated(field: int) -> void:
	Game.bosses_defeated[field] = true
	if boss_node != null and is_instance_valid(boss_node):
		boss_node.queue_free()
	boss_node = null
	if field >= 4:
		Sfx.play("fanfare_big")
		Game.save_game()
		hud.show_ending(_do_prestige, _do_continue)
		return
	var medal_by_field := ["coward_flag", "aqua_regia", "ghost_warcry", "spirit_party"]
	var mid: String = medal_by_field[clampi(field, 0, 3)]
	if Game.own_medal(mid):
		Sfx.play("fanfare_big")
		hud.event("훈장 「%s」 을 손에 넣었다!" % Game.MEDAL_DEFS[mid]["name"], 4.5)
	# 드퀘 열쇠 — 보스가 쥐고 있다 (해금 문법 ⑤)
	if field == 0 and not Game.keys["thief"]:
		Game.keys["thief"] = true
		hud.event("「도둑의 열쇠」 를 손에 넣었다! 마을의 잠긴 창고가 떠오른다…", 5.0)
	elif field == 2 and not Game.keys["magic"]:
		Game.keys["magic"] = true
		hud.event("「마법의 열쇠」 를 손에 넣었다! 붉은 상자가 떠오른다…", 5.0)
	# 다음 땅으로 가는 길이 열린다 (열쇠 문법 — 보스가 곧 문)
	if field + 1 <= 4 and not Game.fields_unlocked[field + 1]:
		Game.unlock_field(field + 1)
		hud.event("%s(으)로 가는 길이 열렸다!" % Game.FIELD_NAMES[field + 1], 4.5)
	# 첫 지배자를 쓰러뜨리면 — 행선지 이정표가 나타난다
	if not Game.signpost_seen:
		Game.signpost_seen = true
		var sp := _add_thing(field_root, "signpost", Vector2(228, 190))
		sp.spawn_pop()
		base_nodes["signpost"] = sp
		hud.event("마을 앞에 행선지 이정표가 세워졌다! 다른 땅으로 갈 수 있다.", 5.0)
	Sfx.play("palette")
	hud.event("%s의 지배자가 쓰러졌다. 이 땅은 해방되었다!" % Game.FIELD_NAMES[field], 4.0)
	Game.save_game()

func _do_prestige() -> void:
	Game.do_prestige()
	get_tree().reload_current_scene()

func _do_continue() -> void:
	Game.ending_seen = true
	Game.save_game()
	hud.event("세계는 평화롭다. …일행은 계속 걷는다.", 4.0)

# ================================================================ 전멸

func _on_wipe() -> void:
	if _wipe_lock:
		return
	_wipe_lock = true
	party.frozen = true
	Sfx.play("wipe")
	_close_all_windows()
	if boss_fighting:
		boss_fighting = false
		if boss_node != null and is_instance_valid(boss_node):
			boss_node.visible = true
			boss_node.bump_cd = 3.0
	hud.fade_black("눈앞이 깜깜해졌다…", 1.4, func():
		var penalty := int(Game.gold * 0.25)
		if penalty > 0:
			Game.add_gold(-penalty)
			hud.popup("-%d G" % penalty, Vector2(320, 170), UILib.COL_RED)
		Game.revive_all()
		var spot: Vector2 = base_nodes["church"].position + Vector2(0, 22) if base_nodes.has("church") else Vector2(108, 200)
		party.teleport(spot)
		_chief_wiped = true
		party.frozen = false
		_wipe_lock = false
		Game.save_game())

# ================================================================ 커맨드 메뉴 효과 훅 (분산 업그레이드)

func up_effect(id: String) -> void:
	Game.up[id] += 1
	if id == "max_hp":
		Game.refresh_max_hp()
	Game.upgrades_changed.emit()
	Game.save_game()

func build_board() -> void:
	# 촌장 "건설" — 수배 게시판 (주민이 아니라 의식)
	Game.buildings["board"] = true
	var n := _add_thing(base_root, "board", BUILD_POS["board"])
	base_nodes["board"] = n
	n.spawn_pop()
	Sfx.play("build")
	hud.event("수배 게시판이 세워졌다! 위험한 놈들을 불러들일 수 있다.", 4.0)
	Game.save_game()

func add_pots() -> void:
	Game.extra_pots += 1
	var idx: int = 2 + (Game.extra_pots - 1) * 2
	for i in range(idx, mini(idx + 2, POT_SPOTS.size())):
		var p := _add_thing(base_root, "pot", POT_SPOTS[i])
		p.spawn_pop()
	hud.event("광장에 항아리가 늘었다! 깨뜨리고 싶다.")
	Game.save_game()

# ================================================================ 동료 (전투 축 — 주민과 별개)

func _check_recruits() -> void:
	var plan := [["warrior", 60, Vector2(70, 172)], ["mage", 350, Vector2(150, 172)], ["priest", 1000, Vector2(110, 120)]]
	for p in plan:
		var cls: String = p[0]
		if Game.total_earned >= int(p[1]) and not Game.recruits_spawned[cls] and not Game.has_member(cls):
			Game.recruits_spawned[cls] = true
			hud.event("누군가 마을로 걸어온다…", 3.0)
			var n := _add_thing(base_root, "recruit", Vector2(108, 352), cls)
			var tw := create_tween()
			tw.tween_property(n, "position", p[2], 3.0)
			Game.save_game()
			return

# ================================================================ 조수

func spawn_assistant(kind: String) -> void:
	var a := Assistant.new()
	var home := Vector2(108, 220)
	if kind == "keeper":
		home = Vector2(160, 290)
	elif kind == "pig":
		home = Vector2(320, 200)
	a.setup(kind, self, home)
	a.position = Vector2(108, 350)
	base_root.add_child(a)

func assistant_collect(node: Node2D) -> void:
	var it := node as Interactable
	if it == null or not is_instance_valid(it) or not it.is_ready:
		return
	Game.discovered[it.kind_key()] = true
	match it.kind:
		"pot":
			_bump_pot(it)
		"chest":
			_bump_chest(it)
		"sparkle":
			_dig_sparkle(it)

func on_forged() -> void:
	if base_nodes.has("smith") and is_instance_valid(base_nodes["smith"]):
		base_nodes["smith"].start_cooldown(20.0)

func smith_ready() -> bool:
	return base_nodes.has("smith") and is_instance_valid(base_nodes["smith"]) and base_nodes["smith"].is_ready

# ================================================================ 자율 AI (용사의 직감)

func _ai_pick() -> Variant:
	if Game.up["intuition"] == 0:
		return null
	if Game.ghost_count() > 0 and base_nodes.has("church") and Game.gold >= Game.revive_cost():
		return base_nodes["church"]
	if Game.lowest_hp_ratio() < 0.35 and base_nodes.has("inn"):
		return base_nodes["inn"]
	if not _windows_full():
		var radius: float = 200.0 + Game.up["radius"] * 80.0
		var best: Node2D = null
		var best_d := 1e9
		for m in get_tree().get_nodes_in_group("monster"):
			if not is_instance_valid(m) or m.is_boss or not m.is_visible_in_tree():
				continue
			var d: float = party.head_pos.distance_to(m.global_position)
			if d < radius and d < best_d:
				best_d = d
				best = m
		if best != null:
			return best
	if Game.up["shovel"] > 0:
		for n in get_tree().get_nodes_in_group("hoverable"):
			if n is Interactable and n.kind == "sparkle" and n.is_visible_in_tree():
				return n
	return null
