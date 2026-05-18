class_name FieldShrine
extends Area2D

## Field-side trigger for the shrine recruit event. Mirrors FieldCampfire
## structure — body_entered → event_tile_triggered → main pops an
## EventWindow with the priest dialogue + recruit.

const EVENT_ID: StringName = &"shrine_priest"

@onready var _sprite: Sprite2D = $Sprite

var _triggered: bool = false
var _flicker_tween: Tween


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	add_to_group("event_tile")
	_start_flicker()


## Subtle vertical breathing so the shrine feels reverent / alive rather
## than a flat decoration. Quieter cadence than the campfire's flicker.
func _start_flicker() -> void:
	if _sprite == null:
		return
	if _flicker_tween and _flicker_tween.is_valid():
		_flicker_tween.kill()
	_flicker_tween = _sprite.create_tween().set_loops()
	_flicker_tween.tween_property(_sprite, "scale", Vector2(1.0, 1.04), 0.6)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_flicker_tween.tween_property(_sprite, "scale", Vector2(1.0, 0.97), 0.6)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func event_id() -> StringName:
	return EVENT_ID


func _on_body_entered(body: Node) -> void:
	if _triggered or body is not Player:
		return
	_triggered = true
	EventBus.event_tile_triggered.emit(self)


func consume() -> void:
	queue_free()
