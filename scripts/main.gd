extends Node2D
## v3.0 메인 오케스트레이터 — "A whole JRPG. One screen."
## 한 화면 고정 (640×360, 카메라 없음): 마을(좌⅓) + 필드(우⅔) + 최심부 지배자.
## 모든 해금은 세계의 변화로만 표현된다. 해금 전용 UI는 존재하지 않는다.

const ROOM := Vector2(640, 360)
const VILLAGE_W := 216.0          # 마을 = 좌 약 ⅓ (팔레트에 물들지 않는다)
const WIN := Vector2(120, 90)     # v3.4 §B-1: 전투창 규격 4:3 — 몬스터가 주인공

# v3.5 씬 리팩터 — UI는 씬으로 (에디터에서 편집)
const HUD_SCENE := preload("res://scenes/hud.tscn")
const BATTLE_WINDOW_SCENE := preload("res://scenes/battle_window.tscn")
const TITLE_SCENE := preload("res://scenes/title.tscn")

const BOSS_TEX := [
	"res://assets/enemies/slime_fly.png",
	"res://assets/enemies/bat.png",
	"res://assets/enemies/slime_chaser.png",
	"res://assets/enemies/slime_fly.png",
	"res://assets/enemies/bat.png",
	"res://assets/enemies/slime_chaser.png",  # 수중의 지배자 (숨겨진 필드, v3.4)
]
const BUILD_POS := {
	"inn": Vector2(44, 92), "church": Vector2(172, 92),
	"smith": Vector2(44, 198), "shop": Vector2(172, 198),
	"casino": Vector2(108, 300), "bard": Vector2(196, 148),
	"medalking": Vector2(20, 148), "board": Vector2(142, 132),
	"bank": Vector2(36, 254), "weaponshop": Vector2(172, 260),
	"train": Vector2(76, 232), "stable": Vector2(148, 232),  # v4.0 신규 건물
	"gearshop": Vector2(60, 300),  # v4.3 장비점 (시작부터)
	"well": Vector2(160, 96), "lamppost": Vector2(108, 186),  # v4.0 기물
	"scarecrow": Vector2(24, 220), "frogstatue": Vector2(68, 266),
}

## v4.0 §B-4: 건설 카탈로그 — 건물(기능+입주 주민) / 기물(소형 오브젝트, 잔돈 쇼핑)
## "건물이 서면 사람이 온다" — 구매 → 건물 팝 → NPC 걸어와 입주 (순서 반전)
const BUILD_CATALOG := [
	{"id": "train", "cat": "building", "name": "훈련소", "cost": 200, "lv": 2,
		"npc": "trainer", "npc_name": "교관", "desc": "전투창·전투 가속·무리 유인을 다루는 곳",
		"join": "훈련소가 섰다! 교관이 걸어 들어온다. \"전선은 넓을수록 좋다!\""},
	{"id": "smith", "cat": "building", "name": "대장간", "cost": 250, "lv": 3,
		"npc": "smithy", "npc_name": "대장장이", "desc": "무기를 벼린다 (벼림 %)",
		"join": "대장간이 섰다! 대장장이가 화덕에 불을 붙였다!"},
	{"id": "stable", "cat": "building", "name": "마구간", "cost": 300, "lv": 3,
		"npc": "hostler", "npc_name": "마부", "desc": "이동속도·행동반경, 그리고 언젠가… 탈것",
		"join": "마구간이 섰다! 마부가 여물을 채운다."},
	{"id": "weaponshop", "cat": "building", "name": "무기점", "cost": 350, "lv": 2,
		"npc": "weaponsmith", "npc_name": "무기상", "desc": "무기를 산다 (플랫 공격력)",
		"join": "무기점이 섰다! 무기상이 좌판을 깐다. \"좋은 무기는 정찰제요.\""},
	{"id": "shop", "cat": "building", "name": "상점", "cost": 400,
		"npc": "merchant", "npc_name": "상인", "desc": "골드 감각·도구·조수 동물",
		"join": "상점이 섰다! 상인이 물건을 나른다. \"뭐든 팔아 보이죠.\""},
	{"id": "casino", "cat": "building", "name": "카지노", "cost": 1500, "lv": 6,
		"npc": "gambler", "npc_name": "도박사", "desc": "어차피 세계는 이미 망했다",
		"join": "카지노 천막이 올라갔다! 도박사가 씩 웃는다."},
	{"id": "bank", "cat": "building", "name": "은행", "cost": 2500, "lv": 8,
		"npc": "banker", "npc_name": "은행원", "desc": "예금은 전멸에도 불가침 + 이자",
		"join": "은행이 섰다! 은행원이 금고를 연다."},
	# ---- 기물 (§B-4: 값싸고 즉각적 — 마을이 물건으로 붐빈다) ----
	{"id": "board", "cat": "fixture", "name": "수배 게시판", "cost": 60, "lv": 2,
		"desc": "위험한 놈들을 불러들인다",
		"join": "수배 게시판이 세워졌다! 위험한 놈들을 불러들일 수 있다."},
	{"id": "lamppost", "cat": "fixture", "name": "가로등", "cost": 40, "clock": true,
		"desc": "밤의 마을을 밝힌다",
		"join": "가로등이 섰다. 밤이 조금 덜 무서워졌다."},
	{"id": "scarecrow", "cat": "fixture", "name": "허수아비", "cost": 50, "needs": "train",
		"desc": "두드리면 30초간 전원 공격력 +25%",
		"join": "허수아비가 섰다. 교관이 흐뭇하게 바라본다."},
	{"id": "well", "cat": "fixture", "name": "우물", "cost": 80, "lv": 3,
		"desc": "가끔 들여다보면 좋은 일이 있다",
		"join": "우물을 팠다! 물소리가 마을을 채운다."},
	{"id": "frogstatue", "cat": "fixture", "name": "개구리 석상", "cost": 120, "needs": "bank",
		"desc": "잔돈을 던져 넣는 저금통 (…오의의 소문이 있다)",
		"join": "개구리 석상이 놓였다. 입이 크게 벌어져 있다."},
]

# (v3.9: 객원 동료 부탁 폐지 — 주민 부탁은 RESIDENTS가 전담)
const POT_SPOTS := [
	Vector2(84, 168), Vector2(132, 168), Vector2(84, 248), Vector2(132, 248),
	Vector2(60, 120), Vector2(160, 120), Vector2(60, 280), Vector2(160, 280),
]

