class_name BattleSim
extends RefCounted
## 전투 시뮬레이션 — 순수 데이터 (노드 아님). BattleWindow가 시그널을 구독해 그린다.
## 파티 스탯은 Game 싱글턴 단일 소스 참조 (편재의 원리).

signal line(text: String)
signal enemy_hit(index: int, dmg: int, crit: bool, dead: bool)
signal member_hit(idx: int, dmg: int, fell: bool)
signal member_healed(idx: int, amount: int)
signal golden_spawned
signal golden_escaped
signal golden_captured(reward: int)
signal victory(gold_reward: int, exp_reward: int)
signal frogified
signal enemy_acted(index: int)   # v3.4 §B-11 — 공격 주체 스텝 연출용

const LETTERS := ["A", "B", "C", "D", "E"]

var enemies: Array = []          # {name, letter, hp, max_hp, atk, gold, exp, tex, scale, dead}
var is_boss := false
var finished := false
var hovered := false             # BattleWindow가 설정 (주시 버프)
var hovered_adj := false         # 천리안 — 옆 창 주시의 절반 (main이 설정, v3.2)
var window_tactic := ""          # 이 창의 유효 작전 (임기응변=창마다 랜덤, v3.2 §B-3)

var golden_active := false
var golden_silver := false       # 밤의 은빛 슬라임 (v3.2 §B-5 — 보상이 다르다)
var golden_timer := 0.0
var golden_gauge := 0.0

var _timer := 0.0
var _queue: Array = []           # ["m"/"e", index] 또는 ["intro"/"win"]
var _won_pending := false

func setup(defs: Array, boss: bool) -> void:
	is_boss = boss
	window_tactic = Game.roll_tactic()
	enemies = []
	for i in defs.size():
		var d: Dictionary = defs[i]
		enemies.append({
			"name": d["name"],
			"mid": d.get("id", ""),
			"family": d.get("family", "slime"),
			"letter": (LETTERS[i] if defs.size() > 1 else ""),
			"hp": int(d["hp"]), "max_hp": int(d["hp"]),
			"atk": int(d["atk"]), "gold": int(d["gold"]), "exp": int(d["exp"]),
			"tex": d["tex"], "scale": d.get("scale", 2.0),
			"dead": false,
		})
	_queue = [["intro"]]
	_timer = 0.6  # 등장 텍스트는 바로

func snapshot() -> Dictionary:
	var saved_enemies: Array = []
	for enemy in enemies:
		saved_enemies.append({
			"id": enemy.get("mid", ""), "name": enemy["name"], "family": enemy.get("family", "slime"),
			"hp": enemy["hp"], "max_hp": enemy["max_hp"], "atk": enemy["atk"],
			"gold": enemy["gold"], "exp": enemy["exp"], "tex": enemy["tex"], "scale": enemy.get("scale", 1.0),
			"dead": enemy["dead"]})
	return {"enemies": saved_enemies, "boss": is_boss, "timer": _timer, "queue": _queue,
		"won_pending": _won_pending, "golden_active": golden_active, "golden_silver": golden_silver,
		"golden_timer": golden_timer, "golden_gauge": golden_gauge, "tactic": window_tactic}

func restore_snapshot(data: Dictionary) -> void:
	var defs: Array = []
	for enemy in data.get("enemies", []):
		defs.append({"id": enemy.get("id", ""), "name": enemy["name"], "family": enemy.get("family", "slime"),
			"hp": enemy["max_hp"], "atk": enemy["atk"], "gold": enemy["gold"], "exp": enemy["exp"],
			"tex": enemy["tex"], "scale": enemy.get("scale", 1.0)})
	setup(defs, bool(data.get("boss", false)))
	for i in mini(enemies.size(), data.get("enemies", []).size()):
		var saved: Dictionary = data["enemies"][i]
		enemies[i]["hp"] = int(saved["hp"])
		enemies[i]["dead"] = bool(saved["dead"])
	_timer = float(data.get("timer", 0.0))
	_queue = data.get("queue", [])
	_won_pending = bool(data.get("won_pending", false))
	golden_active = bool(data.get("golden_active", false))
	golden_silver = bool(data.get("golden_silver", false))
	golden_timer = float(data.get("golden_timer", 0.0))
	golden_gauge = float(data.get("golden_gauge", 0.0))
	window_tactic = String(data.get("tactic", ""))

func display_name(e: Dictionary) -> String:
	return String(e["name"]) + String(e["letter"])

func alive_enemies() -> Array:
	var out: Array = []
	for i in enemies.size():
		if not enemies[i]["dead"]:
			out.append(i)
	return out

