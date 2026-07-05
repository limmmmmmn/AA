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
	"bank": Vector2(36, 254),
}

## 촌장 부탁 — 객원 동료 영입 (v3.1 §B-3. 주민 부탁과 같은 창구)
## req: 선행 조건 (building/up), gold+lv: 지불 게이트
const COMPANION_ASKS := [
	{"id": "hunter",   "gold": 300,  "lv": 0, "req_building": "board",
		"ask": "게시판의 수배서를 보고 온 사냥꾼이다. 장비값만 대 주면…"},
	{"id": "dancer",   "gold": 500,  "lv": 0, "req_building": "casino",
		"ask": "카지노 무대에 선 무희다. 전속 계약을 하자는데…"},
	{"id": "miner",    "gold": 700,  "lv": 0, "req_up": "shovel",
		"ask": "삽질 소리를 듣고 온 광부다. 곡괭이 값이 필요하다고."},
	{"id": "fisher_a", "gold": 900,  "lv": 4, "req_building": "",
		"ask": "어부 형제가 배를 잃었단다. 형제는 세트다. (Lv 4부터)"},
	{"id": "banker",   "gold": 2500, "lv": 8, "req_building": "",
		"ask": "돈 냄새를 맡고 온 은행원이다. 은행을 세워 달라는데… (Lv 8부터)"},
]
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
const REVIVAL_STEPS := [3, 7, 10, 15]   # v3.2 §D: 합류 인원(주민+동료, 용사 제외) 임계 → 마을 물리 확장

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
# v3.1
var _interest_timer := 30.0    # 은행 이자 틱
var _requiem_timer := 0.0      # 스님의 성불 — 유령 자동 부활
var _cave_voice_done := false  # 동굴 벽 목소리 (세션당 1회)
# v3.2
var _night_shade: ColorRect = null   # 필드 밤 장막
var _was_night := false              # 밤낮 경계 알림
var _fish_voice_done := false        # 수중 진입 연출 (세션당 1회)
var _polter_timer := 0.0             # 폴터가이스트 틱
# v3.3
var _title_mode := false             # 타이틀 = 별도 씬이 아니라 메인 씬의 상태 ("게임이 곧 메뉴")
var _title_layer: CanvasLayer = null
var _ending_playing := false         # 엔딩 시퀀스 중 (입력·스폰 잠금)

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

	# v3.3 §B: 부팅 → 타이틀 상태 (스모크/씬 리로드 후엔 바로 게임)
	if OS.get_environment("AAA_SMOKE") == "1" or Game.skip_title:
		Game.skip_title = false
		Game.need_intro = false
		_prologue()
	else:
		_enter_title()

	if OS.get_environment("AAA_SMOKE") == "1":
		var smoke: Node = load("res://scripts/dev_smoke.gd").new()
		smoke.set("main", self)
		add_child(smoke)

func _prologue() -> void:
	if Game.total_earned > 0 or Game.level > 1:
		if Game.hero_name == "":
			Game.hero_name = "늦잠꾸러기"  # 진행 중 세이브 안전망
		return
	# v3.2 §B-4: 게임 시작 = 이름 짓기. 그 다음에야 어머니가 깨운다
	if Game.hero_name == "" and OS.get_environment("AAA_SMOKE") != "1":
		party.frozen = true
		hud.show_name_input(func(n: String):
			Game.hero_name = n
			Game.save_game()
			party.frozen = false
			_prologue_lines())
	else:
		if Game.hero_name == "":
			Game.hero_name = "늦잠꾸러기"
		_prologue_lines()

func _prologue_lines() -> void:
	# v3.3 §E 확정 인트로: 검은 화면 엄마 → 페이드 인 집 앞 → "너무 늦었다" → 조작. 20초 이내
	hud.fade_black("엄마: 「일어나렴, %s.」" % Game.hn(), 1.8, func():
		party.teleport(Vector2(96, 100)))  # 용사의 집 앞 (프롤로그의 발원지)
	get_tree().create_timer(3.6).timeout.connect(func():
		hud.toast("%s은(는) 일어났다. 그러나, 너무 늦었다." % Game.hn(), 3.6))
	get_tree().create_timer(7.6).timeout.connect(func():
		if not Game.ui_unlocked["desc"]:
			hud.toast("WASD — 촌장에게 가 보자. (Space)", 4.0))

# ================================================================ 타이틀 (v3.3 §B — "게임이 곧 메뉴다")

func _enter_title() -> void:
	_title_mode = true
	party.frozen = true
	hud.title_hide(true)
	# 2회차 이후의 타이틀 배경 = 내 마을. 파티는 여관에서 잔다 (늦잠 개그 겸)
	if Game.buildings.get("inn", false):
		party.teleport(BUILD_POS["inn"] + Vector2(10, 26))
	else:
		party.teleport(Vector2(96, 100))
	_title_layer = CanvasLayer.new()
	_title_layer.layer = 20
	add_child(_title_layer)
	# 새벽빛 — 마을 위에 얇게 깔린다
	var dawn := ColorRect.new()
	dawn.color = Color(0.45, 0.4, 0.65, 0.28)
	dawn.set_anchors_preset(Control.PRESET_FULL_RECT)
	dawn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_layer.add_child(dawn)
	var glow := ColorRect.new()
	glow.color = Color(1.0, 0.75, 0.5, 0.10)
	glow.position = Vector2(0, 0)
	glow.size = Vector2(640, 120)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_layer.add_child(glow)
	# 로고 — 드퀘 폰트 그대로
	var logo := UILib.make_label("Appears! Appears! Appears!", 22, UILib.COL_GOLD)
	logo.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	logo.add_theme_constant_override("outline_size", 4)
	logo.position = Vector2(140, 96)
	_title_layer.add_child(logo)
	var sub := UILib.make_label("— A AAA Incremental JRPG —", UILib.FS, UILib.COL_WHITE)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	sub.add_theme_constant_override("outline_size", 3)
	sub.position = Vector2(248, 128)
	_title_layer.add_child(sub)
	var press := UILib.make_label("PRESS  SPACE", UILib.FS, UILib.COL_WHITE)
	press.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	press.add_theme_constant_override("outline_size", 3)
	press.position = Vector2(284, 252)
	press.name = "press"
	_title_layer.add_child(press)
	var tw := create_tween().set_loops()
	tw.tween_property(press, "modulate:a", 0.15, 0.7)
	tw.tween_property(press, "modulate:a", 1.0, 0.7)
	Sfx.title_bgm(true)
	if OS.get_environment("AAA_TITLE_SHOT") == "1":  # DEV: 타이틀 스크린샷 후 종료
		get_tree().create_timer(1.6).timeout.connect(func():
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://shot_title.png")
			print("[SHOT] shot_title.png")
			get_tree().quit())

func _title_space() -> void:
	if hud.is_menu_open():
		return
	Sfx.play("window")
	hud.title_hide(true)
	hud.open_title_menu()

