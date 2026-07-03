extends Node
## 개발용 스모크 테스트 — AAA_SMOKE=1 환경변수로 실행 시에만 동작. (v2.0 룸 구조)

var main: Node2D

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if OS.get_environment("AAA_FONT") == "1":
		await _font_test()
		return
	if OS.get_environment("AAA_SHOT") == "1":
		await _shots()
		return
	await get_tree().create_timer(1.2).timeout
	print("[SMOKE] 시작 — 룸: ", main.current_room)

	# 1) 재건 계획도 구매
	Game.add_gold(100000)
	assert(main.tree_ui.buy_node("win_cap"))
	assert(main.tree_ui.buy_node("win_cap"))
	print("[SMOKE] 계획도 OK — 전투창 상한 ", Game.max_windows())
	assert(Game.max_windows() >= 3)

	# 2) 필드 출격
	main.goto_room(0)
	await get_tree().create_timer(1.2).timeout
	assert(main.current_room == 0)
	var mons: Array = []
	for m in get_tree().get_nodes_in_group("monster"):
		if not m.is_boss:
			mons.append(m)
	print("[SMOKE] 초원 진입 OK — 몬스터 %d마리" % mons.size())
	assert(mons.size() >= 5)

	# 3) 전투 + 황금 슬라임
	main._bump_monster(mons[0])
	main._bump_monster(mons[1])
	await get_tree().create_timer(1.0).timeout
	assert(main.windows.size() >= 1)
	var w = main.windows[0]
	w.sim.spawn_golden(10.0)
	await get_tree().create_timer(0.3).timeout
	var gold_before: int = Game.gold
	for i in 40:
		w.sim.rub_golden(0.04)
	print("[SMOKE] 전투/황금 OK — %d → %d G" % [gold_before, Game.gold])

	# 4) 수배서 3장 → 지배자 각성 → 처치
	Game.posters_f[0] = 3
	main.on_posters_complete(0)
	await get_tree().create_timer(0.5).timeout
	assert(main.boss_node != null and not main.boss_node.asleep)
	main._start_boss_battle(main.boss_node)
	await get_tree().create_timer(1.0).timeout
	for bw in main.windows:
		if bw.is_boss:
			bw.sim._apply_enemy_damage(0, 99999999, false, true)
	await get_tree().create_timer(4.0).timeout
	assert(Game.bosses_defeated[0])
	print("[SMOKE] 지배자 처치 OK — 훈장: ", Game.medals_owned)

	# 5) 소문(이중 열쇠) → 숲 해금
	await get_tree().create_timer(1.5).timeout
	assert(Game.tree_revealed.get("field1", false))
	assert(main.tree_ui.buy_node("field1"))
	assert(Game.fields_unlocked[1])
	print("[SMOKE] 숲 해금 OK")

	# 6) 귀향 수확
	main.pending_gold = 123
	main.goto_room(-1)
	await get_tree().create_timer(1.2).timeout
	assert(main.current_room == -1 and main.pending_gold == 0)
	print("[SMOKE] 귀향 수확 OK")

	# 7) 건물 (대장간) — 걸어 들어와 건설
	assert(main.tree_ui.buy_node("smith"))
	await get_tree().create_timer(3.2).timeout
	assert(Game.buildings["smith"])
	print("[SMOKE] 대장간 건설 OK")

	# 8) 영입 + 대장간 판정
	if not Game.has_member("warrior"):
		Game.recruit("warrior")
	main.hud._apply_forge(1, 3)
	print("[SMOKE] 강화 OK — 무기 +%d, 필살작 %d" % [Game.members[1]["weapon_lv"], Game.smith_perfects])

	# 9) 카지노/서사시/훈장
	Game.coins += 600
	main.hud.open_casino()
	main.hud._casino_spin()
	await get_tree().create_timer(2.5).timeout
	main.hud._casino_exchange("mimic_teeth", 300)
	main.hud.close_menu()
	assert(Game.medals_owned.has("mimic_teeth"))
	while not Game.epic_complete():
		Game.add_gold(20000)
		Game.buy_verse()
	assert(Game.members[0]["weapon_lv"] == 6)
	Game.toggle_medal("coward_flag")
	print("[SMOKE] 카지노/서사시/훈장 OK — ", Game.weapon_name(0))
	Game.toggle_medal("coward_flag")

	# 10) 수배 게시판 탭
	main.hud.open_board(1)
	main.hud.close_menu()

	# 11) 전멸 → 기지 부활
	main.goto_room(1)
	await get_tree().create_timer(1.2).timeout
	for i in Game.members.size():
		Game.damage_member(i, 99999999)
	await get_tree().create_timer(4.0).timeout
	assert(Game.alive_count() == Game.members.size())
	assert(main.current_room == -1)
	print("[SMOKE] 전멸/부활 OK — gold=", Game.gold)

	# 12) 세이브/로드
	Game.save_game()
	Game.load_game()
	print("[SMOKE] 세이브/로드 OK")
	print("[SMOKE] 전부 통과!")
	get_tree().quit()

# ---------------------------------------------------------------- 스크린샷

func _shots() -> void:
	await get_tree().create_timer(1.2).timeout
	await _save_shot("shot_base.png")
	# 필드 + 전투창 도배 (반응형 축소 확인)
	Game.add_gold(50000)
	Game.up["win_cap"] = 7
	main.goto_room(0)
	await get_tree().create_timer(1.2).timeout
	for i in 6:
		main._open_battle([main._field_def(0, 0, 300.0), main._field_def(0, 0, 300.0)], false)
	await get_tree().create_timer(2.0).timeout
	if main.windows.size() > 0:
		main.windows[0].sim.spawn_golden(20.0)
	await get_tree().create_timer(1.0).timeout
	await _save_shot("shot_field.png")
	# 재건 계획도
	main.tree_ui.open()
	await get_tree().create_timer(0.4).timeout
	await _save_shot("shot_tree.png")
	main.tree_ui.close()
	# 성문 메뉴
	main.goto_room(-1)
	await get_tree().create_timer(1.2).timeout
	main.hud.open_gate()
	await get_tree().create_timer(0.4).timeout
	await _save_shot("shot_gate.png")
	# 수배 게시판
	main.hud.open_board()
	await get_tree().create_timer(0.3).timeout
	await _save_shot("shot_board.png")
	main.hud.close_menu()
	print("[SHOT] 완료")
	get_tree().quit()

func _save_shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://" + name)
	print("[SHOT] ", name)

# ---------------------------------------------------------------- 폰트 테스트

func _font_test() -> void:
	await get_tree().create_timer(0.5).timeout
	var layer := CanvasLayer.new()
	layer.layer = 99
	main.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var y := 6
	for fs in [8, 10, 12, 16]:
		var l := UILib.make_label("%dpx — 슬라임A에게 24의 데미지! 회심의 일격!!" % fs, fs)
		l.position = Vector2(6, y)
		layer.add_child(l)
		y += fs + 10
	await _save_shot("shot_font.png")
	get_tree().quit()
