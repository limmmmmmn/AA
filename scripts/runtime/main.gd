extends Node2D

## Main entry point.
## Sets up the party and drives Field -> Town -> Field stage progression.
## Battle window spawning lives in BattleManager.

const TOWN_SCENE: PackedScene = preload("res://scenes/town2.tscn")
const GAME_OVER_SCENE: PackedScene = preload("res://scenes/game_over.tscn")
const HOME_BASE_SCENE: PackedScene = preload("res://scenes/home_base.tscn")
const EVENT_WINDOW_SCENE: PackedScene = preload("res://scenes/event_window.tscn")
const SLIME_DATA: EnemyData = preload("res://data/enemies/slime.tres")

## The run starts with the leader alone. Companions are recruited via
## town cards from the active prototype modifier pool.
const DEFAULT_PARTY_PATHS: PackedStringArray = [
	"res://data/characters/hero.tres",
]

@onready var _field: Field = $Field
@onready var _battle_manager: BattleManager = $BattleManager
@onready var _hud: HUD = $HUD
@onready var _pause_overlay: CanvasLayer = $PauseOverlay

var _town: Town2
var _game_over: GameOver
var _home_base: HomeBase
var _event_layer: CanvasLayer
var _is_manually_paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_set_run_layers_process_mode(Node.PROCESS_MODE_PAUSABLE)
	_pause_overlay.visible = false
	print("Appears! Appears! booted on Godot 4.6 | %dx%d" % [
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"),
	])
	_setup_default_party()
	EventBus.party_wiped.connect(_on_party_wiped)
	EventBus.stage_cleared.connect(_on_stage_cleared)
	EventBus.town_entered.connect(_on_town_entered)
	EventBus.event_tile_triggered.connect(_on_event_tile_triggered)
	# Kick off the first stage. Field listens to stage_started and spawns enemies.
	GameState.advance_stage()


func _setup_default_party() -> void:
	var members: Array[CharacterData] = []
	for path in DEFAULT_PARTY_PATHS:
		var data: CharacterData = load(path)
		if data:
			members.append(data)
	GameState.set_party(members)
	print("[main] party loaded: %d members" % GameState.party_size())


# ─── Stage flow ───────────────────────────────────────────────────────
func _on_stage_cleared(stage_num: int) -> void:
	print("[main] field cleared: %d (gold=%d)" % [stage_num, GameState.gold])
	_battle_manager.abort_all_battles()
	_show_town("Field %d Cleared" % stage_num)


func _on_town_entered(_tile: Node) -> void:
	print("[main] town tile entered — aborting active battles with no rewards")
	_battle_manager.abort_all_battles()
	_show_town("Town")


# ─── Field events ─────────────────────────────────────────────────────
## Campfire (and future event tiles) walk-into trigger. Pauses the field,
## pops a non-combat event window with the matching dialogue, and on
## completion applies the recruit + frees the tile so it can't re-fire.
func _on_event_tile_triggered(tile: Node) -> void:
	if _event_layer != null and is_instance_valid(_event_layer):
		return
	var ev_id: StringName = &""
	if tile != null and tile.has_method("event_id"):
		ev_id = tile.event_id()
	var dialogue: Array = _dialogue_for_event(ev_id)
	var recruit: CharacterData = _recruit_for_event(ev_id)
	var tile_tex: Texture2D = _tile_texture_for_event(ev_id)
	if dialogue.is_empty():
		return
	_set_manual_pause(false)
	var layer := CanvasLayer.new()
	layer.layer = 10
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_event_layer = layer
	var window: EventWindow = EVENT_WINDOW_SCENE.instantiate()
	# IMPORTANT: setup must run before add_child. Once we add the window,
	# its _ready fires immediately and reads recruit_data — if we set it
	# afterwards the mage visual never gets built.
	window.setup(ev_id, dialogue, recruit, tile_tex)
	layer.add_child(window)
	get_tree().paused = true
	window.event_completed.connect(_on_event_completed.bind(tile, recruit, layer))


func _dialogue_for_event(ev_id: StringName) -> Array:
	if ev_id == FieldCampfire.EVENT_ID:
		return [
			{"speaker": "마법사", "line": "난 불이 좋아"},
			{"speaker": "용사", "line": "더 태워볼래?"},
			{"speaker": "마법사", "line": "좋아 함께 가자"},
		]
	if ev_id == FieldShrine.EVENT_ID:
		return [
			{"speaker": "사제", "line": "상처를 입은 어린양이 여기 있군"},
			{"speaker": "용사", "line": "그게 바로 나야."},
		]
	return []


func _recruit_for_event(ev_id: StringName) -> CharacterData:
	if ev_id == FieldCampfire.EVENT_ID:
		var path: String = "res://data/characters/mage.tres"
		if ResourceLoader.exists(path):
			return load(path) as CharacterData
	if ev_id == FieldShrine.EVENT_ID:
		var path: String = "res://data/characters/priest.tres"
		if ResourceLoader.exists(path):
			return load(path) as CharacterData
	return null


## Picks the centerpiece sprite for the event window. New event tiles add
## a branch here so the right texture follows them into the popup.
func _tile_texture_for_event(ev_id: StringName) -> Texture2D:
	if ev_id == FieldCampfire.EVENT_ID:
		return load("res://assets/sprites/objects/bonfire.png") as Texture2D
	if ev_id == FieldShrine.EVENT_ID:
		return load("res://assets/sprites/objects/shrine.png") as Texture2D
	return null


