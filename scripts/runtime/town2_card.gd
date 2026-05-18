class_name Town2Card
extends Button

## Upgrade box for the town2 grid. Every offer renders like a small poster:
## bold flat color, big centered pixel icon, short title, short copy.
## A "▶" arrow appears on focus, Zelda 2 style.

signal purchase_requested(card: Town2Card, mod: ModifierData)

@onready var _name_label: Label = %CardName
@onready var _desc_label: Label = %CardDesc
@onready var _cost_label: Label = %CardCost
@onready var _arrow: Label = %FocusArrow
@onready var _icon: TextureRect = %CardIcon
## Defaults captured from the .tscn so we can swap to a stat-flavor LabelSettings
## set and back without losing the parchment look.
@onready var _default_name_settings: LabelSettings = _name_label.label_settings
@onready var _default_desc_settings: LabelSettings = _desc_label.label_settings
@onready var _default_cost_settings: LabelSettings = _cost_label.label_settings
@onready var _default_icon_minimum_size: Vector2 = _icon.custom_minimum_size
@onready var _default_icon_expand_mode: TextureRect.ExpandMode = _icon.expand_mode
@onready var _default_icon_stretch_mode: TextureRect.StretchMode = _icon.stretch_mode
@onready var _default_desc_vertical_alignment: VerticalAlignment = _desc_label.vertical_alignment

## Last-resort icon mapping for non-class modifiers that don't have their own
## .icon set. Class-tagged modifiers fall back to the owner's attack_effect.
const ICON_FALLBACK_BY_ID: Dictionary = {
	&"atk_up": "res://assets/sprites/effects/basic_attack.png",
	&"hp_up": "res://assets/sprites/holy.png",
	&"agi_up": "res://assets/sprites/dagger.png",
	&"swift_boots": "res://assets/sprites/dagger.png",
	&"recruit": "res://assets/sprites/objects/village.png",
	&"bump_attack": "res://assets/sprites/bump_attack.png",
	&"window_crash": "res://assets/sprites/window_crash.png",
	&"bump_blessing": "res://assets/sprites/bump_heal.png",
}
const ICON_FALLBACK_BY_EFFECT: Dictionary = {
	"atk_flat": "res://assets/sprites/effects/basic_attack.png",
	"hp_flat": "res://assets/sprites/holy.png",
	"agi_flat": "res://assets/sprites/dagger.png",
	"evade_chance": "res://assets/sprites/dagger.png",
}
const CARD_BG_BY_ID: Dictionary = {
	&"atk_up": Color(0.95, 0.28, 0.31, 1),
	&"hp_up": Color(0.79, 0.89, 0.55, 1),
	&"agi_up": Color(0.53, 0.76, 0.93, 1),
	&"swift_boots": Color(0.96, 0.49, 0.17, 1),
	&"battle_prayer": Color(0.74, 0.9, 0.94, 1),
	&"fireburst": Color(0.95, 0.78, 0.14, 1),
	&"heavy_strike": Color(0.96, 0.55, 0.72, 1),
	&"pilfer": Color(0.16, 0.58, 0.78, 1),
	&"bump_attack": Color(0.98, 0.5, 0.12, 1),
	&"window_crash": Color(0.98, 0.66, 0.16, 1),
	&"bump_blessing": Color(0.63, 0.86, 0.68, 1),
	&"recruit_mage": Color(0.76, 0.9, 0.94, 1),
	&"recruit_priest": Color(0.97, 0.71, 0.8, 1),
	&"recruit_thief": Color(0.79, 0.88, 0.58, 1),
	# Risk/reward — darker, more ominous than plain ATK red.
	&"glass_cannon": Color(0.55, 0.12, 0.18, 1),
	&"berserker_pact": Color(0.45, 0.18, 0.28, 1),
	# Synergy cards — purple to read clearly as "advanced" relative to stats.
	&"combo_striker": Color(0.55, 0.35, 0.72, 1),
	&"mana_hoarder": Color(0.4, 0.45, 0.78, 1),
}
const CARD_BG_BY_EFFECT: Dictionary = {
	"atk_flat": Color(0.95, 0.28, 0.31, 1),
	"hp_flat": Color(0.79, 0.89, 0.55, 1),
	"agi_flat": Color(0.53, 0.76, 0.93, 1),
	"evade_chance": Color(0.53, 0.76, 0.93, 1),
}
## Legacy English fallbacks intentionally removed: titles/descriptions now flow
## straight from each ModifierData.display_name / .description, which are
## already localized in Korean.
const DEFAULT_POSTER_BG: Color = Color(0.95, 0.78, 0.14, 1)
const POSTER_DARK_TEXT: Color = Color(0.1, 0.08, 0.07, 1)
const POSTER_LIGHT_TEXT: Color = Color(0.94, 1.0, 0.86, 1)
const POSTER_TITLE_YELLOW: Color = Color(1.0, 0.86, 0.18, 1)
const POSTER_ICON_SLOT_SIZE: Vector2 = Vector2(76, 76)