func title_continue(slot: int) -> void:
	Sfx.title_bgm(false)
	Sfx.play("fanfare")
	Game.continue_game(slot)
	Game.skip_title = true
	get_tree().reload_current_scene()

func title_new(slot: int) -> void:
	Sfx.title_bgm(false)
	Game.new_game(slot)
	Game.skip_title = true
	Game.need_intro = true
	get_tree().reload_current_scene()

func return_to_title() -> void:
	Sfx.title_bgm(false)
	Game.skip_title = false
	get_tree().reload_current_scene()

# ================================================================ 마을 (좌⅓ — 주민 수가 곧 진행바)

func _build_village() -> void:
	for c in base_root.get_children():
		c.queue_free()
	base_nodes.erase("chief")
	var stage := _revival_stage()
	# 마을 바닥 — 부흥 단계에 따라 광장이 자란다 (v3.2: 4단계)
	_repeat_sprite(base_root, "res://assets/Tiles/Grass_Middle.png", Rect2(0, 0, VILLAGE_W, ROOM.y), Vector2.ZERO, Color(1, 1, 1))
	var plaza := Rect2(56, 116, 108, 160)
	if stage >= 1:
		plaza = Rect2(24, 72, 172, 236)
	if stage >= 2:
		plaza = Rect2(12, 48, 196, 276)
	_repeat_sprite(base_root, "res://assets/Tiles/Path_Middle.png", Rect2(0, 0, plaza.size.x, plaza.size.y), plaza.position, Color(1, 1, 1))
	if stage >= 3:
		# 성벽 일부 (임시 도형) — 4단계에 완성
		var wall := Line2D.new()
		wall.points = PackedVector2Array([Vector2(6, 40), Vector2(6, 340), Vector2(210, 340)]) if stage >= 4 \
			else PackedVector2Array([Vector2(6, 120), Vector2(6, 340)])
		wall.width = 3.0
		wall.default_color = Color("6a5a40")
		base_root.add_child(wall)
		if stage >= 4:
			var wall2 := Line2D.new()
			wall2.points = PackedVector2Array([Vector2(9, 43), Vector2(9, 337), Vector2(207, 337)])
			wall2.width = 1.0
			wall2.default_color = Color("8a7a58")
			base_root.add_child(wall2)
	for p in [Vector2(28, 320), Vector2(190, 320)]:
		_decor(base_root, "res://assets/objects/forest.png", p, Color(1, 1, 1))
	# 시작 멤버: 용사의 집+엄마 + 촌장 + 항아리 둘 + "보이는데 못 여는 것" (잠긴 창고·붉은 상자)
	base_nodes["home"] = _add_thing(base_root, "home", Vector2(76, 52))
	_add_thing(base_root, "mom", Vector2(102, 58))
	base_nodes["chief"] = _add_thing(base_root, "chief", Vector2(100, 148))
	_add_thing(base_root, "warehouse", Vector2(34, 48))
	_add_thing(base_root, "redchest", Vector2(186, 48))
	var pot_n: int = mini(2 + Game.extra_pots * 2, POT_SPOTS.size())
	for i in pot_n:
		_add_thing(base_root, "pot", POT_SPOTS[i])
	if stage >= 2:
		_add_thing(base_root, "fountain", Vector2(108, 84))
		_add_thing(base_root, "well", Vector2(160, 96))  # 우물 (v3.2 §B-9)
	# 영입된 주민들의 시설 + 주민 본인
	for r in RESIDENTS:
		if Game.residents.get(r["id"], false):
			_place_resident(r, false)
	if Game.buildings.get("board", false):
		base_nodes["board"] = _add_thing(base_root, "board", BUILD_POS["board"])
	if Game.buildings.get("chest", false):
		_add_thing(base_root, "chest", Vector2(160, 300))
	if Game.buildings.get("bank", false):
		base_nodes["bank"] = _add_thing(base_root, "bank", BUILD_POS["bank"])
		_add_thing(base_root, "frogstatue", BUILD_POS["bank"] + Vector2(32, 12))

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

func join_count() -> int:
	# v3.2 §D: 합류 = 주민 + 동료 통합 (용사 제외. 촌장·엄마는 기본 거주자라 카운트 제외)
	return Game.resident_count() + Game.companion_count() - 1

func _revival_stage() -> int:
	var n := join_count()
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
	Game.current_field = f
	var tint: Color = Game.FIELD_TINTS[f]
	_repeat_sprite(field_root, "res://assets/Tiles/Grass_Middle.png", Rect2(0, 0, ROOM.x - VILLAGE_W, ROOM.y), Vector2(VILLAGE_W, 0), tint)
	var decor_tex := "res://assets/objects/forest.png" if f <= 1 else "res://assets/objects/hill.png"
	var decor_n := 10 if f == 1 else 5
	if f == 4:
		decor_tex = "res://assets/objects/tower.png"
		decor_n = 4
	for i in decor_n:
		_decor(field_root, decor_tex, Vector2(randf_range(260, 560), randf_range(48, 316)), tint)
	# 밤 장막 — 필드만 어두워진다. 마을은 물들지 않는다 (v3.2 §B-5)
	_night_shade = ColorRect.new()
	_night_shade.color = Color(0.05, 0.07, 0.2, 0.0)
	_night_shade.position = Vector2(VILLAGE_W, 0)
	_night_shade.size = Vector2(ROOM.x - VILLAGE_W, ROOM.y)
	_night_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_night_shade.z_index = 50
	field_root.add_child(_night_shade)
	# 행선지 이정표 — 첫 지배자를 쓰러뜨리면 나타난다
	if Game.signpost_seen:
		base_nodes["signpost"] = _add_thing(field_root, "signpost", Vector2(228, 190))
	# 검이 꽂힌 바위 (서사시 제 2절의 사건 — 어느 필드에서든 보인다)
	if Game.sword_rock >= 1:
		_spawn_sword_rock(false)
	# 로토의 방패 — 동굴 지배자를 쓰러뜨린 자리에 남는다 (v3.2 §B-7)
	if Game.bosses_defeated[2] and not Game.roto_shield:
		_add_thing(field_root, "rotoshield", Vector2(430, 120))
	# 수중 = 전원 물고기화 (v3.2 §B-1)
	party.set_underwater(f == 3)
	_spawn_boss(f)
	_add_thing(field_root, "cheatpot", Vector2(560, 300))  # DEBUG: 보스 근처 치트 항아리 — 클릭/Space마다 +1000 G (나중에 이 줄만 지우면 됨)
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
	tw.tween_callback(func():
		_swapping = false
		_field_arrival_voice(f))

func _field_arrival_voice(f: int) -> void:
	# 동굴 벽 처방 (v3.1 §B-6-4) — 벽이 먼저 말을 건다
	if f == 2 and not _cave_voice_done:
		_cave_voice_done = true
		Sfx.play("voice")
		hud.event("…동굴 벽에서 목소리가 스민다. 「기도와… 침대가… 벽을 넘게 하리라…」", 6.0)
	# 수중 진입 (v3.2 §B-1 — 드퀘11 오마주)
	if f == 3 and not _fish_voice_done:
		_fish_voice_done = true
		Sfx.play("warp", 1.4)
		hud.event("일행은 물고기가 되었다!! …헤어스타일은 그대로다.", 5.0)

