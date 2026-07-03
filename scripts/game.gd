extends Node
## 전역 게임 상태 싱글턴 (파티 편재의 원리 = 모든 전투창이 이 단일 상태를 참조)

signal gold_changed(value: int)
signal member_changed(idx: int)
signal party_changed
signal level_changed(value: int)
signal chapter_changed(value: int)
signal party_wiped
signal upgrades_changed

const MAX_WINDOWS_HARD := 8

# 스모크 테스트는 별도 세이브를 쓴다 — 유저의 진짜 세이브를 건드리지 않도록
var save_path := "user://appears_save.json"

# ---------------------------------------------------------------- 파티

const CLASS_DEFS := {
	"hero":    {"name": "용사",   "atk": 4, "hp": 26, "crit": 0.10, "aggro": 1.0, "tex": "res://assets/characters/hero.png",   "frame_h": 26, "weapon": "용사의 검"},
	"warrior": {"name": "전사",   "atk": 6, "hp": 36, "crit": 0.05, "aggro": 3.0, "tex": "res://assets/characters/knight.png", "frame_h": 25, "weapon": "전사의 검"},
	"mage":    {"name": "마법사", "atk": 5, "hp": 18, "crit": 0.05, "aggro": 1.0, "tex": "res://assets/characters/mage.png",   "frame_h": 25, "weapon": "마법사의 지팡이"},
	"priest":  {"name": "승려",   "atk": 2, "hp": 22, "crit": 0.05, "aggro": 1.0, "tex": "res://assets/characters/priest.png", "frame_h": 24, "weapon": "승려의 석장"},
}
const PARTY_ORDER := ["hero", "warrior", "mage", "priest"]

var members: Array = []  # {cls, name, hp, max_hp, ghost, weapon_lv}

# ---------------------------------------------------------------- 재화/성장

var gold: int = 0
var total_earned: int = 0
var level: int = 1
var exp: int = 0
var run_count: int = 1  # 회차
var kills: int = 0

# 업그레이드 — 담당 건물의 커맨드 메뉴로 분산 (v3.0 §B-5. 공격력은 대장간 무기가 담당)
var up := {
	"speed": 0, "win_cap": 0, "battle_speed": 0,
	"gold_mult": 0, "max_hp": 0, "density": 0,
	"shovel": 0, "radius": 0, "intuition": 0,
}

# 진행 플래그 — v3.0 한 화면 월드
var fields_unlocked: Array = [true, false, false, false, false]  # 초원/숲/동굴/설원/마왕성
var bosses_defeated: Array = [false, false, false, false, false]
var posters_f: Array = [0, 0, 0, 0, 0]  # 필드별 수배서 (마왕성 제외)
var extra_pots := 0
var buildings := {"inn": false, "board": false, "church": false, "smith": false, "chest": false, "casino": false, "bard": false, "medalking": false, "shop": false}
var recruits_spawned := {"warrior": false, "mage": false, "priest": false}
var discovered := {}                 # 검시(도감): kind 문자열 → true
var golden_first_done := false
var golden_info := false             # 게시판 "황금 슬라임 목격 정보"
var ending_seen := false

# v3.0 — 주민(시설의 화신) / 열쇠 / 작은 메달 / 부탁
var residents := {}                  # id → true (영입됨). 주민 수 = 마을의 진행바
var kill_counts := {}                # 몬스터 id → 처치 수 (부탁 퀘스트용)
var medals_small := 0                # 작은 메달 (골드 교환 불가 수집품)
var medals_spent := 0                # 메달왕에게 이미 교환한 누적치
var keys := {"thief": false, "magic": false}   # 드퀘 열쇠
var opened := {"warehouse": false, "redchest": false}  # 잠긴 오브젝트
var signpost_seen := false           # 이정표 등장 여부 (보스 1 처치 후)

# UI 공개 스케줄 — 화면의 모든 UI는 해금 이벤트를 가진다 ("게임이 자라는 게임")
var ui_unlocked := {"desc": false, "gold": false, "party": false, "quest": false}