## effect_data key → label shown on stat cards. Order also controls render
## order when a card carries multiple stat changes (Glass Cannon etc.).
const STAT_LABEL_BY_KEY: Dictionary = {
	"atk_flat": "공격력",
	"def_flat": "방어력",
	"hp_flat": "최대 HP",
	"mp_flat": "최대 MP",
	"agi_flat": "민첩",
}

## Active-skill MP costs by card id. Surfaced as a second description line
## so players can tell skills apart from passive stat-ups at a glance.
const SKILL_MP_COST_BY_ID: Dictionary = {
	&"heavy_strike": 2,
	&"fireburst": 6,
	&"battle_prayer": 4,
	&"pilfer": 2,
}

var data: ModifierData
var purchased: bool = false
var free_offer: bool = false

var _poster_name_settings: LabelSettings
var _poster_desc_settings: LabelSettings
var _poster_cost_settings: LabelSettings


func _ready() -> void:
	pressed.connect(_on_pressed)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	_arrow.visible = false
	_build_poster_settings()
	if data:
		_apply_data()


## Inject the modifier this slot represents. Pass null to leave the slot blank.
func setup(mod: ModifierData, is_free_offer: bool = false) -> void:
	data = mod
	purchased = false
	free_offer = is_free_offer
	if is_inside_tree():
		_apply_data()


func _apply_data() -> void:
	if data == null:
		_render_empty()
		return
	disabled = false
	focus_mode = Control.FOCUS_ALL
	modulate = Color.WHITE
	_apply_poster_layout()


func _render_empty() -> void:
	disabled = true
	focus_mode = Control.FOCUS_NONE
	modulate = Color.WHITE
	_arrow.visible = false
	_apply_empty_layout_chrome()
	_name_label.text = ""
	_desc_label.text = ""
	_cost_label.text = ""
	_name_label.visible = false
	_desc_label.visible = false
	_cost_label.visible = false
	_icon.texture = null
	_icon.visible = false


# ─── Stat-flavor layout ───────────────────────────────────────────────
## Returns the effect_data key that drives stat-card styling, or "" if the
## modifier doesn't qualify (i.e. it's a skill, recruit, or world-modifying
## card that needs the full description).
func _stat_card_key() -> String:
	if data == null:
		return ""
	for key in STAT_LABEL_BY_KEY:
		if data.effect_data.has(key):
			return key
	return ""


func _effect_key_for_card() -> String:
	var stat_key: String = _stat_card_key()
	if not stat_key.is_empty():
		return stat_key
	for key in ["evade_chance", "hero_damage_bonus_mult", "priest_heal_flat", "thief_steal_chance"]:
		if data != null and data.effect_data.has(key):
			return key
	return ""


