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

# ---------------------------------------------------------------- 동료 로스터 (v3.1 §B-3 — 정규 7 + 객원 11)
## regular = 시그니처 무기 보유 (대장간 강화 대상). 객원은 공용 티어 (무기 없음).
## passive = 규칙 1개 (수치 나열 금지). 에셋 없는 동료는 임시 틴트 — 유저가 png로 교체 예정.

const COMPANIONS := {
	# 정규 7
	"hero":     {"name": "용사",     "regular": true, "passive": "all",     "atk": 4, "hp": 26, "crit": 0.10, "aggro": 1.0, "tex": "res://assets/characters/hero.png",   "frame_h": 26, "tint": Color(1, 1, 1),          "weapon": "용사의 검",
		"pdesc": "만능 — 모든 창에 균등 기여. 검은 서사시가 벼린다", "hint": "처음부터 함께"},
	"knight":   {"name": "기사",     "regular": true, "passive": "taunt",   "atk": 5, "hp": 40, "crit": 0.05, "aggro": 3.0, "tex": "res://assets/characters/knight.png", "frame_h": 25, "tint": Color(1, 1, 1),          "weapon": "기사의 대검",
		"pdesc": "도발 — 피격을 자신에게 집중시킨다", "hint": "골드를 벌면 소문을 듣고 온다"},
	"warrior":  {"name": "전사",     "regular": true, "passive": "smite",   "atk": 7, "hp": 34, "crit": 0.05, "aggro": 1.5, "tex": "res://assets/characters/knight.png", "frame_h": 25, "tint": Color(1.1, 0.75, 0.65),  "weapon": "전사의 도끼",
		"pdesc": "강타 — 단일 대상에 큰 데미지 (정예 창 담당)", "hint": "이름난 부자를 찾아온다"},
	"priest":   {"name": "사제",     "regular": true, "passive": "pray",    "atk": 2, "hp": 22, "crit": 0.05, "aggro": 1.0, "tex": "res://assets/characters/priest.png", "frame_h": 24, "tint": Color(1, 1, 1),          "weapon": "사제의 석장",
		"pdesc": "기도 — 턴마다 파티가 최대 HP의 2.5%씩 아문다", "hint": "골드를 벌면 소문을 듣고 온다"},
	"mage":     {"name": "마법사",   "regular": true, "passive": "aoe",     "atk": 5, "hp": 18, "crit": 0.05, "aggro": 1.0, "tex": "res://assets/characters/mage.png",   "frame_h": 25, "tint": Color(1, 1, 1),          "weapon": "마법사의 지팡이",
		"pdesc": "전체 주문 — 창 안의 전원을 공격 (무리 창 담당)", "hint": "골드를 벌면 소문을 듣고 온다"},
	"thief":    {"name": "도적",     "regular": true, "passive": "steal",   "atk": 5, "hp": 24, "crit": 0.08, "aggro": 0.7, "tex": "res://assets/characters/hero.png",   "frame_h": 26, "tint": Color(0.75, 0.7, 1.1),   "weapon": "도적의 단검",
		"pdesc": "훔치기 — 골드 배율 상승 + 가끔 작은 메달을 슬쩍", "hint": "서사시 속에서 나타난다"},
	"monkf":    {"name": "무도가",   "regular": true, "passive": "crit",    "atk": 6, "hp": 28, "crit": 0.20, "aggro": 1.2, "tex": "res://assets/characters/hero.png",   "frame_h": 26, "tint": Color(1.15, 0.95, 0.6),  "weapon": "무도가의 권갑",
		"pdesc": "회심 — 파티의 회심의 일격 확률 상승", "hint": "큰 부를 이룬 자를 시험하러 온다"},
	# 객원 11 (임시: 촌장 스프라이트 개별 틴트)
	"druid":    {"name": "드루이드", "regular": false, "passive": "charm",    "atk": 3, "hp": 24, "crit": 0.05, "aggro": 1.0, "tex": "res://assets/NPCs/village_chief.png", "frame_h": 26, "tint": Color(0.6, 1.1, 0.6),
		"pdesc": "매혹 — 승리 시 가끔 적이 아군이 되어 따라온다", "hint": "서사시 제 1절"},
	"merchant_c": {"name": "상인",   "regular": false, "passive": "discount", "atk": 2, "hp": 22, "crit": 0.05, "aggro": 0.8, "tex": "res://assets/NPCs/village_chief.png", "frame_h": 26, "tint": Color(1.1, 0.95, 0.6),
		"pdesc": "장사꾼의 눈 — 전 메뉴 10% 할인 + 전투 후 잡템 습득", "hint": "상점 주민이 곧 동료"},
	"bardc":    {"name": "바드",     "regular": false, "passive": "linger",   "atk": 3, "hp": 20, "crit": 0.05, "aggro": 0.8, "tex": "res://assets/NPCs/village_chief.png", "frame_h": 26, "tint": Color(0.65, 1.0, 0.75),
		"pdesc": "여운 — 주시 버프가 커서를 떼도 2.5초 잔류", "hint": "음유시인이 곧 동료"},
	"fisher_a": {"name": "어부 형",  "regular": false, "passive": "fish",     "atk": 4, "hp": 30, "crit": 0.05, "aggro": 1.0, "tex": "res://assets/NPCs/village_chief.png", "frame_h": 26, "tint": Color(0.6, 0.8, 1.15),
		"pdesc": "낚시 — 발굴에서 가끔 물고기(보너스 골드)", "hint": "아우와 함께 온다"},
	"fisher_b": {"name": "어부 아우","regular": false, "passive": "net",      "atk": 4, "hp": 28, "crit": 0.05, "aggro": 1.0, "tex": "res://assets/NPCs/village_chief.png", "frame_h": 26, "tint": Color(0.5, 0.7, 1.05),
		"pdesc": "그물 — 무리 창(적 3+)의 골드 +30%", "hint": "형과 함께 온다"},
	"monk":     {"name": "스님",     "regular": false, "passive": "requiem",  "atk": 3, "hp": 26, "crit": 0.05, "aggro": 1.0, "tex": "res://assets/NPCs/village_chief.png", "frame_h": 26, "tint": Color(0.9, 0.85, 0.7),
		"pdesc": "성불 — 유령 동료가 시간이 지나면 자동으로 되살아난다", "hint": "신부가 부른 오랜 벗"},
	"dancer":   {"name": "무희",     "regular": false, "passive": "dance",    "atk": 3, "hp": 20, "crit": 0.08, "aggro": 0.8, "tex": "res://assets/NPCs/village_chief.png", "frame_h": 26, "tint": Color(1.15, 0.7, 0.9),
		"pdesc": "춤 — 모든 전투창의 턴 속도 소폭 상승", "hint": "카지노가 생기면 찾아온다"},
	"miner":    {"name": "광부",     "regular": false, "passive": "pickaxe",  "atk": 5, "hp": 32, "crit": 0.05, "aggro": 1.2, "tex": "res://assets/NPCs/village_chief.png", "frame_h": 26, "tint": Color(0.8, 0.7, 0.55),
		"pdesc": "곡괭이 — 발굴 보상 상승 + 메달 확률 상승", "hint": "삽을 든 자를 찾아온다"},
	"hunter":   {"name": "사냥꾼",   "regular": false, "passive": "track",    "atk": 5, "hp": 26, "crit": 0.10, "aggro": 1.0, "tex": "res://assets/NPCs/village_chief.png", "frame_h": 26, "tint": Color(0.7, 0.9, 0.6),
		"pdesc": "추적 — 수배된 몬스터에게 데미지 보너스", "hint": "게시판을 보고 찾아온다"},
	"cook":     {"name": "요리사",   "regular": false, "passive": "meal",     "atk": 3, "hp": 28, "crit": 0.05, "aggro": 1.0, "tex": "res://assets/NPCs/village_chief.png", "frame_h": 26, "tint": Color(1.05, 1.0, 0.8),
		"pdesc": "한 끼 — 성수가 훨씬 잘 차오른다", "hint": "여관 주인이 곧 동료"},
	"banker":   {"name": "은행원",   "regular": false, "passive": "interest", "atk": 2, "hp": 22, "crit": 0.05, "aggro": 0.8, "tex": "res://assets/NPCs/village_chief.png", "frame_h": 26, "tint": Color(0.85, 0.9, 1.0),
		"pdesc": "이자 감각 — 편성 중 필드 골드 +10%. 영입하면 은행이 선다", "hint": "큰돈의 냄새를 맡고 온다"},
}
const CLASS_DEFS := COMPANIONS  # 하위 호환 별칭
const PARTY_MAX := 5

