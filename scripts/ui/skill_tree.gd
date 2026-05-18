class_name SkillTree
extends Control

signal node_hovered_signal(node: SkillNode)
signal node_exited_signal(node: SkillNode)
signal exit_requested(direction: Vector2)

const STEP_X: float = 26.0
const STEP_Y: float = 16.0
const NODE_HALF: Vector2 = Vector2(8, 8)
const ZOOM_MIN: float = 0.35
const ZOOM_MAX: float = 2.0
const ZOOM_FACTOR: float = 1.12
const LINE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.82)
const LINE_WIDTH: float = 2.0
const NODE_DATA_DIR: String = "res://data/skill_nodes"

var _skill_node_scene: PackedScene = preload("res://scenes/ui/skill_node.tscn")
var _defined_nodes: Dictionary = {}
var _nodes: Dictionary = {}
var _edges: Dictionary = {}
var _edge_progress: Dictionary = {}
var _center: Vector2
var _selected_grid: Vector2i = Vector2i.ZERO
var _has_played_opening: bool = false


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	_center = custom_minimum_size / 2.0
	pivot_offset = _center
	_load_node_definitions()
	_spawn_node(Vector2i.ZERO)
	_expand_around(Vector2i.ZERO)
	_select_first_available(Vector2i(0, -2))


func open_for_keyboard() -> void:
	grab_focus.call_deferred()
	if not _has_played_opening:
		_play_opening_reveal()
		_has_played_opening = true
	else:
		_select_first_available(_selected_grid)


func handle_keyboard_event(event: InputEventKey) -> bool:
	if event == null or event.echo or not event.pressed:
		return false
	return _handle_key(event)


func _spawn_node(grid: Vector2i) -> SkillNode:
	if _nodes.has(grid):
		return _nodes[grid]

	var node: SkillNode = _skill_node_scene.instantiate()
	var defined: SkillNodeData = _defined_nodes.get(grid) as SkillNodeData
	if defined != null:
		node.skill_id = defined.skill_id
		node.skill_name = defined.skill_name
		node.description = defined.description
		node.cost = defined.cost
	else:
		node.skill_id = &""
		node.skill_name = "???"
		node.description = "다음 노드가 들어설 자리."
		node.cost = 0
	node.tooltip_text = node.description

	add_child(node)
	node.position = _center - NODE_HALF + Vector2(grid.x * STEP_X, grid.y * STEP_Y)
	_nodes[grid] = node

	node.node_unlocked.connect(_on_node_unlocked)
	node.node_hovered.connect(_on_node_hovered)
	node.node_exited.connect(_on_node_exited)
	node.focus_entered.connect(_on_node_focus_entered.bind(node))

	if not node.is_empty() and RunState.is_unlocked(node.skill_id):
		_expand_around(grid)

	return node


func _load_node_definitions() -> void:
	_defined_nodes.clear()
	var dir: DirAccess = DirAccess.open(NODE_DATA_DIR)
	if dir == null:
		push_warning("Skill node data directory not found: %s" % NODE_DATA_DIR)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var path: String = "%s/%s" % [NODE_DATA_DIR, file_name]
			var data: SkillNodeData = ResourceLoader.load(path) as SkillNodeData
			if data != null and not data.hidden:
				_defined_nodes[data.grid] = data
		file_name = dir.get_next()
	dir.list_dir_end()


func _expand_around(grid: Vector2i, animate: bool = false) -> void:
	const DIRS: Array[Vector2i] = [
		Vector2i(0, -1),
		Vector2i(0, 1),
		Vector2i(-1, 0),
		Vector2i(1, 0),
	]
	var dist: int = 2 if grid == Vector2i.ZERO else 1
	for dir in DIRS:
		var target: Vector2i = grid + dir * dist
		if abs(target.x) + abs(target.y) == 1:
			continue
		if not _defined_nodes.has(target):
			continue
		var node: SkillNode = _spawn_node(target)
		_add_edge(target, grid, animate)
		if animate:
			node.reveal_pop(0.08)


func _find_grid(node: SkillNode) -> Variant:
	for g in _nodes.keys():
		if _nodes[g] == node:
			return g
	return null


func _on_node_unlocked(node: SkillNode) -> void:
	var grid = _find_grid(node)
	if grid != null:
		_expand_around(grid, true)
		_select_grid(grid)


func _on_node_hovered(node: SkillNode) -> void:
	grab_focus()
	var grid = _find_grid(node)
	if grid != null and _is_selectable_grid(grid):
		_select_grid(grid, false)
	node_hovered_signal.emit(node)


func _on_node_exited(node: SkillNode) -> void:
	node_exited_signal.emit(node)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(ZOOM_FACTOR)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0 / ZOOM_FACTOR)
			accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		if _handle_key(event as InputEventKey):
			accept_event()


func _zoom(factor: float) -> void:
	var new_scale: Vector2 = scale * factor
	new_scale.x = clamp(new_scale.x, ZOOM_MIN, ZOOM_MAX)
	new_scale.y = clamp(new_scale.y, ZOOM_MIN, ZOOM_MAX)
	scale = new_scale


