class_name Town2
extends CanvasLayer

## Streamlined between-stage town. Three zones, in descending size:
##   • Top:    4 big offer cards (the actual decision). Buying exhausts that
##             slot until the player rerolls or visits town again.
##   • Middle: a thin feed of party rows — one line each, "[NAME] [stats]
##             [• upgrade • upgrade ...]". Empty hero rows are hidden so the
##             feed only shows recruited members and grows organically.
##   • Bottom: utility bar — Reroll (small), and a prominent Continue.

signal closed

const CARD_SCENE: PackedScene = preload("res://scenes/ui/town2_card.tscn")
const LEVEL_UP_STAT_PANEL_SCENE: PackedScene = preload("res://scenes/ui/level_up_stat_panel.tscn")
const LEVEL_UP_PANEL_SCENE: PackedScene = preload("res://scenes/ui/level_up_panel.tscn")
const CARD_SLOTS: int = 4
const REROLL_COST: int = 5
const LOOT_BIN_POSITION: Vector2 = Vector2(320.0, 312.0)
const LOOT_BIN_SIZE: Vector2 = Vector2(172.0, 28.0)
const LOOT_DROP_START: Vector2 = Vector2(320.0, 248.0)
const LOOT_BODY_SIZE: Vector2 = Vector2(18.0, 18.0)
const LOOT_GRAVITY: float = 920.0
const LOOT_BOUNCE: float = 0.34
const LOOT_FRICTION: float = 0.82
const LOOT_SELL_TICK_SECONDS: float = 0.025
const LOOT_SELL_MAX_TICKS: int = 34

## Stat-card ids that don't get a Trello row — the owner's stat panel already
## shows the buff (ATK number going up), so an extra "ATK ×3" line would be
## redundant noise.
const SILENT_STAT_IDS: Dictionary = {
	&"atk_up": true,
	&"hero_atk_10p": true,
	&"mage_atk_10p": true,
	&"priest_atk_10p": true,
	&"thief_atk_10p": true,
	&"hp_up": true,
	&"agi_up": true,
}

@onready var _stage_label: Label = %StageLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _top_zone: HBoxContainer = %TopZone
@onready var _reroll_button: Button = %RerollButton
@onready var _continue_button: Button = %ContinueButton
@onready var _slot_party: Town2Slot = %SlotParty
@onready var _slot_hero: Town2Slot = %SlotHero
@onready var _slot_mage: Town2Slot = %SlotMage
@onready var _slot_priest: Town2Slot = %SlotPriest
@onready var _slot_thief: Town2Slot = %SlotThief

var _cards: Array[Town2Card] = []
var _hero_slots_by_id: Dictionary = {}  # StringName -> Town2Slot (per-member)
var _all_slots: Array[Town2Slot] = []
var _title_override: String = ""
var _stat_panel: LevelUpStatPanel
var _level_up_panel: LevelUpPanel
var _pending_level_up_choice_rounds: int = 0
var _settled_levels_gained: int = 0
var _loot_bin_layer: Node2D
var _loot_box_root: Node2D
var _loot_physics_bodies: Array[Dictionary] = []
var _sell_loot_button: Button
var _loot_sell_value: int = 0
var _loot_sale_running: bool = false


func setup(title_override: String = "") -> void:
	_title_override = title_override


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED


func _ready() -> void:
	_stage_label.text = _title_override if not _title_override.is_empty() else "Town"
	_settled_levels_gained = GameState.settle_deferred_party_level_ups(false)
	_heal_party_to_full()
	_refresh_gold_label()
	_register_slots()
	_seed_slots_from_active_modifiers()
	_build_top_cards()
	_refresh_offers()
	_continue_button.pressed.connect(_on_continue_pressed)
	_reroll_button.pressed.connect(_on_reroll_pressed)
	_reroll_button.text = "Reroll  %d G" % REROLL_COST
	_build_loot_bin()
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.party_changed.connect(_on_party_changed)
	EventBus.party_member_hp_changed.connect(_on_party_member_hp_changed)
	EventBus.party_member_mp_changed.connect(_on_party_member_mp_changed)
	EventBus.modifier_purchase_succeeded.connect(_on_modifier_purchase_succeeded)
	EventBus.modifier_purchase_failed.connect(_on_modifier_purchase_failed)
	_focus_first_available_card()
	if _settled_levels_gained > 0:
		call_deferred("_open_town_level_up_settlement")


func _physics_process(delta: float) -> void:
	_tick_loot_physics(delta)


