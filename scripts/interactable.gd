class_name Interactable
extends Node2D
## 마을/필드 오브젝트 — 항아리, 상자, 건물, NPC, 반짝이(발굴), 영입 대기 동료

var kind := ""            # pot / chest / inn / smith / church / board / chief / signpost / sparkle / recruit / warehouse / redchest / resident / fountain …
var passive := false      # 배회 중 자연 범프 대상인가 (항아리/상자/반짝이)
var is_ready := true      # 쿨타임 오브젝트용
var recruit_cls := ""     # kind == recruit
var resident_name := ""   # kind == resident (시설의 화신 — 마을에 서 있는 사람)
var show_alert := false:  # 머리 위 "!" — v4.1: 독립 마커 노드가 그린다 (z-order 앞)
	set(v):
		show_alert = v
		if _alert_node != null and is_instance_valid(_alert_node):
			_alert_node.visible = v
var _alert_node: AlertMarker = null

var _sprite: Sprite2D = null
var _cd := 0.0
var _cd_total := 0.0
var _t := 0.0

const TEXTURES := {
	"pot": "res://assets/objects/pot.png",
	"chest": "res://assets/objects/chest_1.png",
	"inn": "res://assets/objects/inn.png",
	"shop": "res://assets/objects/shop_1.png",
	"smith": "res://assets/objects/black_smith.png",
	"church": "res://assets/objects/tower.png",
	"chief": "res://assets/NPCs/village_chief.png",
	"castle": "res://assets/objects/castle.png",
	"casino": "res://assets/objects/shop_1.png",
	"bard": "res://assets/NPCs/village_chief.png",
	"gate": "res://assets/objects/castle.png",
}

func setup(p_kind: String, p_recruit_cls: String = "") -> void:
	kind = p_kind
	recruit_cls = p_recruit_cls
	add_to_group("hoverable")

func _ready() -> void:
	match kind:
		"cheatpot":  # DEBUG: 금색 치트 항아리
			_make_sprite("pot", Rect2(0, 0, 14, 15))
			_sprite.self_modulate = Color(2.2, 1.8, 0.3)
			_sprite.scale = Vector2(1.4, 1.4)
		"pot":
			passive = true
			_make_sprite("pot", Rect2(0, 0, 14, 15))
		"chest":
			passive = true
			_make_sprite("chest", Rect2(0, 0, 16, 18))
		"inn", "shop", "smith":
			_make_sprite(kind, Rect2())
		"church":
			_make_sprite("church", Rect2())
		"chief":
			_make_sprite("chief", Rect2())
		"casino":
			_make_sprite("casino", Rect2())
			_sprite.self_modulate = Color(0.9, 0.65, 1.0)  # 임시 — 보라 틴트 + 점멸 간판
		"weaponshop":
			_make_sprite("shop", Rect2())
			_sprite.self_modulate = Color(0.75, 0.8, 0.95)  # 임시 — 강철빛 무기점 (v3.4)
		"train":
			_make_sprite("inn", Rect2())
			_sprite.self_modulate = Color(1.0, 0.72, 0.5)   # 임시 — 주황 틴트 훈련소 (v4.0)
		"stable":
			_make_sprite("inn", Rect2())
			_sprite.self_modulate = Color(0.8, 0.62, 0.42)  # 임시 — 갈색 틴트 마구간 (v4.0)
		"bard":
			_make_sprite("bard", Rect2())
			_sprite.self_modulate = Color(0.65, 1.0, 0.75)  # 임시 — 초록 틴트 음유시인
		"castle":
			_make_sprite("castle", Rect2())
			_sprite.self_modulate = Color(0.45, 0.4, 0.55)
		"gate":
			_make_sprite("gate", Rect2())
		"exit", "signpost", "warehouse", "fountain", "bank", "frogstatue", "swordrock", "home", "well", "rotoshield":
			pass  # _draw로 그린다 (임시 도형)
		"mom":
			_make_sprite("chief", Rect2())
			_sprite.self_modulate = Color(1.05, 0.8, 0.85)  # 임시 — 엄마는 분홍 톤
		"redchest":
			_make_sprite("chest", Rect2(0, 0, 16, 18))
			_sprite.self_modulate = Color(1.0, 0.45, 0.45)  # 붉은 상자 — 마법의 열쇠로만
		"resident":
			# 주민 — 시설의 화신. 마을에 서 있는 사람 수가 곧 진행바
			_make_sprite("chief", Rect2())
			_sprite.self_modulate = Color(randf_range(0.65, 1.0), randf_range(0.65, 1.0), randf_range(0.65, 1.0))
		"medalking":
			_make_sprite("chief", Rect2())
			_sprite.self_modulate = Color(1.0, 0.85, 0.4)  # 금빛 — 메달왕
		"guide":
			_make_sprite("chief", Rect2())
			_sprite.self_modulate = Color(0.6, 0.95, 1.0)  # 하늘빛 — 튜토리얼 안내원 (v4.1)
		"recruit":
			passive = false
			var d: Dictionary = Game.CLASS_DEFS[recruit_cls]
			_sprite = Sprite2D.new()
			_sprite.texture = load(d["tex"])
			_sprite.hframes = 3
			_sprite.vframes = 4
			_sprite.frame = 1
			_sprite.offset = Vector2(0, -float(d["frame_h"]) / 2.0)
			add_child(_sprite)
		"sparkle", "board":
			pass  # _draw로 그린다
		"lamppost", "scarecrow":
			pass  # _draw로 그린다 (v4.0 기물)
	if kind == "sparkle":
		passive = true
	# v4.1: "!" 마커 = 독립 노드 (높은 z_index로 이웃 건물보다 항상 앞)
	_alert_node = AlertMarker.new()
	_alert_node.top_y = _alert_y()
	_alert_node.visible = show_alert
	add_child(_alert_node)

