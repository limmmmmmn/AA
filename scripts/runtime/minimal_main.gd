extends Node2D

## Tiny "from zero" loop:
## small field -> lone hero -> 3, 2, 1 -> clear settlement -> continue.

@export var countdown_seconds: float = 3.0

@onready var _stage_label: Label = %StageLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _hero: Sprite2D = %Hero
@onready var _settlement: Control = %Settlement
@onready var _settlement_title: Label = %SettlementTitle
@onready var _settlement_body: Label = %SettlementBody
@onready var _continue_button: Button = %ContinueButton

var _stage: int = 0
var _time_left: float = 0.0
var _countdown_active: bool = false
var _clearing: bool = false


func _ready() -> void:
	_continue_button.pressed.connect(_on_continue_pressed)
	_settlement.visible = false
	_start_next_stage()


func _process(delta: float) -> void:
	if not _countdown_active:
		return
	_time_left = maxf(0.0, _time_left - delta)
	if _time_left <= 0.0:
		_finish_stage()
		return
	_timer_label.text = str(maxi(1, int(ceil(_time_left))))


func _start_next_stage() -> void:
	_stage += 1
	_time_left = countdown_seconds
	_countdown_active = true
	_clearing = false
	_settlement.visible = false
	_stage_label.text = "Stage %d" % _stage
	_timer_label.text = str(int(ceil(countdown_seconds)))
	_timer_label.visible = true
	_hero.position = Vector2(320, 184)
	_play_hero_stage_pop()


func _finish_stage() -> void:
	if _clearing:
		return
	_clearing = true
	_countdown_active = false
	_timer_label.text = "게임 클리어!"
	_show_settlement_after_pause()


func _show_settlement_after_pause() -> void:
	await get_tree().create_timer(0.65).timeout
	if not is_inside_tree():
		return
	_timer_label.visible = false
	_settlement_title.text = "게임 클리어!"
	_settlement_body.text = "Stage %d 정산" % _stage
	_settlement.visible = true
	_continue_button.grab_focus()


func _on_continue_pressed() -> void:
	_start_next_stage()


func _play_hero_stage_pop() -> void:
	_hero.scale = Vector2(0.75, 0.75)
	var tween: Tween = create_tween()
	tween.tween_property(_hero, "scale", Vector2.ONE, 0.22)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
