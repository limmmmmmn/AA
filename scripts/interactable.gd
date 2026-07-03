class_name Interactable
extends Node2D
## 마을/필드 오브젝트 — 항아리, 상자, 건물, NPC, 반짝이(발굴), 영입 대기 동료

var kind := ""            # pot / chest / inn / shop / smith / church / board / chief / castle / sparkle / recruit
var passive := false      # 배회 중 자연 범프 대상인가 (항아리/상자/반짝이)
var is_ready := true         # 쿨타임 오브젝트용
var recruit_cls := ""     # kind == recruit
var chief_wiped := false  # 전멸 직후 촌장 대사 변주

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
		"bard":
			_make_sprite("bard", Rect2())
			_sprite.self_modulate = Color(0.65, 1.0, 0.75)  # 임시 — 초록 틴트 음유시인
		"castle":
			_make_sprite("castle", Rect2())
			_sprite.self_modulate = Color(0.45, 0.4, 0.55)
		"gate":
			_make_sprite("gate", Rect2())
		"exit":
			pass  # _draw로 그린다 (이정표)
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
	if kind == "sparkle":
		passive = true

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
	if kind in ["sparkle", "board", "casino", "bard", "smith", "exit", "gate"]:
		queue_redraw()
	if kind == "recruit":
		_sprite.position.y = -absf(sin(_t * 3.0)) * 2.0
		queue_redraw()

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

# ---------------------------------------------------------------- 쿨타임

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
		"chief": return "촌장"
		"castle": return "마왕성"
		"sparkle": return "반짝이는 땅"
		"casino": return "카지노"
		"bard": return "음유시인"
		"gate": return "성문"
		"exit": return "귀환 이정표"
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
			return "촌장이다. 재건 계획도를 품에 안고 있다. (Space)"
		"castle":
			return "마왕성. 저곳의 문은 아직 굳게 닫혀 있다."
		"sparkle":
			return "뭔가 묻혀 있는 것 같다…" if Game.up["shovel"] == 0 else "뭔가 묻혀 있다! 파 보자."
		"recruit":
			match recruit_cls:
				"warrior": return "떠돌이 전사. 함께 싸우고 싶어 한다."
				"mage": return "떠돌이 마법사. 지팡이가 근질거려 보인다."
				"priest": return "떠돌이 승려. 일행을 걱정스레 보고 있다."
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
		"inn", "smith", "casino": return 30.0
		"church": return 24.0
		"castle", "gate": return 28.0
		"pot": return 12.0
		"chest", "board", "chief", "recruit", "bard", "exit": return 16.0
		"sparkle": return 12.0
	return 16.0
