class_name SwordPickup
extends Node2D

const ATTACK_BONUS: int = 2


func collect() -> void:
	RunState.collect_sword()
	queue_free()
