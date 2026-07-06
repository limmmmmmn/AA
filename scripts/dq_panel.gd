@tool
class_name DQPanel
extends PanelContainer
## 드퀘식 창 — 이 게임의 모든 메뉴/HUD 창이 쓰는 공용 컴포넌트.
## v3.7 (GDD v3.5 §C 고증 정정): 굵은 외곽 테두리 없음.
## 짙은 남색 패널 + 가장자리 3px 안쪽 크림 선 1줄 (인셋 보더) + 라운드 + 그림자.
## 에디터에서 노드로 배치하고 인스펙터에서 색만 고르면 된다. (@tool = 에디터 미리보기)

## 인셋 선 색 (기본 크림 #f4f0e0 — 강조 창은 금색 #f5c542)
@export var border_color := Color("f4f0e0"):
	set(v):
		border_color = v
		queue_redraw()

## 창 배경색 (기본 짙은 남색 #1a1c2c, 필드가 은은히 비치는 불투명도)
@export var bg_color := Color(0.102, 0.11, 0.173, 0.93):
	set(v):
		bg_color = v
		_apply_style()

## 인셋 크림 선을 그릴까 (드퀘1 메뉴 창 문법)
@export var inner_line := true:
	set(v):
		inner_line = v
		queue_redraw()

func _init() -> void:
	_apply_style()

func _apply_style() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg_color
	s.set_corner_radius_all(3)
	s.set_content_margin_all(7)
	# 필드 위에 떠 있는 카드 느낌 — 하단 그림자
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 2
	s.shadow_offset = Vector2(0, 1)
	add_theme_stylebox_override("panel", s)

func _draw() -> void:
	# 가장자리에서 3px 안쪽 크림 선 1줄 (인셋 보더 — 드퀘1 구조 그대로)
	if not inner_line:
		return
	var r := Rect2(Vector2(3, 3), size - Vector2(6, 6))
	if r.size.x > 8.0 and r.size.y > 8.0:
		draw_rect(r, border_color, false, 1.0)
