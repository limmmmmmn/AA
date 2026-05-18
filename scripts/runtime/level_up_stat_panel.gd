class_name LevelUpStatPanel
extends Control

## Shown *before* the skill tree on level-up. One card per party member,
## stacked: portrait on top, name below, then a small column of stat
## deltas (old → new with a green arrow + gain). Pressing 확인 closes
## the panel and hands off to the tree popup.

signal confirmed

const CHARACTER_PORTRAIT_SCENE: PackedScene = preload("res://scenes/ui/character_portrait.tscn")

const PANEL_BG: Color = Color(0.06, 0.08, 0.13, 0.94)
const CARD_BG: Color = Color(0.13, 0.16, 0.22, 0.96)
const CARD_BORDER: Color = Color(0.4, 0.45, 0.55)
const NAME_COLOR: Color = Color(1.0, 0.92, 0.42)
const STAT_LABEL_COLOR: Color = Color(0.78, 0.82, 0.9)
const OLD_VALUE_COLOR: Color = Color(0.6, 0.62, 0.72)
const NEW_VALUE_COLOR: Color = Color(0.95, 0.96, 1.0)
const GAIN_COLOR: Color = Color(0.45, 0.92, 0.5)
const ZERO_GAIN_COLOR: Color = Color(0.55, 0.55, 0.6)

const STAT_KEYS: Array = [
	{"label": "HP",  "growth": "hp",  "effective": "max_hp"},
	{"label": "MP",  "growth": "mp",  "effective": "max_mp"},
	{"label": "공격", "growth": "atk", "effective": "attack"},
	{"label": "방어", "growth": "def", "effective": "defense"},
	{"label": "민첩", "growth": "agi", "effective": "agility"},
]

var _levels_gained: int = 1
var _built: bool = false


func setup(levels_gained: int) -> void:
	_levels_gained = maxi(1, levels_gained)
	if is_inside_tree() and not _built:
		_build_ui()
		_built = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not _built:
		_build_ui()
		_built = true


func _unhandled_input(event: InputEvent) -> void:
	# Enter / Space / Escape all confirm — keeps the flow snappy.
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE or key == KEY_ESCAPE:
			_confirm()
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	for child in get_children():
		child.queue_free()

	var bg := ColorRect.new()
	bg.color = PANEL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var vp: Vector2 = get_viewport().get_visible_rect().size

	# Title strip
	var title := Label.new()
	title.text = "레벨 업!  Lv %d" % GameState.current_level
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", NAME_COLOR)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 3)
	title.size = Vector2(vp.x, 18)
	title.position = Vector2(0, 6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var subtitle := Label.new()
	subtitle.text = "스탯 상승" if _levels_gained == 1 else "스탯 상승 (× %d)" % _levels_gained
	subtitle.add_theme_font_size_override("font_size", 9)
	subtitle.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9, 0.85))
	subtitle.size = Vector2(vp.x, 12)
	subtitle.position = Vector2(0, 24)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(subtitle)

	# Member cards row, centered horizontally.
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.size = Vector2(vp.x - 16, vp.y - 90)
	hbox.position = Vector2(8, 42)
	add_child(hbox)
	for i in GameState.party.size():
		var card := _build_member_card(i)
		hbox.add_child(card)

	# Confirm button pinned to the bottom-center.
	var confirm := Button.new()
	confirm.text = "확인  ▶"
	confirm.add_theme_font_size_override("font_size", 11)
	confirm.size = Vector2(110, 28)
	confirm.anchor_left = 0.5
	confirm.anchor_right = 0.5
	confirm.anchor_top = 1.0
	confirm.anchor_bottom = 1.0
	confirm.offset_left = -55
	confirm.offset_right = 55
	confirm.offset_top = -38
	confirm.offset_bottom = -10
	confirm.pressed.connect(_confirm)
	add_child(confirm)
	confirm.grab_focus()