func _make_sprite(tex_key: String, region: Rect2) -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = load(TEXTURES[tex_key])
	if region.size != Vector2.ZERO:
		_sprite.region_enabled = true
		_sprite.region_rect = region
		_sprite.offset = Vector2(0, -region.size.y / 2.0)
	else:
		_sprite.offset = Vector2(0, -_sprite.texture.get_height() / 2.0)
	add_child(_sprite)

func _process(delta: float) -> void:
	_t += delta
	if _cd > 0.0:
		_cd -= delta
		if _cd <= 0.0:
			_set_ready(true)
	if kind in ["sparkle", "board", "casino", "bard", "smith", "exit", "gate", "chief", "signpost", "warehouse", "redchest", "fountain", "medalking", "bank", "frogstatue", "swordrock", "home", "well", "rotoshield", "lamppost", "scarecrow"]:
		queue_redraw()
	if kind == "recruit":
		_sprite.position.y = -absf(sin(_t * 3.0)) * 2.0
		queue_redraw()
	if kind == "resident":
		_sprite.position.y = -absf(sin(_t * 2.0 + position.x)) * 1.0

func _draw() -> void:
	match kind:
		"sparkle":
			var a := 0.55 + 0.45 * sin(_t * 5.0)
			var c := Color(1.0, 0.9, 0.4, a)
			var r := 3.0 + sin(_t * 5.0) * 1.5
			draw_line(Vector2(-r, 0), Vector2(r, 0), c, 1.5)
			draw_line(Vector2(0, -r), Vector2(0, r), c, 1.5)
			draw_circle(Vector2.ZERO, 1.5, Color(1, 1, 0.8, a))
		"board":
			# 나무 게시판 (임시 도형 — 나중에 png 교체)
			draw_rect(Rect2(-11, -20, 2, 20), Color("6a4420"), true)
			draw_rect(Rect2(9, -20, 2, 20), Color("6a4420"), true)
			draw_rect(Rect2(-13, -22, 26, 16), Color("8a5a30"), true)
			draw_rect(Rect2(-13, -22, 26, 16), Color("4a3018"), false, 1.0)
			var shown_field: int = clampi(Game.progress_tier() - 1, 0, 3)
			for i in 3:
				var col := Color(0.95, 0.92, 0.8) if i < Game.posters_f[shown_field] else Color(0.7, 0.65, 0.5)
				draw_rect(Rect2(-10 + i * 8, -19, 6, 9), col, true)
				draw_rect(Rect2(-9 + i * 8, -17, 4, 1), Color(0.3, 0.25, 0.2), true)
				draw_rect(Rect2(-9 + i * 8, -15, 4, 1), Color(0.3, 0.25, 0.2), true)
		"recruit":
			# 머리 위 "!" 말풍선
			var a := 0.7 + 0.3 * sin(_t * 4.0)
			draw_rect(Rect2(-2, -36, 4, 8), Color(1.0, 0.83, 0.29, a), true)
			draw_rect(Rect2(-2, -26, 4, 3), Color(1.0, 0.83, 0.29, a), true)
		"lamppost":
			# 가로등 (v4.0 기물 — 임시 도형): 밤이면 불이 켜지고 주변이 은은히 밝다
			draw_rect(Rect2(-1, -22, 2, 22), Color("4a4a58"), true)
			var lit: bool = Game.clock_on() and Game.is_night()
			if lit:
				draw_circle(Vector2(0, -24), 9.0, Color(1.0, 0.85, 0.4, 0.10))
				draw_circle(Vector2(0, -24), 16.0, Color(1.0, 0.85, 0.4, 0.05))
			draw_circle(Vector2(0, -24), 2.5, Color(1.0, 0.9, 0.5) if lit else Color("6a6a78"))
		"scarecrow":
			# 허수아비 (v4.0 기물 — 임시 도형): 준비되면 모자가 씰룩인다
			draw_rect(Rect2(-1, -18, 2, 18), Color("6a4420"), true)
			draw_rect(Rect2(-7, -14, 14, 2), Color("6a4420"), true)
			draw_circle(Vector2(0, -19), 3.0, Color("d8c890"))
			var hy := -23.0 - (absf(sin(_t * 4.0)) * 1.5 if is_ready else 0.0)
			draw_rect(Rect2(-4, hy, 8, 2), Color("8a5a30") if is_ready else Color("5a4a38"), true)
		"casino":
			# 점멸하는 간판 전구 (임시 도형)
			for i in 5:
				var on: bool = int(_t * 4.0 + i) % 2 == 0
				var c := Color(1.0, 0.85, 0.3) if on else Color(0.5, 0.25, 0.55)
				draw_circle(Vector2(-16 + i * 8, -52), 1.5, c)
		"bard":
			# ♪ 음표 (임시 도형)
			var ay := -30.0 - fmod(_t * 6.0, 10.0)
			var aa := clampf(1.0 - fmod(_t * 6.0, 10.0) / 10.0, 0.0, 1.0)
			draw_rect(Rect2(4, ay, 2, 6), Color(1.0, 0.9, 0.5, aa), true)
			draw_circle(Vector2(4, ay + 6), 2.0, Color(1.0, 0.9, 0.5, aa))
		"smith":
			# 화덕 불씨 — 벼릴 준비가 되면 타오른다
			if is_ready:
				var f := 1.5 + sin(_t * 8.0) * 0.7
				draw_circle(Vector2(-14, -6), f, Color(1.0, 0.55, 0.2, 0.9))
				draw_circle(Vector2(-14, -8), f * 0.5, Color(1.0, 0.85, 0.3, 0.9))
		"exit":
			# 귀환 이정표 — 왼쪽 화살표 (임시 도형)
			draw_rect(Rect2(-1, -18, 2, 18), Color("6a4420"), true)
			draw_rect(Rect2(-10, -20, 20, 8), Color("8a5a30"), true)
			draw_rect(Rect2(-10, -20, 20, 8), Color("4a3018"), false, 1.0)
			var a := 0.6 + 0.4 * sin(_t * 3.0)
			draw_colored_polygon(PackedVector2Array([Vector2(-8, -16), Vector2(-3, -19), Vector2(-3, -13)]), Color(1.0, 0.9, 0.5, a))
		"gate":
			# 성문 위 표식
			var ga := 0.5 + 0.5 * sin(_t * 2.5)
			draw_colored_polygon(PackedVector2Array([Vector2(0, -40), Vector2(-4, -34), Vector2(4, -34)]), Color(1.0, 0.83, 0.29, ga))
		"signpost":
			# 행선지 이정표 — 마을과 필드의 경계 (임시 도형)
			draw_rect(Rect2(-1, -20, 3, 20), Color("6a4420"), true)
			draw_rect(Rect2(-11, -22, 22, 8), Color("8a5a30"), true)
			draw_rect(Rect2(-11, -22, 22, 8), Color("4a3018"), false, 1.0)
			var sa := 0.6 + 0.4 * sin(_t * 3.0)
			draw_colored_polygon(PackedVector2Array([Vector2(9, -18), Vector2(4, -21), Vector2(4, -15)]), Color(1.0, 0.9, 0.5, sa))
			draw_rect(Rect2(-11, -13, 22, 6), Color("8a5a30"), true)
			draw_rect(Rect2(-11, -13, 22, 6), Color("4a3018"), false, 1.0)
		"warehouse":
			# 잠긴 창고 — 시작부터 보이는데 못 여는 것 (임시 도형)
			var opened_w: bool = Game.opened["warehouse"]
			draw_rect(Rect2(-14, -22, 28, 22), Color("6a4a30"), true)
			draw_rect(Rect2(-14, -22, 28, 22), Color("3a2818"), false, 1.5)
			draw_rect(Rect2(-14, -26, 28, 5), Color("8a5a30"), true)
			if opened_w:
				draw_rect(Rect2(-5, -14, 10, 14), Color("1a1a24"), true)  # 열린 문
			else:
				draw_rect(Rect2(-5, -14, 10, 14), Color("4a3018"), true)
				# 자물쇠
				var la := 0.7 + 0.3 * sin(_t * 2.0)
				draw_rect(Rect2(-3, -10, 6, 6), Color(0.85, 0.75, 0.3, la), true)
				draw_arc(Vector2(0, -10), 2.5, PI, TAU, 8, Color(0.85, 0.75, 0.3, la), 1.5)
		"redchest":
			if not Game.opened["redchest"]:
				var ra := 0.7 + 0.3 * sin(_t * 2.0)
				draw_rect(Rect2(-2, -8, 5, 5), Color(0.85, 0.75, 0.3, ra), true)
				draw_arc(Vector2(0, -8), 2.0, PI, TAU, 8, Color(0.85, 0.75, 0.3, ra), 1.5)
		"fountain":
			# 분수 — 마을 부흥의 증표 (임시 도형)
			draw_circle(Vector2(0, -3), 9.0, Color("9aa0aa"))
			draw_circle(Vector2(0, -3), 9.0, Color("5a606a"), false, 1.5)
			draw_circle(Vector2(0, -4), 5.0, Color(0.5, 0.75, 1.0))
			for i in 3:
				var ph := fmod(_t * 1.6 + i * 0.33, 1.0)
				var dy := -6.0 - ph * 8.0
				draw_circle(Vector2((i - 1) * 3.0, dy), 1.2, Color(0.6, 0.85, 1.0, 1.0 - ph))
		"medalking":
			# 왕관 (임시 도형)
			var ka := 0.8 + 0.2 * sin(_t * 3.0)
			draw_colored_polygon(PackedVector2Array([
				Vector2(-5, -28), Vector2(-5, -32), Vector2(-2.5, -29), Vector2(0, -33),
				Vector2(2.5, -29), Vector2(5, -32), Vector2(5, -28)]), Color(1.0, 0.83, 0.29, ka))
		"bank":
			# 은행 — 돌기둥 금고 (임시 도형, 나중에 png 교체)
			draw_rect(Rect2(-16, -24, 32, 24), Color("b8b2a0"), true)
			draw_rect(Rect2(-16, -24, 32, 24), Color("5a564a"), false, 1.5)
			draw_colored_polygon(PackedVector2Array([Vector2(-18, -24), Vector2(18, -24), Vector2(0, -33)]), Color("d0c8b0"))
			for i in 3:
				draw_rect(Rect2(-12 + i * 9, -20, 4, 16), Color("8a8474"), true)
			# 금화 표식
			var ba := 0.75 + 0.25 * sin(_t * 2.5)
			draw_circle(Vector2(0, -28), 2.5, Color(1.0, 0.83, 0.29, ba))
		"frogstatue":
			# 개구리 석상 — 입에 잔돈을 넣는다 (임시 도형)
			draw_circle(Vector2(0, -5), 6.0, Color("7a8a6a"))
			draw_circle(Vector2(0, -12), 4.5, Color("8a9a78"))
			draw_circle(Vector2(-2, -13), 1.2, Color("2a3020"))
			draw_circle(Vector2(2, -13), 1.2, Color("2a3020"))
			draw_rect(Rect2(-2.5, -10.5, 5, 1.5), Color("2a3020"), true)  # 입 (투입구)
			var fa := 0.5 + 0.5 * sin(_t * 3.0)
			draw_circle(Vector2(0, -18), 1.2, Color(1.0, 0.83, 0.29, fa))
		"home":
			# 용사의 집 (v3.2 §B-6 — 프롤로그의 발원지, 임시 도형)
			draw_rect(Rect2(-14, -20, 28, 20), Color("c8a878"), true)
			draw_rect(Rect2(-14, -20, 28, 20), Color("6a5138"), false, 1.5)
			draw_colored_polygon(PackedVector2Array([Vector2(-17, -20), Vector2(17, -20), Vector2(0, -31)]), Color("a05a3a"))
			draw_rect(Rect2(-4, -11, 8, 11), Color("5a3f28"), true)
			draw_rect(Rect2(5, -17, 6, 5), Color(1.0, 0.95, 0.6) if is_ready else Color("3a3448"), true)  # 불 켜진 창
			if is_ready:
				# 굴뚝 연기 — 뭔가 준비돼 있다
				for i in 2:
					var ph := fmod(_t * 0.8 + i * 0.5, 1.0)
					draw_circle(Vector2(-9.0 + sin(_t + i) * 2.0, -32.0 - ph * 7.0), 1.6, Color(0.9, 0.9, 0.9, 0.7 - ph * 0.6))
		"well":
			# 우물 (v3.2 §B-9 — 쿨타임 오브젝트 4호, 임시 도형)
			draw_circle(Vector2(0, -4), 8.0, Color("8a8478"))
			draw_circle(Vector2(0, -4), 5.0, Color("20242e") if is_ready else Color("3a3e48"))
			draw_rect(Rect2(-9, -18, 2, 12), Color("6a4420"), true)
			draw_rect(Rect2(7, -18, 2, 12), Color("6a4420"), true)
			draw_colored_polygon(PackedVector2Array([Vector2(-11, -18), Vector2(11, -18), Vector2(0, -24)]), Color("8a5a30"))
			if is_ready:
				var wla := 0.4 + 0.4 * sin(_t * 3.0)
				draw_circle(Vector2(0, -4), 2.0, Color(0.5, 0.75, 1.0, wla))
		"rotoshield":
			# 로토의 방패 (v3.2 §B-7 — 동굴 지배자가 지키던 것, 임시 도형)
			var sha := 0.75 + 0.25 * sin(_t * 2.0)
			draw_colored_polygon(PackedVector2Array([
				Vector2(-7, -18), Vector2(7, -18), Vector2(7, -8), Vector2(0, -2), Vector2(-7, -8)]),
				Color(0.35, 0.5, 0.9, sha))
			draw_colored_polygon(PackedVector2Array([
				Vector2(-5, -16), Vector2(5, -16), Vector2(5, -9), Vector2(0, -4.5), Vector2(-5, -9)]),
				Color(0.75, 0.8, 1.0, sha))
			for i in 2:
				var ph := fmod(_t * 1.2 + i * 0.5, 1.0)
				draw_circle(Vector2(sin(_t * 1.5 + i * 3.0) * 6.0, -16.0 - ph * 7.0), 1.0, Color(0.8, 0.9, 1.0, 1.0 - ph))
		"swordrock":
			# 검이 꽂힌 바위 (서사시 제 2절 — 임시 도형)
			draw_circle(Vector2(0, -4), 9.0, Color("7a7468"))
			draw_circle(Vector2(-4, -2), 5.0, Color("8a8478"))
			if Game.sword_rock < 2:
				# 검신 + 자루 — 은은히 빛난다
				var swa := 0.7 + 0.3 * sin(_t * 2.0)
				draw_rect(Rect2(-1, -22, 2, 14), Color(0.85, 0.9, 1.0, swa), true)
				draw_rect(Rect2(-4, -23, 8, 2), Color(0.9, 0.8, 0.4, swa), true)
				draw_rect(Rect2(-1, -27, 2, 4), Color(0.7, 0.55, 0.3, swa), true)
				for i in 2:
					var ph := fmod(_t * 1.2 + i * 0.5, 1.0)
					draw_circle(Vector2(sin(_t + i * 3.0) * 5.0, -20.0 - ph * 8.0), 1.0, Color(1.0, 0.95, 0.7, 1.0 - ph))
			else:
				draw_rect(Rect2(-1, -10, 2, 3), Color("4a4640"), true)  # 뽑힌 자리