## 합체기 3종 (v3.1 §B-4 — 딱 3종 동결). needs = 편성 조건 id, ghost = 유령 필요
const COMBO_DEFS := [
	{"id": "tuna", "name": "참치 어택", "needs": ["fisher_a", "fisher_b"], "ghost": false,
		"cutin": "어부 형제의 힘이 하나가 되었다!\n참치 어택!!", "tex": "res://assets/combined/tuna.png", "fallback": "res://assets/enemies/slime_fly.png", "tint": Color(0.5, 0.7, 1.3)},
	{"id": "frog", "name": "개구리의 왈츠", "needs": ["druid", "bardc"], "ghost": false,
		"cutin": "드루이드와 바드의 선율이 겹쳐진다!\n개구리의 왈츠!", "tex": "res://assets/combined/frog.png", "fallback": "res://assets/enemies/slime.png", "tint": Color(0.5, 1.3, 0.5)},
	{"id": "skeleton", "name": "명계의 행진", "needs": ["priest"], "ghost": true,
		"cutin": "사제의 기도가 저승에 닿았다!\n명계의 행진!!", "tex": "res://assets/combined/skeleton.png", "fallback": "res://assets/enemies/bat.png", "tint": Color(1.2, 1.2, 1.25)},
]

var members: Array = []              # 편성된 파티의 런타임 [{cls, name, hp, max_hp, ghost, weapon_lv}]
var companions_owned := {"hero": true}
var party_ids: Array = ["hero"]      # 현재 편성 (여관에서 교체, 최대 5)
var companion_weapons := {}          # id → 무기 레벨 (정규만)
var book_seen := {"hero": true}      # 동료들의 서 — 회차 넘어 영구 기록
var combo_gauge := 0.0               # 합체기 게이지 0..1
var combo_hint_known := false        # 서사시로 힌트 해금
var charmed: Array = []              # 매혹된 몬스터 defs (다음 전투 1회 참전, 최대 2)
var thief_away := false              # 도적 배신 드라마 (서사시)
var thief_return_at := 0.0
var sword_rock := 0                  # 검이 꽂힌 바위: 0 미스폰 / 1 스폰됨 / 2 뽑음
var playtime := 0.0