# ─── Slot wiring ──────────────────────────────────────────────────────
func _register_slots() -> void:
	_all_slots = [_slot_party, _slot_hero, _slot_mage, _slot_priest, _slot_thief]
	_hero_slots_by_id = {
		&"hero": _slot_hero,
		&"mage": _slot_mage,
		&"priest": _slot_priest,
		&"thief": _slot_thief,
	}
	for slot in _all_slots:
		slot.refresh()


## On entry, populate each slot's upgrade list from what the player already
## owns — modifiers persist across town visits, so the list should reflect
## that history rather than starting empty each time.
func _seed_slots_from_active_modifiers() -> void:
	for slot in _all_slots:
		slot.clear_upgrades()
	for mod: ModifierData in GameState.active_modifiers:
		_route_to_slot(mod)


## Place the modifier's title in its target slot. Companion cards intentionally
## skip routing — the recruited member's own slot transitioning from EMPTY to
## PRESENT *is* the visual feedback, and routing them all to PARTY would just
## stack duplicate "Recruit" lines. Plain stat-up cards (ATK +6, HP +10) also
## skip routing because the slot's stat panel already reflects the buff.
func _route_to_slot(mod: ModifierData) -> void:
	if mod.category == ModifierData.Category.COMPANION:
		return
	if SILENT_STAT_IDS.has(mod.id):
		return
	var owner_id: StringName = mod.required_party_member_id
	if owner_id == &"":
		_slot_party.add_upgrade(mod)
		return
	var slot: Town2Slot = _hero_slots_by_id.get(owner_id, null)
	if slot:
		slot.add_upgrade(mod)


func _refresh_all_slots() -> void:
	for slot in _all_slots:
		slot.refresh()


# ─── Card row ─────────────────────────────────────────────────────────
func _build_top_cards() -> void:
	_cards.clear()
	# Top zone is now cards-only — reroll lives in the bottom bar.
	for i in CARD_SLOTS:
		var card: Town2Card = CARD_SCENE.instantiate()
		card.purchase_requested.connect(_on_card_purchase_requested)
		_top_zone.add_child(card)
		_cards.append(card)


## Full random redraw — used on entry and on reroll. Each visible card is
## unique within the current draw to avoid the visual stutter of duplicates.
func _refresh_offers() -> void:
	var pool: Array[ModifierData] = _offerable_pool()
	pool.shuffle()
	_prioritize_field_movement_offer(pool)
	for i in CARD_SLOTS:
		_cards[i].setup(pool[i] if i < pool.size() else null)


## Replace just one slot with a new offer the player doesn't already see in
## another card. Kept for future targeted redraws; purchases intentionally do
## not call this so the shop cannot refill forever.
func _redraw_card(card_index: int) -> void:
	var displayed: Dictionary = {}
	for i in CARD_SLOTS:
		if i == card_index:
			continue
		var c: Town2Card = _cards[i]
		if c.data:
			displayed[c.data.id] = true
	var candidates: Array[ModifierData] = []
	for mod: ModifierData in _offerable_pool():
		if not displayed.has(mod.id):
			candidates.append(mod)
	var slot: Town2Card = _cards[card_index]
	if candidates.is_empty():
		slot.setup(null)
	else:
		slot.setup(candidates.pick_random())


func _offerable_pool() -> Array[ModifierData]:
	var out: Array[ModifierData] = []
	for mod: ModifierData in ModifierDB.get_all():
		if ModifierDB.is_shop_offer(mod) and GameState.can_add_modifier(mod):
			out.append(mod)
	return out


func _prioritize_field_movement_offer(pool: Array[ModifierData]) -> void:
	var field_move: ModifierData = ModifierDB.get_by_id(GameState.FIELD_MOVEMENT_ID)
	if field_move == null or not GameState.can_add_modifier(field_move):
		return
	for i in pool.size():
		if pool[i] != null and pool[i].id == GameState.FIELD_MOVEMENT_ID:
			pool.remove_at(i)
			break
	pool.push_front(field_move)


# ─── Purchase flow ────────────────────────────────────────────────────
func _on_card_purchase_requested(_card: Town2Card, mod: ModifierData) -> void:
	EventBus.modifier_purchase_requested.emit(mod, _card)


func _on_modifier_purchase_succeeded(mod: ModifierData, source: Node) -> void:
	var card := source as Town2Card
	if card == null or not is_instance_valid(card):
		return
	_route_to_slot(mod)
	_refresh_all_slots()
	var idx: int = _cards.find(card)
	if idx >= 0:
		card.setup(null)
		_focus_first_available_card()


