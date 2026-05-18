class_name GoldPickup
extends FloatingPickup

const VALUE: int = 1


func collect() -> void:
	queue_free()
