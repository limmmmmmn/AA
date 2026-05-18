class_name FieldCampfire
extends Area2D

## Field-side trigger for the campfire recruit event. Player walks in,
## emits event_tile_triggered, main pops an EventWindow that runs the
## scripted dialogue + recruit.

## Marker so the event window knows which kind of vignette to play.
const EVENT_ID: StringName = &"campfire_mage"

@onready var _sprite: Sprite2D = $Sprite

var _triggered: bool = false
var _flicker_tween: Tween


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	add_to_group("event_tile")
	_start_flame_flicker()


## Gentle vertical breathing so the sprite looks alive even at rest.
func _start_flame_flicker() -> void:
	if _sprite == null:
		return
	if _flicker_tween and _flicker_tween.is_valid():
		_flicker_tween.kill()
	_flicker_tween = _sprite.create_tween().set_loops()
	_flicker_tween.tween_property(_sprite, "scale", Vector2(1.0, 1.08), 0.38)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_flicker_tween.tween_property(_sprite, "scale", Vector2(1.0, 0.94), 0.38)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func event_id() -> StringName:
	return EVENT_ID


func _on_body_entered(body: Node) -> void:
	if _triggered or body is not Player:
		return
	_triggered = true
	EventBus.event_tile_triggered.emit(self)


## Called by Main once the dialogue resolves (success or skipped) to free
## the campfire so it doesn't keep retriggering.
func consume() -> void:
	queue_free()