func _on_modifier_purchase_failed(_mod: ModifierData, source: Node) -> void:
	var card := source as Town2Card
	if card == null or not is_instance_valid(card):
		return
	card.mark_unaffordable_flash()


# ─── Deferred Level Settlement ────────────────────────────────────────
func _open_town_level_up_settlement() -> void:
	if _settled_levels_gained <= 0:
		return
	_pending_level_up_choice_rounds = maxi(1, _settled_levels_gained)
	_stat_panel = LEVEL_UP_STAT_PANEL_SCENE.instantiate()
	_stat_panel.setup(_settled_levels_gained, GameState.last_level_up_auto_skills())
	add_child(_stat_panel)
	_stat_panel.confirmed.connect(_on_town_stat_panel_confirmed)
	_stat_panel.tree_exited.connect(func() -> void:
		_stat_panel = null
	)


func _on_town_stat_panel_confirmed() -> void:
	call_deferred("_open_town_level_up_offer_sequence")


func _open_town_level_up_offer_sequence() -> void:
	if _pending_level_up_choice_rounds <= 0:
		_seed_slots_from_active_modifiers()
		_refresh_all_slots()
		_refresh_offers()
		_focus_first_available_card()
		return
	_pending_level_up_choice_rounds -= 1
	var offers: Array[ModifierData] = GameState.level_up_card_offers()
	if offers.is_empty():
		call_deferred("_open_town_level_up_offer_sequence")
		return
	_level_up_panel = LEVEL_UP_PANEL_SCENE.instantiate()
	_level_up_panel.setup(-1, "파티", offers)
	add_child(_level_up_panel)
	_level_up_panel.modifier_chosen.connect(_on_town_level_up_modifier_chosen)
	_level_up_panel.tree_exited.connect(func() -> void:
		_level_up_panel = null
	)


func _on_town_level_up_modifier_chosen(_member_index: int, mod: ModifierData) -> void:
	if GameState.apply_level_up_modifier(mod):
		_route_to_slot(mod)
		_refresh_all_slots()
	call_deferred("_open_town_level_up_offer_sequence")


# ─── Loot Bin ─────────────────────────────────────────────────────────
func _build_loot_bin() -> void:
	var items: Array[ItemData] = GameState.inventory_items()
	if items.is_empty():
		return
	_loot_sell_value = GameState.inventory_sell_value()
	_loot_bin_layer = Node2D.new()
	_loot_bin_layer.name = "LootBinPhysics"
	_loot_bin_layer.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(_loot_bin_layer)
	_build_open_loot_box()
	_drop_loot_items(items)
	_build_sell_loot_button(items.size())


func _build_open_loot_box() -> void:
	var box_root := Node2D.new()
	_loot_box_root = box_root
	box_root.name = "OpenLootBox"
	box_root.position = LOOT_BIN_POSITION
	box_root.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_loot_bin_layer.add_child(box_root)
	_add_loot_box_wall(box_root, Vector2(0.0, LOOT_BIN_SIZE.y * 0.5), Vector2(LOOT_BIN_SIZE.x, 7.0), Color(0.44, 0.26, 0.12))
	_add_loot_box_wall(box_root, Vector2(-LOOT_BIN_SIZE.x * 0.5, 3.0), Vector2(7.0, LOOT_BIN_SIZE.y), Color(0.52, 0.31, 0.15))
	_add_loot_box_wall(box_root, Vector2(LOOT_BIN_SIZE.x * 0.5, 3.0), Vector2(7.0, LOOT_BIN_SIZE.y), Color(0.36, 0.2, 0.1))
	_add_loot_box_floor_visual(box_root)


func _add_loot_box_wall(parent: Node2D, local_position: Vector2, size: Vector2, color: Color) -> void:
	var body := StaticBody2D.new()
	body.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	body.position = local_position
	parent.add_child(body)
	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	body.add_child(collision)
	var visual := ColorRect.new()
	visual.color = color
	visual.size = size
	visual.position = -size * 0.5
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(visual)


