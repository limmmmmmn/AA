class_name AlertMarker
extends Node2D
## v4.1: 머리 위 "!" 마커 — 항상 건물보다 앞에 그려지도록 독립 노드 + 높은 z_index.
## (Interactable._draw에 직접 그리면 이웃 건물 스프라이트에 가려진다.)

var _t := 0.0
var top_y := -30.0   # 마커가 뜰 높이 (오브젝트가 지정)
var coin_mode := false:  # v4.3: false="!"(퀘스트) / true=코인(구매 가능)
	set(v):
		coin_mode = v
		queue_redraw()

func _ready() -> void:
	z_index = 3000
	z_as_relative = false   # 부모 z와 무관하게 항상 최상위 근처

func _process(delta: float) -> void:
	_t += delta
	if visible:
		queue_redraw()

func _draw() -> void:
	var ca := 0.8 + 0.2 * sin(_t * 4.0)
	var cy := top_y - (2.0 if fmod(_t, 0.5) < 0.25 else 0.0)
	if coin_mode:
		# v4.3: 금색 코인 — "여기서 뭔가 살 수 있다" (동전으로 또렷이 읽히게)
		var cc := Vector2(0, cy + 6.0)
		draw_circle(cc + Vector2(0, 1.0), 6.0, Color(0, 0, 0, 0.3 * ca))        # 그림자
		draw_circle(cc, 6.0, Color(0.72, 0.55, 0.12, ca))                      # 테두리(어두운 금)
		draw_circle(cc, 4.4, Color(1.0, 0.83, 0.29, ca))                       # 금 본체
		# 통화 표시 — 짧은 세로 막대(동전 안). 바처럼 안 보이게 원 안에 가둔다
		draw_rect(Rect2(cc.x - 0.8, cc.y - 2.4, 1.6, 4.8), Color(0.55, 0.4, 0.1, ca), true)
		var gl := 0.5 + 0.5 * sin(_t * 6.0)
		draw_circle(cc + Vector2(-2.0, -1.8), 1.1, Color(1, 1, 0.9, 0.9 * gl))  # 하이라이트
	else:
		# 금색 느낌표 — 퀘스트(부탁/해금/준비 완료)
		draw_rect(Rect2(-2, cy + 1, 4, 8), Color(0, 0, 0, 0.35 * ca), true)
		draw_rect(Rect2(-2, cy, 4, 8), Color(1.0, 0.83, 0.29, ca), true)
		draw_rect(Rect2(-2, cy + 10, 4, 3), Color(1.0, 0.83, 0.29, ca), true)
