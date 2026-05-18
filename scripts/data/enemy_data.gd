class_name EnemyData
extends Resource

## Enemy archetype data.
## Saved as .tres files under data/enemies/.
## A single .tres = one enemy *species* (Slime, Bat, ...).
## Per-instance state (current HP) lives on the Enemy node, not here.

@export var id: StringName = &""
@export var display_name: String = ""
@export var sprite: Texture2D

## Combat stats.
@export var max_hp: int = 10
@export var attack: int = 2
@export var defense: int = 0
@export var agility: int = 4
@export var party_bump_counter_damage_ratio: float = 0.0

## Field personality.
## Passive enemies wander and only fight if the player touches them.
@export var chases_player_on_field: bool = true
@export var field_wander_speed: float = 18.0
@export var field_chase_speed: float = 58.0
@export var field_detect_radius: float = 92.0
@export var field_lose_radius: float = 180.0
@export var field_charge_enabled: bool = false
@export var field_charge_trigger_radius: float = 72.0
@export var field_charge_speed: float = 180.0
@export var field_charge_duration: float = 0.28
@export var field_charge_cooldown: float = 1.1

## Reward on defeat.
@export var gold_reward: int = 1
@export var xp_reward: int = 1