# ---------------------------------------------------------------- 재화/성장

var gold: int = 0
var total_earned: int = 0
var level: int = 1
var exp: int = 0
var run_count: int = 1  # 회차
var kills: int = 0

# 업그레이드 — 담당 건물의 커맨드 메뉴로 분산 (v3.0 §B-5. 공격력은 대장간 무기가 담당)
# gaze~holy_regen = 교회 "축복" 계열 (v3.1 §B-7), flee/telepathy = 촌장
var up := {
	"speed": 0, "win_cap": 0, "battle_speed": 0,
	"gold_mult": 0, "max_hp": 0, "density": 0,
	"shovel": 0, "radius": 0, "intuition": 0,
	"gaze": 0, "heal_eye": 0, "golden_hands": 0,
	"holy_max": 0, "holy_regen": 0,
	"flee": 0, "telepathy": 0,
	"bank_cap": 0, "bank_rate": 0,
}

# 성수 게이지 (v3.1 §B-7-4 — 수량제 아님, 자동 재생 리소스)
var holy := 12.0

# 은행 (v3.1 §B-8 — 예금은 전멸에도 불가침)
var deposit := 0

# 진행 플래그 — v3.0 한 화면 월드
var fields_unlocked: Array = [true, false, false, false, false]  # 초원/숲/동굴/설원/마왕성
var bosses_defeated: Array = [false, false, false, false, false]
var posters_f: Array = [0, 0, 0, 0, 0]  # 필드별 수배서 (마왕성 제외)
var extra_pots := 0
var buildings := {"inn": false, "board": false, "church": false, "smith": false, "chest": false, "casino": false, "bard": false, "medalking": false, "shop": false, "bank": false}
var recruits_spawned := {"knight": false, "mage": false, "priest": false, "warrior": false, "monkf": false}
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
	"loyal_heart":   {"name": "의리의 심장",         "desc": "도적의 훔치기 확률 2배",                  "hint": "돌아온 자만이 줄 수 있다"},
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
	# v3.1: 절은 '사건'을 판다 — 실제 사건 연출은 main._on_verse_bought 담당
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
	companions_owned = {"hero": true}
	party_ids = ["hero"]
	companion_weapons = {}
	rebuild_party()