func resident_count() -> int:
	var n := 0
	for k in residents.keys():
		if residents[k]:
			n += 1
	return n

func add_kill(id: String) -> void:
	kills += 1
	kill_counts[id] = int(kill_counts.get(id, 0)) + 1

# Phase 4 상태
var coins: int = 0                   # 카지노 코인 (놀이용 칩)
var epic_verses: int = 0             # 서사시 구매한 절 수 (0~6) — 회차 넘어 유지
var smith_perfects: int = 0          # 회심의 필살작 횟수 (도전과제식 훈장)
var casino_wincap: int = 0           # 카지노 교환소 전투창 상한 +1
var assistants := {"monkey": 0, "keeper": 0, "pig": 0}  # 조수 동물 보유 수
var medals_owned: Array = []         # 훈장 도감 — 회차 넘어 영구 소장
var medals_equipped: Array = []      # 장착 중 (슬롯 제한)

# ---------------------------------------------------------------- 훈장 (규칙을 바꾸는 훈장만)

const MEDAL_DEFS := {
	"coward_flag":   {"name": "겁쟁이의 깃발",       "desc": "창 상한 -1, 남은 창 전투 속도 2배",       "hint": "초원의 지배자가 지니고 있다"},
	"aqua_regia":    {"name": "왕수의 성수",         "desc": "받는 데미지 2배, 골드 2배",               "hint": "숲의 지배자가 지니고 있다"},
	"ghost_warcry":  {"name": "원혼의 함성",         "desc": "유령 1명당 파티 공격력 +15%",             "hint": "동굴의 지배자가 지니고 있다"},
	"spirit_party":  {"name": "심령 파티",           "desc": "유령도 모든 창에서 절반 위력으로 싸운다", "hint": "설원의 지배자가 지니고 있다"},
	"sticky_gloves": {"name": "끈끈이 장갑",         "desc": "황금 슬라임 도주까지 +2초",               "hint": "붉은 상자 안에 있는 것 같다"},
	"cracked_pot":   {"name": "금 간 항아리",        "desc": "항아리 쿨타임 절반, 보상 절반",           "hint": "메달왕이 교환해 준다"},
	"mimic_teeth":   {"name": "미믹의 이빨",         "desc": "모든 상자가 미믹, 보상 3배",              "hint": "카지노 교환소 한정"},
	"metal_crown":   {"name": "메탈 슬라임의 왕관",  "desc": "황금 슬라임이 자주 오지만 빨리 도망간다", "hint": "메달왕이 교환해 준다"},
	"slime_incense": {"name": "슬라임 유인향",       "desc": "황금 슬라임이 주시 중인 창에만 나타난다", "hint": "카지노 교환소 한정"},
	"anvil_bless":   {"name": "모루의 축복",         "desc": "대장간 실패 없음, 대신 +3도 없음",        "hint": "회심의 필살작을 3번 쳐내면…"},
}

func medal_slots() -> int:
	return mini(3 + (run_count - 1), 5)

func medal_on(id: String) -> bool:
	return medals_equipped.has(id)

func own_medal(id: String) -> bool:
	# 이미 갖고 있으면 false, 새로 얻으면 true
	if medals_owned.has(id):
		return false
	medals_owned.append(id)
	return true

func toggle_medal(id: String) -> bool:
	if medals_equipped.has(id):
		medals_equipped.erase(id)
		return true
	if medals_equipped.size() >= medal_slots():
		return false
	medals_equipped.append(id)
	return true

# ---------------------------------------------------------------- 서사시 (음유시인)

const EPIC_COSTS := [100, 250, 600, 1500, 4000, 9000]
const EPIC_VERSES := [
	"그날, 나팔은 울리지 않았다.\n마왕군은 소리 없이 국경을 넘었다.",
	"왕도는 하룻밤 만에 떨어졌다.\n왕은 도망쳤고, 깃발만 남았다.",
	"이전 용사는 홀로 마왕성에 올랐다.\n그리고, 돌아오지 않았다.",
	"세계는 넷으로 찢겨 지배자들의 색에 물들었다.\n마을 하나만이 물들지 않았다.",
	"사람들은 마지막 마을에 모여 소문에 기댔다.\n— 용사가 어딘가에 잠들어 있다는 소문에.",
	"그래서 어머니는 오늘도 아이를 깨운다.\n『일어나렴, 용사야.』",
]

