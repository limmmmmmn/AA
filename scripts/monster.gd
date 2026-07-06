class_name FieldMonster
extends Node2D
## 필드 몬스터 — 스폰 지점 주변을 어슬렁거린다. 파티가 들이받으면 전투창.

const FLAVORS := {
	"slime": "슬라임. 만만해 보인다.",
	"bat": "박쥐. 낮인데도 날아다닌다.",
	"angry": "성난 슬라임. 뭔가 화가 나 있다.",
	"cyclops": "외눈 괴수. 눈이 마주쳤다.",
	"mimic": "보물상자…가 아니다!",
}

var def: Dictionary = {}      # 필드 스케일 적용된 스탯
var tier := 1                 # 1~5 (필드 티어)
var is_boss := false
var boss_name := ""
var asleep := false           # 지배자 — 수배서 3장 전까지 잠들어 있다
var bump_cd := 0.0

var _sprite: Sprite2D
var _anchor := Vector2.ZERO
var _move_target := Vector2.ZERO
var _wait := 0.0
var _bob_t := 0.0

func setup(p_def: Dictionary, p_tier: int, boss: bool = false, p_boss_name: String = "") -> void:
	def = p_def
	tier = p_tier
	is_boss = boss
	boss_name = p_boss_name
	add_to_group("monster")
	add_to_group("hoverable")

func _ready() -> void:
	_anchor = position
	_move_target = position
	_sprite = Sprite2D.new()
	var tex: Texture2D = load(def["tex"]) if def["tex"] is String else def["tex"]
	_sprite.texture = tex
	_sprite.offset = Vector2(0, -tex.get_height() / 2.0)
	add_child(_sprite)
	if def.has("tint"):
		_sprite.self_modulate = def["tint"]
	if asleep:
		modulate = Color(0.5, 0.5, 0.6)
	_bob_t = randf() * TAU
	_wait = randf_range(0.5, 3.0)

func _draw() -> void:
	# 지배자의 결계 — 평소에도 "언젠가 깰 저것"이 시야에 있다 (v3.0 §B-4)
	if is_boss and asleep:
		var a := 0.35 + 0.15 * sin(_bob_t * 0.7)
		draw_arc(Vector2(0, -10), 22.0, 0, TAU, 24, Color(0.7, 0.4, 0.95, a), 1.5)
		draw_arc(Vector2(0, -10), 26.0, 0, TAU, 6, Color(0.7, 0.4, 0.95, a * 0.5), 1.0)

func _process(delta: float) -> void:
	bump_cd = maxf(0.0, bump_cd - delta)
	_bob_t += delta * 5.0
	_sprite.position.y = 0.0 if asleep else -absf(sin(_bob_t)) * 2.0
	if is_boss:
		if asleep:
			queue_redraw()  # 결계 일렁임
		return  # 보스는 자리를 지킨다
	_wait -= delta
	if _wait <= 0.0:
		_wait = randf_range(1.5, 4.5)
		_move_target = _anchor + Vector2(randf_range(-34, 34), randf_range(-34, 34))
		# 몬스터는 필드(우⅔)에서만 어슬렁 — 마을(좌⅓)은 침범 금지
		_move_target = _move_target.clamp(Vector2(236, 40), Vector2(620, 320))
	var d := _move_target - position
	if d.length() > 2.0:
		position += d.normalized() * 12.0 * delta
		_sprite.flip_h = d.x < 0.0

func wake_up() -> void:
	asleep = false
	var tw := create_tween()
	modulate = Color(2, 2, 2)
	tw.tween_property(self, "modulate", Color(1, 1, 1), 0.5)

var frogged := false

func frogify() -> void:
	# 개구리의 왈츠 (v3.6) — HP 1, 골드 2배로 홀린 채 춤춘다. 건드리면 한 방
	if frogged or is_boss:
		return
	frogged = true
	def = def.duplicate()
	def["hp"] = 1
	def["gold"] = int(def["gold"]) * 2
	def["name"] = "홀린 " + String(def["name"])
	if _sprite != null:
		_sprite.self_modulate = Color(0.5, 1.3, 0.5)
	var tw := create_tween()
	tw.set_loops(6)
	tw.tween_property(self, "scale", Vector2(1.15, 0.85), 0.12)
	tw.tween_property(self, "scale", Vector2.ONE, 0.12)

# ---------------------------------------------------------------- hover 인터페이스

func kind_key() -> String:
	return "boss_" + str(tier) if is_boss else "mon_" + String(def.get("id", "slime"))

func hover_name() -> String:
	return boss_name if is_boss else String(def.get("name", "몬스터"))

func flavor() -> String:
	if is_boss:
		if asleep:
			return boss_name + ". 깊이 잠들어 있다. …아직은."
		if tier >= 5:
			return "마왕. 세계를 손에 넣은 자다."
		if boss_name.contains("감시자"):
			return "감시자가 당신의 시선을 불쾌해한다."  # 시선 설정에 대한 유일한 농담 (v3.7 §G)
		return boss_name + ". 이 땅의 색은 저 녀석의 것이다."
	return FLAVORS.get(def.get("id", ""), "몬스터다.")

func pick_radius() -> float:
	return 22.0 if is_boss else 14.0
