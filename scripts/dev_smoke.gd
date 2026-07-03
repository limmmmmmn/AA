extends Node
## 개발용 스모크 테스트 — AAA_SMOKE=1 환경변수로 실행 시에만 동작. (v3.0 한 화면 + 주민)

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
	print("[SMOKE] 시작 — 주민 %d명" % Game.resident_count())

	# 0) 공개 스케줄 — 촌장 대화로 설명창, 첫 골드로 카운터, 골드 50으로 부탁 개방
	assert(not Game.ui_unlocked["desc"])
	main._bump_chief()
	assert(Game.ui_unlocked["desc"])
	Game.add_gold(100000)
	assert(Game.ui_unlocked["gold"])
	main._bump_chief()
	assert(Game.ui_unlocked["quest"])
	main.hud.close_menu()
	print("[SMOKE] 공개 스케줄 OK")

	# 1) 촌장 커맨드 — 분산 업그레이드 (지불 포함)
	main.hud.open_chief()
	main.hud._buy_up("win_cap", int(100 * pow(2.2, Game.up["win_cap"])), "chief")
	main.hud._buy_up("win_cap", int(100 * pow(2.2, Game.up["win_cap"])), "chief")
	main.hud.close_menu()
	assert(Game.max_windows() >= 3)
	print("[SMOKE] 촌장 커맨드 OK — 창 %d" % Game.max_windows())

	# 2) 주민 영입 — 부탁(퀘스트) 자동 + 골드 지불
	Game.kill_counts["slime"] = 5   # "슬라임 5마리" 부탁 충족
	await get_tree().create_timer(4.0).timeout
	print("[dbg] res=", Game.residents, " inn=", Game.buildings["inn"], " quest=", Game.ui_unlocked["quest"], " kills=", Game.kill_counts)
	assert(Game.residents.get("innkeep", false) and Game.buildings["inn"])
	Game.add_exp(3000)  # 레벨 게이트 통과용 (Lv 7+)
	assert(main.try_pay_resident("smithy"))
	await get_tree().create_timer(3.0).timeout
	assert(Game.buildings["smith"])
	assert(main.try_pay_resident("merchant"))
	await get_tree().create_timer(4.0).timeout
	assert(Game.resident_count() == 3)
	print("[SMOKE] 주민 3명 영입 OK — 부흥 단계 %d" % main._revival_stage())

	# 3) 전투 + 황금 슬라임 (한 화면 — 필드는 오른쪽에 그대로 있다)
	var mons: Array = []
	for m in get_tree().get_nodes_in_group("monster"):
		if not m.is_boss:
			mons.append(m)
	assert(mons.size() >= 5)
	main._bump_monster(mons[0])
	main._bump_monster(mons[1])
	await get_tree().create_timer(1.0).timeout
	assert(main.windows.size() >= 1)
	var w = main.windows[0]
	w.sim.spawn_golden(10.0)
	await get_tree().create_timer(0.3).timeout
	for i in 40:
		w.sim.rub_golden(0.04)
	print("[SMOKE] 전투/황금 OK — gold=%d" % Game.gold)

	# 4) 수배서 → 결계 해제 → 지배자 처치 → 열쇠/이정표/다음 필드
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
	assert(Game.keys["thief"])
	assert(Game.signpost_seen)
	assert(Game.fields_unlocked[1])
	print("[SMOKE] 지배자 처치 OK — 열쇠/이정표/숲 해금")

	# 5) 잠긴 창고 (열쇠 문법) — 도둑의 열쇠로 연다
	var wh: Interactable = null
	for n in get_tree().get_nodes_in_group("hoverable"):
		if n is Interactable and n.kind == "warehouse":
			wh = n
	assert(wh != null)
	main._bump_warehouse(wh)
	assert(Game.opened["warehouse"] and Game.medals_small >= 2)
	print("[SMOKE] 창고 개방 OK — 메달 %d" % Game.medals_small)

	# 6) 작은 메달 → 메달왕 자동 합류 → 교환
	Game.medals_small = 5
	await get_tree().create_timer(4.0).timeout
	assert(Game.residents.get("medalist", false))
	main.hud._medal_trade("cracked_pot", 3)
	assert(Game.medals_owned.has("cracked_pot"))
	print("[SMOKE] 메달왕 OK — 남은 메달 %d" % Game.medals_small)

	# 7) 필드 스왑 (이정표 — 우⅔만 교체)
	main.swap_field(1)
	await get_tree().create_timer(1.0).timeout
	assert(main.last_field == 1)
	main.swap_field(0)
	await get_tree().create_timer(1.0).timeout
	print("[SMOKE] 필드 스왑 OK")

	# 8) 분산 업그레이드 — 촌장/여관/상점 커맨드가 각자 _buy_up으로 산다
	Game.add_gold(50000)
	main.hud.open_chief()
	main.hud._buy_up("speed", 25, "chief")
	assert(Game.up["speed"] == 1)
	main.hud.open_inn()
	main.hud._buy_up("max_hp", 30, "inn")     # 여관 침구 개선
	assert(Game.up["max_hp"] == 1)
	main.hud.open_shop_menu()
	main.hud._buy_up("gold_mult", 60, "shop") # 상점 골드 감각 — 예전에 여기서 터졌다
	assert(Game.up["gold_mult"] == 1)
	main.hud.close_menu()
	print("[SMOKE] 분산 업글 OK — speed/max_hp/gold_mult")

	# 8.5) 여관 회복 + 대장간 판정
	if not Game.has_member("warrior"):
		Game.recruit("warrior")
	Game.damage_member(0, 5)
	main.hud.open_inn()
	main.hud._inn_rest()
	assert(Game.members[0]["hp"] == Game.members[0]["max_hp"])
	main.hud._apply_forge(1, 3)
	print("[SMOKE] 여관/대장간 OK — 무기 +%d" % Game.members[1]["weapon_lv"])

	# 9) 도박사 영입 → 카지노 + 서사시
	assert(main.try_pay_resident("gambler"))
	await get_tree().create_timer(3.0).timeout
	assert(Game.buildings["casino"])
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
	print("[SMOKE] 카지노/서사시 OK — %s" % Game.weapon_name(0))

	# 10) 전멸 → 부활
	for i in Game.members.size():
		Game.damage_member(i, 99999999)
	await get_tree().create_timer(4.0).timeout
	assert(Game.alive_count() == Game.members.size())
	print("[SMOKE] 전멸/부활 OK — gold=%d" % Game.gold)

	# 11) 세이브/로드
	Game.save_game()
	Game.load_game()
	print("[SMOKE] 세이브/로드 OK")
	print("[SMOKE] 전부 통과!")
	get_tree().quit()