func buy_verse() -> bool:
	if epic_verses >= EPIC_VERSES.size():
		return false
	if not try_spend(EPIC_COSTS[epic_verses]):
		return false
	epic_verses += 1
	# 전설의 검은 돈이 아니라 이야기로 벼려진다
	for m in members:
		if m["cls"] == "hero":
			m["weapon_lv"] = epic_verses
	party_changed.emit()
	return true

func epic_complete() -> bool:
	return epic_verses >= EPIC_VERSES.size()

# ---------------------------------------------------------------- 몬스터 데이터

const MONSTER_DEFS := [
	{"id": "slime",  "name": "슬라임",      "hp": 7,  "atk": 2,  "gold": 4,  "exp": 2,  "tex": "res://assets/enemies/slime.png",        "scale": 1.0},
	{"id": "bat",    "name": "박쥐",        "hp": 14, "atk": 4,  "gold": 10, "exp": 5,  "tex": "res://assets/enemies/bat.png",          "scale": 1.0},
	{"id": "angry",  "name": "성난 슬라임", "hp": 26, "atk": 7,  "gold": 22, "exp": 11, "tex": "res://assets/enemies/slime_chaser.png", "scale": 1.0},
	{"id": "cyclops","name": "외눈 괴수",   "hp": 44, "atk": 11, "gold": 45, "exp": 22, "tex": "res://assets/enemies/slime_fly.png",    "scale": 1.0},
]
const FIELD_NAMES := ["초원", "숲", "동굴", "설원", "마왕성"]
const BOSS_NAMES := ["초원의 지배자", "숲의 지배자", "동굴의 지배자", "설원의 지배자", "마왕"]
const FIELD_TINTS := [
	Color(1, 1, 1),                # 초원
	Color(0.8, 1.05, 0.75),       # 숲
	Color(0.85, 0.75, 1.0),       # 동굴
	Color(0.78, 0.9, 1.15),       # 설원
	Color(0.72, 0.5, 0.85),       # 마왕성
]
const FIELD_PREFIX := ["", "숲 ", "동굴 ", "얼음 ", "마 "]

# 필드 티어(1~5) 기반 스케일
func tier_stat(t: int) -> float:  return pow(2.6, t - 1)
func tier_atk(t: int) -> float:   return pow(2.0, t - 1)
func tier_gold(t: int) -> float:  return pow(2.6, t - 1)
func tier_exp(t: int) -> float:   return pow(2.2, t - 1)

func progress_tier() -> int:
	# 경제 스케일 기준 = 열린 가장 깊은 필드
	var t := 1
	for i in 5:
		if fields_unlocked[i]:
			t = i + 1
	return t

func gold_scale() -> float:
	return pow(2.4, progress_tier() - 1)

func poster_cost(field: int, i: int) -> int:
	return int([60, 250, 700][i] * pow(2.8, field))

# ---------------------------------------------------------------- init

func _ready() -> void:
	_reset_party()
	load_game()

func _reset_party() -> void:
	members = []
	_add_member("hero")

func _add_member(cls: String) -> void:
	var d: Dictionary = CLASS_DEFS[cls]
	members.append({
		"cls": cls, "name": d["name"], "hp": d["hp"], "max_hp": d["hp"],
		"ghost": false, "weapon_lv": 0,
	})

func recruit(cls: String) -> void:
	_add_member(cls)
	party_changed.emit()

func has_member(cls: String) -> bool:
	for m in members:
		if m["cls"] == cls:
			return true
	return false

# ---------------------------------------------------------------- 스탯 공식

