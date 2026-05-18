class_name CharacterData
extends Resource

## Party member archetype data.
## Saved as .tres files under data/characters/.
## A single .tres = one party member (warrior, mage, ...).
## Per-run state (current HP/MP, level) lives on GameState, not here.

## Direction row order in the sprite sheet.
## Standard RPG layout: Down, Left, Right, Up (top to bottom).
enum Direction { DOWN, LEFT, RIGHT, UP }

@export var id: StringName = &""
@export var display_name: String = ""

## Visuals.
## Sprite sheet layout: frames_per_direction columns × 4 rows (one row per direction).
## Default: 3 cols × 4 rows of 16x24 frames (48x96 total).
@export var sprite_sheet: Texture2D
@export var frame_size: Vector2i = Vector2i(16, 24)
@export var frames_per_direction: int = 3
@export var walk_fps: float = 6.0

## Optional UI portrait (separate texture, used in HUD / dialogs).
@export var portrait: Texture2D
@export var attack_effect: Texture2D

## Base stats (level 1).
@export var max_hp: int = 30
@export var max_mp: int = 10
@export var attack: int = 5
@export var defense: int = 1
@export var agility: int = 5