func rebuild_party() -> void:
	# 편성(party_ids)에서 런타임 members를 재구성 — HP는 가득 채워서
	members = []
	for id in party_ids:
		if not COMPANIONS.has(id):
			continue
		var d: Dictionary = COMPANIONS[id]
		members.append({
			"cls": id, "name": d["name"], "hp": d["hp"], "max_hp": d["hp"],
			"ghost": false, "weapon_lv": int(companion_weapons.get(id, 0)),
		})
	refresh_max_hp()
	heal_all_full()
	party_changed.emit()

func own_companion(id: String) -> bool:
	# 새 동료 획득 — 자리가 있으면 자동 편성. 이미 있으면 false
	if companions_owned.get(id, false):
		return false
	companions_owned[id] = true
	book_seen[id] = true
	if party_ids.size() < PARTY_MAX and not party_ids.has(id):
		party_ids.append(id)
		rebuild_party()
	return true

func toggle_party(id: String) -> bool:
	# 여관 편성 — 용사는 고정
	if id == "hero" or not companions_owned.get(id, false):
		return false
	if party_ids.has(id):
		party_ids.erase(id)
	elif party_ids.size() < PARTY_MAX:
		party_ids.append(id)
	else:
		return false
	rebuild_party()
	return true

func recruit(cls: String) -> void:  # 하위 호환
	own_companion(cls)

func has_member(cls: String) -> bool:
	return party_ids.has(cls)

func passive_on(pid: String) -> bool:
	# 편성 중이고 유령이 아닌 동료의 패시브만 살아 있다
	for m in members:
		if not m["ghost"] and COMPANIONS[m["cls"]]["passive"] == pid:
			return true
	return false

func companion_count() -> int:
	var n := 0
	for k in companions_owned.keys():
		if companions_owned[k]:
			n += 1
	return n

# ---------------------------------------------------------------- 스탯 공식

func member_atk(idx: int) -> int:
	var m: Dictionary = members[idx]
	var base: int = COMPANIONS[m["cls"]]["atk"]
	var atk := float(base + m["weapon_lv"] * 2 + int(level / 2.0))
	if medal_on("ghost_warcry"):
		atk *= 1.0 + 0.15 * ghost_count()
	return int(atk)

func member_crit(idx: int) -> float:
	var c: float = COMPANIONS[members[idx]["cls"]]["crit"]
	if passive_on("crit"):
		c += 0.10  # 무도가의 회심 — 파티 전체
	return c

func member_max_hp(idx: int) -> int:
	var m: Dictionary = members[idx]
	var base: int = COMPANIONS[m["cls"]]["hp"]
	# 침구 개선 = %화 (v3.1 §B-6 — 덧셈 방어는 곱셈 공격을 못 따라간다)
	return int((base + (level - 1) * 3) * (1.0 + 0.08 * up["max_hp"]))

