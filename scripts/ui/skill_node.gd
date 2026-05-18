class_name SkillNode
extends Button

signal node_hovered(node: SkillNode)
signal node_exited(node: SkillNode)
signal node_unlocked(node: SkillNode)

const STATE_LOCKED: Color = Color(0.55, 0.55, 0.62)
const STATE_AFFORDABLE: Color = Color(0.98, 0.85, 0.20)
const STATE_OWNED: Color = Color(0.30, 0.85, 0.40)
const STATE_EMPTY: Color = Color(0.22, 0.22, 0.26)
const STATE_SELECTED: Color = Color(1.0, 1.0, 1.0)

@export var skill_id: StringName = &""
@export var skill_name: String = ""
@export_multiline var description: String = ""
@export var cost: int = 5

var _style_normal: StyleBoxFlat
var _style_hover: StyleBoxFlat
var _style_pressed: StyleBoxFlat
var _is_keyboard_selected: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(16, 16)
	size = Vector2(16, 16)
	pivot_offset = Vector2(8, 8)
	focus_mode = Control.FOCUS_NONE
	_setup_styles()
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	RunState.gold_changed.connect(_refresh.unbind(1))
	RunState.skill_unlocked.connect(_refresh.unbind(1))
	_refresh()


func is_empty() -> bool:
	return skill_id == &""


func _setup_styles() -> void:
	_style_normal = _make_style()
	_style_hover = _make_style()
	_style_pressed = _make_style()
	add_theme_stylebox_override(&"normal", _style_normal)
	add_theme_stylebox_override(&"hover", _style_hover)
	add_theme_stylebox_override(&"pressed", _style_pressed)
	add_theme_stylebox_override(&"focus", _style_hover)


func _make_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.set_border_width_all(1)
	style.border_color = Color(1, 1, 1, 1)
	return style


func _refresh() -> void:
	var bg: Color
	if is_empty():
		bg = STATE_EMPTY
	elif RunState.is_unlocked(skill_id):
		bg = STATE_OWNED
	elif RunState.can_afford(cost):
		bg = STATE_AFFORDABLE
	else:
		bg = STATE_LOCKED
	_style_normal.bg_color = bg.lightened(0.25) if _is_keyboard_selected else bg
	_style_hover.bg_color = bg.lightened(0.25)
	_style_pressed.bg_color = bg.darkened(0.25)
	_style_normal.border_color = STATE_SELECTED if _is_keyboard_selected else Color(1, 1, 1, 1)
	_style_hover.border_color = STATE_SELECTED
	_style_pressed.border_color = STATE_SELECTED
	_style_normal.set_border_width_all(2 if _is_keyboard_selected else 1)
	_style_hover.set_border_width_all(2)
	_style_pressed.set_border_width_all(2)


func set_keyboard_selected(is_selected: bool) -> void:
	_is_keyboard_selected = is_selected
	_refresh()


func activate() -> void:
	_on_pressed()


func _on_pressed() -> void:
	if is_empty():
		return
	if RunState.unlock(skill_id, cost):
		_pop_feedback()
		node_unlocked.emit(self)


func _on_mouse_entered() -> void:
	node_hovered.emit(self)


func _on_mouse_exited() -> void:
	node_exited.emit(self)


func reveal_pop(delay: float = 0.0) -> void:
	scale = Vector2.ZERO
	modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE * 1.18, 0.14).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.08).set_delay(delay)
	tween.chain().tween_property(self, "scale", Vector2.ONE, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _pop_feedback() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ONE * 1.35, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
