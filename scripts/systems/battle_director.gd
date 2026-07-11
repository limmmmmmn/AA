class_name BattleDirector
extends Node
## 모든 BattleSim을 10Hz 고정 스텝으로 진행하는 중앙 디렉터.

signal battle_count_changed(count: int)
signal speed_changed(multiplier: int)

const FIXED_STEP := 0.1

var speed_multiplier := 1
var _accumulator := 0.0
var _battles: Array[BattleSim] = []

func register_battle(sim: BattleSim) -> void:
	if sim == null or _battles.has(sim):
		return
	_battles.append(sim)
	battle_count_changed.emit(_battles.size())

func unregister_battle(sim: BattleSim) -> void:
	if not _battles.has(sim):
		return
	_battles.erase(sim)
	battle_count_changed.emit(_battles.size())

func set_speed(multiplier: int) -> void:
	var next := 2 if multiplier >= 2 else 1
	if speed_multiplier == next:
		return
	speed_multiplier = next
	speed_changed.emit(speed_multiplier)

func toggle_speed() -> void:
	set_speed(2 if speed_multiplier == 1 else 1)

func active_count() -> int:
	return _battles.size()

func snapshots() -> Array:
	var result: Array = []
	for sim in _battles:
		if sim != null and not sim.finished: result.append(sim.snapshot())
	return result

func _physics_process(delta: float) -> void:
	_accumulator += delta * speed_multiplier
	while _accumulator >= FIXED_STEP:
		_accumulator -= FIXED_STEP
		_step_all()

func _step_all() -> void:
	for sim in _battles.duplicate():
		if sim == null or sim.finished:
			continue
		sim.tick(FIXED_STEP)
	Game.battle_snapshots = snapshots()
