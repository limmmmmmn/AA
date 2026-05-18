extends Node

## Run-wide state: party, gold, modifiers, stage.
## Read freely. Mutate through helper methods so signals fire correctly.
##
## Use the effective_* helpers when you need stat values during combat —
## they fold in active_modifiers. Raw fields on CharacterData are base only.

# ─── Party ────────────────────────────────────────────────────────────
## The 4 party members chosen for this run.
var party: Array[CharacterData] = []

## Current HP/MP per party member. Index matches `party`.
var party_hp: Array[int] = []
var party_mp: Array[int] = []
## Shared progression. Every member levels in lockstep and pulls XP from
## the same pool — recruits get inserted at the current shared level so
## the party never has a "weak link". Indexed accessors below are kept for
## existing call sites; they all return the same number now.
var current_level: int = 1
var current_xp: int = 0
var _defer_party_level_settlement: bool = true
var party_equipment: Array[Array] = []
var inventory: Array[ItemData] = []
## Legacy skill-tree counters are kept for old call sites, but the live
## progression now goes through per-member level-up card picks.
var party_skill_points: int = 1
var unlocked_tree_skills: Array[StringName] = []
var _last_level_up_auto_skills: Array[ModifierData] = []
var _move_speed_drag_multiplier: float = 1.0
var _move_speed_drag_until_msec: int = 0
var _move_speed_boost_multiplier: float = 1.0
var _move_speed_boost_until_msec: int = 0

# ─── Economy ──────────────────────────────────────────────────────────
const STARTING_GOLD: int = 30

var gold: int = STARTING_GOLD
## Stat-affecting modifiers picked this run.
var active_modifiers: Array[ModifierData] = []
## Recruit cards that successfully added a member to `party` this run.
## Kept separate from active_modifiers because companions are *party state*,
## not stat effects — useful for run summaries and avoiding "modifiers: 0"
## logs after recruiting.
var recruited_companions: Array[ModifierData] = []

# ─── Progression ──────────────────────────────────────────────────────
var current_stage: int = 0

const MAX_CHARACTER_LEVEL: int = 20
const EQUIPMENT_SLOT_COUNT: int = 6
const EQUIPMENT_ACCESSORY_SLOT_A: int = 4
const EQUIPMENT_ACCESSORY_SLOT_B: int = 5
const XP_CURVE_BASE: int = 10
const XP_CURVE_LEVEL_STEP: int = 5
const XP_CURVE_QUADRATIC: int = 3
## Every stat goes up by exactly 1 per level. Class flavor is meant to
## come from base stats + per-member level-up picks instead of the curve.
const DEFAULT_LEVEL_GROWTH: Dictionary = {
	"hp": 1,
	"mp": 1,
	"atk": 1,
	"def": 1,
	"agi": 1,
}
const LEVEL_GROWTH_BY_CHARACTER_ID: Dictionary = {
	&"hero": {"hp": 1, "mp": 1, "atk": 1, "def": 1, "agi": 1},
	&"mage": {"hp": 1, "mp": 1, "atk": 1, "def": 1, "agi": 1},
	&"priest": {"hp": 1, "mp": 1, "atk": 1, "def": 1, "agi": 1},
	&"thief": {"hp": 1, "mp": 1, "atk": 1, "def": 1, "agi": 1},
}
const LEVEL_UP_OFFER_COUNT: int = 3
const AUTO_SKILL_LEVEL_START: int = 2
const AUTO_SKILL_LEVEL_INTERVAL: int = 5
const AUTO_SKILL_IDS_BY_MEMBER_ID: Dictionary = {
	&"hero": [&"heavy_strike", &"hoimi", &"taunt"],
	&"mage": [&"fireburst", &"lightning_bolt"],
	&"priest": [&"battle_prayer", &"holy_strike", &"revive"],
	&"thief": [&"pilfer", &"backstep", &"speed_up"],
}
const BUMP_ATTACK_ID: StringName = &"bump_attack"
const FIELD_MOVEMENT_ID: StringName = &"field_movement"
const LEVEL_UP_PARTY_CARD_OFFER_IDS: Array[StringName] = [&"window_crash", &"bump_blessing", &"shockwave", &"window_fusion", &"window_spin", &"window_split", &"bouncy_ball", &"repulsion_wall"]

const PRICE_LEVEL_MULTIPLIERS = [1.0, 1.45, 2.05, 2.8, 3.7]
const EFFECT_STACK_MULTIPLIERS = [1.0, 0.75, 0.55, 0.4, 0.3]
const DAMAGE_BONUS_STACK_MULTIPLIERS = [1.0, 0.5, 0.3, 0.2, 0.16]
const ENEMY_GOLD_STAGE_INTERVAL: int = 5
const ENEMY_GOLD_STAGE_BONUS_CAP: int = 4
const ENEMY_HP_STAGE_LINEAR: float = 0.12
const ENEMY_HP_STAGE_QUADRATIC: float = 0.01
const ENEMY_ATTACK_STAGE_LINEAR: float = 0.08
const ENEMY_ATTACK_STAGE_QUADRATIC: float = 0.006

## ─── Continuous run-intensity curve ─────────────────────────────────
## A 30-minute run should ramp from "barely a threat" to "the floor is
## lava". The old tier-based scaling jumped every 30s — flat-flat-flat
## then sudden spike. These constants drive a *continuous* multiplier so
## enemies grow every frame, matching the steady party power-up curve.
const RUN_TARGET_SECONDS: float = 1800.0    ## 30 min = full intensity
const ENEMY_HP_AT_TARGET: float = 8.0       ## enemies have 8× HP at 30 min
const ENEMY_ATK_AT_TARGET: float = 5.0      ## enemies hit 5× harder at 30 min
const RUN_INTENSITY_CAP: float = 1.5        ## past 45 min, stop scaling further
const BATTLE_WINDOW_MAX_ENEMIES: int = 5

## ─── Unfolding systems ──────────────────────────────────────────────
## New mechanics are exposed in a small, readable order. Other systems should
## ask is_system_unlocked() rather than hard-code stage numbers.
const SYSTEM_TREASURE: StringName = &"treasure"
const SYSTEM_FIELD_MOVEMENT: StringName = &"field_movement"
const SYSTEM_MAGE_EVENT: StringName = &"mage_event"
const SYSTEM_FOREST: StringName = &"forest"
const SYSTEM_PACK_ENCOUNTERS: StringName = &"pack_encounters"
const SYSTEM_PRIEST_EVENT: StringName = &"priest_event"
const SYSTEM_UNLOCK_STAGE: Dictionary = {
	SYSTEM_TREASURE: 2,
	SYSTEM_FIELD_MOVEMENT: 2,
	SYSTEM_MAGE_EVENT: 2,
	SYSTEM_FOREST: 3,
	SYSTEM_PACK_ENCOUNTERS: 3,
	SYSTEM_PRIEST_EVENT: 4,
}
const SYSTEM_UNLOCK_NAMES: Dictionary = {
	SYSTEM_TREASURE: "Treasure Chests",
	SYSTEM_FIELD_MOVEMENT: "Moving Battles",
	SYSTEM_MAGE_EVENT: "Campfire Event",
	SYSTEM_FOREST: "Forest Field",
	SYSTEM_PACK_ENCOUNTERS: "Enemy Packs",
	SYSTEM_PRIEST_EVENT: "Shrine Event",
}
const SYSTEM_UNLOCK_DESCRIPTIONS: Dictionary = {
	SYSTEM_TREASURE: "적을 처치하면 필드에 보물상자가 나타난다.",
	SYSTEM_FIELD_MOVEMENT: "전투창이 떠도 필드 이동을 이어갈 수 있다.",
	SYSTEM_MAGE_EVENT: "불빛을 따라가면 새 동료를 만날 수 있다.",
	SYSTEM_FOREST: "필드에 숲 지형이 펼쳐진다.",
	SYSTEM_PACK_ENCOUNTERS: "한 전투창에 여러 적이 함께 등장하기 시작한다.",
	SYSTEM_PRIEST_EVENT: "성소에서 회복형 동료를 만날 수 있다.",
}

