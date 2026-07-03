class_name Assistant
extends Node2D
## 조수 동물 — 마을/필드 자동화 담당 (동료 = 전투 / 조수 = 자동화, GDD §8)
## 스프라이트는 임시 코드 생성 (8×8) — 나중에 png 교체

const NAMES := {"monkey": "원숭이", "keeper": "상자지기", "pig": "꽃돼지"}
const FLAVORS := {
	"monkey": "원숭이. 항아리만 보면 신이 난다.",
	"keeper": "상자지기. 상자 여는 솜씨가 수상할 만큼 좋다.",
	"pig": "꽃돼지. 코를 킁킁대며 보물을 찾는다.",
}

var kind := ""
var main: Node2D
var home := Vector2.ZERO

var _sprite: Sprite2D
var _target: Node2D = null
var _wander := Vector2.ZERO
var _wait := 0.0
var _cd := 0.0
var _bob := 0.0

func setup(p_kind: String, p_main: Node2D, p_home: Vector2) -> void:
	kind = p_kind
	main = p_main
	home = p_home
	add_to_group("hoverable")

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = UILib._grid_to_tex(UILib.ASSIST_GRIDS[kind], 1)
	_sprite.offset = Vector2(0, -4)
	add_child(_sprite)
	_wander = home
	_bob = randf() * TAU

func _physics_process(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	_bob += delta * 6.0
	_sprite.position.y = -absf(sin(_bob)) * 1.5
	if kind == "pig" and main != null and main.party != null:
		home = main.party.head_pos  # 꽃돼지는 일행 곁을 맴돈다
	if _target != null and not is_instance_valid(_target):
		_target = null
	if _target == null and _cd <= 0.0:
		_target = _find_target()
	var dest := _wander
	if _target != null:
		dest = _target.global_position
	else:
		_wait -= delta
		if _wait <= 0.0:
			_wait = randf_range(1.5, 3.5)
			var roam := 60.0 if kind != "pig" else 300.0
			_wander = home + Vector2(randf_range(-roam, roam), randf_range(-roam, roam))
			_wander = Vector2(clampf(_wander.x, 30, 1890), clampf(_wander.y, 30, 1050))
	var d := dest - position
	if d.length() > 4.0:
		position += d.normalized() * 45.0 * delta
		_sprite.flip_h = d.x < 0.0
	elif _target != null:
		var t := _target
		_target = null
		_cd = 1.2
		if is_instance_valid(t) and main != null:
			main.assistant_collect(t)

func _find_target() -> Node2D:
	var want: String = {"monkey": "pot", "keeper": "chest", "pig": "sparkle"}[kind]
	var best: Node2D = null
	var best_d := 1e9
	for n in get_tree().get_nodes_in_group("hoverable"):
		if n is Interactable and n.kind == want and n.is_ready:
			var dd: float = global_position.distance_to(n.global_position)
			if dd < best_d:
				best_d = dd
				best = n
	return best

# ---------------------------------------------------------------- hover 인터페이스

func kind_key() -> String:
	return "asst_" + kind

func hover_name() -> String:
	return NAMES[kind]

func flavor() -> String:
	return FLAVORS[kind]

func pick_radius() -> float:
	return 10.0
