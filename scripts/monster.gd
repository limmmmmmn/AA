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

func _process(delta: float) -> void:
	bump_cd = maxf(0.0, bump_cd - delta)
	_bob_t += delta * 5.0
	_sprite.position.y = 0.0 if asleep else -absf(sin(_bob_t)) * 2.0
	if is_boss:
		return  # 보스는 자리를 지킨다
	_wait -= delta
	if _wait <= 0.0:
		_wait = randf_range(1.5, 4.5)
		_move_target = _anchor + Vector2(randf_range(-34, 34), randf_range(-34, 34))
		_move_target = _move_target.clamp(Vector2(24, 34), Vector2(616, 330))
	var d := _move_target - position
	if d.length() > 2.0:
		position += d.normalized() * 12.0 * delta
		_sprite.flip_h = d.x < 0.0

func wake_up() -> void:
	asleep = false
	var tw := create_tween()
	modulate = Color(2, 2, 2)
	tw.tween_property(self, "modulate", Color(1, 1, 1), 0.5)

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
		return boss_name + ". 이 땅의 색은 저 녀석의 것이다."
	return FLAVORS.get(def.get("id", ""), "몬스터다.")

func pick_radius() -> float:
	return 22.0 if is_boss else 14.0
