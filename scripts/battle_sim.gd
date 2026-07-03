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

const LETTERS := ["A", "B", "C", "D", "E"]

var enemies: Array = []          # {name, letter, hp, max_hp, atk, gold, exp, tex, scale, dead}
var is_boss := false
var finished := false
var hovered := false             # BattleWindow가 설정 (주시 버프)

var golden_active := false
var golden_timer := 0.0
var golden_gauge := 0.0

var _timer := 0.0
var _queue: Array = []           # ["m"/"e", index] 또는 ["intro"/"win"]
var _won_pending := false

func setup(defs: Array, boss: bool) -> void:
	is_boss = boss
	enemies = []
	for i in defs.size():
		var d: Dictionary = defs[i]
		enemies.append({
			"name": d["name"],
			"mid": d.get("id", ""),
			"letter": (LETTERS[i] if defs.size() > 1 else ""),
			"hp": int(d["hp"]), "max_hp": int(d["hp"]),
			"atk": int(d["atk"]), "gold": int(d["gold"]), "exp": int(d["exp"]),
			"tex": d["tex"], "scale": d.get("scale", 2.0),
			"dead": false,
		})
	_queue = [["intro"]]
	_timer = 0.6  # 등장 텍스트는 바로

func display_name(e: Dictionary) -> String:
	return String(e["name"]) + String(e["letter"])

func alive_enemies() -> Array:
	var out: Array = []
	for i in enemies.size():
		if not enemies[i]["dead"]:
			out.append(i)
	return out

# ---------------------------------------------------------------- tick

func tick(delta: float) -> void:
	if finished:
		return
	var speed := 1.5 if hovered else 1.0
	# 황금 슬라임 타이머
	if golden_active:
		golden_timer -= delta
		if golden_timer <= 0.0:
			golden_active = false
			line.emit("황금 슬라임은")
			line.emit("도망쳐 버렸다!")
			golden_escaped.emit()
	_timer += delta * speed
	var interval := Game.turn_interval()
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
	for i in Game.members.size():
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
	if is_ghost:
		# 심령 파티 — 유령도 절반 위력으로 싸운다
		var target_g: int = alive[randi() % alive.size()]
		var dmg_g := _roll_damage(idx, 0.5, 0.0)
		line.emit("%s(유령)의 공격!" % m["name"])
		_apply_enemy_damage(target_g, dmg_g[0], dmg_g[1], true)
		return
	if cls == "priest":
		var t := Game.lowest_hp_alive()
		if t >= 0 and Game.members[t]["hp"] < Game.members[t]["max_hp"]:
			var amount := Game.priest_heal_amount()
			Game.heal_member(t, amount)
			line.emit("승려의 기도!")
			line.emit("%s의 상처가 아문다" % Game.members[t]["name"])
			member_healed.emit(t, amount)
			return
		# 회복할 곳이 없으면 약한 공격으로
	if golden_active:
		# 황금 슬라임에게 정신이 팔렸다 — 전부 회피
		line.emit("%s의 공격!" % m["name"])
		line.emit("미스! 미스!")
		return
	var crit_bonus := 0.15 if hovered else 0.0
	if cls == "mage":
		line.emit("마법사의 주문!")
		for i in alive.duplicate():
			var dmg := _roll_damage(idx, 0.7, crit_bonus)
			_apply_enemy_damage(i, dmg[0], dmg[1], alive.size() == 1)
	else:
		var target: int = alive[randi() % alive.size()]
		var dmg2 := _roll_damage(idx, 1.0, crit_bonus)
		if dmg2[1]:
			line.emit("회심의 일격!!")
		else:
			line.emit("%s의 공격!" % m["name"])
		_apply_enemy_damage(target, dmg2[0], dmg2[1], true)

func _roll_damage(idx: int, mult: float, crit_bonus: float) -> Array:
	var atk := Game.member_atk(idx)
	var crit := randf() < (Game.member_crit(idx) + crit_bonus)
	var dmg := int(maxf(1.0, atk * mult * randf_range(0.85, 1.15))) * (2 if crit else 1)
	return [dmg, crit]

func _apply_enemy_damage(i: int, dmg: int, crit: bool, log_line: bool) -> void:
	var e: Dictionary = enemies[i]
	if e["dead"]:
		return
	e["hp"] = maxi(0, e["hp"] - dmg)
	var dead: bool = e["hp"] == 0
	if dead:
		e["dead"] = true
	if log_line:
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
	var dmg := int(maxf(1.0, e["atk"] * randf_range(0.8, 1.2)))
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
	g = int(g * Game.gold_multiplier())
	line.emit("몬스터를 물리쳤다!")
	line.emit("%d G를 손에 넣었다!" % g)
	victory.emit(g, xp)

# ---------------------------------------------------------------- 황금 슬라임

func spawn_golden(duration: float) -> void:
	if finished or golden_active:
		return
	golden_active = true
	golden_timer = duration
	golden_gauge = 0.0
	line.emit("황금 슬라임이")
	line.emit("나타났다!")
	golden_spawned.emit()

func rub_golden(amount: float) -> void:
	if not golden_active:
		return
	golden_gauge += amount
	if golden_gauge >= 1.0:
		golden_active = false
		var reward := int(120.0 * Game.gold_scale() * Game.gold_multiplier())
		line.emit("황금 슬라임을")
		line.emit("붙잡았다!")
		golden_captured.emit(reward)
