class_name StatBar
extends Panel

## Reusable horizontal bar: a background panel with a colored fill that
## stretches from the left edge by `ratio`, plus a text label overlay.
##
## Drives HP and EXP rows in HUD (and is generic enough to drop into any
## other "labeled progress" spot). Fill color + label alignment are @export
## so the same scene serves both flavors without code branches.
##
## "Juicy" drain: when the ratio drops, the fill snaps to the new value
## immediately ("팍 깎이고"), while a yellow ghost slice freezes at the old
## value for a beat ("깎인만큼 반짝거리다가") and then chases the fill down
## as its alpha fades ("주욱~~ 줄어드는거"). Recovery just snaps both.

@export var fill_color: Color = Color(0.84, 0.22, 0.22, 1)
@export_enum("Center", "Right", "Left") var label_alignment: int = 0

const GHOST_FLASH_COLOR: Color = Color(1.0, 0.95, 0.55, 1.0)
const GHOST_HOLD_DURATION: float = 0.18
const GHOST_DRAIN_DURATION: float = 0.45

@onready var _fill: ColorRect = %Fill
@onready var _label: Label = %BarLabel

var _ghost: ColorRect
var _current_ratio: float = 1.0
var _ghost_drain_tween: Tween
var _ghost_color_tween: Tween


func _ready() -> void:
	_fill.color = fill_color
	_label.horizontal_alignment = _alignment_to_godot(label_alignment)
	_build_ghost()


## Ghost is the afterimage that lingers in the just-drained slice. Layered
## *behind* the fill so the live value reads cleanly on top; the ghost only
## peeks out where the fill has already retreated.
func _build_ghost() -> void:
	_ghost = ColorRect.new()
	_ghost.color = GHOST_FLASH_COLOR
	_ghost.color.a = 0.0
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.anchor_left = _fill.anchor_left
	_ghost.anchor_top = _fill.anchor_top
	_ghost.anchor_right = _fill.anchor_right
	_ghost.anchor_bottom = _fill.anchor_bottom
	_ghost.offset_left = _fill.offset_left
	_ghost.offset_top = _fill.offset_top
	_ghost.offset_right = _fill.offset_right
	_ghost.offset_bottom = _fill.offset_bottom
	add_child(_ghost)
	move_child(_ghost, _fill.get_index())


## Width of the colored fill as a 0..1 fraction of the bar's available width.
func set_ratio(ratio: float) -> void:
	var new_ratio: float = clampf(ratio, 0.0, 1.0)
	_fill.anchor_right = new_ratio
	_fill.offset_right = 0.0
	if is_instance_valid(_ghost):
		if new_ratio < _current_ratio:
			_start_juicy_drain(_current_ratio, new_ratio)
		else:
			_cancel_ghost_tweens()
			_ghost.anchor_right = new_ratio
			_ghost.offset_right = 0.0
			_ghost.color.a = 0.0
	_current_ratio = new_ratio


func _start_juicy_drain(old_ratio: float, new_ratio: float) -> void:
	_cancel_ghost_tweens()
	_ghost.anchor_right = old_ratio
	_ghost.offset_right = 0.0
	_ghost.color = GHOST_FLASH_COLOR

	_ghost_drain_tween = create_tween()
	_ghost_drain_tween.tween_interval(GHOST_HOLD_DURATION)
	_ghost_drain_tween.tween_property(_ghost, "anchor_right", new_ratio, GHOST_DRAIN_DURATION)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)

	_ghost_color_tween = create_tween()
	_ghost_color_tween.tween_interval(GHOST_HOLD_DURATION)
	_ghost_color_tween.tween_property(_ghost, "color:a", 0.0, GHOST_DRAIN_DURATION)


func _cancel_ghost_tweens() -> void:
	if _ghost_drain_tween and _ghost_drain_tween.is_valid():
		_ghost_drain_tween.kill()
	if _ghost_color_tween and _ghost_color_tween.is_valid():
		_ghost_color_tween.kill()


## Overlay text (e.g. "12/40", "LV 3").
func set_label(text: String) -> void:
	_label.text = text


func _alignment_to_godot(value: int) -> int:
	match value:
		1: return HORIZONTAL_ALIGNMENT_RIGHT
		2: return HORIZONTAL_ALIGNMENT_LEFT
		_: return HORIZONTAL_ALIGNMENT_CENTER