var unlocked_systems: Dictionary = {}


# ─── Run statistics (for the game-over summary) ───────────────────────
var enemies_killed: int = 0
var total_gold_earned: int = 0  ## lifetime, not affected by spending
var biggest_hit: int = 0
var run_started_at_ms: int = 0

const RECOVERY_ORB_MISSING_RATIO: float = 0.10
const RECOVERY_ORB_HP: StringName = &"hp"
const RECOVERY_ORB_MP: StringName = &"mp"

## Rolling difficulty: the longer the run goes, the higher the enemy stage
## index climbs. Tier 1 unlocks ~30 seconds in, tier 2 at 60s, etc. Pause
## stalls the counter so town visits don't burn the budget.
const DIFFICULTY_TICK_SECONDS: float = 30.0
var _difficulty_elapsed: float = 0.0
var _difficulty_tier_announced: int = 0
var _active_battle_window_count: int = 0

func _ready() -> void:
	# Listen to bus events to keep counters fresh without coupling combat code.
	EventBus.enemy_defeated.connect(_on_enemy_defeated)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.modifier_purchase_requested.connect(_on_modifier_purchase_requested)
	EventBus.battle_window_opened.connect(_on_battle_window_opened)
	EventBus.battle_window_closed.connect(_on_battle_window_closed)


func _on_enemy_defeated(_enemy: Node, _gold: int, _world_position: Vector2) -> void:
	enemies_killed += 1


func _on_damage_dealt(_target: Node, amount: int, _world_position: Vector2) -> void:
	if amount > biggest_hit:
		biggest_hit = amount


func get_run_elapsed_seconds() -> float:
	if run_started_at_ms <= 0:
		return 0.0
	return float(Time.get_ticks_msec() - run_started_at_ms) / 1000.0


# ─── Difficulty pacing ────────────────────────────────────────────────
## Ticks the rolling difficulty timer and emits when a new tier unlocks.
## Pause-friendly: _process is suspended on get_tree().paused, so town
## visits + popups don't accidentally ramp difficulty in the background.
func _process(delta: float) -> void:
	if party.is_empty():
		return
	_difficulty_elapsed += delta
	var tier: int = current_difficulty_tier()
	if tier > _difficulty_tier_announced:
		_difficulty_tier_announced = tier
		EventBus.difficulty_increased.emit(tier)


func current_difficulty_tier() -> int:
	return int(floor(_difficulty_elapsed / DIFFICULTY_TICK_SECONDS))


## 1-based effective stage = base stage + rolling difficulty tier.
## Spawn tables (enemy species, support pool, encounter size) key off this
## so the field gets new species mixed in as the threat clock climbs.
func effective_stage() -> int:
	return maxi(1, current_stage) + current_difficulty_tier()


## Debug / tuning hook: jump the intensity clock forward by a chunky 2-minute
## stride. Under the continuous run_intensity() curve, a single 30s tier bump
## is only ~1.7% intensity — too small to feel. Two minutes ≈ 6.7%, which
## reads as a noticeable difficulty step when mashing the HUD ▲ button.
func bump_difficulty_tier() -> void:
	const BUMP_STRIDE_SECONDS: float = 120.0
	_difficulty_elapsed += BUMP_STRIDE_SECONDS
	var next_tier: int = current_difficulty_tier()
	_difficulty_tier_announced = next_tier
	EventBus.difficulty_increased.emit(next_tier)


# ─── Party setup ──────────────────────────────────────────────────────
## Initialize the party from a list of CharacterData. Resets HP/MP to max.
## Emits party_changed so listeners (HUD, etc.) can re-populate from scratch
## regardless of node-init order.
func set_party(members: Array[CharacterData]) -> void:
	party = members.duplicate()
	party_hp.clear()
	party_mp.clear()
	party_equipment.clear()
	inventory.clear()
	# Shared progression resets each run.
	current_level = 1
	current_xp = 0
	# Legacy SP starts empty; level-up progression is handled by card picks.
	party_skill_points = 0
	unlocked_tree_skills.clear()
	_last_level_up_auto_skills.clear()
	for m: CharacterData in party:
		party_equipment.append(_empty_equipment_slots())
		party_hp.append(effective_max_hp(party_hp.size()))
		party_mp.append(effective_max_mp(party_mp.size()))
	# A fresh party means a fresh run timer.
	run_started_at_ms = Time.get_ticks_msec()
	_difficulty_elapsed = 0.0
	_difficulty_tier_announced = 0
	EventBus.party_changed.emit()


func party_size() -> int:
	return party.size()


func is_alive(index: int) -> bool:
	return index >= 0 and index < party_hp.size() and party_hp[index] > 0


func is_party_wiped() -> bool:
	for hp in party_hp:
		if hp > 0:
			return false
	return true


# ─── Combat hooks ─────────────────────────────────────────────────────
func damage_party_member(index: int, amount: int) -> void:
	if index < 0 or index >= party_hp.size():
		return
	var was_alive: bool = party_hp[index] > 0
	var before_hp: int = party_hp[index]
	party_hp[index] = max(0, party_hp[index] - amount)
	var actual_damage: int = before_hp - party_hp[index]
	if actual_damage > 0:
		EventBus.party_damage_taken.emit(index, actual_damage)
	EventBus.party_member_hp_changed.emit(index, party_hp[index], effective_max_hp(index))
	EventBus.party_hp_changed.emit()
	if was_alive and party_hp[index] == 0 and is_party_wiped():
		EventBus.party_wiped.emit()


func heal_party_member(index: int, amount: int) -> void:
	if index < 0 or index >= party_hp.size():
		return
	party_hp[index] = min(effective_max_hp(index), party_hp[index] + amount)
	EventBus.party_member_hp_changed.emit(index, party_hp[index], effective_max_hp(index))
	EventBus.party_hp_changed.emit()


func can_spend_mp(index: int, amount: int) -> bool:
	if amount <= 0:
		return true
	return index >= 0 and index < party_mp.size() and party_mp[index] >= amount


func spend_mp(index: int, amount: int) -> bool:
	if amount <= 0:
		return true
	if not can_spend_mp(index, amount):
		return false
	party_mp[index] = maxi(0, party_mp[index] - amount)
	EventBus.party_member_mp_changed.emit(index, party_mp[index], effective_max_mp(index))
	return true


func restore_mp(index: int, amount: int) -> void:
	if index < 0 or index >= party_mp.size() or amount <= 0:
		return
	party_mp[index] = mini(effective_max_mp(index), party_mp[index] + amount)
	EventBus.party_member_mp_changed.emit(index, party_mp[index], effective_max_mp(index))


func restore_party_mp_to_full() -> void:
	for i in party.size():
		if i >= party_mp.size():
			continue
		var max_mp: int = effective_max_mp(i)
		if party_mp[i] < max_mp:
			party_mp[i] = max_mp
			EventBus.party_member_mp_changed.emit(i, party_mp[i], max_mp)


func collect_recovery_orb(kind: StringName) -> int:
	if kind == RECOVERY_ORB_MP:
		return _restore_party_resource_evenly(kind, _orb_restore_amount(kind))
	return _restore_party_resource_evenly(RECOVERY_ORB_HP, _orb_restore_amount(RECOVERY_ORB_HP))


