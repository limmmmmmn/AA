class_name FieldRecoveryOrb
extends Area2D

const DAMAGE_NUMBER_SCENE: PackedScene = preload("res://scenes/effects/damage_number.tscn")
const HP_TEXTURE: Texture2D = preload("res://assets/sprites/icons/hp_orb.png")
const MP_TEXTURE: Texture2D = preload("res://assets/sprites/icons/mp_orb.png")

@export var kind: StringName = &"hp"

@onready var _shadow: Polygon2D = $Shadow
@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

var _collected: bool = false
var _base_y: float = 0.0
var _shadow_base_y: float = 0.0
var _bob_time: float = 0.0
var _tween: Tween


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_apply_kind()
	_base_y = position.y
	_shadow_base_y = _shadow.position.y


func setup(orb_kind: StringName) -> void:
	kind = orb_kind
	if is_inside_tree():
		_apply_kind()


func reveal_with_pop() -> void:
	monitoring = false
	monitorable = false
	_collision_shape.disabled = true
	scale = Vector2(0.35, 0.35)
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.10)
	_tween.parallel().tween_property(self, "scale", Vector2(1.2, 0.82), 0.14)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.16)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_enable_pickup)


func _process(delta: float) -> void:
	if _collected:
		return
	_bob_time += delta
	var bob: float = sin(_bob_time * 5.4) * 1.8
	position.y = _base_y + bob
	_shadow.position.y = _shadow_base_y - bob


func _apply_kind() -> void:
	if _sprite == null:
		return
	_sprite.texture = MP_TEXTURE if kind == GameState.RECOVERY_ORB_MP else HP_TEXTURE


func _enable_pickup() -> void:
	monitoring = true
	monitorable = true
	_collision_shape.disabled = false


func _on_body_entered(body: Node) -> void:
	if _collected or body is not Player:
		return
	_collected = true
	var restored: int = GameState.collect_recovery_orb(kind)
	_spawn_pickup_popup(restored)
	monitoring = false
	monitorable = false
	_collision_shape.disabled = true
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 0.0, 0.18)
	_tween.tween_property(self, "scale", Vector2(1.45, 0.6), 0.18)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(queue_free)


func _spawn_pickup_popup(restored: int) -> void:
	var parent_node: Node = get_parent()
	if parent_node == null:
		return
	var num: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate()
	parent_node.add_child(num)
	num.global_position = global_position + Vector2(0, -12)
	num.z_index = 50
	if restored <= 0:
		num.setup_text("Full", Color(1.0, 1.0, 1.0, 1.0))
		return
	if kind == GameState.RECOVERY_ORB_MP:
		num.setup_text("+%d MP" % restored, Color(0.45, 0.72, 1.0, 1.0))
	else:
		num.setup_heal(restored)