func refresh_max_hp() -> void:
	for i in members.size():
		var mx := member_max_hp(i)
		members[i]["max_hp"] = mx
		members[i]["hp"] = mini(members[i]["hp"], mx)
		member_changed.emit(i)

# ---------------------------------------------------------------- 시선(호버) / 성수 / 합체기 / 은행

func gaze_speed() -> float:
	return 1.5 + 0.1 * up["gaze"]      # 주시 강화

func gaze_crit() -> float:
	return 0.15 + 0.03 * up["gaze"]

func holy_max() -> float:
	return 12.0 + 4.0 * up["holy_max"]  # 성수 그릇 확장 (초 단위)

func holy_regen_rate() -> float:
	var r: float = 1.0 * (1.0 + 0.35 * up["holy_regen"])  # 샘의 축복
	if passive_on("meal"):
		r *= 1.5  # 요리사의 한 끼
	return r

func holy_heal_pct() -> float:
	return 0.02 + 0.005 * up["heal_eye"]  # 치유의 눈길 (초당 최대 HP %)

func active_combo() -> Dictionary:
	# 현재 편성으로 성립하는 합체기 (편성 퍼즐 — v3.1 §B-4)
	for cd in COMBO_DEFS:
		var ok := true
		for need in cd["needs"]:
			if not party_ids.has(need):
				ok = false
				break
		if ok and cd["ghost"] and ghost_count() == 0:
			ok = false
		if ok:
			return cd
	return {}

func bank_cap() -> int:
	return int(1000 * pow(2.5, up["bank_cap"]))

func bank_rate() -> float:
	return 0.005 + 0.002 * up["bank_rate"]  # 30초 틱당 이자율

func bank_deposit(v: int) -> int:
	# 넣을 수 있는 만큼만 — 실제 입금액 반환
	var room := maxi(0, bank_cap() - deposit)
	var amt: int = mini(mini(v, gold), room)
	if amt <= 0:
		return 0
	gold -= amt
	deposit += amt
	gold_changed.emit(gold)
	return amt

func bank_withdraw(v: int) -> int:
	var amt: int = mini(v, deposit)
	if amt <= 0:
		return 0
	deposit -= amt
	add_gold(amt)
	return amt

func add_combo_gauge() -> void:
	# 승리할 때마다 게이지가 차오른다 (합체기 성립 편성일 때만)
	if active_combo().is_empty():
		combo_gauge = 0.0
		return
	combo_gauge = minf(1.0, combo_gauge + 0.08)

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
	if passive_on("dance"):
		t *= 0.93  # 무희의 춤
	return t

func gold_multiplier() -> float:
	var g := pow(1.15, up["gold_mult"]) * (1.0 + 0.2 * (run_count - 1))
	if medal_on("aqua_regia"):
		g *= 2.0
	if passive_on("steal"):
		g *= 1.3 if medal_on("loyal_heart") else 1.15  # 도적의 훔치기
	if passive_on("interest"):
		g *= 1.10  # 은행원의 이자 감각
	return g

func price(c: int) -> int:
	# 상인(객원) 편성 시 전 메뉴 10% 할인
	if passive_on("discount"):
		return maxi(1, int(ceil(c * 0.9)))
	return c

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
		var w: float = COMPANIONS[members[i]["cls"]]["aggro"]
		if members[i]["cls"] == "knight":
			w *= 2.0  # 기사의 도발
		for k in maxi(1, int(w)):
			pool.append(i)
	if pool.is_empty():
		return -1
	return pool[randi() % pool.size()]

# ---------------------------------------------------------------- 무기 (대장간)

func weapon_cost(idx: int) -> int:
	return price(int(25 * pow(1.75, members[idx]["weapon_lv"])))

