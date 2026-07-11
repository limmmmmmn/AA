class_name FormationNameplate
extends Button
## 전술판 이름표 — Godot 표준 Control 드래그 앤 드롭.

var member_id := ""
var hud: Hud
var drag_kind := "party_member"
var accepts_kind := "party_member"

func _get_drag_data(_at_position: Vector2) -> Variant:
	if drag_kind == "": return null
	var preview := Label.new()
	preview.text = text
	preview.modulate = Color(1.0, 0.85, 0.3)
	set_drag_preview(preview)
	return {"kind": drag_kind, "id": member_id}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("kind", "") == accepts_kind and data.get("id", "") != member_id

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if hud != null:
		hud._tactics_drop(String(data["kind"]), String(data["id"]), member_id)
