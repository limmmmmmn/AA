class_name ForgeGame
extends Control
## 대장간 리듬 미니게임 — 게임 전체에서 유일한 액티브 미니게임 (GDD §7)
## 화살표가 게이지를 왕복한다. 금색 존에서 클릭! 3회 두들겨 판정 합산 → +1/+2/+3

signal finished(result: int)

const W := 240.0
const H := 84.0
const BAR := Rect2(20, 44, 200, 12)
const PERFECT := 0.07   # 중심에서 ±
const GOOD := 0.21

var member_name := ""
var _swing := 0
var _score := 0.0
var _t := 0.0
var _speed := 1.1
var _done := false
var _judge_text := ""
var _judge_color := UILib.COL_WHITE
var _judge_t := 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	position = Vector2((640 - W) / 2.0, 130)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Sfx.play("build")

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta * _speed
	_judge_t = maxf(0.0, _judge_t - delta)
	queue_redraw()

func _arrow_pos() -> float:
	return pingpong(_t, 1.0)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UILib.COL_BG, true)
	draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), UILib.COL_GOLD, false, 2.0)
	_draw_text_line("%s — 두들겨라! (%d/3)" % [member_name, _swing + 1], Vector2(10, 16), UILib.COL_WHITE)
	if _judge_t > 0.0:
		_draw_text_line(_judge_text, Vector2(10, 30), _judge_color)
	# 게이지
	draw_rect(BAR, Color(0.12, 0.12, 0.18), true)
	var good_w := BAR.size.x * GOOD * 2.0
	draw_rect(Rect2(BAR.position.x + BAR.size.x * (0.5 - GOOD), BAR.position.y, good_w, BAR.size.y), Color(0.3, 0.3, 0.4), true)
	var perf_w := BAR.size.x * PERFECT * 2.0
	draw_rect(Rect2(BAR.position.x + BAR.size.x * (0.5 - PERFECT), BAR.position.y, perf_w, BAR.size.y), Color(0.65, 0.5, 0.1), true)
	draw_rect(BAR, UILib.COL_WHITE, false, 1.0)
	# 화살표
	var x := BAR.position.x + BAR.size.x * _arrow_pos()
	var tip := Vector2(x, BAR.position.y - 3)
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-4, -7), tip + Vector2(4, -7)]), UILib.COL_GOLD)
	_draw_text_line("망치를 클릭!", Vector2(10, size.y - 8), UILib.COL_GRAY)

func _draw_text_line(text: String, pos: Vector2, color: Color) -> void:
	draw_string(UILib.FONT_PX, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, UILib.FS, color)

func _gui_input(event: InputEvent) -> void:
	if _done or not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	accept_event()
	var d := absf(_arrow_pos() - 0.5)
	if d < PERFECT:
		_score += 1.0
		_judge_text = "완벽한 일격!"
		_judge_color = UILib.COL_GOLD
		Sfx.play("crit", 1.2)
	elif d < GOOD:
		_score += 0.5
		_judge_text = "좋은 소리다."
		_judge_color = UILib.COL_WHITE
		Sfx.play("hit", 1.1)
	else:
		_judge_text = "…빗나갔다."
		_judge_color = UILib.COL_GRAY
		Sfx.play("deny")
	_judge_t = 0.8
	_swing += 1
	_speed += 0.25
	if _swing >= 3:
		_done = true
		var result := 1
		if _score >= 2.5:
			result = 3
		elif _score >= 1.5:
			result = 2
		var tw := create_tween()
		tw.tween_interval(0.6)
		tw.tween_callback(func():
			finished.emit(result)
			queue_free())