func member_atk(idx: int) -> int:
	var m: Dictionary = members[idx]
	var base: int = CLASS_DEFS[m["cls"]]["atk"]
	var atk := float(base + m["weapon_lv"] * 2 + int(level / 2.0))
	if medal_on("ghost_warcry"):
		atk *= 1.0 + 0.15 * ghost_count()
	return int(atk)

func member_crit(idx: int) -> float:
	return CLASS_DEFS[members[idx]["cls"]]["crit"]

func member_max_hp(idx: int) -> int:
	var m: Dictionary = members[idx]
	var base: int = CLASS_DEFS[m["cls"]]["hp"]
	return base + up["max_hp"] * 6 + (level - 1) * 3

func priest_heal_amount() -> int:
	var wl := 0
	for m in members:
		if m["cls"] == "priest":
			wl = m["weapon_lv"]
	return 3 + int(level / 2.0) + wl

func refresh_max_hp() -> void:
	for i in members.size():
		var mx := member_max_hp(i)
		members[i]["max_hp"] = mx
		members[i]["hp"] = mini(members[i]["hp"], mx)
		member_changed.emit(i)

func max_windows() -> int:
	var n: int = 1 + up["win_cap"] + (run_count - 1) + casino_wincap
	if medal_on("coward_flag"):
		n -= 1
	return clampi(n, 1, MAX_WINDOWS_HARD)

func max_enemies_per_window() -> int:
	return mini(1 + up["density"] + int(progress_tier() / 2.0), 5)

func move_speed() -> float:
	return 65.0 * pow(1.08, up["speed"])

func turn_interval() -> float:
	var t := 1.1 * pow(0.93, up["battle_speed"])
	if medal_on("coward_flag"):
		t *= 0.5
	return t

func gold_multiplier() -> float:
	var g := pow(1.15, up["gold_mult"]) * (1.0 + 0.2 * (run_count - 1))
	if medal_on("aqua_regia"):
		g *= 2.0
	return g

# ---------------------------------------------------------------- 골드/경험치

func add_gold(v: int) -> void:
	gold += v
	if v > 0:
		total_earned += v
	gold_changed.emit(gold)

func try_spend(v: int) -> bool:
	if gold < v:
		return false
	gold -= v
	gold_changed.emit(gold)
	return true

func exp_to_next() -> int:
	return 18 * level * level

func add_exp(v: int) -> bool:
	exp += v
	var leveled := false
	while exp >= exp_to_next():
		exp -= exp_to_next()
		level += 1
		leveled = true
	if leveled:
		refresh_max_hp()
		# 레벨업 보너스 회복
		for i in members.size():
			if not members[i]["ghost"]:
				members[i]["hp"] = mini(members[i]["hp"] + 5, members[i]["max_hp"])
				member_changed.emit(i)
		level_changed.emit(level)
	return leveled

# ---------------------------------------------------------------- HP/유령

func damage_member(idx: int, dmg: int) -> void:
	var m: Dictionary = members[idx]
	if m["ghost"]:
		return
	if medal_on("aqua_regia"):
		dmg *= 2
	m["hp"] = maxi(0, m["hp"] - dmg)
	if m["hp"] == 0:
		m["ghost"] = true
	member_changed.emit(idx)
	if m["ghost"]:
		party_changed.emit()
		if alive_count() == 0:
			party_wiped.emit()

func heal_member(idx: int, amount: int) -> void:
	var m: Dictionary = members[idx]
	if m["ghost"]:
		return
	m["hp"] = mini(m["max_hp"], m["hp"] + amount)
	member_changed.emit(idx)

func heal_all_full() -> void:
	for i in members.size():
		if not members[i]["ghost"]:
			members[i]["hp"] = members[i]["max_hp"]
			member_changed.emit(i)

func lowest_hp_alive() -> int:
	var best := -1
	var best_ratio := 2.0
	for i in members.size():
		var m: Dictionary = members[i]
		if m["ghost"]:
			continue
		var r: float = float(m["hp"]) / maxf(1.0, float(m["max_hp"]))
		if r < best_ratio:
			best_ratio = r
			best = i
	return best