# ---------------------------------------------------------------- 쿨타임

func _alert_y() -> float:
	# "!"가 뜰 높이 — 스프라이트가 있으면 그 위, 도형이면 대략치
	if _sprite != null and _sprite.texture != null:
		return -float(_sprite.texture.get_height()) - 8.0
	return -30.0

func start_cooldown(seconds: float) -> void:
	_cd = seconds
	_cd_total = seconds
	_set_ready(false)

func _set_ready(v: bool) -> void:
	is_ready = v
	if kind == "pot" and _sprite != null:
		_sprite.region_rect = Rect2(0, 0, 14, 15) if v else Rect2(14, 0, 14, 15)
	elif kind == "chest" and _sprite != null:
		_sprite.region_rect = Rect2(0, 0, 16, 18) if v else Rect2(16, 0, 16, 18)
	if v and (kind == "pot" or kind == "chest"):
		# 리스폰 반짝
		var tw := create_tween()
		modulate = Color(2, 2, 2)
		tw.tween_property(self, "modulate", Color(1, 1, 1), 0.3)

func spawn_pop() -> void:
	scale = Vector2(1.0, 0.05)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func castle_reveal() -> void:
	if _sprite != null:
		var tw := create_tween()
		tw.tween_property(_sprite, "self_modulate", Color(1, 1, 1), 2.0)