func _spawn_sword_rock(pop: bool) -> void:
	var sr := _add_thing(field_root, "swordrock", Vector2(300, 72))
	if pop:
		sr.spawn_pop()

func select_field(f: int) -> void:
	swap_field(f)

func world_to_screen(p: Vector2) -> Vector2:
	return p  # 카메라 없음 — 월드 = 스크린

# ================================================================ loop

func _process(delta: float) -> void:
	if _title_mode:
		return  # 타이틀 상태 — 세계는 새벽 속에 잠들어 있다
	_full_msg_cd = maxf(0.0, _full_msg_cd - delta)
	_update_hover()
	if _wipe_lock or _ending_playing:
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
		_check_revival()
		_check_titles_and_medals()
		# 작전 명령 해금 — 2장(숲) + 여관 (v3.2 §D)
		if not Game.tactic_known and Game.buildings["inn"] and Game.fields_unlocked[1]:
			Game.tactic_known = true
			Sfx.play("fanfare")
			hud.event("여관 주인: 「일행에게 「작전」 을 내려 보시죠. 여관 메뉴에 적어 뒀습니다.」", 5.5)

	_save_timer -= delta
	if _save_timer <= 0.0:
		_save_timer = 20.0
		Game.save_game()

	# ---------- v3.1 ----------
	Game.playtime += delta
	# 합체기 준비 — 파티가 빛난다 (클릭으로 발동)
	party.combo_glow = Game.combo_gauge >= 1.0 and not Game.active_combo().is_empty()
	# 은행 이자 — 접속 중에만, 30초마다 (예금이 예금을 낳는다)
	_interest_timer -= delta
	if _interest_timer <= 0.0:
		_interest_timer = 30.0
		if Game.buildings["bank"] and Game.deposit > 0:
			var cap := int(60.0 * Game.gold_scale())  # 필드 수입 대비 과하지 않게
			var interest: int = clampi(int(Game.deposit * Game.bank_rate()), 1, cap)
			Game.deposit = mini(Game.deposit + interest, Game.bank_cap())
			if base_nodes.has("bank") and is_instance_valid(base_nodes["bank"]):
				hud.popup("이자 +%d G" % interest, base_nodes["bank"].global_position, UILib.COL_GOLD)
	# 스님의 성불 — 유령이 45초면 스스로 돌아온다
	if Game.passive_on("requiem") and Game.ghost_count() > 0:
		_requiem_timer += delta
		if _requiem_timer >= 45.0:
			_requiem_timer = 0.0
			for i in Game.members.size():
				if Game.members[i]["ghost"]:
					Game.members[i]["ghost"] = false
					Game.members[i]["hp"] = maxi(1, int(Game.members[i]["max_hp"] * 0.3))
					Game.add_stat("requiems")
					Game.member_changed.emit(i)
					Game.party_changed.emit()
					Sfx.play("revive")
					hud.event("스님의 독경으로 %s이(가) 성불을… 아니, 환생했다!" % Game.members[i]["name"], 3.5)
					break
	else:
		_requiem_timer = 0.0
	# 도적의 귀환 (서사시 제 4절의 드라마)
	if Game.thief_away and Game.playtime >= Game.thief_return_at:
		_thief_return()

	# ---------- v3.2 ----------
	# 밤낮 — 필드 장막 + 경계 알림 (마을은 물들지 않는다)
	if _night_shade != null and is_instance_valid(_night_shade):
		_night_shade.color.a = 0.38 * Game.night_frac()
	var night := Game.is_night()
	if night != _was_night:
		_was_night = night
		hud._update_top()
		if Game.clock_on():
			Sfx.play("voice" if night else "heal", 1.2)
			if night:
				hud.event("밤이 왔다. 몬스터가 사나워지고… 은빛 무언가가 돌아다닌다.", 4.5)
			else:
				hud.event("아침이 왔다. %s의 하루가 다시 시작된다." % Game.hn(), 3.5)
	# 폴터가이스트 — 유령이 지나가는 항아리를 깨뜨린다
	if Game.medal_on("poltergeist") and Game.ghost_count() > 0:
		_polter_timer -= delta
		if _polter_timer <= 0.0:
			_polter_timer = 0.8
			for n in get_tree().get_nodes_in_group("hoverable"):
				if n is Interactable and n.kind == "pot" and n.is_ready \
						and party.head_pos.distance_to(n.global_position) < 26.0:
					_bump_pot(n)
					break
	# 천리안 — 주시 중인 창의 이웃에게 절반 효과
	if Game.medal_on("clairvoyance"):
		var docked: Array = []
		for w in windows:
			if is_instance_valid(w) and not w.closing and not w.is_boss and w.sim != null:
				docked.append(w)
		var hov := -1
		for i in docked.size():
			if docked[i].sim.hovered:
				hov = i
		for i in docked.size():
			docked[i].sim.hovered_adj = hov >= 0 and absi(i - hov) == 1

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Game.save_game()

# ================================================================ input (몸=Space / 시선=클릭)

func _unhandled_input(event: InputEvent) -> void:
	if _title_mode:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
			_title_space()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				# 메뉴가 열려 있으면 닫고, 아니면 옵션 (v3.3 §D)
				if hud.is_menu_open():
					hud.close_menu()
				elif not _ending_playing:
					hud.open_options(true)
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
	if _wipe_lock or _ending_playing:
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
	if _wipe_lock or _ending_playing or _title_mode or hud.is_menu_open():
		return
	# 합체기 — 빛나는 파티를 클릭하면 터진다 (v3.1 §B-4)
	if party.combo_glow and pos.distance_to(party.head_pos) < 22.0:
		_fire_combo()
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
		"cheatpot":
			_cheat_gold(it)
		_:
			# 상인의 텔레파시 — 멀리서도 건물 메뉴가 열린다 (몸 행위는 잠김)
			if Game.up["telepathy"] > 0:
				_telepathy_open(it)

func _telepathy_open(it: Interactable) -> void:
	var near: bool = party.head_pos.distance_to(it.global_position) < it.pick_radius() + 14.0
	var opener := _menu_opener_for(it.kind)
	if opener.is_null():
		return
	Sfx.play("click")
	hud.remote_open = not near
	opener.call()

func _menu_opener_for(kind: String) -> Callable:
	match kind:
		"inn": return hud.open_inn
		"church": return hud.open_church
		"shop": return hud.open_shop_menu
		"board": return hud.open_board
		"bard": return hud.open_bard
		"medalking": return hud.open_medalking
		"chief":
			if Game.ui_unlocked["quest"]:
				return hud.open_chief
		"bank": return hud.open_bank
		"signpost": return hud.open_gate
	return Callable()