func _apply_poster_layout() -> void:
	_apply_default_layout_chrome()
	var bg: Color = _poster_background()
	var text_color: Color = _poster_text_color(bg)
	_name_label.text = _poster_title()
	var desc_text: String = _poster_description()
	var meta_text: String = _poster_meta_line()
	if not meta_text.is_empty():
		desc_text = "%s\n%s" % [desc_text, meta_text]
	_desc_label.text = desc_text
	_cost_label.text = _poster_cost_text()
	_cost_label.visible = not _cost_label.text.is_empty()
	_name_label.label_settings = _poster_name_settings
	_desc_label.label_settings = _poster_desc_settings
	_cost_label.label_settings = _poster_cost_settings
	_name_label.label_settings.font_color = _poster_title_color(bg)
	_desc_label.label_settings.font_color = text_color
	_cost_label.label_settings.font_color = _poster_title_color(bg)
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_icon.texture = _resolve_icon()
	_icon.visible = true
	_icon.custom_minimum_size = POSTER_ICON_SLOT_SIZE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_apply_poster_color(bg, bg.darkened(0.35))


## Reset the visual chrome (label settings + panel styleboxes + icon visibility)
## back to the parchment defaults from the .tscn. Called when transitioning
## from a stat layout to a regular card or to the empty state.
func _apply_default_layout_chrome() -> void:
	_icon.visible = true
	_icon.custom_minimum_size = _default_icon_minimum_size
	_icon.expand_mode = _default_icon_expand_mode
	_icon.stretch_mode = _default_icon_stretch_mode
	_name_label.visible = true
	_desc_label.visible = true
	_cost_label.visible = true
	_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_label.vertical_alignment = _default_desc_vertical_alignment
	_name_label.label_settings = _default_name_settings
	_desc_label.label_settings = _default_desc_settings
	_cost_label.label_settings = _default_cost_settings
	remove_theme_stylebox_override("normal")
	remove_theme_stylebox_override("hover")
	remove_theme_stylebox_override("pressed")
	remove_theme_stylebox_override("focus")
	remove_theme_stylebox_override("disabled")


func _apply_empty_layout_chrome() -> void:
	var transparent := _transparent_style()
	add_theme_stylebox_override("normal", transparent)
	add_theme_stylebox_override("hover", transparent)
	add_theme_stylebox_override("pressed", transparent)
	add_theme_stylebox_override("focus", transparent)
	add_theme_stylebox_override("disabled", transparent)


func _transparent_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_width_left = 0
	style.border_width_top = 0
	style.border_width_right = 0
	style.border_width_bottom = 0
	style.border_color = Color(0, 0, 0, 0)
	return style


func _build_poster_settings() -> void:
	_poster_name_settings = LabelSettings.new()
	_poster_name_settings.font_size = 10
	_poster_name_settings.font_color = POSTER_DARK_TEXT
	_poster_name_settings.shadow_size = 1
	_poster_name_settings.shadow_color = Color(0, 0, 0, 0.2)
	_poster_desc_settings = LabelSettings.new()
	_poster_desc_settings.font_size = 9
	_poster_desc_settings.font_color = POSTER_DARK_TEXT
	_poster_cost_settings = LabelSettings.new()
	_poster_cost_settings.font_size = 9
	_poster_cost_settings.font_color = POSTER_DARK_TEXT