func _orb_restore_amount(kind: StringName) -> int:
	var missing: int = _total_missing_resource(kind)
	if missing <= 0:
		return 0
	return maxi(1, ceili(float(missing) * RECOVERY_ORB_MISSING_RATIO))


func _total_missing_resource(kind: StringName) -> int:
	var total: int = 0
	for i in party.size():
		total += _missing_resource(i, kind)
	return total


func _restore_party_resource_evenly(kind: StringName, amount: int) -> int:
	var remaining: int = maxi(0, amount)
	var restored: int = 0
	while remaining > 0:
		var targets: Array[int] = _resource_restore_targets(kind)
		if targets.is_empty():
			break
		var share: int = maxi(1, ceili(float(remaining) / float(targets.size())))
		var restored_this_pass: int = 0
		for index: int in targets:
			if remaining <= 0:
				break
			var restore_amount: int = mini(mini(share, remaining), _missing_resource(index, kind))
			if restore_amount <= 0:
				continue
			_apply_resource_restore(index, kind, restore_amount)
			remaining -= restore_amount
			restored += restore_amount
			restored_this_pass += restore_amount
		if restored_this_pass <= 0:
			break
	return restored


func _resource_restore_targets(kind: StringName) -> Array[int]:
	var targets: Array[int] = []
	for i in party.size():
		if _missing_resource(i, kind) > 0:
			targets.append(i)
	targets.sort_custom(func(a: int, b: int) -> bool:
		return _missing_resource(a, kind) > _missing_resource(b, kind)
	)
	return targets


func _missing_resource(index: int, kind: StringName) -> int:
	if index < 0 or index >= party.size():
		return 0
	if kind == RECOVERY_ORB_MP:
		if index >= party_mp.size():
			return 0
		return maxi(0, effective_max_mp(index) - party_mp[index])
	if index >= party_hp.size():
		return 0
	return maxi(0, effective_max_hp(index) - party_hp[index])


func _apply_resource_restore(index: int, kind: StringName, amount: int) -> void:
	if kind == RECOVERY_ORB_MP:
		restore_mp(index, amount)
	else:
		heal_party_member(index, amount)


# ─── Experience / Levels ──────────────────────────────────────────────
## Central XP / level pool. Every member shares the same counter so
## recruits never trail behind, and one level-up tick refreshes stats /
## HP / MP for the entire party in one pass.
func add_party_xp(amount: int) -> void:
	if amount <= 0 or party.is_empty():
		return
	if current_level >= MAX_CHARACTER_LEVEL:
		if current_xp != 0:
			current_xp = 0
			_emit_party_xp_changed()
		return
	if _defer_party_level_settlement:
		current_xp += amount
		_emit_party_xp_changed()
		return
	_settle_party_xp(amount, true)


func settle_deferred_party_level_ups(emit_level_up_signals: bool = true) -> int:
	if party.is_empty() or current_level >= MAX_CHARACTER_LEVEL:
		return 0
	return _settle_party_xp(0, emit_level_up_signals)


func pending_party_level_up_count() -> int:
	if party.is_empty() or current_level >= MAX_CHARACTER_LEVEL:
		return 0
	var simulated_level: int = current_level
	var simulated_xp: int = current_xp
	while simulated_level < MAX_CHARACTER_LEVEL and simulated_xp >= _xp_required_for_level(simulated_level):
		simulated_xp -= _xp_required_for_level(simulated_level)
		simulated_level += 1
	return simulated_level - current_level


func _settle_party_xp(extra_amount: int = 0, emit_level_up_signals: bool = true) -> int:
	var level_before: int = current_level
	current_xp += maxi(0, extra_amount)
	while current_level < MAX_CHARACTER_LEVEL and current_xp >= _xp_required_for_level(current_level):
		current_xp -= _xp_required_for_level(current_level)
		current_level += 1
	if current_level >= MAX_CHARACTER_LEVEL:
		current_xp = 0
	var levels_gained: int = current_level - level_before
	if levels_gained > 0:
		_apply_auto_skill_gains(level_before + 1, current_level)
		_apply_shared_level_gains(levels_gained, emit_level_up_signals)
		EventBus.party_hp_changed.emit()
	_emit_party_xp_changed()
	return levels_gained


func debug_level_up_party() -> void:
	if party.is_empty() or current_level >= MAX_CHARACTER_LEVEL:
		return
	var needed: int = maxi(1, _xp_required_for_level(current_level) - current_xp)
	add_party_xp(needed)


## Indexed accessors — every party member reports the same shared numbers,
## but the index-taking signature stays so HUD / boxes / tooltips don't
## need to change. The argument is ignored.
func party_level(_index: int = 0) -> int:
	return current_level


func party_xp_to_next(_index: int = 0) -> int:
	if current_level >= MAX_CHARACTER_LEVEL:
		return 1
	return _xp_required_for_level(current_level)


func party_xp_ratio(_index: int = 0) -> float:
	if current_level >= MAX_CHARACTER_LEVEL:
		return 1.0
	var to_next: int = _xp_required_for_level(current_level)
	if to_next <= 0:
		return 0.0
	return clampf(float(current_xp) / float(to_next), 0.0, 1.0)


## Bumps every member's HP/MP cap by their per-level growth × levels_gained,
## tops them off (if alive) by the gain, and emits all the per-member
## signals the HUD listens to.
func _apply_shared_level_gains(levels_gained: int, emit_level_up_signals: bool = true) -> void:
	if levels_gained <= 0:
		return
	for i in party.size():
		if i >= party_hp.size() or i >= party_mp.size():
			continue
		var character_id: StringName = party[i].id
		var hp_gain: int = _level_growth_value(character_id, "hp") * levels_gained
		var mp_gain: int = _level_growth_value(character_id, "mp") * levels_gained
		var new_max_hp: int = effective_max_hp(i)
		var new_max_mp: int = effective_max_mp(i)
		if is_alive(i):
			party_hp[i] = mini(new_max_hp, party_hp[i] + maxi(0, hp_gain))
			party_mp[i] = mini(new_max_mp, party_mp[i] + maxi(0, mp_gain))
		EventBus.party_member_hp_changed.emit(i, party_hp[i], new_max_hp)
		EventBus.party_member_mp_changed.emit(i, party_mp[i], new_max_mp)
		if emit_level_up_signals:
			EventBus.party_member_leveled_up.emit(i, current_level)


# ─── Level-up cards / skills ──────────────────────────────────────────
func level_up_card_offers() -> Array[ModifierData]:
	var offers: Array[ModifierData] = []
	var bump_attack_unlearned: bool = modifier_level(BUMP_ATTACK_ID) <= 0
	if bump_attack_unlearned:
		_append_level_up_offer(offers, BUMP_ATTACK_ID)
	var pool: Array[StringName] = []
	if not bump_attack_unlearned:
		for offer_id: StringName in LEVEL_UP_PARTY_CARD_OFFER_IDS:
			pool.append(offer_id)
	pool.shuffle()
	for offer_id: StringName in pool:
		if offers.size() >= LEVEL_UP_OFFER_COUNT:
			return offers
		_append_level_up_offer(offers, offer_id)
	return offers


func last_level_up_auto_skills() -> Array[ModifierData]:
	return _last_level_up_auto_skills.duplicate()


func apply_level_up_modifier(mod: ModifierData) -> bool:
	if mod == null or not can_add_modifier(mod):
		return false
	add_modifier(mod)
	EventBus.party_skills_changed.emit()
	EventBus.party_hp_changed.emit()
	return true


func _append_level_up_offer(offers: Array[ModifierData], offer_id: StringName) -> void:
	if offer_id == &"":
		return
	for existing: ModifierData in offers:
		if existing != null and existing.id == offer_id:
			return
	var mod: ModifierData = ModifierDB.get_by_id(offer_id)
	if mod != null and can_add_modifier(mod):
		offers.append(mod)