## 주민 = 시설의 화신. 영입 조건 = 해금 문법 6종 중 하나 (v3.0 §B-2~B-3)
## cond: {"kill": id, "n": N} 자동 / {"boss": f} 자동 / {"medal": N} 자동 / {"gold": N, "lv": N} 촌장 부탁에서 지불
const RESIDENTS := [
	{"id": "innkeep",  "name": "여관 주인", "building": "inn",       "cond": {"kill": "slime", "n": 5},
		"ask": "슬라임이 무서워 길을 못 떠나요. 5마리만…", "join": "여관 주인이 마을에 정착했다!"},
	{"id": "father",   "name": "신부",     "building": "church",    "cond": {"kill": "bat", "n": 6},
		"ask": "박쥐 떼가 성물을 노립니다. 6마리를…", "join": "신부가 제단을 세웠다!"},
	{"id": "bard_r",   "name": "음유시인", "building": "bard",      "cond": {"boss": 0},
		"ask": "초원의 지배자가 사라지면 노래하러 오겠소.", "join": "음유시인이 광장에 앉았다!"},
	{"id": "medalist", "name": "메달왕",   "building": "medalking", "cond": {"medal": 3},
		"ask": "작은 메달을 3개 모은 자에게 가겠노라.", "join": "메달왕이 행차했다!"},
	{"id": "fishers",  "name": "어부 형제", "building": "",      "cond": {"gold": 900, "lv": 4}, "pos": Vector2(204, 296),
		"ask": "배를 잃었소. 도와주면 「바다의 노래」를 가르쳐 드리리다. (Lv 4부터)", "join": "어부 형제가 마을 끝에 자리를 잡았다!"},  # v3.9: 수중 열쇠 부탁 전담
]
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
var _guide_i := 0              # v4.1: 튜토리얼 안내원 팁 순회 (매번 다음 팁)
# v3.2
var _night_shade: Control = null     # 필드 밤 장막 (v3.4: 등불 구멍 포함)
var _was_night := false              # 밤낮 경계 알림
var _fish_voice_done := false        # 수중 진입 연출 (세션당 1회)
var _polter_timer := 0.0             # 폴터가이스트 틱
# v3.3
var _title_mode := false             # 타이틀 = 별도 씬이 아니라 메인 씬의 상태 ("게임이 곧 메뉴")
var _title_layer: CanvasLayer = null
var _ending_playing := false         # 엔딩 시퀀스 중 (입력·스폰 잠금)
# v3.4 — 밤 시야
var _night_hole: TextureRect = null  # 등불 구멍 (래디얼 그라디언트)
var _night_grad_tex: GradientTexture2D = null
var _night_fills: Array = []         # 그라디언트 밖 근암전 판

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

	# v3.5: HUD는 씬 (scenes/hud.tscn) — 위치·색은 에디터에서 편집
	hud = HUD_SCENE.instantiate()
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
	Music.reset()
	Music.play_field(last_field)

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

	if OS.get_environment("AAA_PROBE") == "1":  # DEV: 타이틀 경유 UI 상태 프로브
		if _title_mode:
			get_tree().create_timer(1.2).timeout.connect(func(): title_new(1))
		else:
			get_tree().create_timer(1.5).timeout.connect(func():
				Game.hero_name = "프로브"
				Game.add_gold(120))
			get_tree().create_timer(3.0).timeout.connect(func():
				print("[PROBE] gold_flag=", Game.ui_unlocked["gold"],
					" top_visible=", hud._top_panel.visible,
					" top_pos=", hud._top_panel.position, " top_size=", hud._top_panel.size,
					" top_text=", hud._top_label.text,
					" suppress=", hud._title_suppress)
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("user://shot_probe.png")
				print("[PROBE] shot saved")
				get_tree().quit())

func _prologue() -> void:
	if Game.total_earned > 0 or Game.level > 1:
		if Game.hero_name == "":
			Game.hero_name = "용사"  # 진행 중 세이브 안전망
		# v3.9 §B-5: 이어하기도 저장된 마을이 팝인으로 재등장 — "Appears!"가 매 부팅의 의식
		if Game.skip_popin_once:
			Game.skip_popin_once = false
		else:
			_play_popin()
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
			Game.hero_name = "용사"
		_prologue_lines()

func _prologue_lines() -> void:
	# v3.8 §B-4: "Appears!" 팝인 — 제목 그 자체의 연출. 세계가 뾱뾱뾱 나타난다
	party.teleport(Vector2(96, 100))  # 용사의 집 앞 (프롤로그의 발원지)
	var popin_t := _play_popin()
	get_tree().create_timer(popin_t + 0.3).timeout.connect(func():
		hud.fade_black("엄마: 「일어나렴, %s.」" % Game.hn(), 1.8, func(): pass))
	get_tree().create_timer(popin_t + 3.9).timeout.connect(func():
		hud.toast("%s은(는) 일어났다. 그러나, 너무 늦었다." % Game.hn(), 3.6))
	get_tree().create_timer(popin_t + 7.9).timeout.connect(func():
		if not Game.ui_unlocked["desc"]:
			hud.toast("WASD — 촌장에게 가 보자. (Space)", 4.0))

func _popin_sequence() -> Array:
	# 팝인 순서: 집 → 엄마 → 촌장 → 항아리 → 나머지 → 나무들 → 슬라임들 (§B-4)
	var first: Array = []
	var pots: Array = []
	var rest: Array = []
	for c in base_root.get_children():
		if c is Interactable:
			match c.kind:
				"home": pass
				"mom": pass
				"chief": pass
				"pot": pots.append(c)
				_: rest.append(c)
		elif c is Sprite2D and not c.region_enabled:
			rest.append(c)
	for k in ["home", "chief"]:
		for c in base_root.get_children():
			if c is Interactable and c.kind == k:
				first.append(c)
	var trees: Array = []
	for c in field_root.get_children():
		if c is Sprite2D and not c.region_enabled:
			trees.append(c)
		elif c is Interactable:
			rest.append(c)
	var mons: Array = []
	for m in get_tree().get_nodes_in_group("monster"):
		if is_instance_valid(m):
			mons.append(m)
	return first + pots + rest + trees + mons