func _add_loot_box_floor_visual(parent: Node2D) -> void:
	var back := Polygon2D.new()
	back.color = Color(0.68, 0.43, 0.2, 0.8)
	back.polygon = PackedVector2Array([
		Vector2(-LOOT_BIN_SIZE.x * 0.5, -LOOT_BIN_SIZE.y * 0.5),
		Vector2(LOOT_BIN_SIZE.x * 0.5, -LOOT_BIN_SIZE.y * 0.5),
		Vector2(LOOT_BIN_SIZE.x * 0.5 - 8.0, LOOT_BIN_SIZE.y * 0.5),
		Vector2(-LOOT_BIN_SIZE.x * 0.5 + 8.0, LOOT_BIN_SIZE.y * 0.5),
	])
	back.z_index = -1
	parent.add_child(back)


func _drop_loot_items(items: Array[ItemData]) -> void:
	_loot_physics_bodies.clear()
	for i in items.size():
		var item: ItemData = items[i]
		var body := RigidBody2D.new()
		body.name = "LootItem"
		body.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
		body.freeze = true
		body.collision_layer = 0
		body.collision_mask = 0
		body.position = LOOT_DROP_START + Vector2(randf_range(-64.0, 64.0), -float(i) * 7.0)
		body.rotation = randf_range(-0.7, 0.7)
		var velocity := Vector2(randf_range(-45.0, 45.0), randf_range(-10.0, 12.0))
		var spin: float = randf_range(-6.0, 6.0)
		_loot_bin_layer.add_child(body)
		var shape := RectangleShape2D.new()
		shape.size = LOOT_BODY_SIZE
		var collision := CollisionShape2D.new()
		collision.shape = shape
		body.add_child(collision)
		if item != null and item.icon != null:
			var sprite := Sprite2D.new()
			sprite.texture = item.icon
			sprite.scale = _loot_icon_scale(item.icon)
			body.add_child(sprite)
		else:
			var fallback := ColorRect.new()
			fallback.color = Color(0.95, 0.85, 0.35)
			fallback.size = LOOT_BODY_SIZE
			fallback.position = -LOOT_BODY_SIZE * 0.5
			fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
			body.add_child(fallback)
		_loot_physics_bodies.append({
			"body": body,
			"velocity": velocity,
			"spin": spin,
			"settled": false,
		})


func _tick_loot_physics(delta: float) -> void:
	if _loot_sale_running or _loot_physics_bodies.is_empty() or not is_instance_valid(_loot_box_root):
		return
	var half_size: Vector2 = LOOT_BODY_SIZE * 0.5
	var left: float = -LOOT_BIN_SIZE.x * 0.5 + half_size.x + 4.0
	var right: float = LOOT_BIN_SIZE.x * 0.5 - half_size.x - 4.0
	var bottom: float = LOOT_BIN_SIZE.y * 0.5 - half_size.y - 4.0
	for i in _loot_physics_bodies.size():
		var entry: Dictionary = _loot_physics_bodies[i]
		var body := entry.get("body", null) as Node2D
		if body == null or not is_instance_valid(body):
			continue
		var velocity: Vector2 = entry.get("velocity", Vector2.ZERO)
		var spin: float = float(entry.get("spin", 0.0))
		velocity.y += LOOT_GRAVITY * delta
		body.position += velocity * delta
		body.rotation += spin * delta

		var local: Vector2 = _loot_box_root.to_local(body.position)
		if local.y >= bottom:
			local.y = bottom
			body.position = _loot_box_root.to_global(local)
			velocity.y = -absf(velocity.y) * LOOT_BOUNCE
			velocity.x *= LOOT_FRICTION
			spin *= 0.72
			if absf(velocity.y) < 18.0:
				velocity.y = 0.0
		if local.y > -LOOT_BIN_SIZE.y * 0.5:
			if local.x < left:
				local.x = left
				body.position = _loot_box_root.to_global(local)
				velocity.x = absf(velocity.x) * LOOT_BOUNCE
				spin *= -0.55
			elif local.x > right:
				local.x = right
				body.position = _loot_box_root.to_global(local)
				velocity.x = -absf(velocity.x) * LOOT_BOUNCE
				spin *= -0.55
		if local.y >= bottom and absf(velocity.y) < 1.0:
			velocity.x = move_toward(velocity.x, 0.0, 80.0 * delta)
			spin = move_toward(spin, 0.0, 6.0 * delta)
		entry["velocity"] = velocity
		entry["spin"] = spin
		_loot_physics_bodies[i] = entry


func _loot_icon_scale(texture: Texture2D) -> Vector2:
	var texture_size: Vector2 = texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return Vector2.ONE
	var longest: float = maxf(texture_size.x, texture_size.y)
	return Vector2.ONE * (18.0 / longest)


