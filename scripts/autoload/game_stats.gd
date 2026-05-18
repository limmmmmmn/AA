extends Node

## Lightweight prototype telemetry. Listens to game signals and prints a
## run-end summary to the console; no gameplay code needs to know the details.

var _run_number: int = 0
var _run_ended: bool = false
var _stages_cleared: int = 0
var _enemies_killed: int = 0
var _total_damage_taken: int = 0
var _card_order: Array[StringName] = []
var _card_counts: Dictionary = {}  ## StringName -> int
var _card_names: Dictionary = {}   ## StringName -> String


func _ready() -> void:
	EventBus.stage_started.connect(_on_stage_started)
	EventBus.stage_cleared.connect(_on_stage_cleared)
	EventBus.enemy_defeated.connect(_on_enemy_defeated)
	EventBus.party_damage_taken.connect(_on_party_damage_taken)
	EventBus.card_purchased.connect(_on_card_purchased)
	EventBus.party_wiped.connect(_on_party_wiped)
	EventBus.run_cleared.connect(_on_run_cleared)


func _on_stage_started(stage_num: int) -> void:
	if stage_num == 1:
		_begin_run()


func _begin_run() -> void:
	_run_number += 1
	_run_ended = false
	_stages_cleared = 0
	_enemies_killed = 0
	_total_damage_taken = 0
	_card_order.clear()
	_card_counts.clear()
	_card_names.clear()
	for mod: ModifierData in ModifierDB.get_all():
		_card_order.append(mod.id)
		_card_counts[mod.id] = 0
		_card_names[mod.id] = mod.display_name


func _on_stage_cleared(stage_num: int) -> void:
	if stage_num > _stages_cleared:
		_stages_cleared = stage_num


func _on_enemy_defeated(_enemy: Node, _gold: int, _world_position: Vector2) -> void:
	_enemies_killed += 1


func _on_party_damage_taken(_member_index: int, amount: int) -> void:
	_total_damage_taken += amount


func _on_card_purchased(mod: ModifierData, _cost: int) -> void:
	if mod == null:
		return
	_card_names[mod.id] = mod.display_name
	_card_counts[mod.id] = int(_card_counts.get(mod.id, 0)) + 1


func _on_party_wiped() -> void:
	end_run("Died at Stage %d" % GameState.current_stage, "HP depleted")


func _on_run_cleared() -> void:
	end_run("Cleared", "cleared")


func end_run(result: String, cause: String) -> void:
	if _run_ended:
		return
	_run_ended = true
	var lines: PackedStringArray = []
	lines.append("=== Run #%d End ===" % _run_number)
	lines.append("Result: %s" % result)
	lines.append("Stages Cleared: %d" % _stages_cleared)
	lines.append("Total Enemies Killed: %d" % _enemies_killed)
	lines.append("Total Gold Earned: %d" % GameState.total_gold_earned)
	lines.append("Total Damage Taken: %d" % _total_damage_taken)
	lines.append("Cards Purchased:")
	for id: StringName in _card_order:
		lines.append("  - %s: %d times" % [_card_names.get(id, str(id)), _card_counts[id]])
	lines.append("Most Bought Card: %s" % _most_bought_card())
	lines.append("Cause of Death: %s" % cause)
	lines.append("Party at End: [%s]" % _party_names())
	lines.append("================")
	print("\n".join(lines))


func _most_bought_card() -> String:
	var best_name := "None"
	var best_count := 0
	for id in _card_counts.keys():
		var count := int(_card_counts[id])
		if count > best_count:
			best_count = count
			best_name = _card_names.get(id, str(id))
	return best_name


func _party_names() -> String:
	var names: PackedStringArray = []
	for i in GameState.party.size():
		var member: CharacterData = GameState.party[i]
		names.append("%s Lv.%d" % [member.display_name, GameState.party_level(i)])
	return ", ".join(names)