func _on_event_completed(_ev_id: StringName, tile: Node, recruit: CharacterData, layer: CanvasLayer) -> void:
	if recruit != null:
		GameState.add_recruit(recruit)
	if tile != null and is_instance_valid(tile) and tile.has_method("consume"):
		tile.consume()
	if is_instance_valid(layer):
		layer.queue_free()
	if _event_layer == layer:
		_event_layer = null
	get_tree().paused = false


func _show_town(title: String = "") -> void:
	if _town and is_instance_valid(_town):
		return
	_set_manual_pause(false)
	_town = TOWN_SCENE.instantiate()
	_town.setup(title)
	_town.closed.connect(_on_town_closed)
	add_child(_town)
	_set_run_layers_visible(false)
	get_tree().paused = true


func _on_town_closed() -> void:
	_town = null
	get_tree().paused = false
	_set_run_layers_visible(true)
	EventBus.town_closed.emit()
	GameState.advance_stage()


func _set_run_layers_visible(should_show: bool) -> void:
	_field.visible = should_show
	_battle_manager.visible = should_show
	_hud.visible = should_show


func _set_run_layers_process_mode(mode: ProcessMode) -> void:
	_field.process_mode = mode
	_battle_manager.process_mode = mode
	_hud.process_mode = mode


func _on_party_wiped() -> void:
	print("[main] PARTY WIPED — gold: %d | modifiers: %d | companions: %d | party: %d" % [
		GameState.gold,
		GameState.active_modifiers.size(),
		GameState.recruited_companions.size(),
		GameState.party_size(),
	])
	_show_home_base()


# ─── Home base (post-wipe Suikoden hub) ───────────────────────────────
func _show_home_base() -> void:
	if _home_base and is_instance_valid(_home_base):
		return
	_set_manual_pause(false)
	# Close town if it happens to be up (defensive — shouldn't be).
	if _town and is_instance_valid(_town):
		_town.queue_free()
		_town = null
	# Hide the run layers so only the base shows. We keep the party intact
	# here so the base can render its current roster; reset happens on deploy.
	_set_run_layers_visible(false)
	get_tree().paused = false
	_home_base = HOME_BASE_SCENE.instantiate()
	_home_base.deploy_pressed.connect(_on_deploy_pressed)
	add_child(_home_base)


func _on_deploy_pressed() -> void:
	_set_manual_pause(false)
	if _home_base and is_instance_valid(_home_base):
		_home_base.queue_free()
	_home_base = null
	_set_run_layers_visible(true)
	GameState.reset_run()
	_setup_default_party()
	# Field listens for stage_started to clear/respawn enemies + recenter the
	# party. set_party (above) already triggered party_changed → fresh visuals.
	GameState.advance_stage()


# ─── Debug ────────────────────────────────────────────────────────────
func _set_manual_pause(is_paused: bool) -> void:
	_is_manually_paused = is_paused
	_pause_overlay.visible = is_paused
	get_tree().paused = is_paused


## F1 = instant stage clear (skip combat to test town)
## F2 = stress spawn 20 battle windows
## F3 = spawn one of each field enemy type
## F4 = toggle auto_battle skill (manual DQ1 mode vs auto windows)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if get_tree().paused:
			return
		if _is_manually_paused:
			return
		match event.physical_keycode:
			KEY_F1:
				print("[main] DEBUG: forcing stage_cleared")
				EventBus.stage_cleared.emit(GameState.current_stage)
			KEY_F2:
				_debug_stress_spawn(20)
			KEY_F3:
				_debug_spawn_all_enemy_types()
			KEY_F4:
				_debug_toggle_auto_battle()


func _debug_stress_spawn(count: int) -> void:
	var mgr: BattleManager = get_node_or_null("BattleManager")
	if mgr == null:
		return
	for i in count:
		mgr.spawn_battle(SLIME_DATA)
	print("[main] DEBUG: spawned %d battle windows (active=%d)" % [count, mgr.active_window_count()])


func _debug_spawn_all_enemy_types() -> void:
	var spawned_count: int = _field.debug_spawn_all_enemy_types()
	print("[main] DEBUG: spawned %d field enemy types" % spawned_count)


## Flip the auto_battle skill on/off so we can sanity-check both encounter
## paths in one sitting. The skill is a single-level on/off card — adding it
## once is enough to leave manual mode; stripping the entry from
## active_modifiers puts the player back in DQ1 land.
func _debug_toggle_auto_battle() -> void:
	if GameState.is_manual_battle_mode():
		var mod: ModifierData = ModifierDB.get_by_id(GameState.AUTO_BATTLE_ID)
		if mod == null:
			push_warning("[main] DEBUG: auto_battle modifier missing from DB")
			return
		GameState.add_modifier(mod)
		print("[main] DEBUG: auto_battle ON — encounters now use battle windows")
		return
	var kept: Array[ModifierData] = []
	for entry: ModifierData in GameState.active_modifiers:
		if entry.id != GameState.AUTO_BATTLE_ID:
			kept.append(entry)
	GameState.active_modifiers = kept
	print("[main] DEBUG: auto_battle OFF — encounters now open the manual screen")