func _apply_auto_skill_gains(from_level: int, to_level: int) -> void:
	_last_level_up_auto_skills.clear()
	for level in range(from_level, to_level + 1):
		if not _is_auto_skill_level(level):
			continue
		for member: CharacterData in party:
			if member == null:
				continue
			var skill: ModifierData = _next_auto_skill_for_member(member.id)
			if skill == null:
				continue
			add_modifier(skill)
			_last_level_up_auto_skills.append(skill)
	if not _last_level_up_auto_skills.is_empty():
		EventBus.party_skills_changed.emit()


func _is_auto_skill_level(level: int) -> bool:
	if level == AUTO_SKILL_LEVEL_START:
		return true
	if level <= 0:
		return false
	return level % AUTO_SKILL_LEVEL_INTERVAL == 0


func _next_auto_skill_for_member(member_id: StringName) -> ModifierData:
	for skill_id: StringName in AUTO_SKILL_IDS_BY_MEMBER_ID.get(member_id, []):
		if modifier_level(skill_id) > 0:
			continue
		var skill: ModifierData = ModifierDB.get_by_id(skill_id)
		if skill != null and can_add_modifier(skill):
			return skill
	return null


# ─── Legacy skill tree ────────────────────────────────────────────────
## Spend one shared SP to unlock (or level up) a tree node. The pick goes
## into active_modifiers exactly like a level-up card pick so existing
## battle-effect code keeps working untouched.
func unlock_skill(mod: ModifierData) -> bool:
	if mod == null:
		return false
	if party_skill_points <= 0:
		return false
	if not can_add_modifier(mod):
		return false
	party_skill_points -= 1
	unlocked_tree_skills.append(mod.id)
	add_modifier(mod)
	EventBus.party_skill_points_changed.emit(party_skill_points)
	EventBus.party_skills_changed.emit()
	return true


## Refund every tree node the party has spent SP on, removing the matching
## modifiers from active_modifiers so stats / abilities revert immediately.
func reset_skills() -> void:
	var refund: int = unlocked_tree_skills.size()
	if refund <= 0:
		return
	var skill_ids: Dictionary = {}
	for id: StringName in unlocked_tree_skills:
		skill_ids[id] = true
	var kept: Array[ModifierData] = []
	for mod: ModifierData in active_modifiers:
		if skill_ids.has(mod.id):
			continue
		kept.append(mod)
	active_modifiers = kept
	unlocked_tree_skills.clear()
	party_skill_points += refund
	EventBus.party_skill_points_changed.emit(party_skill_points)
	EventBus.party_skills_changed.emit()
	EventBus.party_hp_changed.emit()


func skill_points() -> int:
	return party_skill_points


func _emit_party_xp_changed() -> void:
	var to_next: int = _xp_required_for_level(current_level) if current_level < MAX_CHARACTER_LEVEL else 1
	for i in party.size():
		EventBus.party_member_xp_changed.emit(i, current_xp, to_next, current_level)


func _xp_required_for_level(level: int) -> int:
	var l: int = maxi(1, level)
	var t: int = l - 1
	return XP_CURVE_BASE + t * XP_CURVE_LEVEL_STEP + t * t * XP_CURVE_QUADRATIC


func _level_bonus(index: int, key: String) -> int:
	if index < 0 or index >= party.size():
		return 0
	if current_level <= 1:
		return 0
	return _level_growth_value(party[index].id, key) * (current_level - 1)


func _level_growth_value(character_id: StringName, key: String) -> int:
	var growth: Dictionary = LEVEL_GROWTH_BY_CHARACTER_ID.get(character_id, DEFAULT_LEVEL_GROWTH)
	return int(growth.get(key, DEFAULT_LEVEL_GROWTH.get(key, 0)))


# ─── Economy ──────────────────────────────────────────────────────────
func add_gold(amount: int) -> void:
	gold += amount
	if amount > 0:
		total_gold_earned += amount
	EventBus.gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	EventBus.gold_changed.emit(gold)
	return true


func modifier_purchase_cost(mod: ModifierData) -> int:
	if mod == null:
		return 0
	if mod.category == ModifierData.Category.COMPANION or mod.max_level <= 1:
		return mod.cost
	var level: int = clampi(modifier_level(mod.id), 0, mod.max_level - 1)
	if level == 0:
		return mod.cost
	var raw_cost: float = float(mod.cost) * _price_multiplier_for_level(level)
	return maxi(mod.cost, ceili(raw_cost / 5.0) * 5)


func modifier_next_int_effect(mod: ModifierData, key: String) -> int:
	if mod == null:
		return 0
	return _int_effect_value_for_stack(mod, key, modifier_level(mod.id))


func modifier_last_int_effect(mod: ModifierData, key: String) -> int:
	if mod == null:
		return 0
	return _int_effect_value_for_stack(mod, key, maxi(0, modifier_level(mod.id) - 1))


func modifier_next_float_effect(mod: ModifierData, key: String) -> float:
	if mod == null:
		return 0.0
	return _float_effect_value_for_stack(mod, key, modifier_level(mod.id), _multipliers_for_float_key(key))


func modifier_last_float_effect(mod: ModifierData, key: String) -> float:
	if mod == null:
		return 0.0
	return _float_effect_value_for_stack(mod, key, maxi(0, modifier_level(mod.id) - 1), _multipliers_for_float_key(key))


## Check whether `mod` can actually be applied right now. Town shops should
## call this *before* spending gold so a stale/invalid card doesn't silently
## eat the player's coin.
func can_add_modifier(mod: ModifierData) -> bool:
	if mod == null:
		return false
	if mod.id == FIELD_MOVEMENT_ID and not is_system_unlocked(SYSTEM_FIELD_MOVEMENT):
		return false
	if mod.required_party_member_id != &"" and not has_party_member(mod.required_party_member_id):
		return false
	if mod.required_modifier_id != &"" and modifier_level(mod.required_modifier_id) < 1:
		return false
	if mod.category == ModifierData.Category.COMPANION:
		if _available_recruits(mod).is_empty():
			return false
	elif modifier_level(mod.id) >= mod.max_level:
		return false
	return true


func _on_modifier_purchase_requested(mod: ModifierData, source: Node) -> void:
	if not can_add_modifier(mod):
		EventBus.modifier_purchase_failed.emit(mod, source)
		return
	var cost: int = modifier_purchase_cost(mod)
	if not spend_gold(cost):
		EventBus.modifier_purchase_failed.emit(mod, source)
		return
	add_modifier(mod)
	EventBus.modifier_purchased.emit(mod)
	EventBus.card_purchased.emit(mod, cost)
	EventBus.modifier_purchase_succeeded.emit(mod, source)


