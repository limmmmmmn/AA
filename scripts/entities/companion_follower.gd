class_name CompanionFollower
extends Node2D

const MAGE_TEXTURE: Texture2D = preload("res://assets/sprites/characters/mage_1.png")
const THIEF_TEXTURE: Texture2D = preload("res://assets/sprites/characters/thief_1.png")
const KNIGHT_TEXTURE: Texture2D = preload("res://assets/sprites/characters/knight_1.png")

const FOLLOW_GAP: float = 13.0
const FRAME_LEFT: int = 0
const FRAME_FRONT: int = 1
const FRAME_BACK: int = 2

enum Facing { LEFT, RIGHT, DOWN, UP }

@export var companion_type: StringName = &"mage"

@onready var sprite: Sprite2D = $Sprite

var _target: Node2D
var _facing: Facing = Facing.UP


func _ready() -> void:
	add_to_group(&"party")
	_apply_sprite()
	_apply_facing()


func bind_target(target: Node2D) -> void:
	_target = target
	if _target != null:
		position = _target.position + Vector2(0, FOLLOW_GAP)
		_facing = Facing.UP
		_apply_facing()
		z_index = int(round(position.y))


func set_companion_type(type: StringName) -> void:
	companion_type = type
	_apply_sprite()
	_apply_facing()


func _apply_sprite() -> void:
	if sprite == null:
		return
	match companion_type:
		&"mage":
			sprite.texture = MAGE_TEXTURE
		&"thief":
			sprite.texture = THIEF_TEXTURE
		&"knight":
			sprite.texture = KNIGHT_TEXTURE
		_:
			sprite.texture = MAGE_TEXTURE
	sprite.hframes = 3
	sprite.vframes = 1


func _apply_facing() -> void:
	if sprite == null:
		return
	sprite.rotation = 0.0
	match _facing:
		Facing.LEFT:
			sprite.flip_h = false
			sprite.frame = FRAME_LEFT
		Facing.RIGHT:
			sprite.flip_h = true
			sprite.frame = FRAME_LEFT
		Facing.UP:
			sprite.flip_h = false
			sprite.frame = FRAME_BACK
		Facing.DOWN:
			sprite.flip_h = false
			sprite.frame = FRAME_FRONT


func _facing_from_dir(dir: Vector2) -> Facing:
	if absf(dir.x) >= absf(dir.y):
		return Facing.LEFT if dir.x < 0.0 else Facing.RIGHT
	if dir.y < 0.0:
		return Facing.UP
	return Facing.DOWN


func _process(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var to_target: Vector2 = _target.position - position
	var distance: float = to_target.length()
	if distance <= FOLLOW_GAP:
		return
	var move_dir: Vector2 = to_target / distance
	var move_amount: float = distance - FOLLOW_GAP
	position += move_dir * move_amount
	var new_facing: Facing = _facing_from_dir(move_dir)
	if new_facing != _facing:
		_facing = new_facing
		_apply_facing()
	z_index = int(round(position.y))