# ---------------------------------------------------------------- hover 인터페이스

func kind_key() -> String:
	if kind == "recruit":
		return "recruit_" + recruit_cls
	return kind

func hover_name() -> String:
	match kind:
		"pot": return "항아리"
		"chest": return "보물상자"
		"inn": return "여관"
		"shop": return "상점"
		"smith": return "대장간"
		"church": return "교회"
		"board": return "수배 게시판"
		"train": return "훈련소"
		"stable": return "마구간"
		"lamppost": return "가로등"
		"scarecrow": return "허수아비"
		"guide": return "마을 안내원"
		"chief": return "촌장"
		"castle": return "마왕성"
		"sparkle": return "반짝이는 땅"
		"casino": return "카지노"
		"bard": return "음유시인"
		"gate": return "성문"
		"exit": return "귀환 이정표"
		"signpost": return "행선지 이정표"
		"warehouse": return "잠긴 창고"
		"redchest": return "붉은 상자"
		"fountain": return "분수"
		"medalking": return "메달왕"
		"resident": return resident_name
		"cheatpot": return "치트 항아리"
		"bank": return "은행"
		"weaponshop": return "무기점"
		"frogstatue": return "개구리 석상"
		"swordrock": return "검이 꽂힌 바위"
		"home": return "용사의 집"
		"mom": return "엄마"
		"well": return "우물"
		"rotoshield": return "로토의 방패"
		"recruit": return Game.CLASS_DEFS[recruit_cls]["name"]
	return kind