func add_modifier(mod: ModifierData) -> void:
	# Companion cards take a different path: they grow the party instead of
	# stacking onto active_modifiers.
	if mod.category == ModifierData.Category.COMPANION:
		_recruit_companion(mod)
		return
	active_modifiers.append(mod)
	EventBus.modifier_picked.emit(mod)
	# Hearty-style: an HP bonus also heals up so the boost is felt immediately.
	# Per-hero HP cards only heal their owner; party-wide cards heal everyone.
	var hp_bonus: int = _int_effect_value_for_stack(mod, "hp_flat", modifier_level(mod.id) - 1)
	if hp_bonus != 0:
		var owner_id: StringName = mod.required_party_member_id
		for i in party.size():
			if owner_id != &"" and party[i].id != owner_id:
				continue
			var new_max_hp: int = effective_max_hp(i)
			if hp_bonus > 0:
				# Hearty-style heal: max HP gain also restores that much.
				party_hp[i] = min(party_hp[i] + hp_bonus, new_max_hp)
			else:
				# Risk-reward cards (Glass Cannon, etc): keep at least 1 HP and
				# clamp current HP to the new max so the cap shrinks honestly.
				new_max_hp = maxi(1, new_max_hp)
				party_hp[i] = clampi(party_hp[i], 1, new_max_hp)
			EventBus.party_member_hp_changed.emit(i, party_hp[i], new_max_hp)
		EventBus.party_hp_changed.emit()
	var mp_bonus: int = _int_effect_value_for_stack(mod, "mp_flat", modifier_level(mod.id) - 1)
	if mp_bonus != 0:
		var mp_owner_id: StringName = mod.required_party_member_id
		for i in party.size():
			if mp_owner_id != &"" and party[i].id != mp_owner_id:
				continue
			var new_max_mp: int = effective_max_mp(i)
			if mp_bonus > 0:
				party_mp[i] = min(party_mp[i] + mp_bonus, new_max_mp)
			else:
				new_max_mp = maxi(0, new_max_mp)
				party_mp[i] = clampi(party_mp[i], 0, new_max_mp)
			EventBus.party_member_mp_changed.emit(i, party_mp[i], new_max_mp)


func field_combat_movement_enabled() -> bool:
	return (
		is_system_unlocked(SYSTEM_FIELD_MOVEMENT)
		and (modifier_level(FIELD_MOVEMENT_ID) > 0 or _stacked_bool_effect("field_combat_movement"))
	)


func is_field_combat_locked() -> bool:
	return _active_battle_window_count > 0 and not field_combat_movement_enabled()


func _on_battle_window_opened(_window: Node) -> void:
	_active_battle_window_count += 1


func _on_battle_window_closed(_window: Node) -> void:
	_active_battle_window_count = maxi(0, _active_battle_window_count - 1)


## Direct character recruit — used by field events (campfire etc.) where
## there's no recruit modifier card to feed through _recruit_companion.
## Returns true if the character was added; false if they're already in
## the party (no duplicates).
func add_recruit(character: CharacterData) -> bool:
	if character == null:
		return false
	for existing: CharacterData in party:
		if existing != null and existing.id == character.id:
			return false
	party.append(character)
	party_equipment.append(_empty_equipment_slots())
	party_hp.append(effective_max_hp(party.size() - 1))
	party_mp.append(effective_max_mp(party.size() - 1))
	EventBus.party_changed.emit()
	# Fired AFTER party_changed so the HUD's member-box rebuild is already
	# done by the time the toast lands — the recruit's box can pulse along
	# with the banner instead of popping in on a stale row.
	EventBus.character_recruited.emit(character)
	return true


## Add the companion to the party. Caller must verify with can_add_modifier()
## first; this method asserts those preconditions and skips on failure to
## stay safe against logic errors.
## New member's starting HP/MP respects existing modifiers (e.g. Hearty bonus).
func _recruit_companion(mod: ModifierData) -> void:
	if not can_add_modifier(mod):
		push_warning("[GameState] _recruit_companion called with invalid mod: %s" % mod.id)
		return
	var recruits: Array[CharacterData] = _available_recruits(mod)
	if recruits.is_empty():
		return
	var recruited: CharacterData = recruits.pick_random()
	party.append(recruited)
	var idx: int = party.size() - 1
	# No per-member level/xp arrays anymore — recruits inherit the shared
	# current_level automatically. HP / MP start at the level-scaled max so
	# they're battle-ready instead of dragging around a Lv 1 statblock.
	party_equipment.append(_empty_equipment_slots())
	party_hp.append(effective_max_hp(idx))
	party_mp.append(effective_max_mp(idx))
	recruited_companions.append(mod)
	EventBus.modifier_picked.emit(mod)
	EventBus.party_changed.emit()
	EventBus.character_recruited.emit(recruited)


func _available_recruits(mod: ModifierData) -> Array[CharacterData]:
	var candidates: Array[CharacterData] = []
	if mod.companion_pool.is_empty():
		if mod.companion_data:
			candidates.append(mod.companion_data)
	else:
		candidates = mod.companion_pool.duplicate()
	var out: Array[CharacterData] = []
	for candidate: CharacterData in candidates:
		if candidate and not has_party_member(candidate.id):
			out.append(candidate)
	return out


func has_party_member(character_id: StringName) -> bool:
	for member: CharacterData in party:
		if member.id == character_id:
			return true
	return false


func is_system_unlocked(system_id: StringName) -> bool:
	return bool(unlocked_systems.get(system_id, false))


func unlocked_system_names() -> PackedStringArray:
	var names := PackedStringArray()
	for system_id: StringName in unlocked_systems.keys():
		if bool(unlocked_systems[system_id]):
			names.append(str(SYSTEM_UNLOCK_NAMES.get(system_id, system_id)))
	return names


func _apply_stage_unlocks() -> void:
	for system_id: StringName in SYSTEM_UNLOCK_STAGE.keys():
		var unlock_stage: int = int(SYSTEM_UNLOCK_STAGE[system_id])
		if current_stage >= unlock_stage:
			_unlock_system(system_id)


func _unlock_system(system_id: StringName) -> void:
	if is_system_unlocked(system_id):
		return
	unlocked_systems[system_id] = true
	EventBus.system_unlocked.emit(
		system_id,
		str(SYSTEM_UNLOCK_NAMES.get(system_id, system_id)),
		str(SYSTEM_UNLOCK_DESCRIPTIONS.get(system_id, ""))
	)


func modifier_level(modifier_id: StringName) -> int:
	var level: int = 0
	for mod: ModifierData in active_modifiers:
		if mod.id == modifier_id:
			level += 1
	return level


# ─── Stage ────────────────────────────────────────────────────────────
func advance_stage() -> void:
	current_stage += 1
	_apply_stage_unlocks()
	EventBus.stage_started.emit(current_stage)


# ─── Enemy scaling ────────────────────────────────────────────────────
func scaled_enemy_max_hp(data: EnemyData) -> int:
	if data == null:
		return 1
	return maxi(1, int(round(float(data.max_hp) * _enemy_hp_multiplier(data))))


func scaled_enemy_attack(data: EnemyData) -> int:
	if data == null:
		return 1
	return maxi(1, int(round(float(data.attack) * _enemy_attack_multiplier(data))))


func scaled_enemy_defense(data: EnemyData) -> int:
	if data == null:
		return 0
	var bonus: int = 0
	if data.id == &"orc":
		bonus = int(floor(float(_enemy_stage_index()) / 5.0))
	return maxi(0, data.defense + bonus)


func scaled_enemy_agility(data: EnemyData) -> int:
	if data == null:
		return 0
	var bonus: int = 0
	if data.id == &"bat":
		bonus = int(floor(float(_enemy_stage_index()) / 3.0))
	return maxi(0, data.agility + bonus)


func scaled_enemy_gold_reward(data: EnemyData) -> int:
	if data == null:
		return 0
	var bonus: int = mini(
		ENEMY_GOLD_STAGE_BONUS_CAP,
		int(floor(float(_enemy_stage_index()) / float(ENEMY_GOLD_STAGE_INTERVAL)))
	)
	return maxi(1, data.gold_reward + bonus)


func scaled_enemy_xp_reward(data: EnemyData) -> int:
	if data == null:
		return 0
	var stage_bonus: int = int(floor(float(_enemy_stage_index()) / 3.0))
	return maxi(1, data.xp_reward + stage_bonus)