func _cheat_gold(it: Interactable) -> void:  # DEBUG: 나중에 이 함수째 지우면 됨
	Game.add_gold(1000)
	if Game.add_exp(Game.exp_to_next()):  # 딱 다음 레벨까지 — 레벨 1 상승
		hud.levelup_ritual(Game.level)
	Sfx.play("gold_big")
	hud.popup("+1000 G  Lv%d" % Game.level, it.global_position, UILib.COL_GOLD)
	hud.coin_burst(it.global_position, 6)

# ================================================================ 합체기 (v3.1 §B-4 — 게이지→발광→클릭→필드 스윕)

func _fire_combo() -> void:
	var cd: Dictionary = Game.active_combo()
	if cd.is_empty() or Game.combo_gauge < 1.0:
		return
	Game.combo_gauge = 0.0
	party.combo_glow = false
	Game.add_stat("combos")
	Sfx.play("combo")
	hud.show_cutin(String(cd["cutin"]), String(cd["tex"]), String(cd["fallback"]), cd["tint"])
	# 컷인 직후 필드의 모든 전투창을 휩쓴다
	get_tree().create_timer(0.5).timeout.connect(func():
		var hit_any := false
		for w in windows:
			if not is_instance_valid(w) or w.closing or w.sim == null or w.sim.finished:
				continue
			hit_any = true
			if String(cd["id"]) == "frog":
				w.sim.combo_frogify()
			else:
				w.sim.combo_annihilate()
		if String(cd["id"]) == "tuna":
			_rain_fish()
		if not hit_any:
			hud.event("…힘이 허공을 갈랐다. (전투창이 없었다)", 3.0)
		Game.save_game())

func _rain_fish() -> void:
	# 참치 어택의 여운 — 하늘에서 물고기(보너스 골드)가 쏟아진다
	for i in 6:
		var f := Sprite2D.new()
		f.texture = load("res://assets/enemies/slime_fly.png")
		f.modulate = Color(0.5, 0.7, 1.3)
		f.rotation = PI
		f.position = Vector2(randf_range(VILLAGE_W + 30, 610), -20)
		field_root.add_child(f)
		var land := Vector2(f.position.x, randf_range(60, 320))
		var tw := create_tween()
		tw.tween_interval(i * 0.12)
		tw.tween_property(f, "position", land, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			var g := maxi(1, int(randi_range(10, 25) * Game.gold_scale()))
			_gain_gold(g, f.global_position, "coin", 2)
			f.queue_free())

# ================================================================ 서사시 사건 (v3.1 §B-2 — 절은 사건을 판다)

func on_verse_bought(i: int) -> void:
	match i:
		0:  # 절 1 — 침묵의 국경: 드루이드가 숲에서 걸어나온다
			_companion_walkin("druid", "숲의 드루이드가 이야기를 듣고 찾아왔다!")
		1:  # 절 2 — 무너진 왕도: 검이 꽂힌 바위가 필드에 나타난다
			if Game.sword_rock == 0:
				Game.sword_rock = 1
				_spawn_sword_rock(true)
				hud.event("필드 어딘가에… 검이 꽂힌 바위가 나타났다!", 4.5)
		2:  # 절 3 — 돌아오지 않은 용사: 도적이 합류한다
			_companion_walkin("thief", "이야기 속 도적이… 실존했다! 일행에 합류한다!")
		3:  # 절 4 — 찢긴 세계: 도적의 배신
			_thief_betray()
		4:  # 절 5 — 마지막 마을: 합체기의 소문
			Game.combo_hint_known = true
			hud.event("「어부는 형제와, 드루이드는 바드와, 사제는 죽은 자와 통한다더군.」", 6.0)
		5:  # 절 6 — 어머니의 아침: 마왕성의 문이 열린다
			hud.event("이야기의 끝을 알았다. …마왕성의 벽이 사라진 기분이 든다.", 5.0)
	Game.save_game()

func _companion_walkin(id: String, join_msg: String) -> void:
	if Game.companions_owned.get(id, false):
		return
	var walker := Sprite2D.new()
	walker.texture = load(String(Game.COMPANIONS[id]["tex"]))
	walker.hframes = 3
	walker.vframes = 4
	walker.frame = 1
	walker.modulate = Game.COMPANIONS[id].get("tint", Color(1, 1, 1))
	walker.position = Vector2(250, 352)
	walker.offset = Vector2(0, -13)
	add_child(walker)
	hud.event("누군가 이쪽으로 걸어온다…", 2.5)
	var tw := create_tween()
	tw.tween_property(walker, "position", party.head_pos, 2.0)
	tw.tween_callback(func():
		if walker != null and is_instance_valid(walker):
			walker.queue_free()
		Game.own_companion(id)
		Sfx.play("fanfare_big")
		hud.event(join_msg, 4.0)
		if Game.party_ids.has(id):
			hud.toast("%s이(가) 일행에 들어왔다!" % Game.COMPANIONS[id]["name"], 3.0)
		else:
			hud.toast("자리가 없어 여관에서 기다린다. (여관 → 파티 편성)", 4.0)
		Game.save_game())

func _thief_betray() -> void:
	# 서사시의 백미 — 도적이 금고를 털어 떠난다. …그리고 돌아온다 (v3.1 §B-2-4)
	if not Game.companions_owned.get("thief", false) or Game.thief_away:
		hud.event("…그 절의 주인공은 아직 이 마을에 없다.", 3.5)
		return
	var stolen := int(Game.gold * 0.2)
	Game.add_gold(-stolen)
	Game.thief_away = true
	Game.thief_return_at = Game.playtime + 300.0
	Game.party_ids.erase("thief")
	Game.companions_owned["thief"] = false
	Game.rebuild_party()
	Sfx.play("flee")
	hud.event("도적이 %d G를 들고 사라졌다!! …이게 서사시라고?!" % stolen, 6.0)

func _thief_return() -> void:
	Game.thief_away = false
	Game.own_companion("thief")
	Sfx.play("fanfare_big")
	hud.event("도적이 돌아왔다! 「…이자까지 쳐서 갚으러 왔다.」", 5.0)
	var back := int(200 * Game.gold_scale())
	Game.add_gold(back)
	hud.popup("+%d G" % back, party.head_pos, UILib.COL_GOLD)
	if Game.own_medal("loyal_heart"):
		hud.event("훈장 「의리의 심장」 을 손에 넣었다!", 4.5)
	if Game.charmed.size() < 2:
		Game.charmed.append("slime")
		party.refresh_charmed()
		hud.toast("도적이 매혹된 슬라임을 데려왔다…?", 3.5)
	Game.save_game()

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
	return n is Interactable and ((n.kind == "smith" and n.is_ready) or n.kind == "casino" or n.kind == "cheatpot")

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
		"cheatpot":
			_cheat_gold(it)
		"bank":
			Sfx.play("bump")
			hud.open_bank()
		"frogstatue":
			_bump_frogstatue(it)
		"swordrock":
			_bump_swordrock(it)
		"home":
			_bump_home(it)
		"mom":
			Sfx.play("bump")
			hud.event("엄마: 「%s, 밥은 먹고 다니니?」" % Game.hn(), 3.5)
		"well":
			_bump_well(it)
		"rotoshield":
			_bump_rotoshield(it)
		"resident":
			Sfx.play("bump")
			hud.event("%s: 「좋은 마을이 되어 가는군요.」" % it.resident_name)
		"recruit":
			_bump_recruit(it)