# ---------------------------------------------------------------- tick

# ---------------------------------------------------------------- 작전 (v3.2 §B-3 — 가중치 3세트)

func _tp() -> float:
	return Game.tactic_power()

func tactic_out_mult(t: String = "") -> float:      # 아군이 주는 데미지 (v3.6: 개별 작전 지원)
	match (t if t != "" else window_tactic):
		"attack": return 1.0 + 0.15 * _tp()
		"gold": return maxf(0.55, 1.0 - 0.15 * _tp())
	return 1.0

func tactic_in_mult(t: String = "") -> float:       # 아군이 받는 데미지
	match (t if t != "" else window_tactic):
		"attack": return 1.0 + 0.2 * _tp()
		"life": return maxf(0.5, 1.0 - 0.15 * _tp())
	return 1.0

func tactic_speed_mult() -> float:    # 턴 간격 (작을수록 빠름)
	match window_tactic:
		"attack": return maxf(0.6, 1.0 - 0.1 * _tp())
	return 1.0

func tactic_gold_mult() -> float:
	match window_tactic:
		"gold": return 1.0 + 0.25 * _tp()
		"life": return maxf(0.7, 1.0 - 0.1 * _tp())
	return 1.0

func tick(delta: float) -> void:
	if finished:
		return
	var speed: float = Game.gaze_speed() if hovered else 1.0
	if not hovered and hovered_adj:
		speed = 1.0 + (Game.gaze_speed() - 1.0) * 0.5  # 천리안 — 옆 창 절반
	# 황금 슬라임 타이머
	if golden_active:
		golden_timer -= delta
		if golden_timer <= 0.0:
			golden_active = false
			line.emit("황금 슬라임은")
			line.emit("도망쳐 버렸다!")
			golden_escaped.emit()
	_timer += delta * speed
	var interval := Game.turn_interval() * tactic_speed_mult()
	if _timer < interval:
		return
	_timer = 0.0
	_step()

func _step() -> void:
	if _won_pending:
		_finish_victory()
		return
	if _queue.is_empty():
		_build_round()
	if _queue.is_empty():
		return
	var act: Array = _queue.pop_front()
	match act[0]:
		"intro":
			var e0: Dictionary = enemies[0]
			if enemies.size() > 1:
				line.emit("%s이(가) %d마리" % [e0["name"], enemies.size()])
				line.emit("나타났다!")
			else:
				line.emit("%s이(가)" % e0["name"])
				line.emit("나타났다!")
		"m":
			_member_act(act[1])
		"e":
			_enemy_act(act[1])
	# 승리 판정
	if not _won_pending and alive_enemies().is_empty():
		_won_pending = true
		_queue.clear()

func _build_round() -> void:
	var spirits: bool = Game.medal_on("spirit_party")
	# 목숨을 소중히 — 그 작전을 받은 사제(기도)가 맨 먼저 움직인다 (v3.6: 개별 작전 반영)
	var first: Array = []
	for i in Game.members.size():
		var m: Dictionary = Game.members[i]
		if not m["ghost"] and Game.COMPANIONS[m["cls"]]["passive"] == "pray" \
				and Game.member_tactic_of(String(m["cls"]), window_tactic) == "life":
			first.append(i)
			_queue.append(["m", i])
	for i in Game.members.size():
		if first.has(i):
			continue  # 이미 앞줄에 세웠다
		if not Game.members[i]["ghost"] or spirits:
			_queue.append(["m", i])
	for i in enemies.size():
		if not enemies[i]["dead"]:
			_queue.append(["e", i])

# ---------------------------------------------------------------- actions

