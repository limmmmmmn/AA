extends Node

signal gold_changed(amount: int)
signal skill_unlocked(skill_id: StringName)
signal hero_attack_changed(amount: int)
signal armor_changed(equipped: bool)
signal companion_recruited_signal(type: StringName)
signal loot_inventory_changed()

const LOOT_VALUES: Array[int] = [1, 3, 9, 27, 81]
const LOOT_TIER_NAMES: Array[String] = ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const EQUIP_ATK_BONUSES: Array[int] = [1, 3, 9, 27, 81]
const EQUIP_HP_BONUSES: Array[int] = [2, 6, 18, 54, 162]
const HERO_BASE_HP: int = 10

const WEAPON_TYPES: Array[StringName] = [&"sword", &"dagger", &"staff", &"bow"]
const BODY_TYPES: Array[StringName] = [&"armor", &"shield", &"helmet"]
const ACCESSORY_TYPES: Array[StringName] = [&"ring", &"necklace"]

# Hero (knight class) — sword for weapon, body armor for HP.
const HERO_COMPATIBLE_WEAPONS: Array[StringName] = [&"sword"]
const HERO_COMPATIBLE_BODY: Array[StringName] = [&"armor", &"shield", &"helmet"]

var gold: int = 0
var experience: int = 0
var timer_bonus_seconds: int = 0
var hero_base_attack: int = 2
var sword_collected: bool = false
var armor_collected: bool = false
var companion_recruited: bool = false
var companion_type: StringName = &""
var loot_inventory: Array[Dictionary] = []
var unlocked: Dictionary = {
	&"movement": true,
	&"auto_battle": true,
}


func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)


func add_experience(amount: int) -> void:
	experience += amount


func is_unlocked(skill_id: StringName) -> bool:
	return unlocked.get(skill_id, false)


func hero_attack() -> int:
	var best: Dictionary = best_loot_in_types(HERO_COMPATIBLE_WEAPONS)
	if best.is_empty():
		return hero_base_attack
	var t: int = clampi(int(best.get("tier", 0)), 0, EQUIP_ATK_BONUSES.size() - 1)
	return hero_base_attack + EQUIP_ATK_BONUSES[t]


func hero_max_hp() -> int:
	var best: Dictionary = best_loot_in_types(HERO_COMPATIBLE_BODY)
	if best.is_empty():
		return HERO_BASE_HP
	var t: int = clampi(int(best.get("tier", 0)), 0, EQUIP_HP_BONUSES.size() - 1)
	return HERO_BASE_HP + EQUIP_HP_BONUSES[t]


func best_loot_of_type(type: StringName) -> Dictionary:
	var best: Dictionary = {}
	var best_tier: int = -1
	for item in loot_inventory:
		if item.get("type") == type:
			var t: int = int(item.get("tier", 0))
			if t > best_tier:
				best_tier = t
				best = item
	return best


func best_loot_in_types(types: Array[StringName]) -> Dictionary:
	var best: Dictionary = {}
	var best_tier: int = -1
	for item in loot_inventory:
		if not types.has(item.get("type")):
			continue
		var t: int = int(item.get("tier", 0))
		if t > best_tier:
			best_tier = t
			best = item
	return best


func hero_equipped_weapon() -> Dictionary:
	return best_loot_in_types(HERO_COMPATIBLE_WEAPONS)


func hero_equipped_body() -> Dictionary:
	return best_loot_in_types(HERO_COMPATIBLE_BODY)


func collect_sword() -> void:
	# Legacy hook — kept callable for backwards compat. Now adds Common sword to inventory.
	if sword_collected:
		return
	sword_collected = true
	add_loot(&"sword", 0)


func collect_armor() -> void:
	# Legacy hook — kept callable for backwards compat. Now adds Common armor to inventory.
	if armor_collected:
		return
	armor_collected = true
	add_loot(&"armor", 0)


func recruit_companion(type: StringName) -> void:
	if companion_recruited:
		return
	companion_recruited = true
	companion_type = type
	companion_recruited_signal.emit(type)


func reset_run_inventory() -> void:
	# Sell all loot at settlement — reset per-run equipment.
	# Permanent: gold, unlocked nodes, companion_recruited.
	sword_collected = false
	armor_collected = false
	experience = 0
	loot_inventory.clear()
	loot_inventory_changed.emit()
	hero_attack_changed.emit(hero_attack())
	armor_changed.emit(false)


func add_loot(type: StringName, tier: int) -> Dictionary:
	loot_inventory.append({"type": type, "tier": tier})
	var final_tier: int = _try_combine(type, tier)
	loot_inventory_changed.emit()
	hero_attack_changed.emit(hero_attack())
	armor_changed.emit(not hero_equipped_body().is_empty())
	return {"type": type, "starting_tier": tier, "final_tier": final_tier, "combined": final_tier > tier}


func _try_combine(type: StringName, starting_tier: int) -> int:
	var max_tier: int = LOOT_VALUES.size() - 1
	var current_tier: int = starting_tier
	while current_tier < max_tier:
		var count: int = _count_loot(type, current_tier)
		if count < 3:
			break
		var groups: int = count / 3
		var to_remove: int = groups * 3
		var i: int = loot_inventory.size() - 1
		while i >= 0 and to_remove > 0:
			var item: Dictionary = loot_inventory[i]
			if item.get("type") == type and int(item.get("tier", 0)) == current_tier:
				loot_inventory.remove_at(i)
				to_remove -= 1
			i -= 1
		current_tier += 1
		for _j in range(groups):
			loot_inventory.append({"type": type, "tier": current_tier})
	return current_tier


func _count_loot(type: StringName, tier: int) -> int:
	var count: int = 0
	for item in loot_inventory:
		if item.get("type") == type and int(item.get("tier", 0)) == tier:
			count += 1
	return count


func loot_value(item: Dictionary) -> int:
	var t: int = clampi(int(item.get("tier", 0)), 0, LOOT_VALUES.size() - 1)
	return LOOT_VALUES[t]


func loot_sell_base_value() -> int:
	var total: int = 0
	for item in loot_inventory:
		total += loot_value(item)
	return total


func loot_sell_multiplier() -> float:
	var mult: float = 1.0
	if is_unlocked(&"shop_haggle"):
		mult *= 1.5
	if is_unlocked(&"shop_merchant"):
		mult *= 2.0
	if is_unlocked(&"shop_baron"):
		mult *= 3.0
	return mult


func loot_sell_value() -> int:
	return int(round(float(loot_sell_base_value()) * loot_sell_multiplier()))


func loot_count_by_tier_type() -> Dictionary:
	# Returns {tier: {type: count}}
	var grouped: Dictionary = {}
	for item in loot_inventory:
		var t: int = int(item.get("tier", 0))
		var typ: StringName = item.get("type", &"sword")
		if not grouped.has(t):
			grouped[t] = {}
		grouped[t][typ] = int(grouped[t].get(typ, 0)) + 1
	return grouped


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