func flavor() -> String:
	match kind:
		"pot":
			return "평범한 항아리다. 깨뜨리고 싶다." if is_ready else "산산조각났다. 속이 후련하다."
		"chest":
			if not is_ready:
				return "텅 빈 상자다. 다음을 기다리자."
			return "보물상자다. …정말 보물상자겠지?" if Game.progress_tier() >= 2 else "보물상자다. 두근거린다."
		"inn":
			return "여관이다. 일행을 뉘일 수 있다."
		"shop":
			return "상점이다. 좋은 물건이 있을 것 같다."
		"smith":
			return "대장간이다. 화덕이 달아올랐다." if is_ready else "대장간이다. 화덕이 식어 있다…"
		"casino":
			return "카지노다. 어차피 세계는 이미 망했다."
		"bard":
			return "음유시인이다. 잠든 사이의 이야기를 안다."
		"gate":
			return "성문이다. 바깥은 지배자들의 땅이다. (Space)"
		"exit":
			return "기지로 돌아가는 길이다. (Space)"
		"church":
			return "교회다. 경건한 기운이 감돈다."
		"board":
			return "수배 게시판. 위험한 놈들을 불러들일 수 있다."
		"chief":
			return "촌장이다. 마을의 모든 일이 그에게 모인다. (Space)"
		"castle":
			return "마왕성. 저곳의 문은 아직 굳게 닫혀 있다."
		"sparkle":
			if Game.current_field == 3:
				return "진주조개다! 입을 꾹 다물고 있다." if Game.up["shovel"] > 0 else "진주조개다. …열 도구가 없다."
			return "뭔가 묻혀 있는 것 같다…" if Game.up["shovel"] == 0 else "뭔가 묻혀 있다! 파 보자."
		"signpost":
			return "행선지 이정표. 필드를 갈아끼울 수 있다. (Space)"
		"warehouse":
			if Game.opened["warehouse"]:
				return "창고다. 이제 텅 비었다."
			return "잠긴 창고다. 도둑의 열쇠가 필요해 보인다."
		"redchest":
			if Game.opened["redchest"]:
				return "붉은 상자다. 이미 열었다."
			return "붉은 상자다. 마법의 열쇠가 필요해 보인다."
		"fountain":
			return "분수다. 마을이 살아났다는 증거."
		"medalking":
			return "메달왕. 작은 메달이라면 사족을 못 쓴다."
		"resident":
			return "%s. 마을의 일원이 되었다." % resident_name
		"cheatpot":
			return "치트 항아리. 두드릴 때마다 1000 G. (디버그)"
		"bank":
			return "은행이다. 예금은 전멸해도 안전하다. (Space)"
		"weaponshop":
			return "무기점이다. 골드가 곧 공격력이 되는 곳. (Space)"
		"frogstatue":
			return "개구리 석상. 잔돈을 넣어 달라는 표정이다. (Space)"
		"home":
			return "…엄마 생각이 난다. (Space)"
		"mom":
			return "엄마다. 아침마다 용사를 깨워 준 사람."
		"well":
			return "우물이다. 들여다보고 싶다. (Space)" if is_ready else "우물. 방금 들여다봤다."
		"train":
			return "훈련소다. 기합 소리가 들린다."
		"stable":
			return "마구간이다. 여물 냄새가 난다."
		"lamppost":
			return "가로등이다. 밤을 기다리고 있다." if not (Game.clock_on() and Game.is_night()) else "가로등이 마을을 밝히고 있다."
		"scarecrow":
			return "허수아비다. 두드리면 몸이 달아오른다. (Space)" if is_ready else "허수아비를 방금 두드렸다."
		"guide":
			return "마을 안내원이다. 궁금한 걸 물어보자. (Space)"
		"rotoshield":
			return "전설의 방패가 빛나고 있다…! (Space)"
		"swordrock":
			if Game.sword_rock >= 2:
				return "검이 뽑힌 바위. 이야기는 이루어졌다."
			return "바위에 검이 꽂혀 있다. …서사시의 그 검인가?"
		"recruit":
			match recruit_cls:
				"knight": return "떠돌이 기사. 방패가 듬직하다."
				"warrior": return "떠돌이 전사. 도끼가 근질거려 보인다."
				"mage": return "떠돌이 마법사. 지팡이가 근질거려 보인다."
				"priest": return "떠돌이 사제. 일행을 걱정스레 보고 있다."
				"monkf": return "떠돌이 무도가. 주먹을 풀고 있다."
	return "…"

func passive_active() -> bool:
	# 배회 중 자연 범프 가능? (반짝이는 삽이 있어야)
	if not passive or not is_ready:
		return false
	if kind == "sparkle" and Game.up["shovel"] == 0:
		return false
	return true

func pick_radius() -> float:
	match kind:
		"inn", "smith", "casino": return 28.0
		"church": return 24.0
		"castle", "gate": return 28.0
		"pot": return 12.0
		"chest", "board", "chief", "recruit", "bard", "exit", "signpost", "medalking", "resident": return 16.0
		"warehouse", "redchest": return 18.0
		"sparkle": return 12.0
		"fountain": return 14.0
		"bank": return 22.0
		"train", "stable": return 24.0
		"lamppost": return 10.0
		"guide": return 16.0
		"scarecrow": return 12.0
		"weaponshop": return 26.0
		"frogstatue": return 12.0
		"swordrock": return 16.0
		"home": return 20.0
		"mom": return 16.0
		"well": return 14.0
		"rotoshield": return 16.0
	return 16.0