func roll_battle_window_enemy_count() -> int:
	if not is_system_unlocked(SYSTEM_PACK_ENCOUNTERS):
		return 1
	var stage_bonus: int = maxi(0, current_stage - int(SYSTEM_UNLOCK_STAGE[SYSTEM_PACK_ENCOUNTERS]))
	var max_count: int = clampi(2 + int(floor(float(stage_bonus) / 3.0)), 2, BATTLE_WINDOW_MAX_ENEMIES)
	var extra_chance: float = clampf(0.25 + float(stage_bonus) * 0.06 + run_intensity() * 0.25, 0.0, 0.85)
	var count: int = 1
	for i in range(1, max_count):
		if randf() < extra_chance:
			count += 1
	return count


# ─── Equipment ────────────────────────────────────────────────────────
func collect_item(item: ItemData) -> bool:
	if item == null:
		return false
	if equip_item(item):
		return true
	add_item_to_inventory(item)
	return true


func add_item_to_inventory(item: ItemData) -> void:
	if item == null:
		return
	inventory.append(item)
	EventBus.inventory_changed.emit()


func equip_item(item: ItemData) -> bool:
	if item == null:
		return false
	var target_index: int = _equipment_target_index(item)
	if target_index < 0:
		return false
	var slot_index: int = _equipment_slot_index(target_index, item)
	if slot_index < 0:
		return false
	party_equipment[target_index][slot_index] = item
	party_hp[target_index] = mini(party_hp[target_index], effective_max_hp(target_index))
	party_mp[target_index] = mini(party_mp[target_index], effective_max_mp(target_index))
	EventBus.party_member_hp_changed.emit(target_index, party_hp[target_index], effective_max_hp(target_index))
	EventBus.party_member_mp_changed.emit(target_index, party_mp[target_index], effective_max_mp(target_index))
	EventBus.party_equipment_changed.emit(target_index)
	return true


func can_equip_item(item: ItemData) -> bool:
	return item != null and _equipment_target_index(item) >= 0


func inventory_items() -> Array[ItemData]:
	return inventory.duplicate()


func inventory_sell_value() -> int:
	var total: int = 0
	for item: ItemData in inventory:
		total += item_sell_value(item)
	return total


func item_sell_value(item: ItemData) -> int:
	if item == null:
		return 0
	var stat_total: int = maxi(0, item.attack_bonus)
	stat_total += maxi(0, item.defense_bonus)
	stat_total += maxi(0, item.agility_bonus)
	stat_total += ceili(float(maxi(0, item.max_hp_bonus)) * 0.25)
	stat_total += ceili(float(maxi(0, item.max_mp_bonus)) * 0.35)
	return maxi(4, 4 + stat_total * 2)


func sell_inventory_items() -> int:
	var value: int = inventory_sell_value()
	if value <= 0:
		return 0
	inventory.clear()
	EventBus.inventory_changed.emit()
	return value


func equipment_for_member(index: int) -> Array:
	if index < 0 or index >= party_equipment.size():
		return _empty_equipment_slots()
	return party_equipment[index].duplicate()


func _equipment_target_index(item: ItemData) -> int:
	if item.allowed_character_id != &"":
		for i in party.size():
			if party[i].id == item.allowed_character_id:
				return i
		return -1
	for i in party.size():
		var slot_index: int = _equipment_slot_index(i, item, false)
		if slot_index >= 0 and party_equipment[i][slot_index] == null:
			return i
	return 0 if not party.is_empty() else -1


func _equipment_slot_index(member_index: int, item: ItemData, allow_replace: bool = true) -> int:
	if member_index < 0 or member_index >= party_equipment.size():
		return -1
	if item.slot == ItemData.Slot.ACCESSORY:
		if party_equipment[member_index][EQUIPMENT_ACCESSORY_SLOT_A] == null:
			return EQUIPMENT_ACCESSORY_SLOT_A
		if party_equipment[member_index][EQUIPMENT_ACCESSORY_SLOT_B] == null:
			return EQUIPMENT_ACCESSORY_SLOT_B
		return EQUIPMENT_ACCESSORY_SLOT_A if allow_replace else -1
	return int(item.slot)


func _empty_equipment_slots() -> Array:
	var slots: Array = []
	for i in EQUIPMENT_SLOT_COUNT:
		slots.append(null)
	return slots


## Stage index now blends the (mostly-static) current_stage with the
## time-based difficulty tier so the field gets harder even without
## advancing stages.
func _enemy_stage_index() -> int:
	return maxi(0, current_stage - 1) + current_difficulty_tier()


## 0.0 at run start, 1.0 at the 30-min target, capped at 1.5 for long
## sessions. Smooth (no tier steps) so the threat ramp matches the way
## the party power-ups feel: every second the field's a little worse.
func run_intensity() -> float:
	return clampf(_difficulty_elapsed / RUN_TARGET_SECONDS, 0.0, RUN_INTENSITY_CAP)


func _enemy_hp_multiplier(data: EnemyData) -> float:
	var t: float = run_intensity()
	var base_mult: float = 1.0 + t * (ENEMY_HP_AT_TARGET - 1.0)
	return _enemy_species_multiplier(data, base_mult, 0.85, 0.9, 1.1)


func _enemy_attack_multiplier(data: EnemyData) -> float:
	var t: float = run_intensity()
	var base_mult: float = 1.0 + t * (ENEMY_ATK_AT_TARGET - 1.0)
	return _enemy_species_multiplier(data, base_mult, 0.8, 0.9, 1.1)


func _enemy_species_multiplier(
	data: EnemyData,
	base_mult: float,
	slime_growth: float,
	bat_growth: float,
	orc_growth: float
) -> float:
	var growth: float = 1.0
	if data.id == &"slime":
		growth = slime_growth
	elif data.id == &"bat":
		growth = bat_growth
	elif data.id == &"orc":
		growth = orc_growth
	return 1.0 + (base_mult - 1.0) * growth


# ─── Modifier-aware stat helpers ──────────────────────────────────────
## True if `mod` should affect the party member with `character_id`. Modifiers
## with no owner (party-wide) apply to everyone; class-tagged modifiers only
## apply to the matching member. The per-hero stat splits (ATK/HP/dodge) live
## here — that's how Sharper Blades-style cards stay scoped to one hero.
func _modifier_applies_to(mod: ModifierData, character_id: StringName) -> bool:
	return mod.required_party_member_id == &"" or mod.required_party_member_id == character_id


func _price_multiplier_for_level(level: int) -> float:
	return float(PRICE_LEVEL_MULTIPLIERS[mini(level, PRICE_LEVEL_MULTIPLIERS.size() - 1)])


func _effect_multiplier_for_stack(stack_index: int, multipliers: Array) -> float:
	return float(multipliers[mini(stack_index, multipliers.size() - 1)])


func _multipliers_for_float_key(key: String) -> Array:
	if key == "hero_damage_bonus_mult":
		return DAMAGE_BONUS_STACK_MULTIPLIERS
	return EFFECT_STACK_MULTIPLIERS


func _int_effect_value_for_stack(mod: ModifierData, key: String, stack_index: int) -> int:
	var base: int = int(mod.effect_data.get(key, 0))
	if base == 0:
		return 0
	var scaled: int = int(round(float(base) * _effect_multiplier_for_stack(stack_index, EFFECT_STACK_MULTIPLIERS)))
	# Preserve sign and guarantee non-zero magnitude so risk-reward cards
	# (Glass Cannon: hp_flat=-10) still apply even after stacking decay.
	if base > 0:
		return maxi(1, scaled)
	return mini(-1, scaled)


func _float_effect_value_for_stack(mod: ModifierData, key: String, stack_index: int, multipliers: Array) -> float:
	var base: float = float(mod.effect_data.get(key, 0.0))
	if base <= 0.0:
		return 0.0
	return base * _effect_multiplier_for_stack(stack_index, multipliers)