func _bump_frogstatue(it: Interactable) -> void:
	# 개구리 석상 — 잔돈을 던져 넣는다 (Space 한 번 = 100 미만 잔돈 예금)
	var spare: int = Game.gold % 100
	if spare <= 0 or Game.deposit >= Game.bank_cap():
		Sfx.play("bump")
		hud.event("개구리 석상: 「…개굴. (잔돈이 없다)」")
		return
	var moved := Game.bank_deposit(spare)
	Sfx.play("bank")
	hud.popup("개굴! +%d G 예금" % moved, it.global_position, UILib.COL_GOLD)

const MOM_LETTERS := [
	"「반찬 남기지 말고. — 엄마가」",
	"「촌장님 말씀 잘 듣고 있니? — 엄마가」",
	"「마왕이든 뭐든, 저녁엔 들어와. — 엄마가」",
	"「네가 자는 동안에도 엄마는 네 편이었어.」",
]

func _bump_home(it: Interactable) -> void:
	# 용사의 집 (v3.2 §B-6) — 쿨타임마다 랜덤 1종: 도시락/편지/용돈
	Sfx.play("bump")
	if not it.is_ready:
		hud.event("%s의 집. …엄마 생각이 난다." % Game.hn(), 3.0)
		return
	it.start_cooldown(75.0)
	match randi() % 3:
		0:
			Game.lunch_until = Game.playtime + 90.0
			Sfx.play("heal")
			hud.event("엄마의 도시락이다! 힘이 난다. (잠시 공격력 +10%)", 4.5)
		1:
			Sfx.play("blip", 0.8)
			hud.event("편지가 놓여 있다. %s" % MOM_LETTERS[randi() % MOM_LETTERS.size()], 5.0)
		2:
			var g := maxi(3, int(8 * Game.gold_scale()))
			_gain_gold(g, it.global_position, "coin", 2)
			hud.event("베개 밑에 용돈이…! 엄마는 다 알고 있다.", 4.0)

func _bump_well(it: Interactable) -> void:
	# 우물 (v3.2 §B-9) — 들여다본다: 골드 / 메달 / …뭔가 있다
	if not it.is_ready:
		return
	Game.add_stat("wells")
	it.start_cooldown(40.0)
	var roll := randf()
	if roll < 0.06 and not _windows_full():
		Sfx.play("boss")
		hud.event("우물 안에 뭔가 있다…!!", 3.0)
		var t := Game.progress_tier()
		var def := {
			"id": "well_thing", "name": "우물의 그것",
			"hp": int(30 * Game.tier_stat(t)), "atk": int(7 * Game.tier_atk(t)),
			"gold": int(150 * Game.tier_gold(t)), "exp": int(30 * Game.tier_exp(t)),
			"tex": "res://assets/enemies/bat.png", "scale": 1.0, "tint": Color(0.5, 0.6, 0.8),
		}
		_open_battle([def], false)
		return
	if roll < 0.16:
		Game.medals_small += 1
		Sfx.play("golden", 1.3)
		hud.popup("작은 메달!", it.global_position + Vector2(0, -14), UILib.COL_GOLD)
		return
	var g := maxi(1, int(randi_range(4, 12) * Game.gold_scale() * Game.gold_multiplier()))
	_gain_gold(g, it.global_position, "coin", 2)

func _bump_rotoshield(it: Interactable) -> void:
	# 로토의 방패 (v3.2 §B-7 — 지배자가 지키던 두 번째 조각)
	Game.roto_shield = true
	Sfx.play("fanfare_big")
	hud.event("「로토의 방패」 를 손에 넣었다! %s의 몸이 빛난다… (%d/3)" % [Game.hn(), Game.roto_count()], 5.5)
	party._rebuild_sprites()
	it.queue_free()
	Game.save_game()

func vip_spawn() -> void:
	# 카지노 VIP 카드 — 슬롯의 몬스터가 필드에 실체화 (v3.2 조건형)
	_spawn_monster(last_field)
	hud.event("슬롯에서 튀어나온 몬스터가 필드에 나타났다?!", 3.5)

func _bump_swordrock(it: Interactable) -> void:
	if Game.sword_rock >= 2:
		hud.event("검이 뽑힌 바위다. 구멍만 남아 있다.")
		return
	if Game.level >= 10:
		Game.sword_rock = 2
		Sfx.play("fanfare_big")
		Game.set_weapon_lv("hero", 4)
		hud.event("검이… 뽑혔다!! 「여명의 검」 — 이야기가 진짜였다!", 6.0)
		hud.popup("여명의 검!", it.global_position, UILib.COL_GOLD)
		it.queue_redraw()
		Game.save_game()
	else:
		Sfx.play("deny")
		hud.event("바위의 검이 꿈쩍도 않는다. …더 강해져야 한다. (Lv 10)", 4.0)

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
		count = 1  # 수중 정예는 홀로 다닌다
	var defs: Array = []
	if Game.medal_on("duel_manner"):
		# 일기토의 예법 — 모든 조우가 정예 1마리, 보상 집중 (v3.2 양날형)
		var elite: Dictionary = m.def.duplicate()
		elite["name"] = "정예 " + String(elite["name"])
		elite["hp"] = int(elite["hp"] * 1.8)
		elite["atk"] = int(elite["atk"] * 1.3)
		elite["gold"] = int(elite["gold"] * 2.5)
		elite["exp"] = int(elite["exp"] * 2.5)
		defs = [elite]
	else:
		for i in count:
			defs.append(m.def)
	m.queue_free()
	_open_battle(defs, false)

func _bump_pot(it: Interactable) -> void:
	if not it.is_ready:
		return
	Game.add_stat("pots")
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
	Game.add_stat("digs")
	var g := maxi(1, int(randi_range(8, 20) * Game.gold_scale() * Game.gold_multiplier()))
	# 광부의 곡괭이 + 어부 형의 낚시 (수중 각성 ×2, 후미의 긍지 적용)
	g = int(g * (1.0 + 0.3 * Game.passive_scale("pickaxe")))
	var fish_s := Game.passive_scale("fish")
	if fish_s > 0.0 and randf() < 0.25 * fish_s:
		var bonus := maxi(1, int(g * 0.6))
		g += bonus
		hud.event("어부 형이 물고기를 낚아 올렸다! +%d G" % bonus, 2.5)
	var medal_chance := 0.10 + 0.05 * Game.passive_scale("pickaxe")
	_gain_gold(g, it.global_position, "dig", 2)
	_maybe_drop_medal(it.global_position, medal_chance)
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
	Game.own_companion(cls)
	Sfx.play("fanfare_big")
	if Game.party_ids.has(cls):
		hud.event("%s이(가) 일행에 합류했다!" % Game.CLASS_DEFS[cls]["name"], 3.5)
	else:
		hud.event("%s이(가) 동료가 됐다! 자리가 없어 여관에서 기다린다. (파티 편성)" % Game.CLASS_DEFS[cls]["name"], 4.5)
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

