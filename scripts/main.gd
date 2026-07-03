extends Node2D
## v2.0 메인 오케스트레이터 — "기지 ↔ 필드" 룸 시스템
## 룸 = 정확히 카메라 한 화면 (640×360). 스크롤/줌 없음. 전투창은 룸 전환을 관통한다.

const ROOM := Vector2(640, 360)
const WIN_L := Vector2(150, 84)
const WIN_S := Vector2(126, 74)

const CHIEF_LINES := [
	"마왕은 이미 세계를 손에 넣었습니다. …그래도, 하시겠습니까?",
	"계획도에 소문이 모이면, 골드가 길을 만듭니다.",
	"일행이 지치면 여관으로. 쓰러지면 교회로.",
	"성문 밖은 지배자들의 땅입니다. 멀리 갈수록 벌이도, 위험도 큽니다.",
]
const BOSS_TEX := [
	"res://assets/enemies/slime_fly.png",
	"res://assets/enemies/bat.png",
	"res://assets/enemies/slime_chaser.png",
	"res://assets/enemies/slime_fly.png",
	"res://assets/enemies/bat.png",
]
const BUILD_POS := {
	"smith": Vector2(95, 260), "church": Vector2(545, 90),
	"chest": Vector2(320, 285), "bard": Vector2(395, 70), "casino": Vector2(175, 295),
}
const POT_SPOTS := [
	Vector2(240, 190), Vector2(270, 215), Vector2(370, 215), Vector2(400, 190), Vector2(240, 250),
	Vector2(400, 250), Vector2(320, 165), Vector2(285, 250), Vector2(355, 165),
]

var base_root: Node2D
var field_root: Node2D
var shared_root: Node2D       # 파티 + 꽃돼지 (룸을 넘나드는 것들)
var party: Party
var hud: Hud
var tree_ui: RebuildTree

var current_room := -1        # -1 기지, 0~4 필드
var last_field := 0
var base_nodes := {}          # kind → Interactable
var boss_node: FieldMonster = null
var boss_fighting := false
var boss_field := 0
var windows: Array = []
var pending_gold := 0         # 부재중 조수 수확 (귀향 연출)

var _monster_timer := 0.0
var _sparkle_timer := 5.0
var _golden_timer := 90.0
var _save_timer := 20.0
var _rumor_timer := 1.0
var _hover_node: Node2D = null
var _wipe_lock := false
var _transitioning := false
var _full_msg_cd := 0.0
var _chief_wiped := false
var _chief_i := 0
var _field_exit: Interactable = null

# ================================================================ setup

func _ready() -> void:
	base_root = Node2D.new()
	add_child(base_root)
	field_root = Node2D.new()
	field_root.visible = false
	add_child(field_root)
	shared_root = Node2D.new()
	add_child(shared_root)

	_build_base()

	party = Party.new()
	party.init_at(Vector2(320, 220))
	party.bumped.connect(_on_bump)
	party.ai_query = Callable(self, "_ai_pick")
	shared_root.add_child(party)

	hud = Hud.new()
	hud.main = self
	add_child(hud)

	tree_ui = RebuildTree.new()
	tree_ui.main = self
	hud.add_child(tree_ui)

	Game.party_wiped.connect(_on_wipe)

	# 조수 복원 (꽃돼지는 shared, 나머지는 기지)
	for kind in Game.assistants.keys():
		for i in Game.assistants[kind]:
			spawn_assistant(kind)

	# 항상 열려 있는 노드는 조용히 공개
	for n in RebuildTree.NODES:
		if (n["reveal"] as Dictionary).is_empty():
			Game.tree_revealed[n["id"]] = true

	_golden_timer = 90.0 if not Game.golden_first_done else randf_range(150.0, 300.0)
	UILib.set_cursor("point")
	hud.room_name = "기지"
	hud._update_top()
	_prologue()

	if OS.get_environment("AAA_SMOKE") == "1":
		var smoke: Node = load("res://scripts/dev_smoke.gd").new()
		smoke.set("main", self)
		add_child(smoke)

func _prologue() -> void:
	if Game.total_earned > 0 or Game.level > 1:
		return
	hud.event("『일어나렴, 용사야.』", 3.0)
	get_tree().create_timer(3.2).timeout.connect(func():
		hud.event("용사는 일어났다. 그러나, 너무 늦었다.", 4.0))
	get_tree().create_timer(7.6).timeout.connect(func():
		hud.event("WASD로 걷는다. 성문 앞에서 Space — 그리고 몬스터에 부딪히면… 전투다.", 6.0))

# ================================================================ 기지 룸