func _build_member_card(index: int) -> Control:
	var member: CharacterData = GameState.party[index]
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG
	style.border_color = CARD_BORDER
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = Vector2(116, 0)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	card.add_child(vbox)

	# Portrait — center-aligned via a wrapper so it doesn't stretch.
	var portrait_wrap := CenterContainer.new()
	vbox.add_child(portrait_wrap)
	var portrait: CharacterPortrait = CHARACTER_PORTRAIT_SCENE.instantiate()
	portrait.custom_minimum_size = Vector2(40, 40)
	portrait.size = Vector2(40, 40)
	portrait_wrap.add_child(portrait)
	portrait.set_character(member)

	# Name
	var name_label := Label.new()
	name_label.text = member.display_name
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", NAME_COLOR)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	# Divider
	var divider := ColorRect.new()
	divider.color = Color(0.4, 0.45, 0.55, 0.6)
	divider.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(divider)

	# Stat deltas
	for entry: Dictionary in _stat_entries(index):
		vbox.add_child(_build_stat_line(entry))

	return card


## Compute the old / new / gain triplet for every stat row. Old is just
## new minus growth × levels_gained — equipment and modifier contributions
## don't change on level-up so they cancel out cleanly.
func _stat_entries(index: int) -> Array:
	var member_id: StringName = GameState.party[index].id
	var rows: Array = []
	for key_info: Dictionary in STAT_KEYS:
		var growth: int = GameState._level_growth_value(member_id, key_info.growth)
		var gain: int = growth * _levels_gained
		var current: int = _read_effective_stat(index, key_info.effective)
		rows.append({
			"label": key_info.label,
			"old": current - gain,
			"new": current,
			"gain": gain,
		})
	return rows


func _read_effective_stat(index: int, kind: String) -> int:
	match kind:
		"max_hp": return GameState.effective_max_hp(index)
		"max_mp": return GameState.effective_max_mp(index)
		"attack": return GameState.effective_attack(index)
		"defense": return GameState.effective_defense(index)
		"agility": return GameState.effective_agility(index)
	return 0


func _build_stat_line(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)

	var lbl_name := Label.new()
	lbl_name.text = String(entry.label)
	lbl_name.add_theme_font_size_override("font_size", 9)
	lbl_name.add_theme_color_override("font_color", STAT_LABEL_COLOR)
	lbl_name.custom_minimum_size = Vector2(22, 12)
	row.add_child(lbl_name)

	var lbl_old := Label.new()
	lbl_old.text = "%d" % int(entry.old)
	lbl_old.add_theme_font_size_override("font_size", 9)
	lbl_old.add_theme_color_override("font_color", OLD_VALUE_COLOR)
	lbl_old.custom_minimum_size = Vector2(22, 12)
	lbl_old.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(lbl_old)

	var lbl_arrow := Label.new()
	lbl_arrow.text = "→"
	lbl_arrow.add_theme_font_size_override("font_size", 9)
	lbl_arrow.add_theme_color_override("font_color", STAT_LABEL_COLOR)
	row.add_child(lbl_arrow)

	var lbl_new := Label.new()
	lbl_new.text = "%d" % int(entry.new)
	lbl_new.add_theme_font_size_override("font_size", 10)
	lbl_new.add_theme_color_override("font_color", NEW_VALUE_COLOR)
	lbl_new.custom_minimum_size = Vector2(22, 12)
	row.add_child(lbl_new)

	var lbl_gain := Label.new()
	if entry.gain > 0:
		lbl_gain.text = "▲%d" % int(entry.gain)
		lbl_gain.add_theme_color_override("font_color", GAIN_COLOR)
	else:
		lbl_gain.text = "  ─"
		lbl_gain.add_theme_color_override("font_color", ZERO_GAIN_COLOR)
	lbl_gain.add_theme_font_size_override("font_size", 9)
	lbl_gain.custom_minimum_size = Vector2(22, 12)
	row.add_child(lbl_gain)

	return row


func _confirm() -> void:
	if not is_inside_tree():
		return
	confirmed.emit()
	queue_free()
