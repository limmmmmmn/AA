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
	assert(main.buy_catalog("smith"))
	await get_tree().create_timer(3.0).timeout
	assert(Game.buildings["smith"])
	assert(Game.residents.get("smithy", false))  # 건물이 서면 사람이 온다
	assert(main.buy_catalog("shop"))
	await get_tree().create_timer(3.0).timeout
	assert(Game.resident_count() == 3)
	print("[SMOKE] 건설→입주 OK — 주민 %d명, 건설물 %d개, 부흥 %d" % [Game.resident_count(), Game.built_count(), main._revival_stage()])

	# v4.0 — 훈련소/마구간/기물/"!" 마커
	assert(main.buy_catalog("train"))
	assert(main.buy_catalog("stable"))
	await get_tree().create_timer(2.6).timeout
	assert(Game.buildings["train"] and Game.buildings["stable"])
	assert(Game.residents.get("trainer", false) and Game.residents.get("hostler", false))
	assert(main.buy_catalog("scarecrow"))  # needs: train
	var sc: Interactable = null
	for scn in get_tree().get_nodes_in_group("hoverable"):
		if scn is Interactable and scn.kind == "scarecrow":
			sc = scn
	assert(sc != null)
	var g_before := Game.gold
	main._bump_scarecrow(sc)
	assert(Game.gold > g_before and not sc.is_ready)  # 잔돈 + 쿨타임
	assert(main.hud.can_shop("chief"))  # 골드가 넘치니 촌장 위에 "!"가 켜져 있어야 한다
	main._update_chief_alert()
	assert(main.base_nodes["chief"].show_alert)
	assert(main.hud.can_shop("train"))  # 훈련소에도 살 게 있다
	print("[SMOKE] v4.0 건설 카탈로그/기물/마커 OK — 건설물 %d개" % Game.built_count())

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

	# 8.5) 여관 회복 + 무기점(플랫)/대장간(벼림%) 이원화 (v3.4 §B-5)
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
	# 무기점 — 골드 → 즉시 플랫 (무기상 주민 영입 포함)
	assert(main.buy_catalog("weaponshop"))
	await get_tree().create_timer(3.0).timeout
	assert(Game.buildings["weaponshop"])
	var atk_before: int = Game.member_atk(forge_idx)
	main.hud.open_weaponshop()
	main.hud._buy_weapon(forge_idx, Game.weapon_cost(forge_idx))
	assert(Game.member_atk(forge_idx) > atk_before)             # 변화량이 실재한다
	assert(int(Game.companion_weapons.get("warrior", 0)) == 1)  # 플랫 = 무기점
	# 대장간 — 벼림 % (별개 슬롯)
	var flat_now: int = Game.member_atk_flat(forge_idx)
	main.hud._apply_forge(forge_idx, 3)
	assert(int(Game.companion_forge.get("warrior", 0)) == 3)    # 벼림 = 대장간
	assert(Game.member_atk(forge_idx) >= int(flat_now * 1.09))  # ×1.09 배율 반영
	main.hud.close_menu()
	print("[SMOKE] 여관/무기점/대장간 OK — atk %d (플랫 %d × 벼림 %d%%)" % [
		Game.member_atk(forge_idx), Game.member_atk_flat(forge_idx),
		int(Game.forge_mult("warrior") * 100)])

	# 9) 도박사 영입 → 카지노 + 서사시
	assert(main.buy_catalog("casino"))
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

	# 9.7) v3.9 — 오의 장착식 (§B-3: 편성 조건 없음, 슬롯 1개)
	assert(Game.active_combo().is_empty())      # 오의서 없으면 게이지도 없다
	assert(Game.own_art("tuna"))
	assert(Game.equipped_art == "tuna")          # 첫 오의서는 자동 장착
	assert(not Game.own_art("tuna"))             # 중복 획득 방지
	var combo: Dictionary = Game.active_combo()
	assert(not combo.is_empty() and String(combo["id"]) == "tuna")
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
	await get_tree().create_timer(0.3).timeout
	assert(main.hud._combo_btn != null)  # v3.6: 만충 = 반짝이는 필살 버튼
	var field_before := 0
	for m2 in get_tree().get_nodes_in_group("monster"):
		if is_instance_valid(m2) and not m2.is_boss and m2.is_visible_in_tree():
			field_before += 1
	main._fire_combo()
	await get_tree().create_timer(2.5).timeout
	assert(Game.combo_gauge < 0.2)  # 발동으로 리셋 (직후 승리가 +0.08 줄 수 있다)
	assert(cw == null or not is_instance_valid(cw) or cw.sim.alive_enemies().is_empty())
	# v3.6: 필드 스윕 — 창 밖 몬스터도 쓸려나갔다
	var field_after := 0
	for m3 in get_tree().get_nodes_in_group("monster"):
		if is_instance_valid(m3) and not m3.is_boss and m3.is_visible_in_tree():
			field_after += 1
	assert(field_before == 0 or field_after < field_before)
	assert(main.hud._combo_btn == null)  # 버튼은 발동과 함께 사라진다
	print("[SMOKE] 합체기 OK — 버튼/필드 스윕 (필드 %d→%d)" % [field_before, field_after])

	# v3.6: 파티원 개별 작전 — 오버라이드가 창 작전을 이긴다
	Game.tactic_known = true
	Game.tactic = "attack"
	Game.member_tactics["hero"] = "life"
	var sim_m := BattleSim.new()
	sim_m.setup([Game.MONSTER_DEFS[0]], false)
	assert(Game.member_tactic_of("hero", sim_m.window_tactic) == "life")
	assert(Game.member_tactic_of("priest", sim_m.window_tactic) == "attack")
	assert(sim_m.tactic_in_mult("life") < 1.0 and sim_m.tactic_out_mult("attack") > 1.0)
	Game.member_tactics.clear()
	Game.tactic = ""
	print("[SMOKE] 개별 작전 OK")

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

	# 9.9) v3.9 — 은행원·어부 형제 = 주민 부탁 (§B-2)
	Game.add_exp(200000)  # Lv 8 게이트
	assert(main.buy_catalog("bank"))
	await get_tree().create_timer(3.5).timeout
	assert(Game.buildings["bank"])
	assert(Game.residents.get("banker", false))
	Game.add_gold(2000)
	var dep := Game.bank_deposit(800)
	assert(dep > 0 and Game.deposit == dep)
	assert(main.buy_catalog("frogstatue"))  # 기물 — 은행 뒤에 열린다
	assert(main.try_pay_resident("fishers"))
	await get_tree().create_timer(6.8).timeout
	assert(Game.residents.get("fishers", false))
	assert(Game.keys["sea"])  # 어부 부탁 완결 = 바다의 노래
	# 개구리 저금통 누적 → 오의 「개구리의 왈츠」 (§B-3 은행 연동 개그)
	Game.stats["frog_gold"] = 499
	var fs2: Interactable = null
	for n2 in get_tree().get_nodes_in_group("hoverable"):
		if n2 is Interactable and n2.kind == "frogstatue":
			fs2 = n2
	assert(fs2 != null)
	Game.add_gold(77 - Game.gold % 100)  # 잔돈 확보
	main._bump_frogstatue(fs2)
	assert(Game.arts_owned.has("frog"))
	print("[SMOKE] 은행/어부/개구리 오의 OK — 예금 %d G" % Game.deposit)

	# 10) 전멸 → 부활 (예금은 불가침) + 원혼의 함성 위로 지급 (v3.2)
	var dep_before: int = Game.deposit
	for i in Game.members.size():
		Game.damage_member(i, 99999999)
	await get_tree().create_timer(6.0).timeout
	assert(Game.alive_count() == Game.members.size())
	assert(Game.deposit >= dep_before)  # v3.1 §B-8 — 전멸 페널티 면제 (이자 틱은 덤)
	assert(Game.stats["wipes"] >= 1)
	assert(Game.medals_owned.has("ghost_warcry"))  # 쓰러져 본 자에게 주어진다
	print("[SMOKE] 전멸/부활 OK — gold=%d 예금=%d" % [Game.gold, Game.deposit])

	# 12) v3.2 — 작전 명령 (여관 해금 + 창별 가중치)
	assert(Game.tactic_known)  # 숲 개방 + 여관 → 자동 해금
	Game.tactic = "attack"
	var sim_t := BattleSim.new()
	sim_t.setup([Game.MONSTER_DEFS[0]], false)
	assert(sim_t.window_tactic == "attack")
	assert(sim_t.tactic_out_mult() > 1.0 and sim_t.tactic_in_mult() > 1.0)
	Game.tactic = "life"
	var sim_l := BattleSim.new()
	sim_l.setup([Game.MONSTER_DEFS[0]], false)
	assert(sim_l.tactic_in_mult() < 1.0 and sim_l.tactic_gold_mult() < 1.0)
	Game.tactic = ""
	print("[SMOKE] 작전 명령 OK")

	# 13) v3.2 — 밤낮 + 은빛 슬라임 (시계는 숲 개방 후 가동)
	assert(Game.clock_on())
	var save_pt: float = Game.playtime
	Game.playtime = Game.DAY_LEN + 5.0  # 강제로 밤
	assert(Game.is_night())
	var wn: BattleWindow = null
	var mons4: Array = []
	for m in get_tree().get_nodes_in_group("monster"):
		if is_instance_valid(m) and not m.is_boss:
			mons4.append(m)
	main._bump_monster(mons4[0])
	await get_tree().create_timer(0.6).timeout
	for w3 in main.windows:
		if is_instance_valid(w3) and not w3.closing and not w3.sim.finished:
			wn = w3
	assert(wn != null)
	wn.sim.spawn_golden(20.0, true)  # 은빛
	assert(wn.sim.golden_silver)
	var lv_before: int = Game.level
	var xp_before: int = Game.exp
	for i in 60:
		wn.sim.rub_golden(0.04)
	assert(Game.stats["silver_caught"] >= 1)
	assert(Game.level > lv_before or Game.exp > xp_before)  # 은빛 = 경험치
	assert(Game.medals_owned.has("moonlight"))
	Game.playtime = save_pt
	print("[SMOKE] 밤/은빛 OK")

	# 13.5) v3.7 — 복수의 감시자: 전투창 6개가 곧 보스
	var wdef := {"hp": 600, "atk": 10, "gold": 240, "exp": 80}
	main.boss_fighting = true
	main.party.frozen = true
	main._begin_watcher(wdef)
	assert(main._watcher_eyes.size() == 6)
	main._watcher_eyes[0]["sim"].combo_annihilate()
	await get_tree().create_timer(2.5).timeout
	assert(main._watcher_deadline > 0.0)  # 첫 눈이 감기면 카운트다운
	for we in main._watcher_eyes:
		if not we["down"]:
			we["sim"].combo_annihilate()
	await get_tree().create_timer(3.0).timeout
	assert(not main._watcher_active and not main.boss_fighting)
	assert(Game.bosses_defeated[3])
	print("[SMOKE] 복수의 감시자 OK — 6눈 격파")

	# 14) v3.2 — 로토 3점 + 마왕성 이중 열쇠
	Game.add_exp(500000)  # Lv 10+ 보장
	Game.sword_rock = 1
	main._spawn_sword_rock(true)
	var sr: Interactable = null
	var rsh: Interactable = null
	for n in get_tree().get_nodes_in_group("hoverable"):
		if n is Interactable and n.kind == "swordrock":
			sr = n
	assert(sr != null)
	main._bump_swordrock(sr)
	assert(Game.sword_rock == 2)
	assert(Game.weapon_name(0).begins_with("로토의 검"))  # v3.8: 교체 이벤트 (승계)
	# 동굴 지배자 → 방패 / 수중 지배자 → 투구 (직접 격파 처리)
	Game.posters_f[2] = 3
	main._on_boss_defeated(2)
	await get_tree().create_timer(0.5).timeout
	assert(Game.medals_owned.has("pack_hunter") and Game.medals_owned.has("duel_manner"))
	assert(Game.arts_owned.has("skeleton"))  # v3.9: 동굴 지배자 = 오의서 「명계의 행진」
	for n in get_tree().get_nodes_in_group("hoverable"):
		if n is Interactable and n.kind == "rotoshield":
			rsh = n
	assert(rsh != null)
	main._bump_rotoshield(rsh)
	assert(Game.roto_shield)
	main._on_boss_defeated(3)
	await get_tree().create_timer(0.5).timeout
	assert(Game.roto_helm and Game.roto_complete())
	assert(Game.medals_owned.has("clairvoyance"))
	assert(Game.weapon_name(0) == "전설의 검·진")
	print("[SMOKE] 로토 3점 OK — %s" % Game.weapon_name(0))

	# 15) v3.9 — 숨겨진 수중 필드 (어부의 바다의 노래) + 최심부 오의서
	assert(Game.keys["sea"])
	main.swap_field(Game.HIDDEN_FIELD)
	await get_tree().create_timer(1.2).timeout
	assert(main.party.underwater)
	# 최심부의 전설의 오의서 — 참치는 이미 주웠으니 스폰 안 된다 (중복 방지 확인)
	var found_book := false
	for nb in get_tree().get_nodes_in_group("hoverable"):
		if nb is Interactable and nb.kind == "artbook":
			found_book = true
	assert(not found_book)
	main.swap_field(0)
	await get_tree().create_timer(1.2).timeout
	assert(not main.party.underwater)
	# 겹쳐보기 = 소집 토글 (v3.9 §B-4) — 켜야 스택
	Game.up["stack"] = 1
	main.stack_on = true
	Game.up["win_cap"] = 5  # 상한 여유 확보
	for attempt in 12:
		if main._docked_windows().size() >= 3:
			break
		for m in get_tree().get_nodes_in_group("monster"):
			if is_instance_valid(m) and not m.is_boss and m.is_visible_in_tree():
				main._bump_monster(m)
				break
		await get_tree().create_timer(0.4).timeout
	# 전투가 순삭이라 창이 닫히기 전에 — 대기 없이 즉시 검증 (배지는 relayout에서 동기 생성)
	var n_now: int = main._docked_windows().size()
	main._relayout_windows()
	assert(main._stack_active(n_now))
	assert(main.hud._stack_badge != null)
	main._on_window_clicked(main._docked_windows()[0])  # 셔플이 죽지 않는다
	for w4 in main.windows.duplicate():
		if is_instance_valid(w4) and not w4.is_boss:
			w4.close_after(0.0)
	main.stack_on = false
	Game.up["stack"] = 0
	await get_tree().create_timer(0.8).timeout
	print("[SMOKE] 스택 겹쳐보기 OK")
	# 부흥 단계가 올라 우물이 있어야 한다 (합류 인원 다수)
	assert(main.join_count() >= 7)
	await get_tree().create_timer(2.0).timeout  # 재건축 대기
	var well: Interactable = null
	var home: Interactable = null
	for n in get_tree().get_nodes_in_group("hoverable"):
		if n is Interactable and n.kind == "well":
			well = n
		elif n is Interactable and n.kind == "home":
			home = n
	assert(home != null)
	main._bump_home(home)
	if well != null:
		main._bump_well(well)
		assert(Game.stats["wells"] >= 1)
	# 칭호 — 통계 강제 충족 후 폴링 대기 (칭호 1틱 + 훈장 1틱)
	Game.stats["inn_rests"] = 10
	await get_tree().create_timer(3.5).timeout
	assert(Game.titles.size() >= 1)
	assert(Game.medals_owned.has("late_sleep"))
	print("[SMOKE] 수중/우물/집/칭호 OK — 칭호 %s" % str(Game.titles))

	# 16) v3.2 — 카지노 운 트리 (코인 결제)
	Game.coins += 500
	main.hud.open_casino()
	main.hud._casino_buy_up("jackpot", 60)
	assert(Game.casino_up["jackpot"] == 1)
	main.hud._casino_buy_up("hold", 150)
	assert(Game.casino_up["hold"] == 1)
	main.hud.close_menu()
	print("[SMOKE] 카지노 운 트리 OK")

	# 11) 세이브/로드 (v6 — 이름/작전/로토/칭호/통계/카지노 운)
	Game.hero_name = "테스트용사"
	var owned_n: int = Game.companion_count()
	var pids: Array = Game.party_ids.duplicate()
	var titles_n: int = Game.titles.size()
	var pots_n: int = int(Game.stats["pots"])
	Game.save_game()
	Game.load_game()
	assert(Game.companion_count() == owned_n)
	assert(Game.party_ids == pids)
	assert(int(Game.companion_weapons.get("warrior", 0)) == 1)   # 무기점 플랫
	assert(int(Game.companion_forge.get("warrior", 0)) == 3)    # 대장간 벼림 (v3.4)
	assert(Game.deposit >= dep_before)  # 이자 틱 허용
	assert(Game.hero_name == "테스트용사")
	assert(Game.roto_complete())
	assert(Game.titles.size() == titles_n)
	assert(int(Game.stats["pots"]) == pots_n)
	assert(Game.casino_up["hold"] == 1)
	print("[SMOKE] 세이브/로드 OK (v6)")

	# 17) v3.3 — 세이브 슬롯 메타 + 옵션 ConfigFile
	var meta: Dictionary = Game.slot_meta(Game.save_slot)
	assert(meta["exists"] and String(meta["name"]) == "테스트용사")
	assert(int(meta["revival"]) >= 2)
	var ts_save: int = int(Game.opt["text_speed"])
	Game.opt["text_speed"] = 0
	Game.save_options()
	Game.opt["text_speed"] = 2
	Game.load_options()
	assert(int(Game.opt["text_speed"]) == 0)
	Game.opt["text_speed"] = ts_save
	Game.save_options()
	print("[SMOKE] 슬롯 메타/옵션 OK — %s Lv%d 부흥%d" % [meta["name"], meta["level"], meta["revival"]])

	# 18) v3.3 — 엔딩 수미상관 (마왕 격파 → 산책 → 광장 집합 → 크레딧 → 늦잠)
	main._on_boss_defeated(4)
	await get_tree().create_timer(14.0).timeout
	assert(main._ending_playing)
	assert(get_tree().get_nodes_in_group("ending_cast").size() >= 3)  # 내가 모은 사람들
	print("[SMOKE] 엔딩 광장 집합 OK — %d명" % get_tree().get_nodes_in_group("ending_cast").size())
	await get_tree().create_timer(62.0).timeout
	assert(Game.ending_seen)
	assert(not main._ending_playing)
	print("[SMOKE] 엔딩/크레딧 OK — 늦잠까지 확인")

	# 19) v3.3 — 2주차 모험 (뉴게임+ — 배율 없음, 시작 부스트만)
	var medals_n: int = Game.medals_owned.size()
	var titles_keep: int = Game.titles.size()
	Game.do_prestige()
	assert(Game.run_count == 2)
	assert(Game.gold == 500)                                # 시작 부스트: 여비
	assert(Game.companions_owned.get("knight", false))      # 시작 부스트: 배웅 나온 기사
	assert(Game.medals_owned.size() == medals_n)            # 훈장 영구
	assert(Game.titles.size() == titles_keep)               # 칭호 영구
	assert(Game.hero_name == "테스트용사")                  # 이름 영구
	assert(Game.max_windows() <= 4)  # 회차 보너스는 +1 캡 (배율/누적 없음)
	print("[SMOKE] 2주차 모험 OK — 배율 없음, 부스트만")

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
	main.buy_catalog("smith")
	await get_tree().create_timer(3.0).timeout
	main.buy_catalog("shop")
	await get_tree().create_timer(4.5).timeout
	# 파티 4인 — 카드 규격 확인용 (v4.0 §B-3)
	for cid in ["knight", "priest", "mage"]:
		Game.own_companion(cid)
		if not Game.party_ids.has(cid):
			Game.toggle_party(cid)
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
	# 툴팁 — 세로 쪼개짐 회귀 방지 (main._process 정지 → _update_hover가 set_hover 안 지움)
	for w in main.windows.duplicate():
		if is_instance_valid(w) and not w.is_boss:
			w.close_after(0.0)
	await get_tree().create_timer(0.4).timeout
	main.set_process(false)
	var tl: Label = main.hud.get_node("%TooltipLabel")
	main.hud.set_hover("게시판 — 위험한 것들을 훨훨 물 머금은 채로 굽어보고 있다.")
	await get_tree().create_timer(0.2).timeout
	assert(tl.get_line_count() == 1)  # 한 줄 가로 (세로 쪼개짐 회귀 시 여러 줄)
	main.hud._tooltip.position = Vector2(120, 150)
	await _save_shot("shot_tooltip.png")
	main.hud.set_hover("게시판")
	await get_tree().create_timer(0.2).timeout
	assert(tl.get_line_count() == 1)
	main.hud._tooltip.position = Vector2(120, 150)
	await _save_shot("shot_tooltip_short.png")
	main.hud.set_hover("")
	main.set_process(true)
	print("[SMOKE] 툴팁 가로 OK")
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