func candidate_asks() -> Array:
	# 객원 동료 부탁 (v3.1) — 선행 조건을 채운 것만 촌장 입에 오른다
	var out: Array = []
	for a in COMPANION_ASKS:
		if Game.companions_owned.get(a["id"], false):
			continue
		if a["id"] == "banker" and Game.buildings["bank"]:
			continue
		var rb: String = String(a.get("req_building", ""))
		if rb != "" and not Game.buildings.get(rb, false):
			continue
		var ru: String = String(a.get("req_up", ""))
		if ru != "" and Game.up.get(ru, 0) == 0:
			continue
		out.append(a)
		if out.size() >= 2:
			break
	return out

func try_pay_companion(id: String) -> bool:
	for a in COMPANION_ASKS:
		if a["id"] != id or Game.companions_owned.get(id, false):
			continue
		if int(a["lv"]) > 0 and Game.level < int(a["lv"]):
			Sfx.play("deny")
			hud.event("아직 이르다. (Lv %d 필요)" % a["lv"])
			return false
		if not Game.try_spend(Game.price(int(a["gold"]))):
			Sfx.play("deny")
			return false
		if id == "banker":
			_build_bank()
		if id == "fisher_a":
			# 어부 형제는 세트 (합체기 「참치 어택」 의 열쇠)
			_companion_walkin("fisher_a", "어부 형이 그물을 메고 왔다!")
			get_tree().create_timer(2.8).timeout.connect(func():
				_companion_walkin("fisher_b", "어부 아우도 뒤따라왔다! 형제가 모였다!"))
		else:
			_companion_walkin(id, "%s이(가) 동료가 되었다!" % Game.COMPANIONS[id]["name"])
		Game.save_game()
		return true
	return false

func _build_bank() -> void:
	Game.buildings["bank"] = true
	var n := _add_thing(base_root, "bank", BUILD_POS["bank"])
	base_nodes["bank"] = n
	n.spawn_pop()
	var fs := _add_thing(base_root, "frogstatue", BUILD_POS["bank"] + Vector2(32, 12))
	fs.spawn_pop()
	Sfx.play("build")
	hud.event("마을에 은행이 섰다! 개구리 석상도 딸려 왔다.", 4.5)

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
		# 걷는 도중 부흥 재건축(_build_village)이 끼어들면 walker/시설이 이미 처리돼 있다
		if walker != null and is_instance_valid(walker):
			walker.queue_free()
		var b: String = r["building"]
		if not (base_nodes.has(b) and is_instance_valid(base_nodes[b])):
			_place_resident(r, true)
		Sfx.play("build")
		hud.event(r["join"], 4.0)
		_resident_companion(r["id"])
		_check_revival()
		Game.save_game())

# ================================================================ 칭호 + 도전과제식 훈장 (v3.2 §B-8, §C)

func _grant_medal(id: String) -> void:
	if Game.own_medal(id):
		Sfx.play("fanfare_big")
		hud.event("훈장 「%s」 을 손에 넣었다!" % Game.MEDAL_DEFS[id]["name"], 4.5)
		Game.save_game()

func _check_titles_and_medals() -> void:
	# 칭호 — 한 틱에 하나 (의식은 겹치지 않는다)
	var t: Dictionary = Game.check_titles()
	if not t.is_empty():
		Sfx.play("fanfare")
		hud.event("칭호 획득 — 「%s」! 촌장이 알면 좋아하겠다." % t["name"], 4.5)
		Game.save_game()
		return
	# 통계 연동 훈장 (도전과제식 — 획득처가 곧 플레이 습관)
	var s: Dictionary = Game.stats
	if int(s["mimic_wins"]) >= 10 and not Game.medals_owned.has("mimic_teeth"):
		_grant_medal("mimic_teeth")
	elif int(s["pots"]) >= 1000 and not Game.medals_owned.has("cracked_pot"):
		_grant_medal("cracked_pot")
	elif int(s["flees"]) >= 10 and not Game.medals_owned.has("coward_flag"):
		_grant_medal("coward_flag")
	elif int(s["golden_caught"]) >= 10 and not Game.medals_owned.has("metal_crown"):
		_grant_medal("metal_crown")
	elif int(s["inn_rests"]) >= 10 and not Game.medals_owned.has("late_sleep"):
		_grant_medal("late_sleep")
	elif int(s["revives"]) >= 5 and not Game.medals_owned.has("martyr"):
		_grant_medal("martyr")
	elif int(s["requiems"]) >= 1 and not Game.medals_owned.has("poltergeist"):
		_grant_medal("poltergeist")
	elif Game.titles.size() >= 3 and not Game.medals_owned.has("attendance"):
		_grant_medal("attendance")
	elif Game.companions_owned.get("fisher_a", false) and Game.companions_owned.get("fisher_b", false) \
			and not Game.medals_owned.has("fisher_pride"):
		_grant_medal("fisher_pride")
	elif Game.residents.get("father", false) and Game.up["heal_eye"] > 0 \
			and not Game.medals_owned.has("holy_pendant"):
		_grant_medal("holy_pendant")

func _resident_companion(rid: String) -> void:
	# 주민-동료 연동 (v3.1 §B-3) — 시설의 화신이 곧 객원 동료다
	var link := {"innkeep": "cook", "merchant": "merchant_c", "bard_r": "bardc", "father": "monk"}
	if not link.has(rid):
		return
	var cid: String = link[rid]
	if Game.own_companion(cid):
		get_tree().create_timer(2.0).timeout.connect(func():
			Sfx.play("fanfare")
			var cname: String = Game.COMPANIONS[cid]["name"]
			if Game.party_ids.has(cid):
				hud.event("%s이(가) 「저도 데려가 주세요!」 — 일행에 합류했다!" % cname, 4.5)
			else:
				hud.event("%s이(가) 동행을 자청한다! (여관 → 파티 편성)" % cname, 4.5))

var _last_revival_stage := -1

func _check_revival() -> void:
	# 합류 인원 임계점 → 마을이 물리적으로 확장된다 (v3.2: 4단계)
	var s := _revival_stage()
	if _last_revival_stage < 0:
		_last_revival_stage = s
		return
	if s > _last_revival_stage:
		_last_revival_stage = s
		Sfx.play("palette")
		var msgs := [
			"마을이 살아나기 시작했다! 광장이 넓어졌다.",
			"마을에 분수와 우물이 생겼다! 엄마도 부엌에 불을 지폈다.",
			"성벽이 올라가기 시작한다! …큰돈의 냄새를 맡은 자가 있다던데.",
			"성벽이 완성됐다! 마을은 이제 도시라 불러도 좋다.",
		]
		var msg: String = msgs[clampi(s - 1, 0, msgs.size() - 1)]
		get_tree().create_timer(1.2).timeout.connect(func():
			_build_village()
			Sfx.play("fanfare_big")
			hud.event(msg, 5.0))

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
	w.flee_requested.connect(_on_flee.bind(w))
	sim.victory.connect(_on_victory.bind(w, boss))
	sim.member_hit.connect(_on_member_hit_fx.bind(w))
	sim.golden_captured.connect(_on_golden_captured.bind(w))
	sim.golden_escaped.connect(_on_golden_escaped_stat)
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
		hud.fly_xp(w.position + w.size / 2.0, clampi(1 + exp_reward / 10, 1, 5))  # 파란 경험치 입자 (v3.1)
		w.close_after(1.1)
	if Game.add_exp(exp_reward):
		Sfx.play("levelup")
		hud.levelup_ritual(Game.level)
	if boss:
		boss_fighting = false
		party.frozen = false
		_on_boss_defeated(boss_field)

