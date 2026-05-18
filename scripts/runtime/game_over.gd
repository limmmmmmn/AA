class_name GameOver
extends CanvasLayer

## End-of-run summary panel. Classic DQ feel: black panel, single-pixel
## white border, monochrome text with gold-tinted numbers.
##
## Pulls everything from GameState (no caller setup needed). Emits
## try_again_pressed when the player wants to restart.

signal try_again_pressed

@onready var _stats_container: VBoxContainer = %StatsContainer
@onready var _party_label: Label = %PartyLabel
@onready var _try_button: Button = %TryAgainButton

const STAT_FONT_SIZE: int = 8
const VALUE_COLOR: Color = Color(1.0, 0.85, 0.4, 1.0)  # gold
const LABEL_COLOR: Color = Color(0.95, 0.95, 0.97, 1.0)


func _ready() -> void:
	_populate_stats()
	_populate_party()
	_try_button.pressed.connect(_on_try_again)
	_try_button.grab_focus()


func _populate_stats() -> void:
	for child in _stats_container.get_children():
		child.queue_free()
	_add_stat("Stages cleared", str(GameState.current_stage))
	_add_stat("Enemies slain", str(GameState.enemies_killed))
	_add_stat("Gold earned", str(GameState.total_gold_earned))
	_add_stat("Biggest hit", str(GameState.biggest_hit))
	_add_stat("Modifiers", str(GameState.active_modifiers.size()))
	_add_stat("Companions", str(GameState.recruited_companions.size()))
	_add_stat("Time", _format_time(GameState.get_run_elapsed_seconds()))


func _populate_party() -> void:
	if GameState.party_size() == 0:
		_party_label.text = ""
		return
	var names: PackedStringArray = []
	for member: CharacterData in GameState.party:
		names.append(member.display_name)
	_party_label.text = "Party: " + " / ".join(names)


func _add_stat(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.label_settings = _make_settings(LABEL_COLOR)
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.label_settings = _make_settings(VALUE_COLOR)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)

	_stats_container.add_child(row)


func _make_settings(color: Color) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font_size = STAT_FONT_SIZE
	ls.font_color = color
	return ls


func _format_time(seconds: float) -> String:
	var total: int = int(seconds)
	var minutes: int = total / 60
	var secs: int = total % 60
	return "%d:%02d" % [minutes, secs]


func _on_try_again() -> void:
	try_again_pressed.emit()


# Press Enter / Z / Space anywhere to retry too.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_Z:
				_on_try_again()
				get_viewport().set_input_as_handled()