func _member_act(idx: int) -> void:
	if idx >= Game.members.size():
		return
	var m: Dictionary = Game.members[idx]
	var is_ghost: bool = m["ghost"]
	if is_ghost and not Game.medal_on("spirit_party"):
		return
	var alive := alive_enemies()
	if alive.is_empty():
		return
	var cls: String = m["cls"]
	var passive: String = Game.COMPANIONS[cls]["passive"]
	if is_ghost:
		# 심령 파티 — 유령도 절반 위력으로 싸운다
		var target_g: int = alive[randi() % alive.size()]
		var dmg_g := _roll_damage(idx, 0.5, 0.0)
		line.emit("%s(유령)의 공격!" % m["name"])
		_apply_enemy_damage(target_g, dmg_g[0], dmg_g[1], true)
		return
	if passive == "pray":
		# 사제의 기도 — 파티 전원이 최대 HP의 %만큼 아문다 (v3.1 %화)
		var pct := 0.025 + 0.002 * float(m["weapon_lv"])
		var healed_any := false
		for i in Game.members.size():
			var t: Dictionary = Game.members[i]
			if t["ghost"] or t["hp"] >= t["max_hp"]:
				continue
			var amount := maxi(1, int(t["max_hp"] * pct))
			Game.heal_member(i, amount)
			member_healed.emit(i, amount)
			healed_any = true
		if healed_any:
			line.emit("%s의 기도!" % m["name"])
			line.emit("일행의 상처가 아문다")
			return
		# 회복할 곳이 없으면 약한 공격으로
	if golden_active:
		# 황금 슬라임에게 정신이 팔렸다 — 전부 회피
		line.emit("%s의 공격!" % m["name"])
		line.emit("미스! 미스!")
		return
	var crit_bonus: float = Game.gaze_crit() if hovered else (Game.gaze_crit() * 0.5 if hovered_adj else 0.0)
	if passive == "aoe":
		line.emit("%s의 주문!" % m["name"])
		for i in alive.duplicate():
			var dmg := _roll_damage(idx, 0.7, crit_bonus)
			_apply_enemy_damage(i, dmg[0], dmg[1], alive.size() == 1)
	else:
		var mult := 1.5 if passive == "smite" else 1.0  # 전사의 강타
		var target: int = alive[randi() % alive.size()]
		var dmg2 := _roll_damage(idx, mult, crit_bonus)
		if dmg2[1]:
			line.emit("회심의 일격!!")
		elif passive == "smite":
			line.emit("%s의 강타!" % m["name"])
		else:
			line.emit("%s의 공격!" % m["name"])
		_apply_enemy_damage(target, dmg2[0], dmg2[1], true)

func _roll_damage(idx: int, mult: float, crit_bonus: float) -> Array:
	var atk := Game.member_atk(idx)
	var crit := randf() < (Game.member_crit(idx) + crit_bonus)
	var dmg := int(maxf(1.0, atk * mult * randf_range(0.85, 1.15))) * (2 if crit else 1)
	# v3.6: 공격자 본인의 작전이 데미지를 정한다 (개별 지시 > 창의 작전)
	var mt: String = Game.member_tactic_of(String(Game.members[idx]["cls"]), window_tactic)
	dmg = int(maxf(1.0, dmg * tactic_out_mult(mt)))
	return [dmg, crit]

func _apply_enemy_damage(i: int, dmg: int, crit: bool, log_line: bool) -> void:
	var e: Dictionary = enemies[i]
	if e["dead"]:
		return
	# 정찰 보고 (게시판 업글, v3.9) — 수배 몬스터/지배자에게 보너스
	var mid_t: String = String(e.get("mid", ""))
	if Game.up["track"] > 0 and (is_boss or mid_t == "angry" or mid_t == "cyclops"):
		dmg = int(dmg * (1.0 + 0.25 * Game.up["track"]))
	# 무리 사냥꾼 — 적 4마리 이상인 창에서 +50% (v3.2 조건형)
	if Game.medal_on("pack_hunter") and enemies.size() >= 4:
		dmg = int(dmg * 1.5)
	e["hp"] = maxi(0, e["hp"] - dmg)
	var dead: bool = e["hp"] == 0
	if dead:
		e["dead"] = true
	if log_line:
		# v3.8 §B-1: 준 데미지 = 크림(기본), 크리티컬 = 금 + [slam] 자동
		if crit:
			line.emit("%s에 [slam][color=#f5c542]%d[/color][/slam]!" % [display_name(e), dmg])
		else:
			line.emit("%s에 %d!" % [display_name(e), dmg])
	if dead:
		line.emit("%s을(를)" % display_name(e))
		line.emit("쓰러뜨렸다!")
		Game.add_kill(String(e.get("mid", e.get("name", ""))))
	enemy_hit.emit(i, dmg, crit, dead)

func _enemy_act(i: int) -> void:
	var e: Dictionary = enemies[i]
	if e["dead"]:
		return
	var t := Game.pick_target()
	if t < 0:
		return
	enemy_acted.emit(i)
	# v3.6: 맞는 쪽의 작전이 피격량을 정한다 (목숨을 소중히 = 그 사람만 덜 맞는다)
	var tt: String = Game.member_tactic_of(String(Game.members[t]["cls"]), window_tactic)
	var raw := int(maxf(1.0, e["atk"] * randf_range(0.8, 1.2) * tactic_in_mult(tt)))
	var dmg := Game.mitigate(t, raw)  # v4.3: 방어력으로 피해 경감
	line.emit("%s의 공격!" % display_name(e))
	Game.damage_member(t, dmg)
	var fell: bool = Game.members[t]["ghost"]
	if fell:
		line.emit("%s는 쓰러졌다!" % Game.members[t]["name"])
	else:
		line.emit("%s에게 %d!" % [Game.members[t]["name"], dmg])
	member_hit.emit(t, dmg, fell)