func _on_flee(w: BattleWindow) -> void:
	# 퇴각 나팔 — 보상 없이 창을 접는다 (v3.1 §B-7-6)
	if is_instance_valid(w) and not w.closing:
		Game.add_stat("flees")
		hud.event("일행은 도망쳤다! …부끄럽지 않다. 전략이다.", 2.5)
		w.close_after(0.0)

func _on_member_hit_fx(idx: int, dmg: int, fell: bool, w: BattleWindow) -> void:
	if is_instance_valid(w):
		hud.fly_damage(w.position + Vector2(randf_range(20, w.size.x - 20), w.size.y - 30), idx, dmg)
	# 순교자의 성표 — 쓰러지는 순간, 전 창에 폭발 (v3.2 유령 계열)
	if fell and Game.medal_on("martyr"):
		Sfx.play("crit", 0.7)
		hud.event("%s의 혼이 폭발했다!!" % Game.members[idx]["name"], 3.0)
		var blast: int = maxi(4, Game.member_atk(idx) * 3)
		for bw in windows:
			if is_instance_valid(bw) and not bw.closing and bw.sim != null and not bw.sim.finished:
				for ei in bw.sim.alive_enemies():
					bw.sim._apply_enemy_damage(ei, blast, true, false)

func _on_golden_captured(reward: int, w: BattleWindow) -> void:
	if is_instance_valid(w) and w.sim != null and w.sim.golden_silver:
		# 은빛 슬라임 (밤) — 경험치를 남긴다 (v3.2 §B-5)
		Game.add_stat("silver_caught")
		Sfx.play("capture", 0.8)
		hud.fly_xp(w.position + w.size / 2.0, 5)
		if Game.add_exp(reward):
			hud.levelup_ritual(Game.level)
		hud.event("은빛 슬라임을 붙잡았다! 경험치가 쏟아진다!", 3.5)
		if not Game.medals_owned.has("moonlight"):
			_grant_medal("moonlight")  # 달빛 훈장 — 첫 포획의 증표
		return
	Game.add_stat("golden_caught")
	Game.add_gold(reward)
	Sfx.play("gold_big")
	if is_instance_valid(w):
		hud.coin_burst(w.position + w.size / 2.0, 8)
	hud.event("황금 슬라임을 붙잡았다! +%d G!" % reward, 3.5)