func _stacked_int_effect_for_character(character_id: StringName, key: String) -> int:
	var bonus: int = 0
	var stacks_by_id: Dictionary = {}
	for mod: ModifierData in active_modifiers:
		if not _modifier_applies_to(mod, character_id):
			continue
		if not mod.effect_data.has(key):
			continue
		var stack_index: int = int(stacks_by_id.get(mod.id, 0))
		stacks_by_id[mod.id] = stack_index + 1
		bonus += _int_effect_value_for_stack(mod, key, stack_index)
	return bonus


func _stacked_int_effect(key: String) -> int:
	var bonus: int = 0
	var stacks_by_id: Dictionary = {}
	for mod: ModifierData in active_modifiers:
		if not mod.effect_data.has(key):
			continue
		var stack_index: int = int(stacks_by_id.get(mod.id, 0))
		stacks_by_id[mod.id] = stack_index + 1
		bonus += _int_effect_value_for_stack(mod, key, stack_index)
	return bonus


func _stacked_bool_effect(key: String) -> bool:
	for mod: ModifierData in active_modifiers:
		if bool(mod.effect_data.get(key, false)):
			return true
	return false


func _stacked_float_effect(key: String, multipliers: Array) -> float:
	var bonus: float = 0.0
	var stacks_by_id: Dictionary = {}
	for mod: ModifierData in active_modifiers:
		if not mod.effect_data.has(key):
			continue
		var stack_index: int = int(stacks_by_id.get(mod.id, 0))
		stacks_by_id[mod.id] = stack_index + 1
		bonus += _float_effect_value_for_stack(mod, key, stack_index, multipliers)
	return bonus


func _stacked_float_effect_for_character(character_id: StringName, key: String, multipliers: Array) -> float:
	var bonus: float = 0.0
	var stacks_by_id: Dictionary = {}
	for mod: ModifierData in active_modifiers:
		if not _modifier_applies_to(mod, character_id):
			continue
		if not mod.effect_data.has(key):
			continue
		var stack_index: int = int(stacks_by_id.get(mod.id, 0))
		stacks_by_id[mod.id] = stack_index + 1
		bonus += _float_effect_value_for_stack(mod, key, stack_index, multipliers)
	return bonus


func effective_attack(index: int) -> int:
	if index < 0 or index >= party.size():
		return 0
	var character_id: StringName = party[index].id
	var flat_attack: int = party[index].attack + _level_bonus(index, "atk") + _equipment_bonus(index, "attack_bonus") + _stacked_int_effect_for_character(character_id, "atk_flat")
	var mult_bonus: float = _stacked_float_effect_for_character(character_id, "atk_mult", EFFECT_STACK_MULTIPLIERS)
	return maxi(0, int(round(float(flat_attack) * (1.0 + mult_bonus))))


func effective_defense(index: int) -> int:
	if index < 0 or index >= party.size():
		return 0
	var character_id: StringName = party[index].id
	return party[index].defense + _level_bonus(index, "def") + _equipment_bonus(index, "defense_bonus") + _stacked_int_effect_for_character(character_id, "def_flat")


func effective_agility(index: int) -> int:
	if index < 0 or index >= party.size():
		return 0
	var character_id: StringName = party[index].id
	return party[index].agility + _level_bonus(index, "agi") + _equipment_bonus(index, "agility_bonus") + _stacked_int_effect_for_character(character_id, "agi_flat")


func effective_move_speed(base_speed: float) -> float:
	var flat_bonus: float = float(_stacked_int_effect("move_speed_flat"))
	var mult_bonus: float = 0.0
	for mod: ModifierData in active_modifiers:
		mult_bonus += float(mod.effect_data.get("move_speed_mult", 0.0))
	return (base_speed + flat_bonus) * (1.0 + mult_bonus) * _active_move_speed_drag_multiplier() * _active_move_speed_boost_multiplier()


func apply_move_speed_drag(multiplier: float, duration: float) -> void:
	_move_speed_drag_multiplier = minf(_active_move_speed_drag_multiplier(), clampf(multiplier, 0.05, 1.0))
	_move_speed_drag_until_msec = Time.get_ticks_msec() + int(duration * 1000.0)


func apply_move_speed_boost(multiplier: float, duration: float) -> void:
	_move_speed_boost_multiplier = maxf(_active_move_speed_boost_multiplier(), maxf(multiplier, 1.0))
	_move_speed_boost_until_msec = Time.get_ticks_msec() + int(duration * 1000.0)


func clear_move_speed_drag() -> void:
	_move_speed_drag_multiplier = 1.0
	_move_speed_drag_until_msec = 0


func _active_move_speed_drag_multiplier() -> float:
	if Time.get_ticks_msec() > _move_speed_drag_until_msec:
		_move_speed_drag_multiplier = 1.0
	return _move_speed_drag_multiplier


func _active_move_speed_boost_multiplier() -> float:
	if Time.get_ticks_msec() > _move_speed_boost_until_msec:
		_move_speed_boost_multiplier = 1.0
	return _move_speed_boost_multiplier


func roll_evade(index: int) -> bool:
	if index < 0 or index >= party.size():
		return false
	var character_id: StringName = party[index].id
	var chance: float = _stacked_float_effect_for_character(character_id, "evade_chance", EFFECT_STACK_MULTIPLIERS)
	chance = clampf(chance, 0.0, 0.75)
	return randf() < chance


func hero_attack_multiplier() -> float:
	return 1.0 + _stacked_float_effect("hero_damage_bonus_mult", DAMAGE_BONUS_STACK_MULTIPLIERS)


func mage_splash_extra_targets() -> int:
	var extra_targets: int = 0
	for mod: ModifierData in active_modifiers:
		extra_targets += int(mod.effect_data.get("mage_splash_extra_targets", 0))
	return extra_targets


func mage_splash_damage_multiplier() -> float:
	var mult: float = 1.0
	for mod: ModifierData in active_modifiers:
		if mod.effect_data.has("mage_splash_damage_mult"):
			mult = minf(mult, float(mod.effect_data["mage_splash_damage_mult"]))
	return mult


func mage_firewall_damage(index: int) -> int:
	if index < 0 or index >= party.size():
		return 0
	return _stacked_int_effect_for_character(party[index].id, "mage_firewall_damage_flat")


func mage_firewall_unlocked(index: int) -> bool:
	if index < 0 or index >= party.size():
		return false
	return _stacked_int_effect_for_character(party[index].id, "mage_firewall_damage_flat") > 0


func priest_heal_amount() -> int:
	return _stacked_int_effect("priest_heal_flat")


# ─── Skill amounts driven by tree picks ───────────────────────────────
## Hero's Hoimi: small targeted heal. Hero-tagged so only the hero's own
## modifier stack contributes, even if another member somehow ends up with
## the same effect key.
func hero_hoimi_amount(index: int) -> int:
	if index < 0 or index >= party.size():
		return 0
	return _stacked_int_effect_for_character(party[index].id, "hero_heal_flat")


## Mage's Lightning Bolt: single-target damage + a chained spark.
func mage_lightning_damage(index: int) -> int:
	if index < 0 or index >= party.size():
		return 0
	return _stacked_int_effect_for_character(party[index].id, "lightning_damage_flat")


func mage_lightning_chain_chance(index: int) -> float:
	if index < 0 or index >= party.size():
		return 0.0
	return clampf(
		_stacked_float_effect_for_character(party[index].id, "lightning_chain_chance", DAMAGE_BONUS_STACK_MULTIPLIERS),
		0.0,
		1.0,
	)


## Priest's Holy Strike: chip damage that also tops the priest up.
func priest_holy_damage(index: int) -> int:
	if index < 0 or index >= party.size():
		return 0
	return _stacked_int_effect_for_character(party[index].id, "priest_holy_damage_flat")


