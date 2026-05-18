class_name Hero
extends Node2D

enum Direction { LEFT, RIGHT, DOWN, UP }

@onready var sprite: Sprite2D = $Sprite
@onready var body_area: Area2D = $BodyArea

const FRAME_LEFT: int = 0
const FRAME_FRONT: int = 1
const FRAME_BACK: int = 2

var direction: Direction = Direction.DOWN


func _ready() -> void:
	face(Direction.DOWN)


func face(dir: Direction) -> void:
	direction = dir
	sprite.rotation = 0.0
	match dir:
		Direction.LEFT:
			sprite.flip_h = false
			sprite.frame = FRAME_LEFT
		Direction.RIGHT:
			sprite.flip_h = true
			sprite.frame = FRAME_LEFT
		Direction.UP:
			sprite.flip_h = false
			sprite.frame = FRAME_BACK
		Direction.DOWN:
			sprite.flip_h = false
			sprite.frame = FRAME_FRONT


func set_moving(_is_moving: bool) -> void:
	pass


func step_once() -> void:
	pass


func overlapping_body_targets() -> Array[Node2D]:
	var targets: Array[Node2D] = []
	for area in body_area.get_overlapping_areas():
		var target: Node = area.get_parent()
		if target is Node2D:
			targets.append(target as Node2D)
	return targets
