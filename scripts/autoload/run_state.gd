extends Node

signal gold_changed(amount: int)
signal skill_unlocked(skill_id: StringName)

var gold: int = 0
var timer_bonus_seconds: int = 0
var unlocked: Dictionary = {
	&"movement": true,
}


func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)


func is_unlocked(skill_id: StringName) -> bool:
	return unlocked.get(skill_id, false)


func can_afford(cost: int) -> bool:
	return gold >= cost


func unlock(skill_id: StringName, cost: int) -> bool:
	if is_unlocked(skill_id):
		return false
	if gold < cost:
		return false
	gold -= cost
	unlocked[skill_id] = true
	timer_bonus_seconds += 1
	gold_changed.emit(gold)
	skill_unlocked.emit(skill_id)
	return true
