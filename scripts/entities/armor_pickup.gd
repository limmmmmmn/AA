class_name ArmorPickup
extends FloatingPickup

const HP_BONUS: int = 5


func collect() -> void:
	RunState.collect_armor()
	queue_free()
