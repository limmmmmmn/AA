class_name CompanionPickup
extends FloatingPickup

const TYPE_MAGE: StringName = &"mage"
const TYPE_THIEF: StringName = &"thief"
const TYPE_KNIGHT: StringName = &"knight"

const MAGE_TEXTURE: Texture2D = preload("res://assets/sprites/characters/mage_1.png")
const THIEF_TEXTURE: Texture2D = preload("res://assets/sprites/characters/thief_1.png")
const KNIGHT_TEXTURE: Texture2D = preload("res://assets/sprites/characters/knight_1.png")

@export var companion_type: StringName = TYPE_MAGE

@onready var sprite: Sprite2D = $Visual/Sprite2D


func _ready() -> void:
	super._ready()
	if companion_type == &"":
		companion_type = _random_type()
	_apply_sprite()


func setup_random() -> void:
	companion_type = _random_type()
	if sprite != null:
		_apply_sprite()


func _random_type() -> StringName:
	var pool: Array[StringName] = [TYPE_MAGE, TYPE_THIEF, TYPE_KNIGHT]
	return pool[randi() % pool.size()]


func _apply_sprite() -> void:
	if sprite == null:
		return
	match companion_type:
		TYPE_MAGE:
			sprite.texture = MAGE_TEXTURE
			sprite.hframes = 3
			sprite.vframes = 1
		TYPE_THIEF:
			sprite.texture = THIEF_TEXTURE
			sprite.hframes = 3
			sprite.vframes = 1
		TYPE_KNIGHT:
			sprite.texture = KNIGHT_TEXTURE
			sprite.hframes = 3
			sprite.vframes = 1
	sprite.frame = 1


func collect() -> void:
	RunState.recruit_companion(companion_type)
	queue_free()