func _on_golden_escaped_stat() -> void:
	Game.add_stat("golden_missed")
	# 끈끈이 장갑 — 놓쳐 본 자에게 주어지는 위로 (v3.2 §C)
	if Game.up["golden_hands"] > 0 and not Game.medals_owned.has("sticky_gloves"):
		_grant_medal("sticky_gloves")

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
	# 밤에는 황금 대신 은빛이 온다 (v3.2 §B-5 — 밤을 기다릴 이유)
	var silver := Game.is_night()
	w.sim.spawn_golden(dur, silver)
	if silver and not Game.silver_seen:
		Game.silver_seen = true
		hud.event("은빛 슬라임…?! 밤에만 나타나는 놈이다!", 4.0)
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
	var elite: bool = field == 3  # 수중 = 정예의 땅 (어류는 억세다)
	# 밤 = 몬스터 강화 + 보상 상승 (v3.2 §B-5)
	var night_hp := 1.3 if Game.is_night() else 1.0
	var night_gold := 1.5 if Game.is_night() else 1.0
	return {
		"id": base["id"],
		"name": ("밤 " if Game.is_night() else "") + Game.FIELD_PREFIX[field] + String(base["name"]),
		"hp": int(base["hp"] * Game.tier_stat(t) * xf * (1.6 if elite else 1.0) * night_hp),
		"atk": int(maxf(1.0, base["atk"] * Game.tier_atk(t) * xf * (1.3 if elite else 1.0) * (1.2 if Game.is_night() else 1.0))),
		"gold": int(base["gold"] * Game.tier_gold(t) * xf * (1.8 if elite else 1.0) * (1.0 + 0.4 * int(field == 2)) * night_gold),
		"exp": int(maxf(1.0, base["exp"] * Game.tier_exp(t) * xf * (1.3 if Game.is_night() else 1.0))),
		"tex": base["tex"], "scale": 1.0,
		"tint": Game.FIELD_TINTS[field].darkened(0.25) if Game.is_night() else Game.FIELD_TINTS[field],
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
	if last_field >= 4 and not (Game.epic_complete() and Game.roto_complete()):
		Sfx.play("deny")
		# 이중 열쇠 (v3.2 §B-7): 이야기의 끝 + 로토 3점
		if not Game.epic_complete():
			hud.event("마왕 앞에 보이지 않는 벽이 있다. …이야기의 끝을 알아야 한다. (음유시인)", 4.5)
		else:
			hud.event("벽이 속삭인다. 「전설의 세 조각을 걸친 자만이…」 (로토 세트 %d/3)" % Game.roto_count(), 4.5)
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
		Game.save_game()
		_play_ending()
		return
	# v3.2 훈장 재배선: 초원=바람 / 숲=불복종 / 동굴=무리 사냥꾼+일기토 / 수중=천리안
	var medal_by_field := ["wind_sign", "disobedience", "pack_hunter", "clairvoyance"]
	var mid: String = medal_by_field[clampi(field, 0, 3)]
	if Game.own_medal(mid):
		Sfx.play("fanfare_big")
		hud.event("훈장 「%s」 을 손에 넣었다!" % Game.MEDAL_DEFS[mid]["name"], 4.5)
	if field == 2 and Game.own_medal("duel_manner"):
		get_tree().create_timer(2.0).timeout.connect(func():
			hud.event("훈장 「일기토의 예법」 도 함께 손에 넣었다!", 4.0))
	# 로토의 조각 (v3.2 §B-7): 동굴 → 방패가 남는다 / 수중 → 투구 드랍
	if field == 2 and not Game.roto_shield:
		var rs := _add_thing(field_root, "rotoshield", Vector2(430, 120))
		rs.spawn_pop()
		hud.event("지배자가 지키던 것이… 빛나는 방패다!", 4.5)
	if field == 3 and not Game.roto_helm:
		Game.roto_helm = true
		Sfx.play("fanfare_big")
		hud.event("「로토의 투구」 를 손에 넣었다! (%d/3)" % Game.roto_count(), 5.0)
		party._rebuild_sprites()
		if Game.roto_complete():
			get_tree().create_timer(2.5).timeout.connect(func():
				hud.event("세 조각이 모였다… %s의 모습이 전설 그 자체다!" % Game.hn(), 5.5))
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
	Game.skip_title = true  # 2주차는 타이틀 없이 바로 새 아침으로
	get_tree().reload_current_scene()

# ================================================================ 엔딩 (v3.3 §F — 수미상관)

func _play_ending() -> void:
	# 1) 결계 붕괴 → 2) 마지막 산책 → 3) 광장 인구조사 → 4) 크레딧 → 5) "오랜만에 늦잠을 잤다."
	_ending_playing = true
	hud.close_menu()
	_close_all_windows()
	Sfx.play("palette")
	hud.event("마왕성의 결계가 소리 없이 무너져 내린다…", 4.5)
	# 필드를 비운다 — 돌아가는 길은 평화롭다
	for m in get_tree().get_nodes_in_group("monster"):
		if is_instance_valid(m):
			m.queue_free()
	# 마지막 산책 — 파티가 스스로 마을로 걸어 돌아온다
	get_tree().create_timer(2.0).timeout.connect(func():
		party.frozen = false
		party.manual_hold = 0.0
		party.target_node = null
		party.target_point = Vector2(120, 210)
		hud.event("일행은 왔던 길을 천천히 걸어 돌아간다.", 4.0))
	get_tree().create_timer(8.0).timeout.connect(_ending_gather)

func _ending_gather() -> void:
	# 광장 집합 — 이번 모험에서 실제로 모은 사람들만 서 있다 (내 플레이의 인구조사)
	party.frozen = true
	hud.fade_quick(func():
		party.teleport(Vector2(108, 230))
		var spots: Array = []
		for gy in 3:
			for gx in 6:
				spots.append(Vector2(38 + gx * 29, 156 + gy * 30))
		var idx := 0
		# 주민들
		for r in RESIDENTS:
			if Game.residents.get(r["id"], false) and idx < spots.size():
				_ending_cast_sprite("res://assets/NPCs/village_chief.png",
					Color(randf_range(0.7, 1.0), randf_range(0.7, 1.0), randf_range(0.7, 1.0)), spots[idx])
				idx += 1
		# 동료들 (파티는 이미 서 있다 — 대기 인원만)
		for cid in Game.COMPANIONS.keys():
			if Game.companions_owned.get(cid, false) and not Game.party_ids.has(cid) and idx < spots.size():
				var d: Dictionary = Game.COMPANIONS[cid]
				_ending_cast_sprite(String(d["tex"]), d.get("tint", Color(1, 1, 1)), spots[idx], int(d["frame_h"]))
				idx += 1
		# 엄마와 촌장은 언제나 그 자리에 (기본 거주자)
		Sfx.play("fanfare_big"))
	get_tree().create_timer(2.5).timeout.connect(func():
		hud.event("촌장: 「%s… 아니, 용사여. 마을은, 세계는 당신 덕에 살아났습니다.」" % Game.hn(), 5.0))
	get_tree().create_timer(7.0).timeout.connect(func():
		var title_line := ""
		if Game.current_title() != "":
			title_line = "「%s」라 불린 " % Game.current_title()
		hud.event("엄마: 「%s우리 %s. …고생했어. 이제 좀 자렴.」" % [title_line, Game.hn()], 5.5))
	get_tree().create_timer(12.5).timeout.connect(_ending_credits)

func _ending_cast_sprite(tex_path: String, tint: Color, pos: Vector2, frame_h: int = 26) -> void:
	var s := Sprite2D.new()
	s.texture = load(tex_path)
	if s.texture.get_width() > 40:  # 캐릭터 시트면 프레임 컷
		s.hframes = 3
		s.vframes = 4
		s.frame = 1
	s.modulate = tint
	s.offset = Vector2(0, -frame_h / 2.0)
	s.position = pos
	s.add_to_group("ending_cast")
	base_root.add_child(s)
	s.scale = Vector2(1.0, 0.05)
	var tw := create_tween()
	tw.tween_property(s, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _ending_credits() -> void:
	# 크레딧 — 별도 씬 없음. 마을 위로 흐른다
	var credits := [
		"Appears! Appears! Appears!",
		"— A AAA Incremental JRPG —",
		"",
		"기획 · 디렉션",
		"잠에서 깬 용사 본인",
		"",
		"구현 · 임시 도트 · 임시 사운드",
		"클로드 (야근)",
		"",
		"세계를 구한 사람",
		"%s (Lv %d)" % [Game.hn(), Game.level],
		"",
		"플레이타임  %d분" % int(Game.playtime / 60.0),
		"쓰러뜨린 몬스터  %d마리" % Game.kills,
		"깨뜨린 항아리  %d개" % int(Game.stats["pots"]),
		"",
		"Special Thanks",
		"엄마",
		"",
		"— 세계는 아침을 되찾았다 —",
	]
	hud.roll_credits(credits, func():
		hud.fade_black("그리고 %s는, 오랜만에 늦잠을 잤다." % Game.hn(), 4.0, func():
			# 크레딧 후 — 조용히. 팡파레 없음 (v3.3 §F-6)
			for s in get_tree().get_nodes_in_group("ending_cast"):
				if is_instance_valid(s):
					s.queue_free()
			Game.ending_seen = true
			Game.save_game()
			_ending_playing = false
			party.frozen = false
			hud.event("…교회의 신부가 조용히 고개를 끄덕인다. (2주차 모험)", 5.0))
		)

# ================================================================ 전멸

func _on_wipe() -> void:
	if _wipe_lock:
		return
	_wipe_lock = true
	party.frozen = true
	Game.add_stat("wipes")
	# 원혼의 함성 — 쓰러져 본 자에게 주어지는 위로 (v3.2)
	if not Game.medals_owned.has("ghost_warcry"):
		get_tree().create_timer(4.5).timeout.connect(func(): _grant_medal("ghost_warcry"))
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
	# 탈것 — 이속 트리의 끝은 수치가 아니라 존재의 변화 (v3.2 §B-2)
	if id == "speed" and Game.mounted():
		Sfx.play("fanfare_big")
		party._rebuild_sprites()
		hud.event("%s에게 탈것이 생겼다!! 대열 전체가 신이 나서 달린다!" % Game.hn(), 6.0)
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
	# 정규 동료 — 부의 소문을 듣고 온다 (v3.1: 5명 마일스톤)
	var plan := [
		["knight", 60, Vector2(70, 172)], ["mage", 350, Vector2(150, 172)],
		["priest", 1000, Vector2(110, 120)], ["warrior", 2000, Vector2(70, 120)],
		["monkf", 4000, Vector2(150, 120)],
	]
	for p in plan:
		var cls: String = p[0]
		if Game.total_earned >= int(p[1]) and not Game.recruits_spawned[cls] \
				and not Game.companions_owned.get(cls, false):
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