func lowest_hp_ratio() -> float:
	var best := 1.0
	for m in members:
		if m["ghost"]:
			continue
		best = minf(best, float(m["hp"]) / maxf(1.0, float(m["max_hp"])))
	return best

func alive_count() -> int:
	var n := 0
	for m in members:
		if not m["ghost"]:
			n += 1
	return n

func ghost_count() -> int:
	return members.size() - alive_count()

func revive_all() -> void:
	for i in members.size():
		if members[i]["ghost"]:
			members[i]["ghost"] = false
			members[i]["hp"] = members[i]["max_hp"]
			member_changed.emit(i)
	party_changed.emit()

func revive_cost() -> int:
	return int(15 * ghost_count() * gold_scale())

func pick_target() -> int:
	# 생존 멤버 중 랜덤, 전사는 가중치 (어그로)
	var pool: Array = []
	for i in members.size():
		if members[i]["ghost"]:
			continue
		var w: float = CLASS_DEFS[members[i]["cls"]]["aggro"]
		for k in int(w):
			pool.append(i)
	if pool.is_empty():
		return -1
	return pool[randi() % pool.size()]

# ---------------------------------------------------------------- 무기 (대장간)

func weapon_cost(idx: int) -> int:
	return int(25 * pow(1.75, members[idx]["weapon_lv"]))

func weapon_name(idx: int) -> String:
	var m: Dictionary = members[idx]
	var lv: int = m["weapon_lv"]
	if m["cls"] == "hero":
		# 전설의 검 — 서사시로만 자란다
		var stages := ["녹슨 검", "낡은 검", "기억의 검", "새벽의 검", "여명의 검", "전설의 검", "전설의 검 (진)"]
		return stages[clampi(lv, 0, stages.size() - 1)]
	var base: String = CLASS_DEFS[m["cls"]]["weapon"]
	if lv >= 10:
		base = "빛나는 " + base
	elif lv >= 5:
		base = "강철 " + base
	return base + (" +%d" % lv if lv > 0 else "")

# ---------------------------------------------------------------- 필드/회차

func unlock_field(i: int) -> void:
	fields_unlocked[i] = true
	chapter_changed.emit(progress_tier())

func do_prestige() -> void:
	run_count += 1
	gold = 0
	total_earned = 0
	level = 1
	exp = 0
	kills = 0
	coins = 0
	fields_unlocked = [true, false, false, false, false]
	bosses_defeated = [false, false, false, false, false]
	posters_f = [0, 0, 0, 0, 0]
	extra_pots = 0
	for k in up.keys():
		up[k] = 0
	for k in assistants.keys():
		assistants[k] = 0
	buildings = {"inn": false, "board": false, "church": false, "smith": false, "chest": false, "casino": false, "bard": false, "medalking": false, "shop": false}
	recruits_spawned = {"warrior": false, "mage": false, "priest": false}
	residents = {}
	kill_counts = {}
	medals_small = 0
	medals_spent = 0
	keys = {"thief": false, "magic": false}
	opened = {"warehouse": false, "redchest": false}
	signpost_seen = false
	golden_first_done = false
	golden_info = false
	ending_seen = false
	# 영구 유지: 훈장 도감/장착, 서사시 이력, 도감(discovered), 필살작 기록, 카지노 상한
	_reset_party()
	members[0]["weapon_lv"] = epic_verses  # 전설의 검은 이야기를 기억한다
	save_game()
	gold_changed.emit(gold)
	chapter_changed.emit(progress_tier())
	party_changed.emit()
	upgrades_changed.emit()

# ---------------------------------------------------------------- 세이브