func _build_base() -> void:
	for c in base_root.get_children():
		c.queue_free()
	base_nodes = {}
	# 바닥 — 마을은 어떤 색에도 물들지 않는다
	_ground(base_root, "res://assets/Tiles/Grass_Middle.png", Color(1, 1, 1))
	_repeat_sprite(base_root, "res://assets/Tiles/Path_Middle.png", Rect2(0, 0, 440, 260), Vector2(100, 60))
	_repeat_sprite(base_root, "res://assets/Tiles/Path_Middle.png", Rect2(0, 0, 100, 32), Vector2(540, 174))
	# 장식
	for p in [Vector2(40, 60), Vector2(50, 320), Vector2(600, 330), Vector2(590, 60)]:
		_decor(base_root, "res://assets/objects/forest.png", p, Color(1, 1, 1))
	# 건물 — 여관은 처음부터, 나머지는 재건 계획도로
	base_nodes["inn"] = _add_thing(base_root, "inn", Vector2(95, 90))
	base_nodes["chief"] = _add_thing(base_root, "chief", Vector2(305, 135))
	base_nodes["board"] = _add_thing(base_root, "board", Vector2(355, 135))
	base_nodes["gate"] = _add_thing(base_root, "gate", Vector2(612, 190))
	for k in BUILD_POS.keys():
		if Game.buildings.get(k, false):
			base_nodes[k] = _add_thing(base_root, k, BUILD_POS[k])
	# 항아리
	var pot_n: int = mini(5 + Game.extra_pots * 2, POT_SPOTS.size())
	for i in pot_n:
		_add_thing(base_root, "pot", POT_SPOTS[i])

func _ground(root: Node2D, tex: String, tint: Color) -> Sprite2D:
	var s := _repeat_sprite(root, tex, Rect2(0, 0, ROOM.x, ROOM.y), Vector2.ZERO)
	s.modulate = tint
	return s