# ---------------------------------------------------------------- 스크린샷

func _shots() -> void:
	await get_tree().create_timer(1.5).timeout
	await _save_shot("shot_start.png")   # 시작: 용사·촌장·항아리·잠긴 것들뿐
	# 공개 스케줄 진행 + 주민 셋
	main._bump_chief()
	Game.add_gold(50000)
	main._bump_chief()
	main.hud.close_menu()
	Game.kill_counts["slime"] = 5
	Game.add_exp(3000)
	await get_tree().create_timer(4.5).timeout
	main.try_pay_resident("smithy")
	await get_tree().create_timer(3.0).timeout
	main.try_pay_resident("merchant")
	await get_tree().create_timer(4.5).timeout
	# 전투창 도배
	Game.up["win_cap"] = 5
	var mons: Array = []
	for m in get_tree().get_nodes_in_group("monster"):
		if not m.is_boss:
			mons.append(m)
	for i in mini(4, mons.size()):
		main._bump_monster(mons[i])
	await get_tree().create_timer(2.5).timeout
	if main.windows.size() > 0:
		main.windows[0].sim.spawn_golden(20.0)
	await get_tree().create_timer(1.0).timeout
	await _save_shot("shot_village3.png")  # 한 화면: 마을⅓ + 필드⅔ + 창
	# 촌장 커맨드 메뉴
	main.hud.open_chief()
	await get_tree().create_timer(0.4).timeout
	await _save_shot("shot_chief.png")
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