# ---------------------------------------------------------------- 승리

func _finish_victory() -> void:
	finished = true
	var g := 0
	var xp := 0
	for e in enemies:
		g += int(e["gold"])
		xp += int(e["exp"])
	g = int(g * Game.gold_multiplier() * tactic_gold_mult())
	# 어부의 긍지 — 어부 형제가 마을에 있으면 무리 창 보상 +50% (v3.9: 주민 조건)
	if enemies.size() >= 3 and Game.medal_on("fisher_pride") and Game.residents.get("fishers", false):
		g = int(g * 1.5)
	# 통계 — 미믹 승수 (도전과제식 훈장의 재료)
	for e in enemies:
		if String(e.get("mid", "")) == "mimic":
			Game.add_stat("mimic_wins")
	line.emit("몬스터를 물리쳤다!")
	line.emit("%d G를 손에 넣었다!" % g)
	# (v3.9: 상인 잡템 패시브 폐지 — 상인은 주민)
	# 도적의 훔치기 — 가끔 작은 메달을 슬쩍
	if Game.passive_on("steal"):
		var p := 0.02 if Game.medal_on("loyal_heart") else 0.01
		if randf() < p:
			Game.medals_small += 1
			line.emit("도적이 작은 메달을 슬쩍했다!")
	# 드루이드의 매혹 — 승리 시 가끔 적이 따라온다
	if Game.passive_on("charm") and Game.charmed.size() < 2 and randf() < 0.08:
		var mid: String = String(enemies[0].get("mid", ""))
		if mid != "":
			Game.charmed.append(mid)
			line.emit("%s이(가) 매혹되어\n일행을 따라온다!" % String(enemies[0]["name"]))
	# 합체기 게이지 — 승리가 쌓일수록 차오른다
	Game.add_combo_gauge()
	victory.emit(g, xp)

# ---------------------------------------------------------------- 합체기 (v3.1 §B-4)

func combo_annihilate() -> void:
	# 참치 어택 / 명계의 행진 — 창의 전 몬스터 소탕 (보상은 정상 지급)
	if finished:
		return
	for i in alive_enemies():
		_apply_enemy_damage(i, 99999, true, false)
	if not _won_pending and alive_enemies().is_empty():
		_won_pending = true
		_queue.clear()
		_timer = Game.turn_interval()  # 다음 틱에 바로 승리 정산

func combo_frogify() -> void:
	# 개구리의 왈츠 — 전 몬스터 개구리화: HP 1, 골드 2배
	if finished:
		return
	for i in alive_enemies():
		var e: Dictionary = enemies[i]
		e["hp"] = 1
		e["gold"] = int(e["gold"]) * 2
	line.emit("몬스터들이 홀려서")
	line.emit("개구리처럼 춤춘다!")
	frogified.emit()

# ---------------------------------------------------------------- 황금 슬라임

func spawn_golden(duration: float, silver: bool = false) -> void:
	if finished or golden_active:
		return
	golden_active = true
	golden_silver = silver
	# v4.3: 처음부터 붙잡을 수 있다. 손길 업글은 도주까지 시간을 벌어 준다 (+2초/lv)
	golden_timer = duration + 2.0 * Game.up["golden_hands"]
	golden_gauge = 0.0
	line.emit("%s 슬라임이" % ("은빛" if silver else "황금"))
	line.emit("나타났다!")
	golden_spawned.emit()

func rub_golden(amount: float) -> void:
	if not golden_active:
		return
	# v4.3: 손길 업글은 문지를 때 더 빨리 찬다 (+25%/lv)
	golden_gauge += amount * (1.0 + 0.25 * Game.up["golden_hands"])
	if golden_gauge >= 1.0:
		golden_active = false
		# 은빛(밤)은 경험치를, 황금(낮)은 골드를 남긴다 (v3.2 §B-5)
		var reward: int
		if golden_silver:
			reward = int(60.0 * Game.tier_exp(Game.progress_tier()))
		else:
			reward = int(120.0 * Game.gold_scale() * Game.gold_multiplier())
		line.emit("%s 슬라임을" % ("은빛" if golden_silver else "황금"))
		line.emit("붙잡았다!")
		golden_captured.emit(reward)
