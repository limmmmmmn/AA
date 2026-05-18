extends Node

## Catalog of every modifier in the game.
## Loads the active prototype pool. Older cards remain under data/modifiers/
## as archived resources, but are intentionally excluded from shop offers.
## Query by id / rarity / category, or pull random offerings for the shop.

const ACTIVE_POOL: ModifierPoolData = preload("res://data/modifiers/prototype_pool.tres")
const FALLBACK_POOL_DIR: String = "res://data/modifiers/prototype"
const OFFER_MODE_FIXED_ORDER: ModifierPoolData.OfferMode = ModifierPoolData.OfferMode.FIXED_ORDER
const OFFER_MODE_RANDOM_UNIQUE: ModifierPoolData.OfferMode = ModifierPoolData.OfferMode.RANDOM_UNIQUE
const LEVEL_UP_ONLY_EFFECT_KEYS: Array[String] = [
	"atk_flat",
	"atk_mult",
	"hp_flat",
	"mp_flat",
	"def_flat",
	"agi_flat",
	"evade_chance",
	"hero_damage_bonus_mult",
	"mage_splash_extra_targets",
	"mage_firewall_damage_flat",
	"priest_heal_flat",
	"thief_steal_chance",
	"window_shockwave_speed",
	"window_fusion",
	"window_spin_damage_ratio",
	"window_split",
	"window_bounce_mult",
	"window_bounce_speed_mult",
	"window_wall_bounce_restitution",
	"window_wall_bounce_min_speed",
]

var _all: Array[ModifierData] = []
var _by_id: Dictionary = {}                  # StringName -> ModifierData
var _by_rarity: Dictionary = {}              # Rarity -> Array[ModifierData]
var _active_offer_paths: PackedStringArray = []


func _ready() -> void:
	_load_all()
	print("[ModifierDB] loaded %d modifiers" % _all.size())


func _load_all() -> void:
	_all.clear()
	_by_id.clear()
	_by_rarity.clear()
	_active_offer_paths = _resolve_offer_paths()
	for path in _active_offer_paths:
		var resource := load(path)
		if resource is ModifierData:
			_register(resource)
	# Build rarity buckets.
	for mod: ModifierData in _all:
		var bucket: Array = _by_rarity.get(mod.rarity, [])
		bucket.append(mod)
		_by_rarity[mod.rarity] = bucket


func _register(mod: ModifierData) -> void:
	if mod.id == &"":
		push_warning("[ModifierDB] modifier has empty id: %s" % mod.resource_path)
		return
	if _by_id.has(mod.id):
		push_warning("[ModifierDB] duplicate id: %s" % mod.id)
		return
	_all.append(mod)
	_by_id[mod.id] = mod


# ─── Queries ──────────────────────────────────────────────────────────
func get_by_id(id: StringName) -> ModifierData:
	return _by_id.get(id, null)


func get_by_rarity(rarity: ModifierData.Rarity) -> Array[ModifierData]:
	var typed: Array[ModifierData] = []
	for mod: ModifierData in _by_rarity.get(rarity, []):
		typed.append(mod)
	return typed


func count() -> int:
	return _all.size()


func get_all() -> Array[ModifierData]:
	return _all.duplicate()


func is_shop_offer(mod: ModifierData) -> bool:
	if mod == null:
		return false
	if mod.level_up_only:
		return false
	for key: String in LEVEL_UP_ONLY_EFFECT_KEYS:
		if mod.effect_data.has(key):
			return false
	return true


## Pull `n` random modifiers (with replacement = false).
## Prototype mode supports fixed-order offers so purchase data is cleaner.
func get_random_modifiers(n: int) -> Array[ModifierData]:
	return get_shop_offers(n)


func get_shop_offers(n: int) -> Array[ModifierData]:
	var out: Array[ModifierData] = []
	if ACTIVE_POOL.offer_mode == OFFER_MODE_FIXED_ORDER:
		for i in mini(n, _active_offer_paths.size()):
			var fixed_mod := get_by_path(_active_offer_paths[i])
			if fixed_mod and GameState.can_add_modifier(fixed_mod):
				out.append(fixed_mod)
		return out
	if ACTIVE_POOL.offer_mode == OFFER_MODE_RANDOM_UNIQUE:
		var pool: Array[ModifierData] = _offerable_modifiers()
		pool.shuffle()
		for i in mini(n, pool.size()):
			out.append(pool[i])
		return out
	for i in n:
		var pool: Array[ModifierData] = _offerable_modifiers()
		if pool.is_empty():
			break
		out.append(pool.pick_random())
	return out


func get_random_offer_excluding(excluded_ids: Dictionary) -> ModifierData:
	var pool: Array[ModifierData] = []
	for mod: ModifierData in _offerable_modifiers():
		if not excluded_ids.has(mod.id):
			pool.append(mod)
	if pool.is_empty():
		return null
	return pool.pick_random()


func get_by_path(path: String) -> ModifierData:
	var resource := load(path)
	if resource is ModifierData:
		return resource
	return null


func _offerable_modifiers() -> Array[ModifierData]:
	var out: Array[ModifierData] = []
	for mod: ModifierData in _all:
		if is_shop_offer(mod) and GameState.can_add_modifier(mod):
			out.append(mod)
	return out


func _resolve_offer_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	for path: String in ACTIVE_POOL.offer_paths:
		paths.append(path)
	if not paths.is_empty():
		return paths
	print("[ModifierDB] prototype_pool has no offer_paths; scanning %s" % FALLBACK_POOL_DIR)
	var dir := DirAccess.open(FALLBACK_POOL_DIR)
	if dir == null:
		push_warning("[ModifierDB] fallback pool dir not found: %s" % FALLBACK_POOL_DIR)
		return paths
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			paths.append("%s/%s" % [FALLBACK_POOL_DIR, file_name])
		file_name = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths
