extends Node

signal gold_changed(amount: int)
signal skill_unlocked(skill_id: StringName)
signal hero_attack_changed(amount: int)
signal armor_changed(equipped: bool)
signal companion_recruited_signal(type: StringName)

var gold: int = 0
var timer_bonus_seconds: int = 0
var hero_base_attack: int = 2
var hero_attack_bonus: int = 0
var sword_collected: bool = false
var armor_collected: bool = false
var companion_recruited: bool = false
var companion_type: StringName = &""
var unlocked: Dictionary = {
	&"movement": true,
	&"auto_battle": true,
}


func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)


func is_unlocked(skill_id: StringName) -> bool:
	return unlocked.get(skill_id, false)


func hero_attack() -> int:
	return hero_base_attack + hero_attack_bonus


func collect_sword() -> void:
	if sword_collected:
		return
	sword_collected = true
	hero_attack_bonus += 2
	hero_attack_changed.emit(hero_attack())


func collect_armor() -> void:
	if armor_collected:
		return
	armor_collected = true
	armor_changed.emit(true)


func recruit_companion(type: StringName) -> void:
	if companion_recruited:
		return
	companion_recruited = true
	companion_type = type
	companion_recruited_signal.emit(type)


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
