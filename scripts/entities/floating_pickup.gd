class_name FloatingPickup
extends Node2D

@export var bob_amplitude: float = 3.0
@export var bob_speed: float = 3.2

@onready var visual: Node2D = get_node_or_null("Visual") as Node2D
@onready var shadow: Polygon2D = get_node_or_null("Visual/Shadow") as Polygon2D

var _time: float = 0.0
var _phase: float = 0.0


func _ready() -> void:
	_phase = randf() * TAU


func _process(delta: float) -> void:
	_time += delta
	var wave: float = sin(_time * bob_speed + _phase)
	if visual != null:
		visual.position.y = -6.0 + wave * bob_amplitude
	if shadow != null:
		var squash: float = 1.0 - wave * 0.12
		shadow.scale = Vector2(squash, 1.0)
		shadow.modulate.a = 0.22 - wave * 0.04
