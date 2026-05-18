class_name LevelUpPanel
extends Control

signal modifier_chosen(member_index: int, modifier: ModifierData)

const CARD_SCENE: PackedScene = preload("res://scenes/ui/town2_card.tscn")

@onready var _title_label: Label = %TitleLabel
@onready var _cards: HBoxContainer = %Cards

var _member_index: int = -1
var _member_name: String = ""
var _offers: Array[ModifierData] = []
var _pending_setup: bool = false


func setup(member_index: int, member_name: String, offers: Array[ModifierData]) -> void:
	_member_index = member_index
	_member_name = member_name
	_offers = offers.duplicate()
	if is_inside_tree():
		_apply()
	else:
		_pending_setup = true


func _ready() -> void:
	if _pending_setup:
		_pending_setup = false
		_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()


func _apply() -> void:
	_title_label.text = "%s 레벨업 — 카드를 고르세요" % _member_name
	for child in _cards.get_children():
		child.queue_free()
	for mod: ModifierData in _offers:
		var card: Town2Card = CARD_SCENE.instantiate()
		card.custom_minimum_size = Vector2(108, 138)
		_cards.add_child(card)
		card.setup(mod, true)
		card.purchase_requested.connect(_on_card_pressed)
	if _cards.get_child_count() > 0:
		(_cards.get_child(0) as Control).call_deferred("grab_focus")


func _on_card_pressed(_card: Town2Card, mod: ModifierData) -> void:
	modifier_chosen.emit(_member_index, mod)
	queue_free()
