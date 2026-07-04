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

	# 8.5) 여관 회복 + 대장간 판정 (v3.1: 무기는 companion_weapons에 기억된다)
	if not Game.has_member("warrior"):
		Game.own_companion("warrior")
	Game.damage_member(0, 5)
	main.hud.open_inn()
	main.hud._inn_rest()
	assert(Game.members[0]["hp"] == Game.members[0]["max_hp"])
	var forge_idx := -1
	for i in Game.members.size():
		if Game.members[i]["cls"] == "warrior":
			forge_idx = i
	assert(forge_idx >= 0)
	main.hud._apply_forge(forge_idx, 3)
	assert(int(Game.companion_weapons.get("warrior", 0)) == 3)  # 편성을 넘어 기억
	print("[SMOKE] 여관/대장간 OK — 무기 +%d" % Game.members[forge_idx]["weapon_lv"])

	# 9) 도박사 영입 → 카지노 + 서사시
	assert(main.try_pay_resident("gambler"))
	await get_tree().create_timer(3.0).timeout
	assert(Game.buildings["casino"])
	Game.coins += 600
	main.hud.open_casino()
	# _menu_panel이 _menu_kind를 지우면 안 된다 (슬롯 가드가 여기 걸린다)
	assert(main.hud._menu_kind == "casino")
	assert(main.hud.is_menu_open())
	var coins_before: int = Game.coins
	main.hud._casino_spin()
	await get_tree().create_timer(0.1).timeout
	assert(Game.coins == coins_before - 1)   # 스핀이 실제로 코인을 소모했다
	await get_tree().create_timer(2.5).timeout
	main.hud._casino_exchange("mimic_teeth", 300)
	main.hud.close_menu()
	assert(Game.medals_owned.has("mimic_teeth"))
	while not Game.epic_complete():
		Game.add_gold(20000)
		var vi: int = Game.epic_verses
		if Game.buy_verse():
			main.on_verse_bought(vi)  # 절은 사건을 판다 (v3.1)
	print("[SMOKE] 카지노/서사시 OK — 사건 발화 완료")

	# 9.6) v3.1 — 서사시 사건 검증 (드루이드/검바위/도적/합체기 힌트)
	await get_tree().create_timer(3.0).timeout
	assert(Game.companions_owned.get("druid", false))
	assert(Game.sword_rock >= 1)
	assert(Game.combo_hint_known)
	print("[SMOKE] 서사시 사건 OK — 드루이드/검바위/힌트")

	# 9.7) v3.1 — 편성 + 합체기 (어부 형제 → 참치 어택)
	Game.own_companion("fisher_a")
	Game.own_companion("fisher_b")
	for id in Game.party_ids.duplicate():
		if id != "hero" and id != "fisher_a" and id != "fisher_b" and Game.party_ids.size() > 3:
			Game.toggle_party(id)
	if not Game.party_ids.has("fisher_a"):
		assert(Game.toggle_party("fisher_a"))
	if not Game.party_ids.has("fisher_b"):
		assert(Game.toggle_party("fisher_b"))
	assert(not Game.active_combo().is_empty())
	Game.combo_gauge = 1.0
	var mons3: Array = []
	for m in get_tree().get_nodes_in_group("monster"):
		if is_instance_valid(m) and not m.is_boss:
			mons3.append(m)
	assert(mons3.size() >= 1)
	main._bump_monster(mons3[0])
	await get_tree().create_timer(0.8).timeout
	var cw: BattleWindow = null
	for w2 in main.windows:
		if is_instance_valid(w2) and not w2.closing:
			cw = w2
	assert(cw != null)
	main._fire_combo()
	await get_tree().create_timer(2.5).timeout
	assert(Game.combo_gauge < 0.2)  # 발동으로 리셋 (직후 승리가 +0.08 줄 수 있다)
	assert(cw == null or not is_instance_valid(cw) or cw.sim.alive_enemies().is_empty())
	print("[SMOKE] 합체기 OK — 참치 어택")

	# 9.8) v3.1 — 교회 축복 + 도망 나팔
	Game.add_gold(50000)
	main.hud.open_church()
	main.hud._buy_up("gaze", 120, "church")
	assert(Game.up["gaze"] == 1 and Game.gaze_speed() > 1.5)
	main.hud._buy_up("golden_hands", 200, "church")
	assert(Game.up["golden_hands"] == 1)
	main.hud.open_chief()
	main.hud._buy_up("flee", 300, "chief")
	assert(Game.up["flee"] == 1)
	main.hud.close_menu()
	print("[SMOKE] 축복/도망 OK")

	# 9.9) v3.1 — 은행 (banker 부탁 → 건물 → 예금)
	Game.add_exp(200000)  # Lv 8 게이트
	assert(main.try_pay_companion("banker"))
	await get_tree().create_timer(3.5).timeout
	assert(Game.buildings["bank"])
	assert(Game.companions_owned.get("banker", false))
	Game.add_gold(2000)
	var dep := Game.bank_deposit(800)
	assert(dep > 0 and Game.deposit == dep)
	print("[SMOKE] 은행 OK — 예금 %d G" % Game.deposit)

	# 10) 전멸 → 부활 (예금은 불가침)
	var dep_before: int = Game.deposit
	for i in Game.members.size():
		Game.damage_member(i, 99999999)
	await get_tree().create_timer(4.0).timeout
	assert(Game.alive_count() == Game.members.size())
	assert(Game.deposit == dep_before)  # v3.1 §B-8 — 전멸 페널티 면제
	print("[SMOKE] 전멸/부활 OK — gold=%d 예금=%d" % [Game.gold, Game.deposit])

	# 11) 세이브/로드 (v5 — 동료/편성/무기/합체기/은행)
	var owned_n: int = Game.companion_count()
	var pids: Array = Game.party_ids.duplicate()
	Game.save_game()
	Game.load_game()
	assert(Game.companion_count() == owned_n)
	assert(Game.party_ids == pids)
	assert(int(Game.companion_weapons.get("warrior", 0)) == 3)
	assert(Game.deposit == dep_before)
	print("[SMOKE] 세이브/로드 OK (v5)")
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