func save_game() -> void:
	var mem_save: Array = []
	for m in members:
		mem_save.append({"cls": m["cls"], "weapon_lv": m["weapon_lv"], "hp": m["hp"], "ghost": m["ghost"]})
	var data := {
		"version": 4,
		"gold": gold, "total_earned": total_earned,
		"level": level, "exp": exp, "run_count": run_count, "kills": kills,
		"up": up,
		"fields_unlocked": fields_unlocked, "bosses_defeated": bosses_defeated,
		"posters_f": posters_f, "extra_pots": extra_pots,
		"buildings": buildings, "recruits_spawned": recruits_spawned,
		"discovered": discovered, "golden_first_done": golden_first_done,
		"golden_info": golden_info,
		"members": mem_save,
		"coins": coins, "epic_verses": epic_verses, "smith_perfects": smith_perfects,
		"casino_wincap": casino_wincap, "assistants": assistants,
		"medals_owned": medals_owned, "medals_equipped": medals_equipped,
		"ui_unlocked": ui_unlocked,
		"residents": residents, "kill_counts": kill_counts,
		"medals_small": medals_small, "medals_spent": medals_spent,
		"keys": keys, "opened": opened, "signpost_seen": signpost_seen,
	}
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

func load_game() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		return
	var d: Dictionary = parsed
	if int(d.get("version", 1)) < 4:
		return  # v3 이전 세이브는 구조가 달라 버린다 (프로토타입)
	gold = int(d.get("gold", 0))
	total_earned = int(d.get("total_earned", 0))
	level = int(d.get("level", 1))
	exp = int(d.get("exp", 0))
	run_count = int(d.get("run_count", 1))
	kills = int(d.get("kills", 0))
	var fu: Array = d.get("fields_unlocked", [])
	var bd: Array = d.get("bosses_defeated", [])
	var pf: Array = d.get("posters_f", [])
	for i in 5:
		if i < fu.size():
			fields_unlocked[i] = bool(fu[i])
		if i < bd.size():
			bosses_defeated[i] = bool(bd[i])
		if i < pf.size():
			posters_f[i] = int(pf[i])
	extra_pots = int(d.get("extra_pots", 0))
	golden_info = bool(d.get("golden_info", false))
	residents = d.get("residents", {})
	kill_counts = d.get("kill_counts", {})
	medals_small = int(d.get("medals_small", 0))
	medals_spent = int(d.get("medals_spent", 0))
	var kk: Dictionary = d.get("keys", {})
	for k in keys.keys():
		keys[k] = bool(kk.get(k, false))
	var op: Dictionary = d.get("opened", {})
	for k in opened.keys():
		opened[k] = bool(op.get(k, false))
	signpost_seen = bool(d.get("signpost_seen", false))
	var u: Dictionary = d.get("up", {})
	for k in up.keys():
		up[k] = int(u.get(k, 0))
	var b: Dictionary = d.get("buildings", {})
	for k in buildings.keys():
		buildings[k] = bool(b.get(k, buildings[k]))
	var r: Dictionary = d.get("recruits_spawned", {})
	for k in recruits_spawned.keys():
		recruits_spawned[k] = bool(r.get(k, false))
	discovered = d.get("discovered", {})
	golden_first_done = bool(d.get("golden_first_done", false))
	coins = int(d.get("coins", 0))
	epic_verses = int(d.get("epic_verses", 0))
	smith_perfects = int(d.get("smith_perfects", 0))
	casino_wincap = int(d.get("casino_wincap", 0))
	var asst: Dictionary = d.get("assistants", {})
	for k in assistants.keys():
		assistants[k] = int(asst.get(k, 0))
	medals_owned = d.get("medals_owned", [])
	medals_equipped = d.get("medals_equipped", [])
	var uiu: Dictionary = d.get("ui_unlocked", {})
	for k in ui_unlocked.keys():
		ui_unlocked[k] = bool(uiu.get(k, false))
	var mem: Array = d.get("members", [])
	if not mem.is_empty():
		members = []
		for ms in mem:
			_add_member(ms["cls"])
			var m: Dictionary = members[members.size() - 1]
			m["weapon_lv"] = int(ms.get("weapon_lv", 0))
			m["ghost"] = bool(ms.get("ghost", false))
	refresh_max_hp()
	for i in members.size():
		var msave: Dictionary = mem[i] if i < mem.size() else {}
		members[i]["hp"] = clampi(int(msave.get("hp", members[i]["max_hp"])), 0, members[i]["max_hp"])
		if members[i]["ghost"]:
			members[i]["hp"] = 0
