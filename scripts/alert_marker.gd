class_name AlertMarker
extends Node2D
## v4.1: 머리 위 "!" 마커 — 항상 건물보다 앞에 그려지도록 독립 노드 + 높은 z_index.
## (Interactable._draw에 직접 그리면 이웃 건물 스프라이트에 가려진다.)

var _t := 0.0
var top_y := -30.0   # 마커가 뜰 높이 (오브젝트가 지정)

func _ready() -> void:
	z_index = 3000
	z_as_relative = false   # 부모 z와 무관하게 항상 최상위 근처

func _process(delta: float) -> void:
	_t += delta
	if visible:
		queue_redraw()

func _draw() -> void:
	# 금색 느낌표 — 통통 튀는 2프레임 느낌 (전 오브젝트 1종 통일)
	var ca := 0.75 + 0.25 * sin(_t * 4.0)
	var cy := top_y - (2.0 if fmod(_t, 0.5) < 0.25 else 0.0)
	# 얇은 그림자(가독성) + 금색 본체
	draw_rect(Rect2(-2, cy + 1, 4, 8), Color(0, 0, 0, 0.35 * ca), true)
	draw_rect(Rect2(-2, cy, 4, 8), Color(1.0, 0.83, 0.29, ca), true)
	draw_rect(Rect2(-2, cy + 10, 4, 3), Color(1.0, 0.83, 0.29, ca), true)