func set_weapon_lv(cls: String, lv: int) -> void:
	# 무기 레벨은 편성 재구성에도 살아남도록 companion_weapons에 기록
	companion_weapons[cls] = lv
	for m in members:
		if m["cls"] == cls:
			m["weapon_lv"] = lv
	party_changed.emit()

func weapon_name(idx: int) -> String:
	var m: Dictionary = members[idx]
	var lv: int = m["weapon_lv"]
	if m["cls"] == "hero":
		# 전설의 검 — 돈이 아니라 이야기(서사시)와 바위가 벼린다
		var stages := ["녹슨 검", "낡은 검", "기억의 검", "새벽의 검", "여명의 검", "전설의 검", "전설의 검 (진)"]
		return stages[clampi(lv, 0, stages.size() - 1)]
	var d: Dictionary = COMPANIONS[m["cls"]]
	var base: String = d.get("weapon", "여행자의 지팡이")  # 객원은 공용 무기
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
	buildings = {"inn": false, "board": false, "church": false, "smith": false, "chest": false, "casino": false, "bard": false, "medalking": false, "shop": false, "bank": false}
	recruits_spawned = {"knight": false, "mage": false, "priest": false, "warrior": false, "monkf": false}
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
	# v3.1 리셋 (book_seen은 영구 — 동료들의 서는 회차를 기억한다)
	combo_gauge = 0.0
	charmed = []
	thief_away = false
	thief_return_at = 0.0
	sword_rock = 0
	holy = holy_max()
	deposit = 0
	# 영구 유지: 훈장 도감/장착, 서사시 이력, 도감(discovered), 필살작 기록, 카지노 상한, book_seen, combo_hint_known
	_reset_party()
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
		"version": 5,
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
		# v3.1
		"companions_owned": companions_owned, "party_ids": party_ids,
		"companion_weapons": companion_weapons, "book_seen": book_seen,
		"combo_gauge": combo_gauge, "combo_hint_known": combo_hint_known,
		"thief_away": thief_away, "thief_return_at": thief_return_at,
		"sword_rock": sword_rock, "playtime": playtime, "deposit": deposit,
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
	# v3.1 동료 데이터 (v4 세이브는 members 목록에서 유추 — 마이그레이션)
	var mem: Array = d.get("members", [])
	if d.has("companions_owned"):
		companions_owned = d.get("companions_owned", {"hero": true})
		party_ids = d.get("party_ids", ["hero"])
		companion_weapons = d.get("companion_weapons", {})
		book_seen = d.get("book_seen", {"hero": true})
	else:
		companions_owned = {"hero": true}
		party_ids = []
		companion_weapons = {}
		for ms in mem:
			var c: String = ms["cls"]
			# v3.0 warrior 슬롯은 v3.1 로스터에도 존재 — 그대로 편성
			if COMPANIONS.has(c):
				companions_owned[c] = true
				book_seen[c] = true
				if party_ids.size() < PARTY_MAX:
					party_ids.append(c)
				companion_weapons[c] = int(ms.get("weapon_lv", 0))
		if party_ids.is_empty():
			party_ids = ["hero"]
	combo_gauge = float(d.get("combo_gauge", 0.0))
	combo_hint_known = bool(d.get("combo_hint_known", false))
	thief_away = bool(d.get("thief_away", false))
	thief_return_at = float(d.get("thief_return_at", 0.0))
	sword_rock = int(d.get("sword_rock", 0))
	playtime = float(d.get("playtime", 0.0))
	deposit = int(d.get("deposit", 0))
	holy = holy_max()
	# 편성 재구성 후 저장된 HP/유령 상태 복원
	rebuild_party()
	for ms in mem:
		for i in members.size():
			if members[i]["cls"] == ms["cls"]:
				members[i]["ghost"] = bool(ms.get("ghost", false))
				members[i]["hp"] = clampi(int(ms.get("hp", members[i]["max_hp"])), 0, members[i]["max_hp"])
				if members[i]["ghost"]:
					members[i]["hp"] = 0
				member_changed.emit(i)
				break