func _build_sell_loot_button(item_count: int) -> void:
	_sell_loot_button = Button.new()
	_sell_loot_button.name = "SellLootButton"
	_sell_loot_button.text = "Sell Loot  +%d G" % _loot_sell_value
	_sell_loot_button.tooltip_text = "장착하지 않은 아이템 %d개 판매" % item_count
	_sell_loot_button.add_theme_font_size_override("font_size", 10)
	_sell_loot_button.size = Vector2(118.0, 24.0)
	_sell_loot_button.position = Vector2(406.0, 298.0)
	_sell_loot_button.disabled = true
	_sell_loot_button.pressed.connect(_on_sell_loot_pressed)
	add_child(_sell_loot_button)
	var tween: Tween = create_tween()
	tween.tween_interval(0.85)
	tween.tween_callback(func() -> void:
		if is_instance_valid(_sell_loot_button):
			_sell_loot_button.disabled = false
	)


func _on_sell_loot_pressed() -> void:
	if _loot_sale_running or _loot_sell_value <= 0:
		return
	var sale_value: int = GameState.sell_inventory_items()
	if sale_value <= 0:
		return
	_loot_sale_running = true
	_sell_loot_button.disabled = true
	_sell_loot_button.text = "Sold!"
	_fade_loot_bodies()
	_roll_gold_gain(sale_value)


func _fade_loot_bodies() -> void:
	if not is_instance_valid(_loot_bin_layer):
		return
	_loot_physics_bodies.clear()
	for child: Node in _loot_bin_layer.get_children():
		if child is RigidBody2D:
			var body := child as RigidBody2D
			body.freeze = true
			var tween: Tween = body.create_tween().set_parallel(true)
			tween.tween_property(body, "modulate:a", 0.0, 0.35)
			tween.tween_property(body, "scale", Vector2(1.35, 0.55), 0.35)\
				.set_trans(Tween.TRANS_BACK)\
				.set_ease(Tween.EASE_IN)
			tween.chain().tween_callback(body.queue_free)


func _roll_gold_gain(amount: int) -> void:
	var ticks: int = mini(LOOT_SELL_MAX_TICKS, maxi(1, amount))
	var base: int = int(floor(float(amount) / float(ticks)))
	var remainder: int = amount - base * ticks
	for i in ticks:
		var gain: int = base + (1 if i < remainder else 0)
		if gain > 0:
			GameState.add_gold(gain)
		await get_tree().create_timer(LOOT_SELL_TICK_SECONDS).timeout
	if is_instance_valid(_sell_loot_button):
		_sell_loot_button.queue_free()
	_sell_loot_button = null
	_loot_sale_running = false


# ─── Reroll / Recovery ────────────────────────────────────────────────
func _on_reroll_pressed() -> void:
	if not GameState.spend_gold(REROLL_COST):
		_flash_red(_reroll_button)
		return
	_refresh_offers()
	_focus_first_available_card()


func _heal_party_to_full() -> void:
	for i in GameState.party_size():
		var max_hp: int = GameState.effective_max_hp(i)
		if GameState.party_hp[i] < max_hp:
			GameState.heal_party_member(i, max_hp - GameState.party_hp[i])
	GameState.restore_party_mp_to_full()


# ─── Reactive plumbing ────────────────────────────────────────────────
func _on_party_changed() -> void:
	_seed_slots_from_active_modifiers()
	_refresh_all_slots()


func _on_party_member_hp_changed(_index: int, _new_hp: int, _max_hp: int) -> void:
	_refresh_all_slots()


func _on_party_member_mp_changed(_index: int, _new_mp: int, _max_mp: int) -> void:
	_refresh_all_slots()


func _on_gold_changed(_new_gold: int) -> void:
	_refresh_gold_label()


func _refresh_gold_label() -> void:
	_gold_label.text = "%d G" % GameState.gold


# ─── Focus / arrow cursor ─────────────────────────────────────────────
func _focus_first_available_card() -> void:
	for card in _cards:
		if not card.disabled:
			card.grab_focus()
			return
	_continue_button.grab_focus()


func _focus_after_purchase(card_index: int) -> void:
	var same: Town2Card = _cards[card_index]
	if not same.disabled:
		same.grab_focus()
		return
	_focus_first_available_card()


func _flash_red(target: Control) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(target, "modulate", Color(1, 0.4, 0.4, 1), 0.1)
	tween.tween_property(target, "modulate", Color.WHITE, 0.2)


func _on_continue_pressed() -> void:
	closed.emit()
	queue_free()