func _play_popin() -> float:
	# 뾱! 뾱! 뾱! — 스케일 0→1 바운스, 계단식 음정 (v3.8 §B-4)
	var seq := _popin_sequence()
	party.visible = false
	for n in seq:
		if is_instance_valid(n):
			n.visible = false
	var i := 0
	for n in seq:
		if not is_instance_valid(n):
			continue
		var delay := 0.35 + i * 0.07
		var pitch := 0.65 + minf(float(i) * 0.045, 1.2)
		get_tree().create_timer(delay).timeout.connect(_popin_node.bind(n.get_instance_id(), pitch))
		i += 1
	var total := 0.35 + i * 0.07 + 0.4
	get_tree().create_timer(total).timeout.connect(func():
		party.visible = true
		party.scale = Vector2(0.05, 0.05)
		Sfx.play("pop", 1.9)
		var tw := create_tween()
		tw.tween_property(party, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	return total + 0.3

func _popin_node(instance_id: int, pitch: float) -> void:
	var node := instance_from_id(instance_id) as CanvasItem
	if node == null:
		return
	node.visible = true
	node.scale = Vector2(0.05, 0.05)
	Sfx.play("pop", pitch)
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ================================================================ 타이틀 (v3.3 §B — "게임이 곧 메뉴다")

func _enter_title() -> void:
	_title_mode = true
	party.frozen = true
	hud.title_hide(true)
	party.teleport(Vector2(96, 100))
	# v3.5: 타이틀 = 씬 (scenes/title.tscn) — 로고·문구·새벽빛 전부 에디터에서 편집
	# v3.9 §B-5: 타이틀 배경은 항상 빈 초원 — 잔디만 남기고 전부 숨긴다 (시작 시 씬 리로드로 복원)
	party.visible = false
	for m in get_tree().get_nodes_in_group("monster"):
		if is_instance_valid(m):
			m.visible = false
	for c in base_root.get_children():
		if c is Sprite2D and c.region_enabled and c.texture != null \
				and c.texture.resource_path.contains("Grass"):
			continue
		if c is CanvasItem:
			c.visible = false
	for c in field_root.get_children():
		if c is Sprite2D and c.region_enabled:
			continue
		if c is CanvasItem:
			c.visible = false
	_title_layer = TITLE_SCENE.instantiate()
	add_child(_title_layer)
	var press: Label = _title_layer.get_node("%Press")
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
	# 로고는 상단으로 살짝 이동·축소 — 단일 연속 씬, 화면 교체감 금지 (§B-5)
	if _title_layer != null and is_instance_valid(_title_layer):
		var logo: Label = _title_layer.get_node_or_null("%Logo")
		if logo != null and logo.scale == Vector2.ONE:
			logo.pivot_offset = logo.size / 2.0
			var tw := create_tween()
			tw.set_parallel(true)
			tw.tween_property(logo, "scale", Vector2(0.72, 0.72), 0.3).set_trans(Tween.TRANS_QUAD)
			tw.tween_property(logo, "position:y", 44.0, 0.3).set_trans(Tween.TRANS_QUAD)
			var subl: Label = _title_layer.get_node_or_null("%Subtitle")
			if subl != null:
				tw.tween_property(subl, "modulate:a", 0.0, 0.25)
			var pressl: Label = _title_layer.get_node_or_null("%Press")
			if pressl != null:
				pressl.visible = false
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

# ================================================================ 마을 (좌⅓ — 건설된 세계가 곧 진행바)

func _build_village() -> void:
	for c in base_root.get_children():
		c.queue_free()
	base_nodes.erase("chief")
	var stage := _revival_stage()
	# 마을 바닥 — 유저 맵(village.png 216×360)이 있으면 그것을, 없으면 절차 잔디+광장
	var has_map: bool = _custom_bg(base_root, "res://assets/maps/village.png", Vector2.ZERO, Vector2(VILLAGE_W, ROOM.y))
	if not has_map:
		_repeat_sprite(base_root, "res://assets/tiles/Grass_Middle.png", Rect2(0, 0, VILLAGE_W, ROOM.y), Vector2.ZERO, Color(1, 1, 1))
		var plaza := Rect2(56, 116, 108, 160)
		if stage >= 1:
			plaza = Rect2(24, 72, 172, 236)
		if stage >= 2:
			plaza = Rect2(12, 48, 196, 276)
		_repeat_sprite(base_root, "res://assets/tiles/Path_Middle.png", Rect2(0, 0, plaza.size.x, plaza.size.y), plaza.position, Color(1, 1, 1))
	if stage >= 3 and not has_map:
		# 성벽 일부 (임시 도형) — 4단계에 완성 (유저 맵이면 유저가 그린다)
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
	if not has_map:
		for p in [Vector2(28, 320), Vector2(190, 320)]:
			_decor(base_root, "res://assets/objects/forest.png", p, Color(1, 1, 1))
	# 시작 오브젝트 — v4.2: 상단 HUD 스트립(y≤38)을 피해 아래로. 엄마·건물앞 NPC 삭제(심플)
	base_nodes["home"] = _add_thing(base_root, "home", Vector2(184, 108))  # 용사의 집 (우상단, 클리어)
	base_nodes["chief"] = _add_thing(base_root, "chief", Vector2(100, 150))
	_add_thing(base_root, "guide", Vector2(130, 152))  # v4.1: 튜토리얼 안내원
	base_nodes["gearshop"] = _add_thing(base_root, "gearshop", BUILD_POS["gearshop"])  # v4.3: 장비점(초반 강화)
	_add_thing(base_root, "warehouse", Vector2(30, 108))
	_add_thing(base_root, "redchest", Vector2(184, 300))
	var pot_n: int = mini(2 + Game.extra_pots * 2, POT_SPOTS.size())
	for i in pot_n:
		_add_thing(base_root, "pot", POT_SPOTS[i])
	if stage >= 2:
		_add_thing(base_root, "fountain", Vector2(108, 84))
	# v4.0 §B-4: 기물 — 구매한 것들이 마을을 물건으로 채운다
	if Game.fixtures["well"]:
		_add_thing(base_root, "well", BUILD_POS["well"])
	if Game.fixtures["lamppost"]:
		base_nodes["lamppost"] = _add_thing(base_root, "lamppost", BUILD_POS["lamppost"])
	if Game.fixtures["scarecrow"]:
		base_nodes["scarecrow"] = _add_thing(base_root, "scarecrow", BUILD_POS["scarecrow"])
	if Game.fixtures["frogstatue"]:
		_add_thing(base_root, "frogstatue", BUILD_POS["frogstatue"])
	# 영입된 주민들의 시설 + 주민 본인
	for r in RESIDENTS:
		if Game.residents.get(r["id"], false):
			_place_resident(r, false)
	if Game.fixtures.get("board", false):
		base_nodes["board"] = _add_thing(base_root, "board", BUILD_POS["board"])
	if Game.buildings.get("chest", false):
		_add_thing(base_root, "chest", Vector2(160, 300))
	# v4.0: 구매한 건물 + 입주 주민 ("건물이 서면 사람이 온다")
	for e in BUILD_CATALOG:
		if e["cat"] == "building" and Game.buildings.get(String(e["id"]), false):
			base_nodes[e["id"]] = _add_thing(base_root, String(e["id"]), BUILD_POS[e["id"]])  # v4.2: 건물만

func _place_resident(r: Dictionary, pop: bool) -> void:
	var b: String = r["building"]
	if b == "":
		# 건물 없는 주민 (어부 형제 등) — 사람만 선다
		var solo := _add_thing(base_root, "resident", r.get("pos", Vector2(200, 300)))
		solo.resident_name = r["name"]
		if pop:
			solo.spawn_pop()
		return
	var node := _add_thing(base_root, b, BUILD_POS[b])
	base_nodes[b] = node
	if pop:
		node.spawn_pop()
	# v4.2: 건물 앞 NPC 삭제 — 건물만으로 기능한다 (심플 이즈 베스트)

func join_count() -> int:
	# v3.2 §D: 합류 = 주민 + 동료 통합 (용사 제외. 촌장·엄마는 기본 거주자라 카운트 제외)
	return Game.resident_count() + Game.companion_count() - 1

func _revival_stage() -> int:
	return Game.revival_stage()

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

# v4.3: 유저가 직접 그린 배경 PNG가 있으면 절차 생성 대신 그것을 깐다.
# 규격 — 필드: 424×360 (res://assets/maps/field_0.png ~ field_5.png)
#        마을: 216×360 (res://assets/maps/village.png)
func _custom_bg(root: Node2D, path: String, at: Vector2, sz: Vector2) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var s := Sprite2D.new()
	s.texture = load(path)
	s.centered = false
	s.position = at
	# 규격이 달라도 지정 크기에 맞춰 늘린다 (유저가 대충 그려도 채워지게)
	var tex_sz := s.texture.get_size()
	if tex_sz.x > 0 and tex_sz.y > 0:
		s.scale = Vector2(sz.x / tex_sz.x, sz.y / tex_sz.y)
	root.add_child(s)
	return true

func _build_field(f: int) -> void:
	for c in field_root.get_children():
		c.queue_free()
	boss_node = null
	last_field = f
	Game.current_field = f
	var tint: Color = Game.FIELD_TINTS[f]
	var field_sz := Vector2(ROOM.x - VILLAGE_W, ROOM.y)
	if _custom_bg(field_root, "res://assets/maps/field_%d.png" % f, Vector2(VILLAGE_W, 0), field_sz):
		pass  # 유저 맵 사용 — 절차 잔디·장식 생략 (몬스터/오브젝트만 얹는다)
	else:
		_repeat_sprite(field_root, "res://assets/tiles/Grass_Middle.png", Rect2(0, 0, field_sz.x, field_sz.y), Vector2(VILLAGE_W, 0), tint)
		var decor_tex := "res://assets/objects/forest.png" if f <= 1 else "res://assets/objects/hill.png"
		var decor_n := 10 if f == 1 else 5
		if f == 4:
			decor_tex = "res://assets/objects/tower.png"
			decor_n = 4
		for i in decor_n:
			_decor(field_root, decor_tex, Vector2(randf_range(260, 560), randf_range(48, 316)), tint)
	# 밤 시야 (v3.4 §B-4) — 용사 중심 원형 시야만 밝고 바깥은 근암전. 마을은 전체 조명 유지
	_night_shade = Control.new()
	_night_shade.position = Vector2(VILLAGE_W, 0)
	_night_shade.size = Vector2(ROOM.x - VILLAGE_W, ROOM.y)
	_night_shade.clip_contents = true  # 어둠은 필드 밖으로 새지 않는다
	_night_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_night_shade.z_index = 50
	_night_shade.visible = false        # _process가 밤일 때만 켠다 (타이틀 = 항상 새벽)
	_night_shade.modulate.a = 0.0
	field_root.add_child(_night_shade)
	if _night_grad_tex == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(0.03, 0.05, 0.16, 0.0))   # 중심 = 등불 빛
		grad.set_color(1, Color(0.03, 0.05, 0.16, 1.0))   # 바깥 = 근암전
		grad.add_point(0.45, Color(0.03, 0.05, 0.16, 0.15))
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(0.5, 0.0)
		gt.width = 256
		gt.height = 256
		_night_grad_tex = gt
	_night_hole = TextureRect.new()
	_night_hole.texture = _night_grad_tex
	_night_hole.stretch_mode = TextureRect.STRETCH_SCALE
	_night_hole.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_night_shade.add_child(_night_hole)
	# 그라디언트 밖 영역을 채우는 근암전 판 4장 (구멍 텍스처가 못 덮는 곳)
	_night_fills = []
	for i in 4:
		var fill := ColorRect.new()
		fill.color = Color(0.03, 0.05, 0.16, 1.0)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_night_shade.add_child(fill)
		_night_fills.append(fill)
	# 행선지 이정표 — 첫 지배자를 쓰러뜨리면 나타난다
	if Game.signpost_seen:
		base_nodes["signpost"] = _add_thing(field_root, "signpost", Vector2(228, 190))
	# 검이 꽂힌 바위 (서사시 제 2절의 사건 — 어느 필드에서든 보인다)
	if Game.sword_rock >= 1:
		_spawn_sword_rock(false)
	# 로토의 방패 — 동굴 지배자를 쓰러뜨린 자리에 남는다 (v3.2 §B-7)
	if Game.bosses_defeated[2] and not Game.roto_shield:
		_add_thing(field_root, "rotoshield", Vector2(430, 120))
	# 수중(숨겨진 필드) = 전원 물고기화 (v3.4 §B-7)
	party.set_underwater(f == Game.HIDDEN_FIELD)
	# 수중 최심부 — 전설의 오의서 (v3.9 §B-3: 발견의 재미)
	if f == Game.HIDDEN_FIELD and not Game.arts_owned.has("tuna"):
		_add_thing(field_root, "artbook", Vector2(596, 300))
	# UI 챕터 틴트 (v3.7 §B) — 전투창 카드에 필드 기운을 22% 얹는다
	if hud != null:
		hud.windows_root.modulate = Color.WHITE.lerp(Game.FIELD_TINTS[f], 0.22)
	if hud != null:
		Music.play_field(f)  # 필드 변주 크로스페이드 (M1-b/c)
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
	tw.tween_callback(func():
		_swapping = false
		_field_arrival_voice(f))

func _field_arrival_voice(f: int) -> void:
	# 동굴 벽 처방 (v3.1 §B-6-4) — 벽이 먼저 말을 건다
	if f == 2 and not _cave_voice_done:
		_cave_voice_done = true
		Sfx.play("voice")
		hud.event("…동굴 벽에서 목소리가 스민다. 「기도와… 침대가… 벽을 넘게 하리라…」", 6.0)
	# 수중 진입 (드퀘11 오마주 — 숨겨진 필드의 보상)
	if f == Game.HIDDEN_FIELD and not _fish_voice_done:
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

	_golden_timer -= delta * (2.0 if (last_field == 3 or last_field == Game.HIDDEN_FIELD) else 1.0)
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
	if Game.up["requiem"] > 0 and Game.ghost_count() > 0:  # 성불의 종 (교회 업글, v3.9)
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
					hud.event("성불의 종이 울려 %s이(가) 되살아났다!" % Game.members[i]["name"], 3.5)
					break
	else:
		_requiem_timer = 0.0
	# 도적의 귀환 (서사시 제 4절의 드라마)
	if Game.thief_away and Game.playtime >= Game.thief_return_at:
		_thief_return()
	# 복수의 감시자 — 제한 시간 초과 시 감긴 눈 부활 (v3.7 §G)
	if _watcher_active and _watcher_deadline > 0.0 and Game.playtime >= _watcher_deadline:
		_watcher_revive()

	# ---------- v3.2 ----------
	# 밤낮 — 필드 장막 + 등불 시야 (v3.4 §B-4). 마을은 물들지 않는다
	if _night_shade != null and is_instance_valid(_night_shade):
		var nf := Game.night_frac()
		_night_shade.modulate.a = nf * 0.88  # 근암전
		_night_shade.visible = nf > 0.01
		if _night_shade.visible and _night_hole != null and is_instance_valid(_night_hole):
			var r := Game.lantern_radius()
			if Game.up["lantern"] >= 3:
				r += party._history.size() * 0.6  # 최종 단계 — 대열 전체가 빛의 뱀
			var ts := 256.0 * (r / 55.0)
			var center: Vector2 = party.head_pos - _night_shade.position
			_night_hole.size = Vector2(ts, ts)
			_night_hole.position = center - Vector2(ts, ts) / 2.0
			# 구멍 텍스처 밖 근암전 판 4장
			var L: Vector2 = _night_hole.position
			var S: Vector2 = _night_hole.size
			var W: Vector2 = _night_shade.size
			if _night_fills.size() == 4:
				_night_fills[0].position = Vector2(0, 0)
				_night_fills[0].size = Vector2(W.x, maxf(0.0, L.y))
				_night_fills[1].position = Vector2(0, L.y + S.y)
				_night_fills[1].size = Vector2(W.x, maxf(0.0, W.y - L.y - S.y))
				_night_fills[2].position = Vector2(0, L.y)
				_night_fills[2].size = Vector2(maxf(0.0, L.x), S.y)
				_night_fills[3].position = Vector2(L.x + S.x, L.y)
				_night_fills[3].size = Vector2(maxf(0.0, W.x - L.x - S.x), S.y)
	var night := Game.is_night()
	if night != _was_night:
		_was_night = night
		hud._update_top()
		Music.set_night(night)  # 밤 어레인지 크로스페이드 (M1-a)
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
	# 겹쳐보기 스택 — 스택 호버 = 스택 내 전체 창에 주시 버프 (v3.4 §B-1)
	var docked := _docked_windows()
	if _stack_active(docked.size()):
		var mp := get_viewport().get_mouse_position()
		var any_hov := false
		for w in docked:
			if w.get_global_rect().has_point(mp):
				any_hov = true
		for w in docked:
			if w.sim != null:
				w.sim.hovered = any_hov
	# 천리안 — 주시 중인 창의 이웃에게 절반 효과
	if Game.medal_on("clairvoyance"):
		var hov := -1
		for i in docked.size():
			if docked[i].sim != null and docked[i].sim.hovered:
				hov = i
		for i in docked.size():
			docked[i].sim.hovered_adj = hov >= 0 and absi(i - hov) == 1

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Game.save_game()

# ================================================================ input (몸=Space / 시선=클릭)

func _unhandled_input(event: InputEvent) -> void:
	if _title_mode:
		if event is InputEventKey and event.pressed and not event.echo:
			_title_space()  # PRESS ANY KEY (v3.9 §B-5)
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
		"weaponshop": return hud.open_weaponshop
		"signpost": return hud.open_gate
	return Callable()

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
	# 컷인 직후 — 전투창은 물론, 필드의 모든 적까지 휩쓴다 (v3.6: 그 정도는 되어야 합체기)
	get_tree().create_timer(0.5).timeout.connect(func():
		for w in windows:
			if not is_instance_valid(w) or w.closing or w.sim == null or w.sim.finished:
				continue
			if String(cd["id"]) == "frog":
				w.sim.combo_frogify()
			else:
				w.sim.combo_annihilate()
		_combo_field_sweep(String(cd["id"]))
		if String(cd["id"]) == "tuna":
			_rain_fish()
		Game.save_game())

func _combo_field_sweep(kind: String) -> void:
	# 필드 스윕 — 빛의 파도가 필드를 훑고, 창 밖의 몬스터도 휩쓸린다 (보스 제외)
	var wave := ColorRect.new()
	wave.color = Color(1.0, 0.95, 0.6, 0.5) if kind != "frog" else Color(0.5, 1.2, 0.5, 0.45)
	wave.position = Vector2(VILLAGE_W, 0)
	wave.size = Vector2(30, ROOM.y)
	wave.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wave.z_index = 60
	field_root.add_child(wave)
	var wtw := create_tween()
	wtw.tween_property(wave, "position:x", ROOM.x, 0.45).set_trans(Tween.TRANS_QUAD)
	wtw.tween_callback(wave.queue_free)
	# 파도가 닿는 순간 정산
	get_tree().create_timer(0.25).timeout.connect(func():
		var g_sum := 0
		var xp_sum := 0
		var n := 0
		for m in get_tree().get_nodes_in_group("monster"):
			if not is_instance_valid(m) or m.is_boss or not m.is_visible_in_tree():
				continue
			if kind == "frog":
				m.frogify()
				n += 1
			else:
				g_sum += int(m.def["gold"])
				xp_sum += int(m.def["exp"])
				n += 1
				hud.popup("+%d" % int(m.def["gold"]), m.global_position, UILib.COL_GOLD)
				m.queue_free()
		if n == 0:
			return
		if kind == "frog":
			hud.event("필드의 몬스터 %d마리가 홀려서 춤춘다! (건드리면 한 방)" % n, 4.0)
		else:
			g_sum = int(g_sum * Game.gold_multiplier())
			Game.add_gold(g_sum)
			hud.coin_burst(party.head_pos, 8)
			hud.fly_xp(party.head_pos, 5)
			hud.event("필드의 몬스터 %d마리를 쓸어버렸다!! +%d G" % [n, g_sum], 4.5)
			if Game.add_exp(xp_sum):
				hud.levelup_ritual(Game.level))

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
		tw.tween_callback(_finish_fish_drop.bind(f.get_instance_id()))

func _finish_fish_drop(instance_id: int) -> void:
	var fish := instance_from_id(instance_id) as Sprite2D
	if fish == null:
		return
	var g := maxi(1, int(randi_range(10, 25) * Game.gold_scale()))
	_gain_gold(g, fish.global_position, "coin", 2)
	fish.queue_free()

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
	tw.tween_callback(_finish_companion_walkin.bind(walker.get_instance_id(), id, join_msg))

func _finish_companion_walkin(instance_id: int, id: String, join_msg: String) -> void:
	var walker := instance_from_id(instance_id) as Sprite2D
	if walker != null:
		walker.queue_free()
	Game.own_companion(id)
	Sfx.play("fanfare_big")
	hud.event(join_msg, 4.0)
	if Game.party_ids.has(id):
		hud.toast("%s이(가) 일행에 들어왔다!" % Game.COMPANIONS[id]["name"], 3.0)
	else:
		hud.toast("자리가 없어 여관에서 기다린다. (여관 → 파티 편성)", 4.0)
	Game.save_game()

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
		"train":
			Sfx.play("bump")
			hud.open_training()
		"stable":
			Sfx.play("bump")
			hud.open_stable()
		"lamppost":
			hud.event("가로등이다. 밤이 조금 덜 무서워졌다.")
		"scarecrow":
			_bump_scarecrow(it)
		"guide":
			_bump_guide(it)
		"gearshop":
			Sfx.play("bump")
			hud.open_gearshop()
		"bank":
			Sfx.play("bump")
			hud.open_bank()
		"weaponshop":
			Sfx.play("bump")
			hud.open_weaponshop()
		"frogstatue":
			_bump_frogstatue(it)
		"swordrock":
			_bump_swordrock(it)
		"home":
			_bump_home(it)
		"mom":
			Sfx.play("bump")
			hud.event("엄마: 「%s, 밥은 먹고 다니니?」" % Game.hn(), 3.5, "mom")
		"well":
			_bump_well(it)
		"rotoshield":
			_bump_rotoshield(it)
		"artbook":
			Game.own_art("tuna")
			Sfx.play("fanfare_big")
			hud.event("전설의 오의서가 잠들어 있었다. [slam]…참치다.[/slam] (여관에서 장착)", 6.0)
			it.queue_free()
			Game.save_game()
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
	# 개구리는 은혜를 기억한다 — 누적 500G 저금 시 오의서 (v3.9 §B-3, 은행 연동 개그)
	Game.add_stat("frog_gold", moved)
	if int(Game.stats["frog_gold"]) >= 500 and Game.own_art("frog"):
		Sfx.play("fanfare_big")
		hud.event("석상이 눈을 번쩍! 오의서 「개구리의 왈츠」 를 뱉어냈다!!", 6.0)

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
			"tex": "res://assets/enemies/bat.png", "scale": 1.0, "tint": Color(0.5, 0.6, 0.8), "family": "undead",
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
		# v3.8 §B-6: 무기 "교체" — 강화 레벨은 목검에서 그대로 승계, 고유 보너스 +6
		Game.party_changed.emit()
		hud.event("검이… 뽑혔다!! 「%s」 — 목검의 세월이 그대로 깃든다!" % Game.weapon_name(0), 6.0)
		hud.popup("로토의 검!", it.global_position, UILib.COL_GOLD)
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
		hud.event("촌장: 「마왕은 이미 세계를 손에 넣었습니다. …그래도, 하시겠습니까?」", 6.0, "chief")
		return
	if _chief_wiped:
		_chief_wiped = false
		hud.event("촌장: 「…괜찮습니다. 다들 그렇게 시작합니다.」", 4.0, "chief")
		return
	# 공개 스케줄 2: 골드 50 → 부탁(주민 영입)이 열린다
	if not Game.ui_unlocked["quest"]:
		if Game.gold >= 50:
			hud.unlock_ui("quest")
			Sfx.play("fanfare_big")
			hud.event("촌장: 「마을을 되살려 주십시오. …사람이 필요합니다.」", 5.0, "chief")
			hud.open_chief()
		else:
			hud.event("촌장: 「골드를 조금 모아 오시면… 부탁드릴 일이 있습니다.」", 4.0, "chief")
		return
	hud.open_chief()

func _set_marker(key: String, on: bool, coin: bool) -> void:
	if base_nodes.has(key) and is_instance_valid(base_nodes[key]):
		base_nodes[key].set_alert(on, coin)

func _update_chief_alert() -> void:
	# v4.3: 마커 두 종류 — 부탁/해금은 "!"(퀘스트), 그냥 살 수 있으면 코인(쇼핑)
	if base_nodes.has("chief") and is_instance_valid(base_nodes["chief"]):
		var quest: bool = (not Game.ui_unlocked["desc"]) or (not Game.ui_unlocked["quest"] and Game.gold >= 50)
		# 촌장 부탁(주민 영입 가능) = "!", 건설만 가능 = 코인
		var has_ask := false
		if Game.ui_unlocked["quest"]:
			for r in candidate_residents():
				var c: Dictionary = r["cond"]
				if c.has("gold") and (not c.has("lv") or Game.level >= int(c["lv"])) and Game.gold >= int(c["gold"]):
					has_ask = true
		if quest or has_ask:
			base_nodes["chief"].set_alert(true, false)   # "!" 퀘스트
		else:
			base_nodes["chief"].set_alert(Game.ui_unlocked["quest"] and hud.marker_on("chief"), true)  # 코인
	for key in ["inn", "church", "shop", "smith", "train", "stable", "bank", "weaponshop", "board", "gearshop"]:
		_set_marker(key, hud.marker_on(key), true)  # 건물 구매 = 코인
	if base_nodes.has("scarecrow") and is_instance_valid(base_nodes["scarecrow"]):
		base_nodes["scarecrow"].set_alert(base_nodes["scarecrow"].is_ready, false)  # 준비 완료 = "!"

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
	var spawn_at := m.global_position  # v3.9 §B-4: 창은 싸움이 난 자리에 팝
	var count := randi_range(1, Game.max_enemies_per_window())
	if last_field == 2:
		count = maxi(count, randi_range(1, Game.max_enemies_per_window()))
	elif last_field == 3 or last_field == Game.HIDDEN_FIELD:
		count = 1  # 설원·수중의 정예는 홀로 다닌다
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
		defs.append(m.def)  # 처음 한 마리는 부딪힌 그 몬스터
		var unlocked: int = Game.posters_f[last_field] if last_field < 4 else 3
		for i in range(1, count):
			# v4.3: 서로 다른 종류가 섞여 나올 수 있다 (40%). 섞이면 전투창이 그라데이션
			if unlocked >= 1 and randf() < 0.4:
				var other := randi_range(0, unlocked)
				defs.append(_field_def(last_field, other, m.position.x + randf_range(-30, 30)))
			else:
				defs.append(m.def)
	m.queue_free()
	_open_battle(defs, false, spawn_at)

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
			"tex": atlas, "scale": 1.0, "tint": Color(1, 0.85, 0.85), "family": "undead",
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
	# 곡괭이 (촌장 업글, v3.9 — 광부 패시브의 이관)
	g = int(g * (1.0 + 0.3 * Game.up["pickaxe"]))
	var medal_chance: float = 0.10 + 0.05 * Game.up["pickaxe"]
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
		hud.popup("작은 메달!", world_pos + Vector2(0, -12), UILib.COL_GOLD)
		hud.loot_toast("작은 메달 (%d개째)" % Game.medals_small, "small")

func _bump_recruit(it: Interactable) -> void:
	var cls := it.recruit_cls
	Game.own_companion(cls)
	Sfx.play("fanfare_big")
	var nm: String = Game.CLASS_DEFS[cls]["name"]
	hud.speech_bubble("%s: 「함께 가겠소!」" % nm, it.global_position + Vector2(0, -20), 3.0)
	if Game.party_ids.has(cls):
		hud.event("%s이(가) 일행에 합류했다!" % nm, 3.5)
	else:
		hud.event("%s이(가) 동료가 됐다! 자리가 없어 여관에서 기다린다. (파티 편성)" % nm, 4.5)
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
	return []  # v3.9: 객원 부탁 폐지 — RESIDENTS로 통합

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
	walker.texture = load("res://assets/npcs/village_chief.png")
	walker.modulate = Color(randf_range(0.7, 1.0), randf_range(0.7, 1.0), randf_range(0.7, 1.0))
	walker.position = Vector2(108, 352)
	walker.offset = Vector2(0, -13)
	base_root.add_child(walker)
	hud.event("누군가 마을로 걸어 들어온다…", 2.5)
	# 건물 없는 주민(어부 형제)은 자기 자리로 걷는다 (v3.9)
	var walk_to: Vector2 = BUILD_POS[r["building"]] if r["building"] != "" else r.get("pos", Vector2(200, 300))
	var tw := create_tween()
	tw.tween_property(walker, "position", walk_to, 2.2)
	tw.tween_callback(_finish_resident_join.bind(walker.get_instance_id(), r.duplicate(true)))
	if r["id"] == "fishers":
		get_tree().create_timer(3.2).timeout.connect(func():
			if not Game.keys["sea"]:
				Game.keys["sea"] = true
				Sfx.play("fanfare_big")
				hud.event("어부 형제가 「바다의 노래」 를 가르쳐 줬다!! …이정표가 반응한다?", 6.0))

func _finish_resident_join(instance_id: int, resident: Dictionary) -> void:
	# 걷는 도중 부흥 재건축이 끼어들어도 해제된 노드를 캡처하지 않는다.
	var walker := instance_from_id(instance_id) as Sprite2D
	if walker != null:
		walker.queue_free()
	var building: String = resident["building"]
	if building == "" or not (base_nodes.has(building) and is_instance_valid(base_nodes[building])):
		_place_resident(resident, true)
	Sfx.play("build")
	hud.speech_bubble("「%s」" % String(resident["join"]), BUILD_POS.get(building, Vector2(108, 300)) + Vector2(12, -18), 3.5)
	hud.event(resident["join"], 4.0)
	_resident_companion(resident["id"])
	_check_revival()
	Game.save_game()

# ================================================================ 칭호 + 도전과제식 훈장 (v3.2 §B-8, §C)

func _grant_medal(id: String) -> void:
	if Game.own_medal(id):
		Game.mark_new(id)
		hud.loot_toast("훈장 「%s」 획득!" % Game.MEDAL_DEFS[id]["name"], "medal")  # v3.4 §B-10
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
	elif Game.residents.get("fishers", false) and not Game.medals_owned.has("fisher_pride"):
		_grant_medal("fisher_pride")
	elif Game.residents.get("father", false) and Game.up["heal_eye"] > 0 \
			and not Game.medals_owned.has("holy_pendant"):
		_grant_medal("holy_pendant")

func _resident_companion(_rid: String) -> void:
	pass  # v3.9: 주민은 주민, 동료는 동료 — 연동 폐지 (§B-2)

var _last_revival_stage := -1

func _check_revival() -> void:
	# 건설물 임계점 → 마을이 물리적으로 확장된다 (v4.0: 4단계)
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

const WIN_ZONE_MIN := Vector2(4, 44)     # 금지 구역: 상단 HUD 스트립 (§B-1)
const WIN_ZONE_MAX := Vector2(516, 198)  # 하단 대사 박스 영역 위까지

func _clamp_win(pos: Vector2) -> Vector2:
	return pos.clamp(WIN_ZONE_MIN, WIN_ZONE_MAX)

func _open_battle(defs: Array, boss: bool, at: Vector2 = Vector2.ZERO) -> void:
	# v4.2: 한 번 싸운 적은 이름을 안다 — 필드 호버 시 ??? → 이름
	for d in defs:
		if d is Dictionary and d.has("id"):
			Game.discovered["mon_" + String(d["id"])] = true
	var sim := BattleSim.new()
	sim.setup(defs, boss)
	var w: BattleWindow = BATTLE_WINDOW_SCENE.instantiate()  # v3.5: 씬 인스턴스
	if boss:
		w.setup(sim, Vector2(224, 128), true)
		w.position = Vector2(208, 56)
		party.frozen = true
		boss_fighting = true
		boss_field = last_field
		Music.set_boss(true)
	else:
		w.setup(sim, WIN, false)
		# 인카운트 지점 근방 스폰 — "어디서 싸움이 났는지"가 공간으로 읽힌다 (§B-4)
		var base := at if at != Vector2.ZERO else Vector2(randf_range(240, 500), randf_range(60, 180))
		w.position = _clamp_win(base - WIN / 2.0 + Vector2(randf_range(-14, 14), randf_range(-10, 10)))
	hud.windows_root.add_child(w)
	windows.append(w)
	w.clicked.connect(_on_window_clicked.bind(w))
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

var _stack_cycle := 0   # 스택 셔플 오프셋 (v3.4 §B-1)

var stack_on := false  # v3.9 §B-4: 겹쳐보기 = 소집 토글 (구매 후 사용)

func _stack_active(n: int) -> bool:
	return Game.up["stack"] > 0 and stack_on and n >= 2

func _docked_windows() -> Array:
	var docked: Array = []
	for w in windows:
		if is_instance_valid(w) and not w.is_boss and not w.closing:
			docked.append(w)
	return docked

func _relayout_windows() -> void:
	var docked := _docked_windows()
	var n := docked.size()
	if _stack_active(n):
		# 겹쳐보기 — 윈도우 카스케이드 스택 (뒤 창은 테두리만 빼꼼, 맨 앞이 주인공)
		var order: Array = []
		for i in n:
			order.append(docked[(i + _stack_cycle) % n])
		for k in n:
			var w: BattleWindow = order[k]
			w.apply_dock(Vector2(8 + k * 13, 40 + k * 9), WIN)
			hud.windows_root.move_child(w, k)  # 마지막 자식 = 맨 앞
		hud.update_stack_badge(n, Vector2(8 + (n - 1) * 13 + WIN.x - 6, 40 + (n - 1) * 9 - 6))
	else:
		# 기본 = 현장 스폰 유지 — 겹침만 밀어내기로 해소 (§B-4, 물리엔진 불필요)
		hud.update_stack_badge(0, Vector2.ZERO)
		for pass_i in 3:
			for i in n:
				for j in range(i + 1, n):
					var a: BattleWindow = docked[i]
					var b: BattleWindow = docked[j]
					var d := (b.position + WIN / 2.0) - (a.position + WIN / 2.0)
					var overlap_x := WIN.x + 6.0 - absf(d.x)
					var overlap_y := WIN.y + 6.0 - absf(d.y)
					if overlap_x > 0.0 and overlap_y > 0.0:
						if overlap_x < overlap_y:
							var push_x := overlap_x / 2.0 * (1.0 if d.x >= 0.0 else -1.0)
							a.position.x -= push_x
							b.position.x += push_x
						else:
							var push_y := overlap_y / 2.0 * (1.0 if d.y >= 0.0 else -1.0)
							a.position.y -= push_y
							b.position.y += push_y
		for i in n:
			docked[i].nudge_to(_clamp_win(docked[i].position))

func _on_window_clicked(w: BattleWindow) -> void:
	# 스택 클릭 = 순환 셔플 (뒤 창 확인)
	var n := _docked_windows().size()
	if _stack_active(n) and not w.is_boss:
		_stack_cycle = (_stack_cycle + 1) % maxi(1, n)
		Sfx.play("click")
		_relayout_windows()

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
		Music.set_boss(false)
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
	interval /= (1.0 + 0.4 * Game.up["golden_hands"])  # v4.3: 손길 업글 = 더 자주
	if Game.medal_on("metal_crown"):
		interval *= 0.4
	_golden_timer = interval

# ================================================================ 몬스터 스폰 (필드 좌→우 = 위험도)

func _field_def(field: int, mtier: int, x: float) -> Dictionary:
	var base: Dictionary = Game.MONSTER_DEFS[mtier]
	var t := Game.field_tier(field)
	var xf := 0.75 + ((x - VILLAGE_W) / (ROOM.x - VILLAGE_W)) * 0.6
	var elite: bool = field == 3 or field == Game.HIDDEN_FIELD  # 설원·수중 = 정예의 땅
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
		"family": "water" if field == Game.HIDDEN_FIELD else String(base.get("family", "slime")),
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
	var t := Game.field_tier(f)
	var def := {
		"id": "boss", "name": Game.BOSS_NAMES[f],
		"hp": int(300 * Game.tier_stat(t)),
		"atk": int(12 * Game.tier_atk(t)),
		"gold": int(500 * Game.tier_gold(t)),
		"exp": int(80 * Game.tier_exp(t)),
		"tex": BOSS_TEX[f], "scale": 1.0,
		"family": Game.BOSS_FAMILY[f],
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
		hud.event("지배자의 소굴을 알아냈다! 최심부에서 놈이 모습을 드러낸다…", 4.0)
	else:
		hud.event("%s의 지배자가 사는 곳을 알아냈다는 소문이다…" % Game.FIELD_NAMES[field], 4.0)

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
	# 설원의 지배자 = 복수(複數)의 감시자 — 전투창 6개가 곧 보스 (v3.7 §G)
	if last_field == 3:
		party.frozen = true
		boss_fighting = true
		boss_field = 3
		hud.event("[shake]복수(複數)의 감시자[/shake] — 눈들이 일제히 뜬다!!", 4.0)
		Music.set_boss(true)
		_begin_watcher(m.def)
		return
	hud.event("%s이(가) 나타났다! 모두가 지켜보는 결전이다!" % m.boss_name, 3.0)
	_open_battle([m.def], true)

# ================================================================ 복수의 감시자 (v3.7 §G — 창의 동시 관리 시험)

const WATCHER_EYES := 6
const WATCHER_REVIVE_SEC := 22.0
var _watcher_active := false
var _watcher_eyes: Array = []       # [{sim, window, down}]
var _watcher_deadline := -1.0       # 첫 눈이 감긴 뒤, 이 안에 전부 감기지 않으면 부활
var _watcher_base_def := {}

func _begin_watcher(base_def: Dictionary) -> void:
	_watcher_active = true
	_watcher_eyes = []
	_watcher_deadline = -1.0
	_watcher_base_def = base_def
	for k in WATCHER_EYES:
		_spawn_eye(k)

func _eye_def() -> Dictionary:
	return {
		"id": "watcher_eye", "name": "감시하는 눈",
		"hp": int(_watcher_base_def["hp"] * 0.22),
		"atk": int(maxf(1.0, _watcher_base_def["atk"] * 0.55)),
		"gold": int(_watcher_base_def["gold"] / 8.0),
		"exp": int(_watcher_base_def["exp"] / 8.0),
		"tex": "res://assets/enemies/slime_fly.png", "scale": 1.0,
		"family": "undead", "tint": Color(0.8, 0.7, 1.1),
	}

func _spawn_eye(k: int) -> void:
	# 3×2 그리드 + 살짝 기울여 겹침 (연기 레이어 — §F)
	var sim := BattleSim.new()
	sim.setup([_eye_def()], true)
	var w: BattleWindow = BATTLE_WINDOW_SCENE.instantiate()
	w.setup(sim, WIN, true)
	w.position = Vector2(226 + (k % 3) * 132 + randf_range(-4, 4), 52 + int(k / 3.0) * 100 + randf_range(-4, 4))
	w.rotation_degrees = randf_range(-3.0, 3.0)
	hud.windows_root.add_child(w)
	windows.append(w)
	w.tree_exiting.connect(_on_window_gone.bind(w))
	sim.member_hit.connect(_on_member_hit_fx.bind(w))
	var entry := {"sim": sim, "window": w, "down": false}
	_watcher_eyes.append(entry)
	sim.victory.connect(func(g: int, xp: int):
		_on_eye_down(entry, g, xp))

func _on_eye_down(entry: Dictionary, g: int, xp: int) -> void:
	entry["down"] = true
	Game.add_gold(g)
	Game.add_exp(xp)
	if is_instance_valid(entry["window"]):
		hud.coin_burst(entry["window"].position + entry["window"].size / 2.0, 3)
		entry["window"].close_after(0.6)
	var downs := 0
	for e in _watcher_eyes:
		if e["down"]:
			downs += 1
	if downs >= _watcher_eyes.size():
		_watcher_win()
	elif _watcher_deadline < 0.0:
		_watcher_deadline = Game.playtime + WATCHER_REVIVE_SEC
		hud.event("눈 하나가 감겼다. …남은 눈들이 [shake]꿈틀거린다[/shake]. 서둘러라!", 4.0)

func _watcher_win() -> void:
	_watcher_active = false
	_watcher_deadline = -1.0
	_watcher_eyes = []
	boss_fighting = false
	party.frozen = false
	Music.set_boss(false)
	hud.event("모든 눈이 감겼다. 감시자는 더 이상 아무것도 보지 못한다.", 4.5)
	_on_boss_defeated(3)

func _watcher_revive() -> void:
	# 시간 초과 — 감긴 눈들이 다시 뜬다 (시선 경제의 시험)
	_watcher_deadline = -1.0
	Sfx.play("boss", 1.2)
	hud.event("[shake]감긴 눈이 다시 떴다!![/shake]", 3.5)
	for e in _watcher_eyes.duplicate():
		if e["down"]:
			_watcher_eyes.erase(e)
	var need := WATCHER_EYES - _watcher_eyes.size()
	for k in need:
		_spawn_eye(k)

func _abort_watcher() -> void:
	_watcher_active = false
	_watcher_deadline = -1.0
	_watcher_eyes = []

func _on_boss_defeated(field: int) -> void:
	Game.bosses_defeated[field] = true
	if boss_node != null and is_instance_valid(boss_node):
		boss_node.queue_free()
	boss_node = null
	if field == Game.HIDDEN_FIELD:
		# 수중의 지배자 (숨겨진 필드의 끝) — 발견한 자의 보상
		Sfx.play("fanfare_big")
		var bonus_g := int(800 * Game.gold_scale())
		Game.add_gold(bonus_g)
		Game.medals_small += 5
		hud.event("수중의 지배자가 가라앉았다! 진주 보따리(%d G + 작은 메달 5개)를 손에 넣었다!" % bonus_g, 5.5)
		Sfx.play("palette")
		Game.save_game()
		return
	if field >= 4:
		Game.save_game()
		_play_ending()
		return
	# v3.4 훈장 재배선: 초원=바람 / 숲=불복종 / 동굴=무리 사냥꾼+일기토 / 설원=천리안
	var medal_by_field := ["wind_sign", "disobedience", "pack_hunter", "clairvoyance"]
	var mid: String = medal_by_field[clampi(field, 0, 3)]
	if Game.own_medal(mid):
		Sfx.play("fanfare_big")
		hud.event("훈장 「%s」 을 손에 넣었다!" % Game.MEDAL_DEFS[mid]["name"], 4.5)
	if field == 2 and Game.own_art("skeleton"):
		get_tree().create_timer(1.2).timeout.connect(func():
			hud.event("오의서 「명계의 행진」 을 손에 넣었다!! (여관에서 장착)", 5.5))
	if field == 2 and Game.own_medal("duel_manner"):
		get_tree().create_timer(2.0).timeout.connect(func():
			hud.event("훈장 「일기토의 예법」 도 함께 손에 넣었다!", 4.0))
	# 로토의 조각 (v3.4): 동굴 → 방패가 남는다 / 설원 → 투구 드랍
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
	Music.set_boss(false)
	Music.play_title()  # M4 — 타이틀/엔딩 겸용 (수미상관)
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
				_ending_cast_sprite("res://assets/npcs/village_chief.png",
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
	if _watcher_active:
		_abort_watcher()  # 감시자는 다음 도전을 기다린다
	Music.set_boss(false)
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

func catalog_entry(id: String) -> Dictionary:
	for e in BUILD_CATALOG:
		if e["id"] == id:
			return e
	return {}

func catalog_built(e: Dictionary) -> bool:
	if e["cat"] == "building":
		return Game.buildings.get(String(e["id"]), false)
	return Game.fixtures.get(String(e["id"]), false)

func catalog_unlocked(e: Dictionary) -> bool:
	# 게이트 미달 항목은 카탈로그에 아예 안 보인다 — 한 화면 원칙 (§D-②)
	if e.has("lv") and Game.level < int(e["lv"]):
		return false
	if e.has("needs") and not Game.buildings.get(String(e["needs"]), false):
		return false
	if e.has("clock") and not Game.clock_on():
		return false
	return true

func buy_catalog(id: String) -> bool:
	var e := catalog_entry(id)
	if e.is_empty() or catalog_built(e) or not catalog_unlocked(e):
		return false
	if not Game.try_spend(int(e["cost"])):
		Sfx.play("deny")
		return false
	Sfx.play("build")
	var node := _add_thing(base_root, String(e["id"]), BUILD_POS[e["id"]])
	node.spawn_pop()
	hud.event(String(e["join"]), 4.0)
	if e["cat"] == "building":
		Game.buildings[String(e["id"])] = true
		base_nodes[e["id"]] = node
		# v4.2: 건물이 서면 곧 기능이 열린다 (건물만으로 충분 — 입주 인물 삭제)
		Game.residents[String(e["npc"])] = true
	else:
		Game.fixtures[String(e["id"])] = true
		if String(e["id"]) in ["board", "lamppost", "scarecrow"]:
			base_nodes[e["id"]] = node
	_check_revival()
	Game.save_game()
	return true

func _npc_movein(npc_name: String, dest: Vector2) -> void:
	# 새 건물의 주인이 마을 밖에서 걸어 들어온다
	var walker := Sprite2D.new()
	walker.texture = load("res://assets/npcs/village_chief.png")
	walker.modulate = Color(randf_range(0.7, 1.0), randf_range(0.7, 1.0), randf_range(0.7, 1.0))
	walker.position = Vector2(108, 352)
	walker.offset = Vector2(0, -13)
	base_root.add_child(walker)
	var tw := create_tween()
	tw.tween_property(walker, "position", dest, 2.0)
	tw.tween_callback(_finish_npc_movein.bind(walker.get_instance_id(), npc_name, dest))

func _finish_npc_movein(instance_id: int, npc_name: String, dest: Vector2) -> void:
	var walker := instance_from_id(instance_id) as Sprite2D
	if walker != null:
		walker.queue_free()
	# 걷는 도중 부흥 재건축이 끼면 _build_village가 이미 NPC를 세워 뒀다.
	for c in base_root.get_children():
		if c is Interactable and c.kind == "resident" and c.position.distance_to(dest) < 6.0:
			return
	var npc := _add_thing(base_root, "resident", dest)
	npc.resident_name = npc_name
	npc.spawn_pop()
	Sfx.play("pop", 1.4)

func _bump_scarecrow(it: Interactable) -> void:
	# v4.1: 허수아비 = 단련 — 두드리면 30초간 전원 공격력 +25% (훈련소 연동)
	if not it.is_ready:
		hud.event("허수아비를 방금 두드렸다. 숨 좀 고르자…")
		return
	Sfx.play("hit")
	Game.buff_scarecrow()
	hud.popup("공격 ↑", it.global_position, UILib.COL_RED)
	hud.event("허수아비를 실컷 두드렸다! 몸이 후끈 달아오른다. (%d초간 공격력 +%d%%)"
		% [int(Game.SCARECROW_DUR), int((Game.SCARECROW_MULT - 1.0) * 100)], 4.0)
	it.start_cooldown(Game.SCARECROW_DUR)  # 버프 지속 = 쿨타임 (연장 스팸 방지)

const GUIDE_TIPS := [
	"전투창에 [color=#f5c542]마우스를 올리면[/color] 그 창의 아군이 힘을 내. 여러 창을 번갈아 주시하는 게 요령이야.",
	"[color=#f5c542]황금 슬라임[/color]이 나타나면 도망가기 전에 마구 문질러(클릭) 붙잡아! 교회 「황금의 손길」은 포획을 더 빠르게 해 줘.",
	"쓰러진 몬스터의 [color=#f5c542]수배서[/color]를 게시판에서 모으면 그 필드의 [color=#ef476f]지배자[/color]의 결계가 풀려.",
	"작은 [color=#f5c542]메달[/color]은 항아리·상자·발굴에서 나와. 메달왕에게 가져가면 훈장으로 바꿔 줘.",
	"[color=#f5c542]훈장[/color]은 도전과제처럼 습관이 모이면 얻어. 촌장 옆에서 여섯 개까지 달 수 있지.",
	"어부 형제의 [color=#f5c542]바다의 노래[/color]를 배우면… 이정표에 없던 길이 하나 열린다더군. (숨겨진 필드!)",
	"전설의 [color=#f5c542]오의서[/color]를 찾으면 여관에서 장착해. 게이지가 차면 필살기를 쏠 수 있어.",
	"교회에서 [color=#f5c542]겹쳐보기[/color]를 배우고 「소집」을 켜면, 창들이 깔끔하게 포개져. 후반 필수야.",
	"허수아비를 두드리면 잠깐 공격력이 오르니, [color=#ef476f]지배자[/color]와 붙기 직전에 들르면 좋아.",
	"밤이 오면 시야가 좁아져. 촌장의 [color=#f5c542]등불[/color]과 마을 가로등이 어둠을 밀어내지.",
]

func _bump_guide(it: Interactable) -> void:
	Sfx.play("bump")
	var tip: String = GUIDE_TIPS[_guide_i % GUIDE_TIPS.size()]
	_guide_i += 1
	hud.event("안내원: 「%s」" % tip, 6.0, "chief")

func build_board() -> void:
	# (v4.0: buy_catalog("board")가 표준 경로 — 직접 호출 호환용)
	Game.fixtures["board"] = true
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
	# v3.4 §B-9: 자율 이동 = 필드 한정. 마을 안은 언제나 수동
	if party.head_pos.x < VILLAGE_W + 6.0:
		return null
	# 회복이 필요하면 — 종착점은 마을 입구까지만
	if (Game.ghost_count() > 0 and Game.gold >= Game.revive_cost()) or Game.lowest_hp_ratio() < 0.35:
		return Vector2(VILLAGE_W - 12.0, 210.0)
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
