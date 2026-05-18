class_name SwordPickup
extends FloatingPickup

const ATTACK_BONUS: int = 2


func collect() -> void:
	RunState.collect_sword()
	queue_free()
