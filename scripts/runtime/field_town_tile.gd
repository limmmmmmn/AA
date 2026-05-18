class_name FieldTownTile
extends Area2D

## Field tile that sends the party to town.
## Entering town is an escape: active battle windows are aborted by Main, so no
## pending combat rewards are paid out.

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

var _triggered: bool = false
var _revealed: bool = true
var _reveal_tween: Tween


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func reset() -> void:
	_triggered = false
	hide_until_revealed()


func hide_until_revealed() -> void:
	_revealed = false
	visible = false
	monitoring = false
	monitorable = false
	_collision_shape.disabled = true
	if _reveal_tween:
		_reveal_tween.kill()
	scale = Vector2.ONE
	modulate = Color.WHITE


func reveal_with_impact() -> void:
	if _revealed:
		return
	_revealed = true
	visible = true
	monitoring = false
	monitorable = false
	_collision_shape.disabled = true
	scale = Vector2(2.2, 0.35)
	modulate = Color(1.0, 0.92, 0.55, 0.0)
	if _reveal_tween:
		_reveal_tween.kill()
	_reveal_tween = create_tween()
	_reveal_tween.tween_property(self, "modulate:a", 1.0, 0.12)
	_reveal_tween.parallel().tween_property(self, "scale", Vector2(0.86, 1.18), 0.18)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	_reveal_tween.tween_property(self, "scale", Vector2(1.08, 0.94), 0.12)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_IN_OUT)
	_reveal_tween.tween_property(self, "scale", Vector2.ONE, 0.10)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	_reveal_tween.tween_callback(_enable_entry)


func _enable_entry() -> void:
	monitoring = true
	monitorable = true
	_collision_shape.disabled = false


func _on_body_entered(body: Node) -> void:
	if _triggered or not _revealed or body is not Player:
		return
	_triggered = true
	EventBus.town_entered.emit(self)