func _apply_poster_color(bg: Color, border: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.border_width_left = 0
	normal.border_width_top = 0
	normal.border_width_right = 0
	normal.border_width_bottom = 0
	normal.border_color = bg
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = bg.lightened(0.08)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = bg.darkened(0.08)
	var focus: StyleBoxFlat = normal.duplicate()
	focus.bg_color = bg.lightened(0.12)
	focus.border_width_left = 0
	focus.border_width_top = 0
	focus.border_width_right = 0
	focus.border_width_bottom = 0
	focus.border_color = bg
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", pressed)
	add_theme_stylebox_override("focus", focus)


func _poster_title() -> String:
	var title: String = data.display_name
	if data.max_level <= 1 or data.category == ModifierData.Category.COMPANION:
		return title
	var next_level: int = mini(GameState.modifier_level(data.id) + 1, data.max_level)
	return "%s Lv %d/%d" % [title, next_level, data.max_level]


func _poster_description() -> String:
	if data == null:
		return ""
	# Multi-stat readout. Walks STAT_LABEL_BY_KEY in order so trade-off cards
	# (Glass Cannon = +ATK / -HP) show both lines with a proper sign prefix.
	var stat_lines: PackedStringArray = []
	for key in STAT_LABEL_BY_KEY:
		if not data.effect_data.has(key):
			continue
		var value: int = GameState.modifier_next_int_effect(data, key)
		if value == 0:
			continue
		var sign_prefix: String = "+" if value > 0 else ""
		stat_lines.append("%s%d %s" % [sign_prefix, value, STAT_LABEL_BY_KEY[key]])
	if not stat_lines.is_empty():
		return "\n".join(stat_lines)
	if data.effect_data.has("move_speed_flat"):
		return "이동 속도 +%d" % GameState.modifier_next_int_effect(data, "move_speed_flat")
	if data.effect_data.has("hero_damage_bonus_mult"):
		var amount: int = int(round(GameState.modifier_next_float_effect(data, "hero_damage_bonus_mult") * 100.0))
		return "용사 데미지 +%d%%" % amount
	if data.effect_data.has("mage_firewall_damage_flat"):
		return "모든 적: %d 데미지" % GameState.modifier_next_int_effect(data, "mage_firewall_damage_flat")
	if data.effect_data.has("priest_heal_flat"):
		var amount: int = GameState.modifier_next_int_effect(data, "priest_heal_flat")
		return "아군 회복 +%d" % amount
	if data.effect_data.has("thief_steal_chance"):
		var amount: int = int(round(GameState.modifier_next_float_effect(data, "thief_steal_chance") * 100.0))
		return "훔치기 확률 %d%%" % amount
	if data.effect_data.has("evade_chance"):
		var amount: int = int(round(GameState.modifier_next_float_effect(data, "evade_chance") * 100.0))
		return "회피 +%d%%" % amount
	if data.effect_data.has("party_bump_damage_ratio"):
		var amount: int = int(round(GameState.modifier_next_float_effect(data, "party_bump_damage_ratio") * 100.0))
		return "범프 공격 +%d%%" % amount
	if data.effect_data.has("window_collision_damage_ratio"):
		var amount: int = int(round(GameState.modifier_next_float_effect(data, "window_collision_damage_ratio") * 100.0))
		return "충돌 데미지 +%d%%" % amount
	if data.effect_data.has("window_collision_heal_flat"):
		return "범프 회복 +%d" % GameState.modifier_next_int_effect(data, "window_collision_heal_flat")
	return data.description


## Extra one-liner appended below the main effect — flags MP cost on active
## skills and synergy gates (required_modifier_id). Returns "" when nothing
## special applies so the card stays compact for plain stat picks.
func _poster_meta_line() -> String:
	if data == null:
		return ""
	var parts: PackedStringArray = []
	if SKILL_MP_COST_BY_ID.has(data.id):
		parts.append("MP %d 소모" % int(SKILL_MP_COST_BY_ID[data.id]))
	if data.required_modifier_id != &"":
		var gate: ModifierData = ModifierDB.get_by_id(data.required_modifier_id)
		var gate_name: String = gate.display_name if gate else String(data.required_modifier_id)
		parts.append("%s 필요" % gate_name)
	return " · ".join(parts)


func _poster_cost_text() -> String:
	# Level-up cards don't show a price tag — the panel itself signals the
	# context, and freeing this slot gives the description more room.
	if free_offer:
		return ""
	var cost: int = GameState.modifier_purchase_cost(data)
	if cost <= 0:
		return ""
	return "%d G" % cost


func _poster_text_color(bg: Color) -> Color:
	return POSTER_LIGHT_TEXT if bg.get_luminance() < 0.42 else POSTER_DARK_TEXT


func _poster_title_color(bg: Color) -> Color:
	return POSTER_TITLE_YELLOW if bg.get_luminance() < 0.42 else Color(0.21, 0.28, 0.52, 1)


func _poster_background() -> Color:
	if data == null:
		return DEFAULT_POSTER_BG
	if CARD_BG_BY_ID.has(data.id):
		return CARD_BG_BY_ID[data.id]
	var effect_key: String = _effect_key_for_card()
	if CARD_BG_BY_EFFECT.has(effect_key):
		return CARD_BG_BY_EFFECT[effect_key]
	return DEFAULT_POSTER_BG


# ─── Icon resolution (default-layout cards only) ──────────────────────
## Surface a small pixel sprite that hints at what the card does. Class-tagged
## modifiers (Heavy Strike, Pilfer, etc.) reuse the owner's attack_effect so
## the icon and the in-battle effect read as the same thing. Non-class cards
## fall back to a hand-curated id→path map. If nothing matches we leave the
## TextureRect visible-but-blank so all four cards stay vertically aligned.
func _apply_icon() -> void:
	_icon.texture = _resolve_icon()
	_icon.visible = true


func _resolve_icon() -> Texture2D:
	if data.icon:
		return data.icon
	var effect_key: String = _effect_key_for_card()
	var effect_path: String = ICON_FALLBACK_BY_EFFECT.get(effect_key, "")
	if not effect_path.is_empty() and ResourceLoader.exists(effect_path):
		var effect_res := load(effect_path)
		if effect_res is Texture2D:
			return effect_res
	if data.required_party_member_id != &"":
		var character: CharacterData = _load_character(data.required_party_member_id)
		if character and character.attack_effect:
			return character.attack_effect
	if data.category == ModifierData.Category.COMPANION:
		var sprite: Texture2D = _recruit_sprite(data)
		if sprite:
			return sprite
	var path: String = ICON_FALLBACK_BY_ID.get(data.id, "")
	if not path.is_empty() and ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			return res
	return null


## Pre-resolved single-companion recruit cards (recruit_mage etc.) carry the
## character directly; older random-pool recruit cards fall back to the first
## still-available pool entry. Use one original-size full-body idle frame.
func _recruit_sprite(mod: ModifierData) -> Texture2D:
	var character: CharacterData = mod.companion_data
	if character == null and not mod.companion_pool.is_empty():
		for c in mod.companion_pool:
			if c and not GameState.has_party_member(c.id):
				character = c
				break
	if character == null or character.sprite_sheet == null:
		return null
	var fw: int = character.frame_size.x
	var fh: int = character.frame_size.y
	var idle_col: int = clampi(1, 0, maxi(0, character.frames_per_direction - 1))
	var atlas := AtlasTexture.new()
	atlas.atlas = character.sprite_sheet
	atlas.region = Rect2(idle_col * fw, 0, fw, fh)
	atlas.filter_clip = true
	return atlas


func _load_character(id: StringName) -> CharacterData:
	var path := "res://data/characters/%s.tres" % id
	if not ResourceLoader.exists(path):
		return null
	var res := load(path)
	return res as CharacterData


func _display_name_with_level() -> String:
	if data.category == ModifierData.Category.COMPANION or data.max_level <= 1:
		return data.display_name
	var next_level: int = mini(GameState.modifier_level(data.id) + 1, data.max_level)
	return "%s Lv %d/%d" % [data.display_name, next_level, data.max_level]


# ─── Input / state ────────────────────────────────────────────────────
func _on_pressed() -> void:
	if purchased or data == null:
		return
	purchase_requested.emit(self, data)


func _on_focus_entered() -> void:
	_arrow.visible = true


func _on_focus_exited() -> void:
	_arrow.visible = false


func mark_purchased() -> void:
	purchased = true
	disabled = true
	modulate = Color(0.45, 0.45, 0.45, 1)
	_cost_label.text = "OWNED"


func mark_unaffordable_flash() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(_cost_label, "modulate", Color(1, 0.3, 0.3, 1), 0.1)
	tween.tween_property(_cost_label, "modulate", Color.WHITE, 0.2)