func _repeat_sprite(root: Node2D, tex_path: String, region: Rect2, pos: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load(tex_path)
	s.centered = false
	s.region_enabled = true
	s.region_rect = region
	s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	s.position = pos
	root.add_child(s)
	return s

func _decor(root: Node2D, tex_path: String, pos: Vector2, tint: Color) -> void:
	var s := Sprite2D.new()
	s.texture = load(tex_path)
	s.offset = Vector2(0, -s.texture.get_height() / 2.0)
	s.position = pos
	s.modulate = tint
	root.add_child(s)

func _add_thing(root: Node2D, kind: String, pos: Vector2, recruit_cls: String = "") -> Interactable:
	var n := Interactable.new()
	n.setup(kind, recruit_cls)
	n.position = pos
	root.add_child(n)
	return n

# ================================================================ 필드 룸

func _build_field(f: int) -> void:
	for c in field_root.get_children():
		c.queue_free()
	var tint: Color = Game.FIELD_TINTS[f]
	_ground(field_root, "res://assets/Tiles/Grass_Middle.png", tint)
	# 특산 장식
	var decor_tex := "res://assets/objects/forest.png" if f <= 1 else "res://assets/objects/hill.png"
	var decor_n := 12 if f == 1 else 6
	if f == 4:
		decor_tex = "res://assets/objects/tower.png"
		decor_n = 4
	for i in decor_n:
		var p := Vector2(randf_range(70, 550), randf_range(50, 320))
		_decor(field_root, decor_tex, p, tint)
	# 출구 (왼쪽) / 지배자 (최심부 오른쪽)
	_field_exit = _add_thing(field_root, "exit", Vector2(22, 190))
	_spawn_boss(f)
	# 몬스터 첫 스폰
	for i in 8:
		_spawn_monster(f)
	# 숲은 반짝이 밭
	if f == 1:
		for i in 3:
			_spawn_sparkle()

func goto_room(idx: int) -> void:
	if _transitioning or _wipe_lock or boss_fighting:
		return
	_transitioning = true
	Sfx.play("warp")
	hud.fade_quick(func(): _set_room(idx))
	get_tree().create_timer(0.6).timeout.connect(func(): _transitioning = false)

func _set_room(idx: int) -> void:
	current_room = idx
	base_root.visible = idx == -1
	field_root.visible = idx != -1
	if idx >= 0:
		last_field = idx
		_build_field(idx)
		party.teleport(Vector2(42, 190))
		hud.room_name = Game.FIELD_NAMES[idx]
	else:
		for c in field_root.get_children():
			c.queue_free()
		boss_node = null
		party.teleport(Vector2(586, 190))
		hud.room_name = "기지"
		_harvest_pending()
	hud._update_top()

func _harvest_pending() -> void:
	# 귀향 연출 — 조수들이 모아둔 것을 한꺼번에
	if pending_gold <= 0:
		return
	var g := pending_gold
	pending_gold = 0
	Game.add_gold(g)
	Sfx.play("gold_big")
	hud.coin_burst(Vector2(586, 190), 8)
	hud.event("다녀왔습니다! 조수들이 %d G를 모아 뒀다." % g, 4.0)

# ================================================================ loop

func _process(delta: float) -> void:
	_full_msg_cd = maxf(0.0, _full_msg_cd - delta)
	_update_hover()
	if _wipe_lock:
		return

	# 필드에서만: 몬스터/반짝이
	if current_room >= 0:
		_monster_timer -= delta
		if _monster_timer <= 0.0:
			_monster_timer = 0.8
			var pop := 0
			for m in get_tree().get_nodes_in_group("monster"):
				if is_instance_valid(m) and not m.is_boss:
					pop += 1
			var target: int = 8 + (current_room + 1) * 2 + (4 if current_room == 2 else 0)
			if pop < target:
				_spawn_monster(current_room)
		_sparkle_timer -= delta
		if _sparkle_timer <= 0.0:
			_sparkle_timer = 4.0 if current_room == 1 else 10.0
			var count := 0
			for n in get_tree().get_nodes_in_group("hoverable"):
				if n is Interactable and n.kind == "sparkle":
					count += 1
			if count < 6:
				_spawn_sparkle()

	# 황금 슬라임 (설원에 있으면 배로 잦다)
	_golden_timer -= delta * (2.0 if current_room == 3 else 1.0)
	if _golden_timer <= 0.0:
		_try_spawn_golden()

	# 소문(이중 열쇠) + 동료 영입
	_rumor_timer -= delta
	if _rumor_timer <= 0.0:
		_rumor_timer = 1.0
		_check_rumors()
		_check_recruits()

	_save_timer -= delta
	if _save_timer <= 0.0:
		_save_timer = 20.0
		Game.save_game()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Game.save_game()

# ================================================================ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if tree_ui.visible:
					tree_ui.close()
				else:
					hud.close_menu()
			KEY_TAB:
				hud.close_menu()
				tree_ui.toggle()
			KEY_SPACE:
				_space_interact()
			KEY_F11:
				var mode := DisplayServer.window_get_mode()
				if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				else:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _space_interact() -> void:
	if _wipe_lock or _transitioning:
		return
	if tree_ui.visible:
		return
	if hud.is_menu_open():
		hud.close_menu()
		return
	party.manual_hold = 4.0
	var best: Node2D = null
	var best_d := 1e9
	for n in get_tree().get_nodes_in_group("hoverable"):
		if not is_instance_valid(n) or not n.is_visible_in_tree():
			continue
		var d: float = party.head_pos.distance_to(n.position)
		if d < n.pick_radius() + 10.0 and d < best_d:
			best_d = d
			best = n
	if best != null:
		_on_bump(best)
	else:
		Sfx.play("bump", 0.8)

# ================================================================ hover (시선에는 힘이 있다)

func _update_hover() -> void:
	if _wipe_lock:
		UILib.set_cursor("point")
		return
	var ctrl := get_viewport().gui_get_hovered_control()
	if ctrl != null:
		var bw := _find_battle_window(ctrl)
		if bw != null:
			UILib.set_cursor("hand" if bw.is_golden_hovering() else "eye")
			if bw.is_golden_hovering():
				hud.set_hover("쓰다듬어 주기를 바라는 것 같다.")
			else:
				hud.set_hover("당신이 지켜보고 있다. 일행이 힘을 낸다!")
		elif ctrl is ForgeGame:
			UILib.set_cursor("hand")
			hud.set_hover("리듬에 맞춰… 지금이다!")
		else:
			UILib.set_cursor("point")
			hud.set_hover(hud.menu_hover)
		_set_hover_node(null)
		return
	var node := _pick_at(get_global_mouse_position())
	_set_hover_node(node)
	if node != null:
		UILib.set_cursor("point")
		var key: String = node.kind_key()
		if Game.discovered.get(key, false):
			hud.set_hover(node.flavor())
		else:
			hud.set_hover("?????")
	else:
		UILib.set_cursor("point")
		hud.set_hover("")

func _pick_at(pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := 1e9
	for n in get_tree().get_nodes_in_group("hoverable"):
		if not is_instance_valid(n) or not n.is_visible_in_tree():
			continue
		var d: float = pos.distance_to(n.position)
		var r: float = n.pick_radius() + 5.0
		if d < r and d < best_d:
			best_d = d
			best = n
	return best

func _find_battle_window(ctrl: Control) -> BattleWindow:
	var c: Node = ctrl
	while c != null:
		if c is BattleWindow:
			return c
		c = c.get_parent()
	return null

func _set_hover_node(node: Node2D) -> void:
	if node == _hover_node:
		return
	if _hover_node != null and is_instance_valid(_hover_node):
		_hover_node.scale = Vector2.ONE
	_hover_node = node
	if _hover_node != null:
		_hover_node.scale = Vector2(1.07, 1.07)

# ================================================================ bump

func _on_bump(node: Node2D) -> void:
	if _wipe_lock or not is_instance_valid(node):
		return
	if node is FieldMonster:
		_bump_monster(node)
		return
	var it := node as Interactable
	if it == null:
		return
	Game.discovered[it.kind_key()] = true
	match it.kind:
		"pot":
			_bump_pot(it)
		"chest":
			_bump_chest(it)
		"sparkle":
			_bump_sparkle(it)
		"inn":
			_bump_inn()
		"church":
			_bump_church()
		"smith":
			if not it.is_ready:
				hud.event("화덕이 아직 식어 있다… 조금 기다리자.")
				return
			Sfx.play("bump")
			hud.open_smith()
		"board":
			Sfx.play("bump")
			hud.open_board()
		"casino":
			Sfx.play("bump")
			hud.open_casino()
		"bard":
			Sfx.play("bump")
			hud.open_bard()
		"chief":
			_bump_chief()
		"gate":
			_bump_gate()
		"exit":
			goto_room(-1)
		"recruit":
			_bump_recruit(it)

func _bump_gate() -> void:
	# 용사의 직감 — 자율 재출격 (수동 조작 직후가 아니면)
	if Game.up["intuition"] > 0 and party.manual_hold <= 0.0:
		goto_room(last_field)
		return
	Sfx.play("bump")
	hud.open_gate()

func _bump_monster(m: FieldMonster) -> void:
	if m.is_boss:
		_start_boss_battle(m)
		return
	if _windows_full():
		m.bump_cd = 1.5
		if _full_msg_cd <= 0.0:
			_full_msg_cd = 1.2
			Sfx.play("deny")
			hud.event("전투창이 가득 찼다!")
		return
	Sfx.play("bump")
	var count := randi_range(1, Game.max_enemies_per_window())
	if current_room == 2:
		count = maxi(count, randi_range(1, Game.max_enemies_per_window()))  # 동굴 — 무리 조우
	elif current_room == 3:
		count = 1  # 설원 — 정예 단일
	var defs: Array = []
	for i in count:
		defs.append(m.def)
	m.queue_free()
	_open_battle(defs, false)

func _bump_pot(it: Interactable) -> void:
	if not it.is_ready:
		return
	var cracked := Game.medal_on("cracked_pot")
	var g := maxi(1, int(randi_range(3, 8) * Game.gold_scale() * Game.gold_multiplier() * (0.5 if cracked else 1.0)))
	_gain_gold(g, it.position, "pot", 2, _is_quiet(it))
	it.start_cooldown(12.5 if cracked else 25.0)

func _bump_chest(it: Interactable) -> void:
	if not it.is_ready:
		hud.event("텅 빈 상자다.")
		return
	it.start_cooldown(120.0)
	var quiet := _is_quiet(it)
	var teeth := Game.medal_on("mimic_teeth")
	var mimic_roll: bool = teeth or (Game.progress_tier() >= 2 and randf() < 0.18)
	if mimic_roll and not _windows_full() and not quiet:
		Sfx.play("boss")
		hud.event("보물상자가… 이빨을 드러냈다!", 3.0)
		var atlas := AtlasTexture.new()
		atlas.atlas = load("res://assets/objects/chest_1.png")
		atlas.region = Rect2(16, 0, 16, 18)
		var t := Game.progress_tier()
		var def := {
			"id": "mimic", "name": "미믹",
			"hp": int(24 * Game.tier_stat(t)), "atk": int(6 * Game.tier_atk(t)),
			"gold": int(130 * Game.tier_gold(t) * (3.0 if teeth else 1.0)),
			"exp": int(25 * Game.tier_exp(t)),
			"tex": atlas, "scale": 1.0, "tint": Color(1, 0.85, 0.85),
		}
		_open_battle([def], false)
		return
	var g := maxi(1, int(40 * Game.gold_scale() * Game.gold_multiplier()))
	_gain_gold(g, it.position, "chest", 4, quiet)
	if not quiet and randf() < 0.06:
		for id in ["sticky_gloves", "cracked_pot"]:
			if not Game.medals_owned.has(id):
				Game.own_medal(id)
				Sfx.play("fanfare_big")
				hud.event("상자 바닥에서 훈장 「%s」 을 발견했다!" % Game.MEDAL_DEFS[id]["name"], 4.0)
				Game.save_game()
				break

func _bump_sparkle(it: Interactable) -> void:
	if Game.up["shovel"] == 0:
		hud.event("뭔가 묻혀 있는 것 같다… (삽이 필요하다)")
		return
	_dig_sparkle(it)

func _dig_sparkle(it: Interactable) -> void:
	var g := maxi(1, int(randi_range(8, 20) * Game.gold_scale() * Game.gold_multiplier()))
	_gain_gold(g, it.position, "dig", 2, false)
	it.queue_free()

func _gain_gold(g: int, world_pos: Vector2, sfx_name: String, coins_n: int, quiet: bool) -> void:
	if quiet:
		pending_gold += g
		return
	Game.add_gold(g)
	Sfx.play(sfx_name, randf_range(0.9, 1.1))
	hud.popup("+%d G" % g, world_pos)
	hud.coin_burst(world_pos, coins_n)

func _is_quiet(it: Interactable) -> bool:
	# 기지 오브젝트를 조수가 파밍하는데 파티가 부재중이면 → 귀향 수확으로 적립
	return current_room != -1 and it.get_parent() == base_root

func _bump_inn() -> void:
	if Game.lowest_hp_ratio() >= 1.0 and Game.ghost_count() == 0:
		hud.event("여관 주인: 「모두 팔팔하신데요.」")
		return
	Sfx.play("heal")
	Game.heal_all_full()
	if Game.ghost_count() > 0:
		hud.event("…늦잠은 금물. (유령은 교회에서)", 3.0)
	else:
		hud.event("…늦잠은 금물.", 2.5)

func _bump_church() -> void:
	if Game.ghost_count() == 0:
		hud.event("신부: 「오늘도 무탈하시기를.」")
		return
	var cost := Game.revive_cost()
	if Game.try_spend(cost):
		Sfx.play("revive")
		Game.revive_all()
		hud.popup("-%d G" % cost, base_nodes["church"].position, UILib.COL_WHITE)
		hud.event("빛이 일행을 감싸안았다. 되살아났다!", 3.0)
	else:
		Sfx.play("deny")
		hud.event("헌금이 부족하다… (%d G)" % cost)

func _bump_chief() -> void:
	Sfx.play("bump")
	if _chief_wiped:
		_chief_wiped = false
		hud.event("촌장: 「…괜찮습니다. 다들 그렇게 시작합니다.」", 4.0)
		return
	if _chief_i == 0:
		hud.event("촌장: 「" + CHIEF_LINES[0] + "」", 4.0)
		_chief_i += 1
		return
	# 촌장 = 재건 계획도 관리인
	tree_ui.open()

func _bump_recruit(it: Interactable) -> void:
	var cls := it.recruit_cls
	Game.recruit(cls)
	Sfx.play("fanfare_big")
	hud.event("%s이(가) 일행에 합류했다!" % Game.CLASS_DEFS[cls]["name"], 3.5)
	it.queue_free()
	Game.save_game()

# ================================================================ 전투창 (도킹 + 공간 관통)

func _windows_full() -> bool:
	var n := 0
	for w in windows:
		if is_instance_valid(w) and not w.closing and not w.is_boss:
			n += 1
	return n >= Game.max_windows()

func _open_battle(defs: Array, boss: bool) -> void:
	var sim := BattleSim.new()
	sim.setup(defs, boss)
	var w := BattleWindow.new()
	if boss:
		w.setup(sim, Vector2(220, 124), true)
		w.position = Vector2(210, 60)
		party.frozen = true
		boss_fighting = true
		boss_field = current_room
	else:
		w.setup(sim, WIN_L, false)
		w.position = Vector2(4 + windows.size() * 154, 22)
	hud.windows_root.add_child(w)
	windows.append(w)
	w.tree_exiting.connect(_on_window_gone.bind(w))
	sim.victory.connect(_on_victory.bind(w, boss))
	sim.member_hit.connect(_on_member_hit_fx.bind(w))
	sim.golden_captured.connect(_on_golden_captured.bind(w))
	_relayout_windows()

func _relayout_windows() -> void:
	# 상단 밴드 도킹 — 창이 많아지면 한 단계 작아진다 (하단 1/3은 보호 구역)
	var docked: Array = []
	for w in windows:
		if is_instance_valid(w) and not w.is_boss and not w.closing:
			docked.append(w)
	var n := docked.size()
	var big: bool = n <= 4
	var sz := WIN_L if big else WIN_S
	for i in n:
		var pos: Vector2
		if big:
			pos = Vector2(4 + i * 154, 22)
		else:
			pos = Vector2(4 + (i % 4) * 130, 20 + int(i / 4.0) * 80)
		docked[i].apply_dock(pos, sz)

func _on_window_gone(w: BattleWindow) -> void:
	windows.erase(w)
	_relayout_windows()

func _on_victory(gold_reward: int, exp_reward: int, w: BattleWindow, boss: bool) -> void:
	Game.add_gold(gold_reward)
	if is_instance_valid(w):
		hud.coin_burst(w.position + w.size / 2.0, clampi(2 + gold_reward / 25, 2, 7))
		w.close_after(1.1)
	if Game.add_exp(exp_reward):
		Sfx.play("levelup")
		hud.event("일행은 레벨 %d이(가) 되었다!" % Game.level, 3.0)
	if boss:
		boss_fighting = false
		party.frozen = false
		_on_boss_defeated(boss_field)

func _on_member_hit_fx(idx: int, dmg: int, _fell: bool, w: BattleWindow) -> void:
	if is_instance_valid(w):
		hud.fly_damage(w.position + Vector2(randf_range(20, w.size.x - 20), w.size.y - 30), idx, dmg)

func _on_golden_captured(reward: int, w: BattleWindow) -> void:
	Game.add_gold(reward)
	Sfx.play("gold_big")
	if is_instance_valid(w):
		hud.coin_burst(w.position + w.size / 2.0, 8)
	hud.event("황금 슬라임을 붙잡았다! +%d G!" % reward, 3.5)

func _close_all_windows() -> void:
	for w in windows.duplicate():
		if is_instance_valid(w):
			w.close_after(0.0)

func _try_spawn_golden() -> void:
	var incense := Game.medal_on("slime_incense")
	var candidates: Array = []
	for w in windows:
		if is_instance_valid(w) and not w.closing and not w.is_boss and w.sim != null \
				and not w.sim.finished and not w.sim.golden_active:
			if incense and not w.sim.hovered:
				continue
			candidates.append(w)
	if candidates.is_empty():
		_golden_timer = 12.0 if not incense else 6.0
		return
	var w: BattleWindow = candidates[randi() % candidates.size()]
	var dur := 16.0 if not Game.golden_first_done else 8.0
	if Game.medal_on("metal_crown"):
		dur *= 0.6
	if Game.medal_on("sticky_gloves"):
		dur += 2.0
	w.sim.spawn_golden(dur)
	Game.golden_first_done = true
	var interval := randf_range(150.0, 300.0) * (0.5 if Game.golden_info else 1.0)
	if Game.medal_on("metal_crown"):
		interval *= 0.4
	_golden_timer = interval

# ================================================================ 몬스터 스폰 (좌→우 = 위험도)

func _field_def(field: int, mtier: int, x: float) -> Dictionary:
	var base: Dictionary = Game.MONSTER_DEFS[mtier]
	var t := field + 1
	var xf := 0.8 + (x / ROOM.x) * 0.55
	var elite: bool = field == 3  # 설원 — 정예
	var def := {
		"id": base["id"],
		"name": Game.FIELD_PREFIX[field] + String(base["name"]),
		"hp": int(base["hp"] * Game.tier_stat(t) * xf * (1.6 if elite else 1.0)),
		"atk": int(maxf(1.0, base["atk"] * Game.tier_atk(t) * xf * (1.3 if elite else 1.0))),
		"gold": int(base["gold"] * Game.tier_gold(t) * xf * (1.8 if elite else 1.0) * (1.0 + 0.4 * int(field == 2))),
		"exp": int(maxf(1.0, base["exp"] * Game.tier_exp(t) * xf)),
		"tex": base["tex"], "scale": 1.0,
		"tint": Game.FIELD_TINTS[field],
	}
	return def

func _spawn_monster(f: int = -1) -> void:
	if f < 0:
		f = current_room
	if f < 0:
		return
	var pos := Vector2(randf_range(70, 560), randf_range(44, 326))
	if pos.distance_to(party.head_pos) < 90.0:
		return
	# 수배서로 해금된 티어까지, 오른쪽일수록 상위
	var unlocked: int = Game.posters_f[f] if f < 4 else 3
	var max_tier: int = clampi(int(pos.x / 640.0 * (unlocked + 1.6)), 0, unlocked)
	var mtier := randi_range(0, max_tier)
	var m := FieldMonster.new()
	m.setup(_field_def(f, mtier, pos.x), f + 1)
	m.position = pos
	field_root.add_child(m)

func _spawn_sparkle() -> void:
	if current_room < 0:
		return
	var sp := _add_thing(field_root, "sparkle", Vector2(randf_range(60, 580), randf_range(50, 320)))
	sp.passive = true

# ================================================================ 지배자 (필드 최심부)

func _spawn_boss(f: int) -> void:
	if Game.bosses_defeated[f]:
		boss_node = null
		return
	var t := f + 1
	var def := {
		"id": "boss", "name": Game.BOSS_NAMES[f],
		"hp": int(300 * Game.tier_stat(t)),
		"atk": int(12 * Game.tier_atk(t)),
		"gold": int(500 * Game.tier_gold(t)),
		"exp": int(80 * Game.tier_exp(t)),
		"tex": BOSS_TEX[f], "scale": 1.0,
		"tint": Color(0.55, 0.35, 0.75) if f >= 4 else Color(1.1, 0.65, 0.65),
	}
	boss_node = FieldMonster.new()
	boss_node.setup(def, t, true, Game.BOSS_NAMES[f])
	boss_node.asleep = f < 4 and Game.posters_f[f] < 3
	boss_node.position = Vector2(596, 190)
	field_root.add_child(boss_node)

func on_posters_complete(field: int) -> void:
	Sfx.play("boss")
	if current_room == field and boss_node != null and is_instance_valid(boss_node) and boss_node.asleep:
		boss_node.wake_up()
		hud.event("최심부에서 지배자가 깨어났다…", 4.0)
	else:
		hud.event("%s의 지배자가 깨어났다는 소문이다…" % Game.FIELD_NAMES[field], 4.0)

func _start_boss_battle(m: FieldMonster) -> void:
	if boss_fighting:
		return
	if m.asleep:
		hud.event("%s은(는) 깊이 잠들어 있다. 수배서를 모으자." % m.boss_name, 3.5)
		m.bump_cd = 2.0
		return
	m.visible = false
	m.bump_cd = 9999.0
	Sfx.play("boss")
	hud.event("%s이(가) 나타났다!" % m.boss_name, 3.0)
	_open_battle([m.def], true)

func _on_boss_defeated(field: int) -> void:
	Game.bosses_defeated[field] = true
	if boss_node != null and is_instance_valid(boss_node):
		boss_node.queue_free()
	boss_node = null
	if field >= 4:
		Sfx.play("fanfare_big")
		Game.save_game()
		hud.show_ending(_do_prestige, _do_continue)
		return
	# 챕터 보스 첫 처치 확정 훈장
	var medal_by_field := ["coward_flag", "aqua_regia", "ghost_warcry", "spirit_party"]
	var mid: String = medal_by_field[clampi(field, 0, 3)]
	if Game.own_medal(mid):
		Sfx.play("fanfare_big")
		hud.event("훈장 「%s」 을 손에 넣었다!" % Game.MEDAL_DEFS[mid]["name"], 4.5)
	Sfx.play("palette")
	hud.event("%s의 지배자가 쓰러졌다. 이 땅은 해방되었다!" % Game.FIELD_NAMES[field], 4.0)
	Game.save_game()

func _do_prestige() -> void:
	Game.do_prestige()
	get_tree().reload_current_scene()

func _do_continue() -> void:
	Game.ending_seen = true
	Game.save_game()
	hud.event("세계는 평화롭다. …일행은 계속 걷는다.", 4.0)

# ================================================================ 전멸

func _on_wipe() -> void:
	if _wipe_lock:
		return
	_wipe_lock = true
	party.frozen = true
	Sfx.play("wipe")
	_close_all_windows()
	if boss_fighting:
		boss_fighting = false
		if boss_node != null and is_instance_valid(boss_node):
			boss_node.visible = true
			boss_node.bump_cd = 3.0
	hud.fade_black("눈앞이 깜깜해졌다…", 1.4, func():
		var penalty := int(Game.gold * 0.25)
		if penalty > 0:
			Game.add_gold(-penalty)
			hud.popup("-%d G" % penalty, Vector2(320, 170), UILib.COL_RED)
		Game.revive_all()
		_set_room(-1)
		var spot: Vector2 = base_nodes["church"].position + Vector2(0, 22) if base_nodes.has("church") else Vector2(320, 220)
		party.teleport(spot)
		_chief_wiped = true
		party.frozen = false
		_wipe_lock = false
		Game.save_game())

# ================================================================ 재건 계획도 연동

func tree_effect(effect: String) -> void:
	var parts: PackedStringArray = effect.split(":")
	match parts[0]:
		"up":
			Game.up[parts[1]] += 1
			if parts[1] == "max_hp":
				Game.refresh_max_hp()
			Game.upgrades_changed.emit()
		"assist":
			Game.assistants[parts[1]] += 1
			spawn_assistant(parts[1])
			hud.event("새 조수가 마을에 도착했다!")
		"building":
			_unlock_building(parts[1])
		"field":
			var f := int(parts[1])
			Game.unlock_field(f)
			Sfx.play("fanfare_big")
			hud.event("%s(으)로 가는 길이 열렸다! 성문에서 출발할 수 있다." % Game.FIELD_NAMES[f], 4.5)
		"pots":
			Game.extra_pots += 1
			var start: int = mini(5 + (Game.extra_pots - 1) * 2, POT_SPOTS.size())
			var endi: int = mini(5 + Game.extra_pots * 2, POT_SPOTS.size())
			for i in range(start, endi):
				var p := _add_thing(base_root, "pot", POT_SPOTS[i])
				p.spawn_pop()
			hud.event("광장에 항아리가 늘었다!")

func _unlock_building(kind: String) -> void:
	var pos: Vector2 = BUILD_POS[kind]
	var walker := Sprite2D.new()
	walker.texture = load("res://assets/NPCs/village_chief.png")
	walker.modulate = Color(randf_range(0.7, 1.0), randf_range(0.7, 1.0), randf_range(0.7, 1.0))
	walker.position = Vector2(320, 352)
	walker.offset = Vector2(0, -13)
	base_root.add_child(walker)
	hud.event("소문을 듣던 이가 마을로 걸어온다…", 3.0)
	var tw := create_tween()
	tw.tween_property(walker, "position", pos, 2.4)
	tw.tween_callback(func():
		walker.queue_free()
		Game.buildings[kind] = true
		var n := _add_thing(base_root, kind, pos)
		base_nodes[kind] = n
		n.spawn_pop()
		Sfx.play("build")
		var names := {"church": "교회", "smith": "대장간", "chest": "보물상자", "bard": "음유시인의 자리", "casino": "카지노"}
		hud.event("%s이(가) 마을에 생겼다!" % names.get(kind, kind), 3.5)
		Game.save_game())

# ================================================================ 소문 (이중 열쇠) + 동료

func _check_rumors() -> void:
	for n in RebuildTree.NODES:
		var id: String = n["id"]
		if Game.tree_revealed.get(id, false):
			continue
		if RebuildTree.node_level(n) > 0:
			Game.tree_revealed[id] = true
			continue
		if RebuildTree.reveal_met(n):
			Game.tree_revealed[id] = true
			Sfx.play("window")
			var rumor: String = n.get("rumor", "")
			if rumor != "":
				hud.event("소문을 들었다: " + rumor, 4.5)

func _check_recruits() -> void:
	var plan := [["warrior", 60, Vector2(250, 160)], ["mage", 350, Vector2(390, 160)], ["priest", 1000, Vector2(320, 110)]]
	for p in plan:
		var cls: String = p[0]
		if Game.total_earned >= int(p[1]) and not Game.recruits_spawned[cls] and not Game.has_member(cls):
			Game.recruits_spawned[cls] = true
			hud.event("누군가 마을로 걸어온다…", 3.0)
			var n := _add_thing(base_root, "recruit", Vector2(320, 352), cls)
			var tw := create_tween()
			tw.tween_property(n, "position", p[2], 3.0)
			Game.save_game()

# ================================================================ 조수

func spawn_assistant(kind: String) -> void:
	var a := Assistant.new()
	var home := Vector2(320, 230)
	if kind == "keeper":
		home = Vector2(320, 280)
	a.setup(kind, self, home)
	a.position = Vector2(320, 350)
	if kind == "pig":
		shared_root.add_child(a)  # 꽃돼지는 일행과 동행 (필드 발굴 담당)
	else:
		base_root.add_child(a)

func assistant_collect(node: Node2D) -> void:
	var it := node as Interactable
	if it == null or not is_instance_valid(it) or not it.is_ready:
		return
	Game.discovered[it.kind_key()] = true
	match it.kind:
		"pot":
			_bump_pot(it)
		"chest":
			_bump_chest(it)
		"sparkle":
			_dig_sparkle(it)

func on_forged() -> void:
	if base_nodes.has("smith") and is_instance_valid(base_nodes["smith"]):
		base_nodes["smith"].start_cooldown(20.0)

func smith_ready() -> bool:
	return base_nodes.has("smith") and is_instance_valid(base_nodes["smith"]) and base_nodes["smith"].is_ready

# ================================================================ 자율 AI (용사의 직감)

func _ai_pick() -> Variant:
	if Game.up["intuition"] == 0:
		return null
	if current_room == -1:
		if Game.ghost_count() > 0 and base_nodes.has("church") and Game.gold >= Game.revive_cost():
			return base_nodes["church"]
		if Game.lowest_hp_ratio() < 0.92:
			return base_nodes["inn"]
		return base_nodes["gate"]  # 회복 끝 — 다시 출격
	# 필드: 지치면 귀환, 아니면 사냥
	if Game.lowest_hp_ratio() < 0.35 or Game.alive_count() <= Game.members.size() / 2:
		if _field_exit != null and is_instance_valid(_field_exit):
			return _field_exit
	if not _windows_full():
		var radius: float = 180.0 + Game.up["radius"] * 60.0
		var best: Node2D = null
		var best_d := 1e9
		for m in get_tree().get_nodes_in_group("monster"):
			if not is_instance_valid(m) or m.is_boss or not m.is_visible_in_tree():
				continue
			var d: float = party.head_pos.distance_to(m.position)
			if d < radius and d < best_d:
				best_d = d
				best = m
		if best != null:
			return best
	if Game.up["shovel"] > 0:
		for n in get_tree().get_nodes_in_group("hoverable"):
			if n is Interactable and n.kind == "sparkle" and n.is_visible_in_tree():
				return n
	return null
