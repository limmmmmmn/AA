class_name EquipmentPickup
extends FloatingPickup

const TYPE_SWORD: StringName = &"sword"
const TYPE_DAGGER: StringName = &"dagger"
const TYPE_STAFF: StringName = &"staff"
const TYPE_BOW: StringName = &"bow"
const TYPE_ARMOR: StringName = &"armor"
const TYPE_SHIELD: StringName = &"shield"
const TYPE_HELMET: StringName = &"helmet"
const TYPE_RING: StringName = &"ring"
const TYPE_NECKLACE: StringName = &"necklace"

const ALL_TYPES: Array[StringName] = [
	TYPE_SWORD, TYPE_DAGGER, TYPE_STAFF, TYPE_BOW,
	TYPE_ARMOR, TYPE_SHIELD, TYPE_HELMET,
	TYPE_RING, TYPE_NECKLACE,
]

const TYPE_NAMES: Dictionary = {
	TYPE_SWORD: "검",
	TYPE_DAGGER: "단검",
	TYPE_STAFF: "지팡이",
	TYPE_BOW: "활",
	TYPE_ARMOR: "갑옷",
	TYPE_SHIELD: "방패",
	TYPE_HELMET: "투구",
	TYPE_RING: "반지",
	TYPE_NECKLACE: "목걸이",
}

const SWORD_TEXTURE: Texture2D = preload("res://assets/sprites/icons/sword_1.png")
const DAGGER_TEXTURE: Texture2D = preload("res://assets/sprites/icons/thief_sword.png")
const STAFF_TEXTURE: Texture2D = preload("res://assets/sprites/icons/mage_staff.png")
const BOW_TEXTURE: Texture2D = preload("res://assets/sprites/icons/bow_charm.png")
const ARMOR_TEXTURE: Texture2D = preload("res://assets/sprites/icons/armor.png")
const SHIELD_TEXTURE: Texture2D = preload("res://assets/sprites/icons/shield.png")
const HELMET_TEXTURE: Texture2D = preload("res://assets/sprites/icons/helmet.png")
const RING_TEXTURE: Texture2D = preload("res://assets/sprites/icons/ring.png")
const NECKLACE_TEXTURE: Texture2D = preload("res://assets/sprites/icons/necklace.png")

const TIER_COLORS: Array[Color] = [
	Color(0.88, 0.88, 0.88, 1.0),  # Common
	Color(0.4, 0.95, 0.4, 1.0),    # Uncommon
	Color(0.35, 0.65, 1.0, 1.0),   # Rare
	Color(0.85, 0.4, 1.0, 1.0),    # Epic
	Color(1.0, 0.65, 0.15, 1.0),   # Legendary
]

@export var loot_type: StringName = TYPE_SWORD
@export var tier: int = 0

@onready var sprite: Sprite2D = $Visual/Sprite2D


func _ready() -> void:
	super._ready()
	_apply_visual()


func setup(type: StringName, t: int) -> void:
	loot_type = type
	tier = t
	if sprite != null:
		_apply_visual()


static func texture_for_type(type: StringName) -> Texture2D:
	match type:
		TYPE_SWORD: return SWORD_TEXTURE
		TYPE_DAGGER: return DAGGER_TEXTURE
		TYPE_STAFF: return STAFF_TEXTURE
		TYPE_BOW: return BOW_TEXTURE
		TYPE_ARMOR: return ARMOR_TEXTURE
		TYPE_SHIELD: return SHIELD_TEXTURE
		TYPE_HELMET: return HELMET_TEXTURE
		TYPE_RING: return RING_TEXTURE
		TYPE_NECKLACE: return NECKLACE_TEXTURE
	return SWORD_TEXTURE


static func display_name_for_type(type: StringName) -> String:
	return TYPE_NAMES.get(type, "장비")


func _apply_visual() -> void:
	if sprite == null:
		return
	sprite.texture = texture_for_type(loot_type)
	sprite.modulate = TIER_COLORS[clampi(tier, 0, TIER_COLORS.size() - 1)]


func collect() -> Dictionary:
	var result: Dictionary = RunState.add_loot(loot_type, tier)
	queue_free()
	return result
