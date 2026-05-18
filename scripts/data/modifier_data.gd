class_name ModifierData
extends Resource

## Modifier (relic) data.
## Saved as .tres files under data/modifiers/{rarity}/.
## Loaded by ModifierDB autoload.

enum Rarity { COMMON, UNCOMMON, RARE, LEGENDARY }
enum Category { QUANTITY, CONDITIONAL, TRANSFORM, COMPANION }

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var cost: int = 5
@export_range(1, 99, 1) var max_level: int = 5

@export var rarity: Rarity = Rarity.COMMON
@export var category: Category = Category.QUANTITY
@export var required_party_member_id: StringName = &""

## Free-form effect data. Read by battle calculation code.
## Example: { "atk_flat": 5 } or { "trigger": "single_target", "atk_mult": 2.0 }
@export var effect_data: Dictionary = {}

## For category=COMPANION cards: the character that joins the party on pick.
## Ignored for other categories.
@export var companion_data: CharacterData

## For random recruit cards: available companions. If empty, companion_data is
## used as the single recruit target.
@export var companion_pool: Array[CharacterData] = []

## When true, this card never appears in shop offers — only via level-up panel.
## Used for synergy / risk-reward cards that don't make sense as pure purchases.
@export var level_up_only: bool = false

## Synergy gate: this card only becomes offerable when the player already owns
## the referenced modifier (any level ≥ 1). Empty = no gate.
@export var required_modifier_id: StringName = &""
