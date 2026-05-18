extends Node

## Global signal bus.
## Game-wide events go here. Local communication should use plain signals.
## Connect with: EventBus.signal_name.connect(_on_signal_name)

# ─── Field / Encounter ────────────────────────────────────────────────
## Player collided with an enemy on the field. Triggers a battle_window spawn.
signal enemy_encountered(enemy: Node)

## Player stepped onto the town field tile. Main handles the scene transition.
signal town_entered(tile: Node)

## A field event tile (campfire etc.) was triggered by walking into it.
## Main listens, pauses the field, and instantiates the matching event
## window with the right dialogue + recruit data.
signal event_tile_triggered(tile: Node)

## The town scene was just dismissed. Field listens to consume the current
## town tile and schedule the next one elsewhere on the map.
signal town_closed()

## Fires every time the rolling difficulty tier crosses another threshold.
## Tier 1 = ~30s elapsed, tier 2 = ~60s, etc. HUD listens for a toast.
signal difficulty_increased(tier: int)

# ─── Party Composition ────────────────────────────────────────────────
## Party roster changed (run start, swap, revival). Listeners should re-read
## GameState.party / party_hp from scratch.
signal party_changed()

## Fired specifically when a recruit event (campfire, shrine, …) lands a
## new companion. party_changed also fires, but this one carries the
## character so the HUD can show a toast and Field can pop the sprite.
signal character_recruited(character: CharacterData)

# ─── Battle Window Lifecycle ──────────────────────────────────────────
signal battle_window_opened(window: Node)
signal battle_window_closed(window: Node)
signal battle_window_enemy_attack_started(window: Node)
## All battle windows have finished — there is no active combat anywhere.
## Used to gate stage_cleared so it doesn't fire while combat is still running.
signal all_battles_resolved()

# ─── Combat ───────────────────────────────────────────────────────────
## Damage dealt to *any* combatant. Used by floating numbers, juice, etc.
signal damage_dealt(target: Node, amount: int, world_position: Vector2)

## Enemy died. Used by reward popups, combat log, modifier triggers.
signal enemy_defeated(enemy: Node, gold: int, world_position: Vector2)

## Party HP changed for a specific member. Used by HUD.
signal party_member_hp_changed(index: int, new_hp: int, max_hp: int)
signal party_member_mp_changed(index: int, new_mp: int, max_mp: int)

## Party EXP/level changed for a specific member. Used by HUD.
signal party_member_xp_changed(index: int, xp: int, xp_to_next: int, level: int)
signal party_member_leveled_up(index: int, new_level: int)

## Legacy skill-point state changed. party_skills_changed is still used by
## the HUD chips when level-up cards add or improve skills.
signal party_skill_points_changed(points: int)
signal party_skills_changed()

## A party member just fired a learned skill in battle. Picked up by the
## HUD skill chips to play a "knock!" feedback animation.
signal party_skill_activated(member_index: int, skill_id: StringName)

## Party equipment changed for a specific member. Used by HUD.
signal party_equipment_changed(index: int)
signal inventory_changed()

## Field should spawn an item pickup at this world position.
signal field_item_drop_requested(item: ItemData, world_position: Vector2)
signal field_recovery_orb_requested(kind: StringName, world_position: Vector2)

## At least one party member changed HP. Used for "any-change" listeners.
signal party_hp_changed()

## All party members are dead. Game over.
signal party_wiped()

## Actual HP removed from a party member after clamping overkill.
signal party_damage_taken(member_index: int, amount: int)

# ─── Stage / Progression ──────────────────────────────────────────────
signal stage_started(stage_num: int)
signal stage_cleared(stage_num: int)
signal run_cleared()

## A new run system has unfolded. HUD listens for the announcement; field /
## town code reads GameState.is_system_unlocked() for actual gating.
signal system_unlocked(system_id: StringName, display_name: String, description: String)

# ─── Economy / Modifiers ──────────────────────────────────────────────
signal gold_changed(new_gold: int)
signal modifier_offered(modifiers: Array)  ## Array[ModifierData]
signal modifier_purchase_requested(modifier: ModifierData, source: Node)
signal modifier_purchase_succeeded(modifier: ModifierData, source: Node)
signal modifier_purchase_failed(modifier: ModifierData, source: Node)
signal modifier_purchased(modifier: ModifierData)
signal card_purchased(modifier: ModifierData, cost: int)
signal modifier_picked(modifier: ModifierData)