func priest_holy_self_heal(index: int) -> int:
	if index < 0 or index >= party.size():
		return 0
	return _stacked_int_effect_for_character(party[index].id, "priest_holy_self_heal_flat")


func priest_attack_multiplier() -> float:
	var mult: float = 1.0
	for mod: ModifierData in active_modifiers:
		if mod.effect_data.has("priest_attack_mult"):
			mult = minf(mult, float(mod.effect_data["priest_attack_mult"]))
	return mult


func thief_steal_chance() -> float:
	var chance: float = _stacked_float_effect("thief_steal_chance", EFFECT_STACK_MULTIPLIERS)
	return clampf(chance, 0.0, 0.95)


func thief_steal_gold_amount() -> int:
	var amount: int = 0
	for mod: ModifierData in active_modifiers:
		amount = maxi(amount, int(mod.effect_data.get("thief_steal_gold", 0)))
	return amount


func effective_max_hp(index: int) -> int:
	if index < 0 or index >= party.size():
		return 0
	var character_id: StringName = party[index].id
	return party[index].max_hp + _level_bonus(index, "hp") + _equipment_bonus(index, "max_hp_bonus") + _stacked_int_effect_for_character(character_id, "hp_flat")


func effective_max_mp(index: int) -> int:
	if index < 0 or index >= party.size():
		return 0
	var character_id: StringName = party[index].id
	return party[index].max_mp + _level_bonus(index, "mp") + _equipment_bonus(index, "max_mp_bonus") + _stacked_int_effect_for_character(character_id, "mp_flat")


func _equipment_bonus(index: int, property_name: StringName) -> int:
	if index < 0 or index >= party_equipment.size():
		return 0
	var total: int = 0
	for item in party_equipment[index]:
		if item is ItemData:
			total += int((item as ItemData).get(property_name))
	return total


## Roll a crit. Returns { is_crit: bool, mult: float }.
## Multiple crit modifiers stack their chances (capped at 1.0); the largest
## multiplier wins.
func roll_crit() -> Dictionary:
	var total_chance: float = 0.0
	var max_mult: float = 1.0
	for mod: ModifierData in active_modifiers:
		total_chance += float(mod.effect_data.get("crit_chance", 0.0))
		var m: float = float(mod.effect_data.get("crit_mult", 1.0))
		if m > max_mult:
			max_mult = m
	total_chance = min(total_chance, 1.0)
	var rolled: bool = randf() < total_chance
	return { "is_crit": rolled, "mult": (max_mult if rolled else 1.0) }


## Roll Echo Strike-style modifiers. Returns the number of *extra* windows
## the encounter should spawn (beyond the original).
func roll_window_duplicates() -> int:
	var extras: int = 0
	for mod: ModifierData in active_modifiers:
		extras += int(mod.effect_data.get("extra_windows_flat", 0))
		var chance: float = float(mod.effect_data.get("duplicate_chance", 0.0))
		var max_dup: int = int(mod.effect_data.get("duplicate_max", 0))
		for j in max_dup:
			if randf() < chance:
				extras += 1
	return extras


func window_collision_damage_ratio() -> float:
	var ratio: float = 0.0
	for mod: ModifierData in active_modifiers:
		ratio = maxf(ratio, float(mod.effect_data.get("window_collision_damage_ratio", 0.0)))
	return ratio


func party_bump_damage_ratio() -> float:
	var ratio: float = 0.0
	for mod: ModifierData in active_modifiers:
		ratio = maxf(ratio, float(mod.effect_data.get("party_bump_damage_ratio", 0.0)))
	return ratio


func window_collision_heal_amount() -> int:
	return _stacked_int_effect("window_collision_heal_flat")


func window_shockwave_speed() -> float:
	var speed: float = 0.0
	for mod: ModifierData in active_modifiers:
		if mod.effect_data.has("window_shockwave_speed"):
			speed = maxf(speed, float(mod.effect_data.get("window_shockwave_speed", 0.0)))
	return speed


func window_fusion_enabled() -> bool:
	for mod: ModifierData in active_modifiers:
		if bool(mod.effect_data.get("window_fusion", false)):
			return true
	return false


func window_spin_enabled() -> bool:
	return window_spin_damage_ratio() > 0.0


func window_spin_damage_ratio() -> float:
	var ratio: float = 0.0
	for mod: ModifierData in active_modifiers:
		ratio = maxf(ratio, float(mod.effect_data.get("window_spin_damage_ratio", 0.0)))
	return ratio


func window_split_enabled() -> bool:
	for mod: ModifierData in active_modifiers:
		if bool(mod.effect_data.get("window_split", false)):
			return true
	return false


func window_bounce_multiplier() -> float:
	var multiplier: float = 1.0
	for mod: ModifierData in active_modifiers:
		multiplier = maxf(multiplier, float(mod.effect_data.get("window_bounce_mult", 1.0)))
	return multiplier


func window_bounce_speed_multiplier() -> float:
	var multiplier: float = 1.0
	for mod: ModifierData in active_modifiers:
		multiplier = maxf(multiplier, float(mod.effect_data.get("window_bounce_speed_mult", 1.0)))
	return multiplier


func window_bounce_enabled() -> bool:
	return window_bounce_multiplier() > 1.0 or window_bounce_speed_multiplier() > 1.0 or window_wall_bounce_restitution() > 0.0


func window_wall_bounce_restitution() -> float:
	var restitution: float = 0.0
	for mod: ModifierData in active_modifiers:
		restitution = maxf(restitution, float(mod.effect_data.get("window_wall_bounce_restitution", 0.0)))
	if restitution <= 0.0 and (window_bounce_multiplier() > 1.0 or window_bounce_speed_multiplier() > 1.0):
		restitution = 0.86
	return restitution


func window_wall_bounce_min_speed() -> float:
	var speed: float = 0.0
	for mod: ModifierData in active_modifiers:
		speed = maxf(speed, float(mod.effect_data.get("window_wall_bounce_min_speed", 0.0)))
	return speed


func battle_window_push_enabled() -> bool:
	return window_collision_damage_ratio() > 0.0


func party_window_push_enabled() -> bool:
	return party_bump_damage_ratio() > 0.0 or window_collision_heal_amount() > 0


## Apply gold modifiers to a base reward. Multiplicative then additive.
func modify_gold_reward(base: int) -> int:
	var mult: float = 1.0
	var flat: int = 0
	for mod: ModifierData in active_modifiers:
		mult *= float(mod.effect_data.get("gold_mult", 1.0))
		flat += int(mod.effect_data.get("gold_flat", 0))
	return int(round(base * mult)) + flat


# ─── Reset ────────────────────────────────────────────────────────────
func reset_run() -> void:
	party.clear()
	party_hp.clear()
	party_mp.clear()
	current_level = 1
	current_xp = 0
	party_equipment.clear()
	inventory.clear()
	gold = STARTING_GOLD
	total_gold_earned = 0
	enemies_killed = 0
	biggest_hit = 0
	active_modifiers.clear()
	recruited_companions.clear()
	party_skill_points = 0
	unlocked_tree_skills.clear()
	_last_level_up_auto_skills.clear()
	_move_speed_drag_multiplier = 1.0
	_move_speed_drag_until_msec = 0
	_move_speed_boost_multiplier = 1.0
	_move_speed_boost_until_msec = 0
	_active_battle_window_count = 0
	current_stage = 0
	run_started_at_ms = Time.get_ticks_msec()
	unlocked_systems.clear()
	# Make sure UI listeners flush stale numbers (HUD gold, etc.).
	EventBus.gold_changed.emit(gold)
