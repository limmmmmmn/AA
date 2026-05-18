class_name EquipSlot
extends ColorRect

## A single equipment slot. Shows an ItemData icon when equipped.

const EMPTY_COLOR: Color = Color(0.66, 0.66, 0.68, 0.85)
const FILLED_COLOR: Color = Color(0.08, 0.1, 0.08, 0.92)

@onready var _icon: TextureRect = $Icon


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clear()


## Drop the slot back to the empty state. Convenience for "unequip" /
## "rebuild on party change" paths.
func clear() -> void:
	color = EMPTY_COLOR
	_icon.texture = null
	_icon.hide()
	tooltip_text = ""


func set_paint(c: Color) -> void:
	color = c


func set_item(item: ItemData) -> void:
	if item == null:
		clear()
		return
	color = FILLED_COLOR
	_icon.texture = item.icon
	_icon.visible = item.icon != null
	tooltip_text = _build_tooltip(item)


func _build_tooltip(item: ItemData) -> String:
	var lines: PackedStringArray = [item.display_name]
	if item.attack_bonus != 0:
		lines.append("공격력 +%d" % item.attack_bonus)
	if item.defense_bonus != 0:
		lines.append("방어력 +%d" % item.defense_bonus)
	if item.agility_bonus != 0:
		lines.append("민첩 +%d" % item.agility_bonus)
	if item.max_hp_bonus != 0:
		lines.append("최대 HP +%d" % item.max_hp_bonus)
	if item.max_mp_bonus != 0:
		lines.append("최대 MP +%d" % item.max_mp_bonus)
	return "\n".join(lines)