func _draw() -> void:
	for target in _edges.keys():
		var parent: Vector2i = _edges[target]
		if not _nodes.has(target) or not _nodes.has(parent):
			continue
		var from_pos: Vector2 = _node_center(parent)
		var to_pos: Vector2 = _node_center(target)
		var progress: float = float(_edge_progress.get(target, 1.0))
		var end_pos: Vector2 = from_pos.lerp(to_pos, progress)
		draw_line(from_pos, end_pos, LINE_COLOR, LINE_WIDTH)


func _node_center(grid: Vector2i) -> Vector2:
	var node: SkillNode = _nodes[grid]
	return node.position + node.size * 0.5


func _play_opening_reveal() -> void:
	for node in _nodes.values():
		(node as SkillNode).scale = Vector2.ZERO
		(node as SkillNode).modulate.a = 0.0
	for target in _edges.keys():
		_edge_progress[target] = 1.0
	queue_redraw()

	var center_node: SkillNode = _nodes[Vector2i.ZERO]
	center_node.reveal_pop()

	var delay: float = 0.14
	for grid in _ordered_grids_for_opening():
		if grid == Vector2i.ZERO:
			continue
		var node: SkillNode = _nodes[grid]
		node.reveal_pop(delay)
		delay += 0.04
	_select_first_available(Vector2i(0, -2))


func _ordered_grids_for_opening() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for grid in _nodes.keys():
		out.append(grid)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da: int = absi(a.x) + absi(a.y)
		var db: int = absi(b.x) + absi(b.y)
		if da == db:
			if a.y == b.y:
				return a.x < b.x
			return a.y < b.y
		return da < db
	)
	return out


func _select_grid(grid: Vector2i, emit_hover: bool = true) -> void:
	if not _is_selectable_grid(grid):
		return
	if _nodes.has(_selected_grid):
		(_nodes[_selected_grid] as SkillNode).set_keyboard_selected(false)
	_selected_grid = grid
	var node: SkillNode = _nodes[_selected_grid]
	node.set_keyboard_selected(true)
	if emit_hover:
		node_hovered_signal.emit(node)


func _handle_key(event: InputEventKey) -> bool:
	match event.physical_keycode:
		KEY_LEFT, KEY_A:
			_move_or_request_exit(Vector2.LEFT)
			return true
		KEY_RIGHT, KEY_D:
			_move_or_request_exit(Vector2.RIGHT)
			return true
		KEY_UP, KEY_W:
			_move_or_request_exit(Vector2.UP)
			return true
		KEY_DOWN, KEY_S:
			_move_or_request_exit(Vector2.DOWN)
			return true
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_activate_selected()
			return true
	return false


func _move_or_request_exit(dir: Vector2) -> void:
	if not _move_selection(dir):
		exit_requested.emit(dir)


func _move_selection(dir: Vector2) -> bool:
	var current_pos: Vector2 = _grid_world_pos(_selected_grid)
	var best_grid: Variant = null
	var best_score: float = INF
	for grid in _nodes.keys():
		if grid == _selected_grid or not _is_selectable_grid(grid):
			continue
		var delta: Vector2 = _grid_world_pos(grid) - current_pos
		if delta == Vector2.ZERO or delta.normalized().dot(dir) < 0.55:
			continue
		var side_penalty: float = absf(delta.cross(dir)) * 0.35
		var score: float = delta.length() + side_penalty
		if score < best_score:
			best_score = score
			best_grid = grid
	if best_grid != null:
		_select_grid(best_grid)
		return true
	return false


func _grid_world_pos(grid: Vector2i) -> Vector2:
	return Vector2(grid.x * STEP_X, grid.y * STEP_Y)


func _activate_selected() -> void:
	if not _is_selectable_grid(_selected_grid):
		return
	(_nodes[_selected_grid] as SkillNode).activate()


func _on_node_focus_entered(node: SkillNode) -> void:
	var grid = _find_grid(node)
	if grid != null and _is_selectable_grid(grid):
		_select_grid(grid)


func _is_selectable_grid(grid: Vector2i) -> bool:
	if not _nodes.has(grid):
		return false
	return not (_nodes[grid] as SkillNode).is_empty()


func _select_first_available(preferred: Vector2i) -> void:
	if _is_selectable_grid(preferred):
		_select_grid(preferred)
		return
	for grid in _ordered_grids_for_opening():
		if _is_selectable_grid(grid):
			_select_grid(grid)
			return


func _add_edge(target: Vector2i, parent: Vector2i, animate: bool) -> void:
	var is_new_edge: bool = not _edges.has(target)
	_edges[target] = parent
	if not animate or not is_new_edge:
		_edge_progress[target] = 1.0
		queue_redraw()
		return
	_edge_progress[target] = 0.0
	var tween: Tween = create_tween()
	tween.tween_method(_set_edge_progress.bind(target), 0.0, 1.0, 0.24)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)


func _set_edge_progress(value: float, target: Vector2i) -> void:
	_edge_progress[target] = value
	queue_redraw()
