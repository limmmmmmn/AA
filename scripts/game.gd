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

# ---------------------------------------------------------------- 세이브 3슬롯 (v3.3 §C — 드퀘3 문법)
var save_slot := 1
var save_path := "user://appears_save_1.json"
# 타이틀→게임 전환용 일시 플래그 (저장 안 함)
var skip_title := false   # 씬 리로드 후 타이틀 건너뛰고 바로 게임
var need_intro := false   # 새 모험 — 이름 입력+인트로부터
var skip_popin_once := false  # 팝인 1회 생략 (프레스티지 직행 등)

func set_slot(i: int) -> void:
	save_slot = clampi(i, 1, 3)
	save_path = "user://appears_save_%d.json" % save_slot

# ---------------------------------------------------------------- 옵션 (v3.3 §D — 세이브와 분리, 전 슬롯 공통)
var opt := {"bgm": 6, "sfx": 8, "fullscreen": false, "text_speed": 2, "shake": true, "lang": "ko"}
const OPT_PATH := "user://options.cfg"

func load_options() -> void:
	var cf := ConfigFile.new()
	if cf.load(OPT_PATH) != OK:
		return
	for k in opt.keys():
		opt[k] = cf.get_value("opt", k, opt[k])
	save_slot = int(cf.get_value("opt", "last_slot", 1))
	set_slot(save_slot)
	apply_options()

func save_options() -> void:
	var cf := ConfigFile.new()
	for k in opt.keys():
		cf.set_value("opt", k, opt[k])
	cf.set_value("opt", "last_slot", save_slot)
	cf.save(OPT_PATH)

func apply_options() -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.apply_volumes()
	var full: bool = opt["fullscreen"]
	var mode := DisplayServer.window_get_mode()
	if full and mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not full and mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func opt_sfx_db() -> float:
	return -80.0 if int(opt["sfx"]) <= 0 else -8.0 + (int(opt["sfx"]) - 8) * 3.0

func opt_bgm_db() -> float:
	return -80.0 if int(opt["bgm"]) <= 0 else -18.0 + (int(opt["bgm"]) - 6) * 3.0

func opt_type_mult() -> float:
	# 텍스트 속도: 0 순간 / 1 빠름 / 2 보통
	match int(opt["text_speed"]):
		0: return 0.0
		1: return 0.45
	return 1.0

# ---------------------------------------------------------------- 동료 로스터 (v3.1 §B-3 — 정규 7 + 객원 11)
## regular = 시그니처 무기 보유 (대장간 강화 대상). 객원은 공용 티어 (무기 없음).
## passive = 규칙 1개 (수치 나열 금지). 에셋 없는 동료는 임시 틴트 — 유저가 png로 교체 예정.

const COMPANIONS := {
	# v3.9 (GDD v3.7 §B-2): 동료 8인 고정 — "규칙 8개가 규칙 17개보다 각자 진하다"
	# 주민은 시설·부탁 전담 (main.RESIDENTS) — 파티 편성 불가
	"hero":    {"name": "용사",     "regular": true, "passive": "all",   "atk": 4, "hp": 26, "crit": 0.10, "aggro": 1.0, "tex": "res://assets/characters/hero.png",   "frame_h": 26, "tint": Color(1, 1, 1),         "weapon": "용사의 검",
		"pdesc": "만능 — 모든 창에 균등 기여", "hint": "처음부터 함께"},
	"knight":  {"name": "기사",     "regular": true, "passive": "taunt", "atk": 5, "hp": 40, "crit": 0.05, "aggro": 3.0, "tex": "res://assets/characters/knight.png", "frame_h": 25, "tint": Color(1, 1, 1),         "weapon": "기사의 대검",
		"pdesc": "도발 — 피격을 자신에게 집중시킨다", "hint": "골드를 벌면 소문을 듣고 온다"},
	"warrior": {"name": "전사",     "regular": true, "passive": "smite", "atk": 7, "hp": 34, "crit": 0.05, "aggro": 1.5, "tex": "res://assets/characters/knight.png", "frame_h": 25, "tint": Color(1.1, 0.75, 0.65), "weapon": "전사의 도끼",
		"pdesc": "강타 — 단일 대상에 큰 데미지", "hint": "이름난 부자를 찾아온다"},
	"priest":  {"name": "사제",     "regular": true, "passive": "pray",  "atk": 2, "hp": 22, "crit": 0.05, "aggro": 1.0, "tex": "res://assets/characters/priest.png", "frame_h": 24, "tint": Color(1, 1, 1),         "weapon": "사제의 석장",
		"pdesc": "기도 — 턴마다 파티가 최대 HP의 %씩 아문다", "hint": "골드를 벌면 소문을 듣고 온다"},
	"mage":    {"name": "마법사",   "regular": true, "passive": "aoe",   "atk": 5, "hp": 18, "crit": 0.05, "aggro": 1.0, "tex": "res://assets/characters/mage.png",   "frame_h": 25, "tint": Color(1, 1, 1),         "weapon": "마법사의 지팡이",
		"pdesc": "전체 주문 — 창 안의 전원을 공격", "hint": "골드를 벌면 소문을 듣고 온다"},
	"thief":   {"name": "도적",     "regular": true, "passive": "steal", "atk": 5, "hp": 24, "crit": 0.08, "aggro": 0.7, "tex": "res://assets/characters/hero.png",   "frame_h": 26, "tint": Color(0.75, 0.7, 1.1),  "weapon": "도적의 단검",
		"pdesc": "훔치기 — 골드 배율 상승 + 가끔 작은 메달", "hint": "서사시 속에서 나타난다"},
	"monkf":   {"name": "무도가",   "regular": true, "passive": "crit",  "atk": 6, "hp": 28, "crit": 0.20, "aggro": 1.2, "tex": "res://assets/characters/hero.png",   "frame_h": 26, "tint": Color(1.15, 0.95, 0.6), "weapon": "무도가의 권갑",
		"pdesc": "회심 — 파티의 크리티컬 확률 대폭 상승", "hint": "큰 부를 이룬 자를 시험하러 온다"},
	"druid":   {"name": "드루이드", "regular": true, "passive": "charm", "atk": 3, "hp": 24, "crit": 0.05, "aggro": 1.0, "tex": "res://assets/NPCs/village_chief.png", "frame_h": 26, "tint": Color(0.6, 1.1, 0.6), "weapon": "드루이드의 낫",
		"pdesc": "매혹 — 승리 시 가끔 적이 아군이 되어 따라온다", "hint": "서사시 제 1절"},
}
const CLASS_DEFS := COMPANIONS  # 하위 호환 별칭
const PARTY_MAX := 4  # v3.9 §B-2: 파티 4인 편성

## 합체기 3종 (v3.4 §B-14 재편 — 참치=고전 4인 파티의 부조리, 어부 형제는 수중 담당으로 해방)
## needs = 편성 조건 id, ghost = 유령 필요. 부분집합 조합이 있으므로 구체적인 것(참치)부터 판정
## 오의(합체기) 3종 — 장착식 (v3.9 §B-3, FF6 마석 문법). 오의서 획득 → 슬롯 1개 장착. 편성 조건 없음
const COMBO_DEFS := [
	{"id": "tuna", "name": "참치 어택",
		"cutin": "전설의 오의가 해방되었다!\n[slam]…참치다.[/slam]", "tex": "res://assets/combined/tuna.png", "fallback": "res://assets/enemies/slime_fly.png", "tint": Color(0.5, 0.7, 1.3),
		"src": "수중 필드 최심부에 잠들어 있다"},
	{"id": "frog", "name": "개구리의 왈츠",
		"cutin": "저금통이 은혜를 갚는다!\n개구리의 왈츠!", "tex": "res://assets/combined/frog.png", "fallback": "res://assets/enemies/slime.png", "tint": Color(0.5, 1.3, 0.5),
		"src": "개구리 저금통에 정성껏 저금하면…"},
	{"id": "skeleton", "name": "명계의 행진",
		"cutin": "저승의 문이 열린다!\n명계의 행진!!", "tex": "res://assets/combined/skeleton.png", "fallback": "res://assets/enemies/bat.png", "tint": Color(1.2, 1.2, 1.25),
		"src": "동굴의 지배자가 지키고 있다"},
]

var members: Array = []              # 편성된 파티의 런타임 [{cls, name, hp, max_hp, ghost, weapon_lv}]
var companions_owned := {"hero": true}
var party_ids: Array = ["hero"]      # 현재 편성 (여관에서 교체, 최대 5)
var companion_weapons := {}          # id → 무기 레벨 (무기점 플랫, 정규만)
var companion_forge := {}            # id → 벼림 포인트 (대장간 % 배율, v3.4 §B-5)
var new_flags: Array = []            # NEW 뱃지 대기열 — 도감 열람 시 해제 (v3.4 §B-10)

func mark_new(id: String) -> void:
	if not new_flags.has(id):
		new_flags.append(id)

func is_new(id: String) -> bool:
	return new_flags.has(id)

func clear_new(ids: Array) -> void:
	for id in ids:
		new_flags.erase(id)
var book_seen := {"hero": true}      # 동료들의 서 — 회차 넘어 영구 기록
var combo_gauge := 0.0               # 오의 게이지 0..1
var combo_hint_known := false        # 서사시로 획득처 힌트 해금
var arts_owned: Array = []           # 보유한 오의서 (v3.9 §B-3)
var equipped_art := ""               # 장착 중인 오의 (슬롯 1개)

func own_art(id: String) -> bool:
	if arts_owned.has(id):
		return false
	arts_owned.append(id)
	mark_new("art_" + id)
	if equipped_art == "":
		equipped_art = id  # 첫 오의서는 자동 장착 — "장착하면 되는구나"
	return true

func art_def(id: String) -> Dictionary:
	for cd in COMBO_DEFS:
		if cd["id"] == id:
			return cd
	return {}
var charmed: Array = []              # 매혹된 몬스터 defs (다음 전투 1회 참전, 최대 2)
var thief_away := false              # 도적 배신 드라마 (서사시)
var thief_return_at := 0.0
var sword_rock := 0                  # 검이 꽂힌 바위: 0 미스폰 / 1 스폰됨 / 2 뽑음 (=로토의 검)
var playtime := 0.0

# ---------------------------------------------------------------- v3.2
var hero_name := ""                  # 이름 입력 (§B-4) — ""이면 새 게임에서 문자판이 뜬다
var current_field := 0               # main이 갱신 — interactable 검시가 참조 (진주조개 등)
var tactic := ""                     # 전체 작전 명령 (§B-3): "" / attack / life / gold
var tactic_known := false            # 2장 여관에서 해금
var member_tactics := {}             # v3.6: 동료별 작전 오버라이드 (cls → tactic, ""=전체 따름)

func member_tactic_of(cls: String, window_tactic: String) -> String:
	# 개별 지시가 있으면 그것을, 없으면 창의 작전(=전체/임기응변)을 따른다
	var o := String(member_tactics.get(cls, ""))
	return o if o != "" else window_tactic
var roto_shield := false             # 로토 3점 세트 (§B-7): 검=sword_rock, +방패/투구
var roto_helm := false
var lunch_until := 0.0               # 엄마의 도시락 버프 (playtime 기준, §B-6)
var silver_seen := false             # 은빛 슬라임 첫 조우 (밤 예고용)
var titles: Array = []               # 획득한 칭호 id 순서 (§B-8)
var casino_up := {"jackpot": 0, "consol": 0, "hold": 0}  # 카지노 운 트리 (§B-10 — 코인 결제)
# 통계 카운터 — 칭호·도전과제식 훈장·(장래) 스팀 업적이 공유 (§E)
var stats := {
	"pots": 0, "digs": 0, "wells": 0, "flees": 0, "inn_rests": 0, "forges": 0,
	"golden_caught": 0, "silver_caught": 0, "golden_missed": 0, "frog_gold": 0,
	"mimic_wins": 0, "combos": 0, "revives": 0, "requiems": 0, "wipes": 0,
}

func hn() -> String:
	return hero_name if hero_name != "" else "용사"

func add_stat(key: String, v: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + v

# 밤낮 (§B-5) — 숲 개방 후 시작. 낮 150초 + 밤 70초 순환
const DAY_LEN := 150.0
const NIGHT_LEN := 70.0

func clock_on() -> bool:
	return fields_unlocked[1]

func is_night() -> bool:
	if not clock_on():
		return false
	return fmod(playtime, DAY_LEN + NIGHT_LEN) >= DAY_LEN

func night_frac() -> float:
	# 0=완전 낮, 1=완전 밤 (경계 6초 부드럽게)
	if not clock_on():
		return 0.0
	var t := fmod(playtime, DAY_LEN + NIGHT_LEN)
	if t < DAY_LEN:
		return clampf(1.0 - (DAY_LEN - t) / 6.0, 0.0, 1.0) if t > DAY_LEN - 6.0 else 0.0
	var left := (DAY_LEN + NIGHT_LEN) - t
	return clampf(left / 6.0, 0.0, 1.0) if left < 6.0 else 1.0

func roto_count() -> int:
	return int(sword_rock >= 2) + int(roto_shield) + int(roto_helm)

func roto_complete() -> bool:
	return roto_count() >= 3

func lunch_on() -> bool:
	return playtime < lunch_until

# 작전 (§B-3) — 창별 유효 작전은 battle_sim이 roll_tactic()으로 뽑는다
const TACTIC_NAMES := {"attack": "가차없이 공격", "life": "목숨을 소중히", "gold": "골드를 노려라"}

func tactic_power() -> float:
	# 명령 불복종 = 효과 2배, 임기응변 = +50%
	if medal_on("disobedience"):
		return 2.0
	if medal_on("improvise"):
		return 1.5
	return 1.0

func roll_tactic() -> String:
	# 창이 열릴 때 한 번 — 임기응변은 매창 랜덤, 불복종은 가끔 제멋대로
	var t := tactic
	var keys: Array = TACTIC_NAMES.keys()
	if medal_on("improvise"):
		t = keys[randi() % keys.size()]
	elif medal_on("disobedience") and t != "" and randf() < 0.15:
		t = keys[randi() % keys.size()]
	return t

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
	"gaze": 0, "heal_eye": 0, "golden_hands": 0,  # v4.3 golden_hands = 포획 속도·출현 빈도 강화(해금 아님)
	"holy_max": 0, "holy_regen": 0,
	"flee": 0, "telepathy": 0,
	"bank_cap": 0, "bank_rate": 0,
	"lantern": 0, "stack": 0,  # v3.4: 밤 시야 등불 / 겹쳐보기(=소집 토글)
	# v3.9 §B-2: 고아가 된 객원 패시브의 이관
	"requiem": 0, "linger": 0, "meal": 0, "pickaxe": 0, "track": 0,
	# v4.3 장비점 = 초반 강화축 (진짜 아이템 아님, 수치업). def = 신설 방어 스탯
	"gear_atk": 0, "gear_hp": 0, "gear_def": 0, "gear_spd": 0, "gear_gold": 0,
}

# 성수 게이지 (v3.1 §B-7-4 — 수량제 아님, 자동 재생 리소스)
var holy := 12.0

# v4.1 허수아비 = 공격력 버프 (두드리면 일정 시간 전원 공격 ↑)
var scarecrow_until := 0.0        # playtime 기준 만료 시각
const SCARECROW_DUR := 30.0
const SCARECROW_MULT := 1.25
var _building_ack := {}           # v4.1 §마커: 건물별 "확인한 구매 목록" — 방문하면 마커 꺼짐

func scarecrow_on() -> bool:
	return playtime < scarecrow_until

func scarecrow_mult() -> float:
	return SCARECROW_MULT if scarecrow_on() else 1.0

func buff_scarecrow() -> void:
	scarecrow_until = playtime + SCARECROW_DUR

# 은행 (v3.1 §B-8 — 예금은 전멸에도 불가침)
var deposit := 0

# 진행 플래그 — v3.0 한 화면 월드 (+v3.4: 6번째 = 숨겨진 수중)
var fields_unlocked: Array = [true, false, false, false, false, false]
var bosses_defeated: Array = [false, false, false, false, false, false]
var posters_f: Array = [0, 0, 0, 0, 0, 0]  # 필드별 수배서 (마왕성·수중 제외)
var extra_pots := 0
var buildings := {"inn": false, "church": false, "smith": false, "chest": false, "casino": false, "bard": false, "medalking": false, "shop": false, "bank": false, "weaponshop": false, "train": false, "stable": false}  # v4.0: 훈련소/마구간 신설, 게시판은 기물로
var fixtures := {"board": false, "well": false, "frogstatue": false, "lamppost": false, "scarecrow": false}  # v4.0 §B-4: 기물 — 소형 오브젝트, 잔돈 쇼핑의 층
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
var keys := {"thief": false, "magic": false, "sea": false}   # 드퀘 열쇠 (+바다의 노래)
var opened := {"warehouse": false, "redchest": false}  # 잠긴 오브젝트
var signpost_seen := false           # 이정표 등장 여부 (보스 1 처치 후)

# UI 공개 스케줄 — 화면의 모든 UI는 해금 이벤트를 가진다 ("게임이 자라는 게임")
var ui_unlocked := {"desc": false, "gold": false, "party": false, "quest": false}

func built_count() -> int:
	# v4.0 §B-4: 부흥 단계 = 건설된 건물·기물 수 ("건물이 곧 진행바")
	var n := 0
	for k in buildings.keys():
		if buildings[k]:
			n += 1
	for k in fixtures.keys():
		if fixtures[k]:
			n += 1
	return n + extra_pots

func inn_rest_cost() -> int:
	# v4.1: 쉬어가기 유료화 — 잃은 HP 비율만큼 현재 골드의 %를 낸다 (최소 1G, 상한 완만)
	var miss := 1.0 - lowest_hp_ratio()
	if ghost_count() > 0:
		miss = maxf(miss, 0.5)  # 유령이 있으면 최소 절반값
	if miss <= 0.001:
		return 0
	var pct := 0.08 + 0.12 * miss   # 8~20%
	return maxi(1, int(gold * pct))

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

## 훈장 3계층 (v3.2 §C — 순수형 7 / 양날형 9 / 조건형 9 / 유령 계열 5)
const MEDAL_DEFS := {
	# --- 순수형 (무조건 이득 — 비용은 슬롯 희소성) ---
	"sturdy_charm":  {"tier": "순수", "name": "튼튼한 부적",        "desc": "최대 HP +20%",                             "hint": "메달왕이 교환해 준다"},
	"sharp_crest":   {"tier": "순수", "name": "날카로운 문장",      "desc": "파티 공격력 +15%",                         "hint": "메달왕이 교환해 준다"},
	"wind_sign":     {"tier": "순수", "name": "바람의 징표",        "desc": "이동속도 +15%",                            "hint": "초원의 지배자가 지니고 있다"},
	"rich_seal":     {"tier": "순수", "name": "부자의 인장",        "desc": "골드 획득 +10%",                           "hint": "카지노 교환소 한정"},
	"holy_pendant":  {"tier": "순수", "name": "성수병 목걸이",      "desc": "성수 재생 +30%",                           "hint": "신부의 눈길이 벼려지면…"},
	"watch_eye":     {"tier": "순수", "name": "파수꾼의 눈",        "desc": "전투창 상한 +1",                           "hint": "카지노 교환소 한정"},
	"attendance":    {"tier": "순수", "name": "개근상",             "desc": "경험치 획득 +10%",                         "hint": "칭호를 3개 모으면…"},
	# --- 양날형 (이득 + 대가) ---
	"mimic_teeth":   {"tier": "양날", "name": "미믹의 이빨",        "desc": "모든 상자가 미믹, 보상 3배",               "hint": "미믹을 10번 이기면…"},
	"cracked_pot":   {"tier": "양날", "name": "금 간 항아리",       "desc": "항아리 쿨타임 절반, 보상 절반",            "hint": "항아리를 1000개 깨뜨리면…"},
	"coward_flag":   {"tier": "양날", "name": "겁쟁이의 깃발",      "desc": "창 상한 -1, 남은 창 전투 속도 2배",        "hint": "10번 도망치면…"},
	"aqua_regia":    {"tier": "양날", "name": "왕수의 성수",        "desc": "받는 데미지 2배, 골드 2배",                "hint": "메달왕이 교환해 준다"},
	"duel_manner":   {"tier": "양날", "name": "일기토의 예법",      "desc": "모든 조우가 정예 1마리, 보상 집중",        "hint": "동굴의 지배자가 지니고 있다"},
	"late_sleep":    {"tier": "양날", "name": "늦잠",               "desc": "여관에서 유령까지 깨어나지만, 늦잠을 잔다","hint": "여관을 사랑하면…"},
	"anvil_bless":   {"tier": "양날", "name": "모루의 축복",        "desc": "대장간 실패 없음, 대신 +3도 없음",         "hint": "회심의 필살작을 3번 쳐내면…"},
	"metal_crown":   {"tier": "양날", "name": "메탈 슬라임의 왕관", "desc": "황금 슬라임이 자주 오지만 빨리 도망간다",  "hint": "황금 슬라임을 10번 붙잡으면…"},
	"disobedience":  {"tier": "양날", "name": "명령 불복종",        "desc": "작전 효과 2배, 가끔 파티가 제멋대로 군다", "hint": "숲의 지배자가 지니고 있다"},
	# --- 조건형 (상황·편성·환경 발동 — 조합은 발견하는 것) ---
	"rear_pride":    {"tier": "조건", "name": "후미의 긍지",        "desc": "대열 맨 뒤 동료의 패시브 2배",             "hint": "붉은 상자 안에 있는 것 같다"},
	"moonlight":     {"tier": "조건", "name": "달빛 훈장",          "desc": "밤 동안 골드 2배",                         "hint": "은빛으로 반짝이는 것을 붙잡으면…"},
	"fisher_pride":  {"tier": "조건", "name": "어부의 긍지",        "desc": "어부 편성 시 무리 창 보상 +50%",           "hint": "형제가 모이면…"},
	"pack_hunter":   {"tier": "조건", "name": "무리 사냥꾼",        "desc": "창 안 적 4마리 이상이면 데미지 +50%",      "hint": "동굴의 지배자가 지니고 있다"},
	"improvise":     {"tier": "조건", "name": "임기응변",           "desc": "창마다 작전이 랜덤, 전 작전 효과 +50%",    "hint": "카지노 교환소 한정"},
	"vip_card":      {"tier": "조건", "name": "카지노 VIP 카드",    "desc": "슬롯에 몬스터가 뜨면 필드에 진짜 나타난다","hint": "카지노 교환소 한정"},
	"slime_incense": {"tier": "조건", "name": "슬라임 유인향",      "desc": "황금 슬라임이 주시 중인 창에만 나타난다",  "hint": "메달왕이 교환해 준다"},
	"sticky_gloves": {"tier": "조건", "name": "끈끈이 장갑",        "desc": "황금 슬라임 도주까지 +2초",                "hint": "놓쳐 본 자에게 주어진다"},
	"clairvoyance":  {"tier": "조건", "name": "천리안",             "desc": "주시 효과가 옆 창에도 절반 걸린다",        "hint": "수중의 지배자가 지니고 있다"},
	# --- 유령 계열 (조건형 하위군 — 유령 빌드) ---
	"poltergeist":   {"tier": "유령", "name": "폴터가이스트",       "desc": "유령이 지나가는 항아리를 깨뜨린다",        "hint": "스님의 독경이 통하면…"},
	"ghost_warcry":  {"tier": "유령", "name": "원혼의 함성",        "desc": "유령 1명당 파티 공격력 +15%",              "hint": "쓰러져 본 자에게 주어진다"},
	"spirit_party":  {"tier": "유령", "name": "심령 파티",          "desc": "유령도 모든 창에서 절반 위력으로 싸운다",  "hint": "메달왕이 교환해 준다 (고가)"},
	"martyr":        {"tier": "유령", "name": "순교자의 성표",      "desc": "동료가 쓰러지는 순간 전 창에 폭발",        "hint": "빛으로 다섯 번 되살리면…"},
	"loyal_heart":   {"tier": "유령", "name": "돌아온 자의 맹세",   "desc": "도적 편성 시 훔치기 2배",                  "hint": "돌아온 자만이 줄 수 있다"},
}

func medal_slots() -> int:
	return mini(3 + (run_count - 1), 6)  # v3.2: 상한 3→6

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

# family = 전투창 계열색 (v3.7 §B): slime 청록 / beast 퍼플 / plant 라임 / undead 남보라 / fire 주황 / water 하늘
const MONSTER_DEFS := [
	{"id": "slime",  "name": "슬라임",      "hp": 7,  "atk": 2,  "gold": 4,  "exp": 2,  "tex": "res://assets/enemies/slime.png",        "scale": 1.0, "family": "slime"},
	{"id": "bat",    "name": "박쥐",        "hp": 14, "atk": 4,  "gold": 10, "exp": 5,  "tex": "res://assets/enemies/bat.png",          "scale": 1.0, "family": "beast"},
	{"id": "angry",  "name": "성난 슬라임", "hp": 26, "atk": 7,  "gold": 22, "exp": 11, "tex": "res://assets/enemies/slime_chaser.png", "scale": 1.0, "family": "plant"},
	{"id": "cyclops","name": "외눈 괴수",   "hp": 44, "atk": 11, "gold": 45, "exp": 22, "tex": "res://assets/enemies/slime_fly.png",    "scale": 1.0, "family": "fire"},
]
const BOSS_FAMILY := ["slime", "plant", "undead", "undead", "fire", "water"]  # 필드별 지배자 계열
# v3.4 §B-7: 메인 라인 = 초원→숲→동굴→설원→마왕성. 수중(5) = 숨겨진 필드 ("바다의 노래")
const FIELD_NAMES := ["초원", "숲", "동굴", "설원", "마왕성", "수중"]
const BOSS_NAMES := ["초원의 지배자", "숲의 지배자", "동굴의 지배자", "복수(複數)의 감시자", "마왕", "수중의 지배자"]  # 설원 = 눈알 보스 (v3.7 §G)
const FIELD_TINTS := [
	Color(1, 1, 1),                # 초원
	Color(0.8, 1.05, 0.75),       # 숲
	Color(0.85, 0.75, 1.0),       # 동굴
	Color(0.78, 0.9, 1.15),       # 설원
	Color(0.72, 0.5, 0.85),       # 마왕성
	Color(0.55, 0.8, 1.25),       # 수중 — 물빛 (숨겨진 필드)
]
const FIELD_PREFIX := ["", "숲 ", "동굴 ", "얼음 ", "마 ", "물 "]
const HIDDEN_FIELD := 5

func field_tier(f: int) -> int:
	# 수중은 T3.5~T4 동급 (v3.4 밸런스 노트) — 메인 라인은 index+1
	return 4 if f == HIDDEN_FIELD else f + 1

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
	load_options()
	_migrate_legacy_save()
	_reset_party()
	load_game()

func _migrate_legacy_save() -> void:
	# v3.2 이전 단일 세이브 → 슬롯 1로 이사 (v3.3)
	if FileAccess.file_exists("user://appears_save.json") and not FileAccess.file_exists("user://appears_save_1.json"):
		var f := FileAccess.open("user://appears_save.json", FileAccess.READ)
		if f:
			var txt := f.get_as_text()
			f.close()
			var g := FileAccess.open("user://appears_save_1.json", FileAccess.WRITE)
			if g:
				g.store_string(txt)
				g.close()

func slot_meta(i: int) -> Dictionary:
	# 슬롯 목록 표시용 경량 메타 (v3.3 §C)
	var p := "user://appears_save_%d.json" % i
	if not FileAccess.file_exists(p):
		return {"exists": false}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {"exists": false}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		return {"exists": false}
	var d: Dictionary = parsed
	var joins := 0
	var res: Dictionary = d.get("residents", {})
	for k in res.keys():
		if res[k]:
			joins += 1
	var comp: Dictionary = d.get("companions_owned", {})
	for k in comp.keys():
		if comp[k]:
			joins += 1
	joins = maxi(0, joins - 1)  # 용사 제외
	var stage := 0
	for t in [3, 7, 10, 15]:
		if joins >= t:
			stage += 1
	return {
		"exists": true,
		"name": String(d.get("hero_name", "용사")),
		"level": int(d.get("level", 1)),
		"playtime": float(d.get("playtime", 0.0)),
		"revival": stage,
		"run": int(d.get("run_count", 1)),
	}

func new_game(slot: int) -> void:
	# "처음부터 시작한다" — 슬롯 하나를 완전한 백지로 (v3.3)
	set_slot(slot)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	reset_all()
	save_options()  # last_slot 기억

func continue_game(slot: int) -> void:
	set_slot(slot)
	reset_all()
	load_game()
	save_options()

func reset_all() -> void:
	# 새 모험의 백지 상태 — 모든 것이 기본값으로 (2주차와 달리 영구물도 지운다)
	gold = 0
	total_earned = 0
	level = 1
	exp = 0
	run_count = 1
	kills = 0
	coins = 0
	holy = 12.0
	deposit = 0
	for k in up.keys():
		up[k] = 0
	for k in assistants.keys():
		assistants[k] = 0
	fields_unlocked = [true, false, false, false, false, false]
	bosses_defeated = [false, false, false, false, false, false]
	posters_f = [0, 0, 0, 0, 0, 0]
	extra_pots = 0
	buildings = {"inn": false, "church": false, "smith": false, "chest": false, "casino": false, "bard": false, "medalking": false, "shop": false, "bank": false, "weaponshop": false, "train": false, "stable": false}
	fixtures = {"board": false, "well": false, "frogstatue": false, "lamppost": false, "scarecrow": false}
	recruits_spawned = {"knight": false, "mage": false, "priest": false, "warrior": false, "monkf": false}
	discovered = {}
	golden_first_done = false
	golden_info = false
	ending_seen = false
	residents = {}
	kill_counts = {}
	medals_small = 0
	medals_spent = 0
	keys = {"thief": false, "magic": false, "sea": false}
	opened = {"warehouse": false, "redchest": false}
	signpost_seen = false
	ui_unlocked = {"desc": false, "gold": false, "party": false, "quest": false}
	epic_verses = 0
	smith_perfects = 0
	casino_wincap = 0
	medals_owned = []
	medals_equipped = []
	companions_owned = {"hero": true}
	party_ids = ["hero"]
	companion_weapons = {}
	companion_forge = {}
	new_flags = []
	book_seen = {"hero": true}
	combo_gauge = 0.0
	combo_hint_known = false
	arts_owned = []
	equipped_art = ""
	charmed = []
	thief_away = false
	thief_return_at = 0.0
	sword_rock = 0
	playtime = 0.0
	hero_name = ""
	current_field = 0
	tactic = ""
	member_tactics = {}
	tactic_known = false
	roto_shield = false
	roto_helm = false
	lunch_until = 0.0
	silver_seen = false
	titles = []
	casino_up = {"jackpot": 0, "consol": 0, "hold": 0}
	for k in stats.keys():
		stats[k] = 0
	_reset_party()

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

func passive_scale(pid: String) -> float:
	# 패시브 보너스 배율: 0=꺼짐 / 1=기본 / 2=후미의 긍지 (대열 맨 뒤, v3.2)
	# 어부 계열은 수중에서 각성 ×2 (v3.2 §B-1)
	if not passive_on(pid):
		return 0.0
	var s := 1.0
	if medal_on("rear_pride"):
		for i in range(members.size() - 1, -1, -1):
			if not members[i]["ghost"]:
				if COMPANIONS[members[i]["cls"]]["passive"] == pid:
					s *= 2.0
				break
	return s

func companion_count() -> int:
	var n := 0
	for k in companions_owned.keys():
		if companions_owned[k]:
			n += 1
	return n

# ---------------------------------------------------------------- 스탯 공식

func member_atk_flat(idx: int) -> int:
	# 플랫 = 무기점의 영역 (v3.4 §B-5 — 주 성장축)
	var m: Dictionary = members[idx]
	var base: int = COMPANIONS[m["cls"]]["atk"]
	var flat: int = base + int(m["weapon_lv"]) * 2 + int(level / 2.0) + up["gear_atk"] * 2  # v4.3 장비:무기
	# 로토의 검 고유 보너스 (v3.8 §B-6 — 스토리 성장은 교체 이벤트로)
	if m["cls"] == "hero" and sword_rock >= 2:
		flat += 6
	return flat

func forge_mult(cls: String) -> float:
	# 벼림 보정 = 대장간의 영역 (% 배율 — 플랫이 클수록 가치 상승)
	return 1.0 + 0.03 * int(companion_forge.get(cls, 0))

func member_atk(idx: int) -> int:
	var m: Dictionary = members[idx]
	var atk := float(member_atk_flat(idx)) * forge_mult(m["cls"])
	if medal_on("ghost_warcry"):
		atk *= 1.0 + 0.15 * ghost_count()
	if medal_on("sharp_crest"):
		atk *= 1.15
	if lunch_on():
		atk *= 1.1  # 엄마의 도시락
	if scarecrow_on():
		atk *= SCARECROW_MULT  # v4.1: 허수아비 단련
	return int(atk)

func member_def(idx: int) -> int:
	# v4.3 방어력 = 장비(방어구) + 레벨 + 기사의 도발 계열 살짝. 설원 보스를 정당한 성장으로 넘게 한다
	var d: int = up["gear_def"] * 4 + int(level / 2.0)
	if members[idx]["cls"] == "knight":
		d += 4  # 기사는 태생이 단단하다
	if medal_on("sturdy_charm"):
		d += 6
	return d

func mitigate(idx: int, dmg: int) -> int:
	# 받는 피해 경감: dmg * K/(K+def). def=30 → 절반, def=90 → ¼. 성장할수록 계속 유효
	var d := float(member_def(idx))
	return maxi(1, int(round(float(dmg) * 40.0 / (40.0 + d))))

func member_crit(idx: int) -> float:
	var c: float = COMPANIONS[members[idx]["cls"]]["crit"]
	c += 0.10 * passive_scale("crit")  # 무도가의 회심 — 파티 전체
	return c

func member_max_hp(idx: int) -> int:
	var m: Dictionary = members[idx]
	var base: int = COMPANIONS[m["cls"]]["hp"]
	# 침구 개선 = %화 (v3.1 §B-6 — 덧셈 방어는 곱셈 공격을 못 따라간다)
	var mx: float = (base + (level - 1) * 4) * (1.0 + 0.08 * up["max_hp"] + 0.10 * up["gear_hp"])  # v4.3 장비:방어구
	if medal_on("sturdy_charm"):
		mx *= 1.2
	return int(mx)

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
	r *= 1.0 + 0.5 * up["meal"]  # 요리사의 한 끼 (여관 업글, v3.9)
	if medal_on("holy_pendant"):
		r *= 1.3
	return r

func holy_heal_pct() -> float:
	return 0.02 + 0.005 * up["heal_eye"]  # 치유의 눈길 (초당 최대 HP %)

func active_combo() -> Dictionary:
	# v3.9 §B-3: 장착식 — 편성 조건 없음. 장착한 오의가 곧 합체기
	if equipped_art == "":
		return {}
	return art_def(equipped_art)

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
	# 승리할 때마다 게이지가 차오른다 (오의 장착 중일 때만)
	if equipped_art == "":
		combo_gauge = 0.0
		return
	combo_gauge = minf(1.0, combo_gauge + 0.08)

func max_windows() -> int:
	# v3.3 §A 철칙 3: 회차 보너스는 소폭 시작 부스트까지만 (+1 캡)
	var n: int = 1 + up["win_cap"] + mini(run_count - 1, 1) + casino_wincap
	if medal_on("watch_eye"):
		n += 1
	if medal_on("coward_flag"):
		n -= 1
	return clampi(n, 1, MAX_WINDOWS_HARD)

func max_enemies_per_window() -> int:
	# v3.4 §B-3: 창내 최대 적 수 = 편성 인원 수 ("우리가 커지면 싸움도 커진다")
	# 무리 유인 업글은 +1 보정으로만 존치
	return mini(party_ids.size() + up["density"], 5)

func mounted() -> bool:
	# 탈것 (v3.2 §B-2) — 이속 트리의 끝은 수치가 아니라 존재
	return up["speed"] >= 9

func move_speed() -> float:
	var v := 65.0 * pow(1.08, up["speed"]) * (1.0 + 0.05 * int(up["gear_spd"]))  # v4.3 장비:신발
	if mounted():
		v *= 1.25  # 탈것 보너스
	if medal_on("wind_sign"):
		v *= 1.15
	return v

func turn_interval() -> float:
	var t := 1.1 * pow(0.93, up["battle_speed"])
	if medal_on("coward_flag"):
		t *= 0.5
	return t

func gold_multiplier() -> float:
	# v3.3 §A: 회차 배율 스케일링 금지 — 프레스티지 수학이 침투하면 2주차가 의무가 된다
	var g := pow(1.15, up["gold_mult"]) * (1.0 + 0.08 * int(up["gear_gold"]))  # v4.3 장비:벨트
	if medal_on("aqua_regia"):
		g *= 2.0
	var steal_s := passive_scale("steal")
	if steal_s > 0.0:
		g *= 1.0 + (0.3 if medal_on("loyal_heart") else 0.15) * steal_s  # 도적의 훔치기
	if medal_on("rich_seal"):
		g *= 1.1
	if medal_on("moonlight") and is_night():
		g *= 2.0  # 달빛 훈장 — 밤을 기다릴 이유
	return g

func price(c: int) -> int:
	return c  # v3.9: 할인 패시브 폐지 (상인은 주민)

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
	if medal_on("attendance"):
		v = int(v * 1.1)  # 개근상
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

func forge_cost(idx: int) -> int:
	# 대장간 벼림 — 선택적 손맛 보너스라 무기점보다 싸게
	return price(int(18 * pow(1.6, int(companion_forge.get(members[idx]["cls"], 0)))))

func lantern_radius() -> float:
	# 밤 시야 반경 (v3.4 §B-4). 최종 단계 = 대열 전체가 빛의 뱀
	return 60.0 + 34.0 * up["lantern"]

func set_weapon_lv(cls: String, lv: int) -> void:
	# 무기 레벨은 편성 재구성에도 살아남도록 companion_weapons에 기록
	companion_weapons[cls] = lv
	for m in members:
		if m["cls"] == cls:
			m["weapon_lv"] = lv
	party_changed.emit()

# 무기 명명 (v3.2 §B-11 — 환상수호전 오마주. 진화 마디 +5/+10마다 새 이름, 골드 전용)
const WEAPON_NAMES := {
	"knight": ["물려받은 대검", "성채의 벽", "불락의 맹세"],
	"warrior": ["이 빠진 도끼", "산울림", "일격필살"],
	"priest": ["참나무 지팡이", "기도하는 손", "새벽의 축도"],
	"mage": ["낡은 마도서", "별부스러기", "소용돌이치는 밤"],
	"thief": ["녹슨 단검", "달그림자", "밤을 가르는 자"],
	"monkf": ["맨주먹", "감아쥔 붕대", "회심의 주먹"],
	"druid": ["풋낫", "숲의 휘광", "만물의 노래"],
}

func weapon_name(idx: int) -> String:
	var m: Dictionary = members[idx]
	var lv: int = m["weapon_lv"]
	if m["cls"] == "hero":
		# v3.8 §B-6: 용사도 무기점·대장간 정식 편입. 로토의 검 = 무기 "교체" (강화 레벨 승계)
		var base_h := "아빠의 목검"
		if sword_rock >= 2:
			base_h = "전설의 검·진" if (roto_complete() and epic_complete()) else "로토의 검"
		return base_h + (" +%d" % lv if lv > 0 else "")
	if WEAPON_NAMES.has(m["cls"]):
		var stages: Array = WEAPON_NAMES[m["cls"]]
		var base2: String = stages[2 if lv >= 10 else (1 if lv >= 5 else 0)]
		return base2 + (" +%d" % lv if lv > 0 else "")
	var base: String = COMPANIONS[m["cls"]].get("weapon", "여행자의 지팡이")
	if lv >= 10:
		base = "빛나는 " + base
	elif lv >= 5:
		base = "강철 " + base
	return base + (" +%d" % lv if lv > 0 else "")

# ---------------------------------------------------------------- 칭호 (v3.2 §B-8 — 플레이 습관의 거울)

const TITLE_DEFS := [
	{"id": "pot_king",     "name": "항아리 파괴왕",     "stat": "pots",          "n": 100},
	{"id": "late_riser",   "name": "늦잠꾸러기",        "stat": "inn_rests",     "n": 10},
	{"id": "tuna_witness", "name": "참치를 목격한 자",  "stat": "combos",        "n": 1},
	{"id": "runaway",      "name": "삼십육계의 달인",   "stat": "flees",         "n": 10},
	{"id": "gold_hand",    "name": "황금손",            "stat": "golden_caught", "n": 5},
	{"id": "mole",         "name": "두더지",            "stat": "digs",          "n": 50},
	{"id": "night_walker", "name": "밤을 걷는 자",      "stat": "silver_caught", "n": 1},
	{"id": "well_gazer",   "name": "우물 들여다보는 자","stat": "wells",         "n": 30},
]

func current_title() -> String:
	if titles.is_empty():
		return ""
	for t in TITLE_DEFS:
		if t["id"] == titles[titles.size() - 1]:
			return t["name"]
	return ""

func check_titles() -> Dictionary:
	# 새로 달성한 칭호 하나를 반환 (한 번에 하나 — 의식은 겹치지 않는다)
	for t in TITLE_DEFS:
		if titles.has(t["id"]):
			continue
		if int(stats.get(t["stat"], 0)) >= int(t["n"]):
			titles.append(t["id"])
			return t
	return {}

# ---------------------------------------------------------------- 필드/회차

func unlock_field(i: int) -> void:
	fields_unlocked[i] = true
	chapter_changed.emit(progress_tier())

func do_prestige() -> void:
	# v3.3 §A: 프레스티지가 아니라 뉴게임+ ("2주차 모험" — 크로노 트리거 문법)
	# 배율 없음. 보상 = 소폭 시작 부스트(초기 골드·시작 동료·훈장 슬롯 +1) + 회차 콘텐츠 개봉
	run_count += 1
	gold = 0
	total_earned = 0
	level = 1
	exp = 0
	kills = 0
	coins = 0
	fields_unlocked = [true, false, false, false, false, false]
	bosses_defeated = [false, false, false, false, false, false]
	posters_f = [0, 0, 0, 0, 0, 0]
	extra_pots = 0
	for k in up.keys():
		up[k] = 0
	for k in assistants.keys():
		assistants[k] = 0
	buildings = {"inn": false, "church": false, "smith": false, "chest": false, "casino": false, "bard": false, "medalking": false, "shop": false, "bank": false, "weaponshop": false, "train": false, "stable": false}
	fixtures = {"board": false, "well": false, "frogstatue": false, "lamppost": false, "scarecrow": false}
	recruits_spawned = {"knight": false, "mage": false, "priest": false, "warrior": false, "monkf": false}
	residents = {}
	kill_counts = {}
	medals_small = 0
	medals_spent = 0
	keys = {"thief": false, "magic": false, "sea": false}
	opened = {"warehouse": false, "redchest": false}
	signpost_seen = false
	golden_first_done = false
	golden_info = false
	ending_seen = false
	# v3.1 리셋 (book_seen은 영구 — 동료들의 서는 회차를 기억한다)
	combo_gauge = 0.0
	arts_owned = []
	equipped_art = ""
	charmed = []
	thief_away = false
	thief_return_at = 0.0
	sword_rock = 0
	holy = holy_max()
	deposit = 0
	companion_forge = {}
	new_flags = []
	# v3.2 리셋 — 로토/작전/카지노 운. 이름·칭호·통계는 영구 (도전과제식)
	roto_shield = false
	roto_helm = false
	tactic = ""
	member_tactics = {}
	lunch_until = 0.0
	silver_seen = false
	casino_up = {"jackpot": 0, "consol": 0, "hold": 0}
	# 영구 유지: 훈장 도감/장착, 서사시 이력, 도감(discovered), 필살작 기록, 카지노 상한, book_seen, combo_hint_known, hero_name, titles, stats, tactic_known
	_reset_party()
	# 2주차 시작 부스트 — 기사가 배웅 나와 있고, 엄마가 여비를 찔러준다
	gold = 500
	own_companion("knight")
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
		"version": 6,
		"gold": gold, "total_earned": total_earned,
		"level": level, "exp": exp, "run_count": run_count, "kills": kills,
		"up": up,
		"fields_unlocked": fields_unlocked, "bosses_defeated": bosses_defeated,
		"posters_f": posters_f, "extra_pots": extra_pots,
		"buildings": buildings, "fixtures": fixtures, "recruits_spawned": recruits_spawned,
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
		"companion_weapons": companion_weapons, "companion_forge": companion_forge,
		"new_flags": new_flags, "book_seen": book_seen,
		"arts_owned": arts_owned, "equipped_art": equipped_art,
		"combo_gauge": combo_gauge, "combo_hint_known": combo_hint_known,
		"thief_away": thief_away, "thief_return_at": thief_return_at,
		"sword_rock": sword_rock, "playtime": playtime, "deposit": deposit,
		# v3.2
		"hero_name": hero_name, "tactic": tactic, "tactic_known": tactic_known,
		"member_tactics": member_tactics,
		"roto_shield": roto_shield, "roto_helm": roto_helm, "silver_seen": silver_seen,
		"titles": titles, "casino_up": casino_up, "stats": stats,
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
	for i in 6:  # v3.4: 6번째 = 숨겨진 수중 (구 세이브는 5개 — 기본값 유지)
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
	var fx: Dictionary = d.get("fixtures", {})
	for k in fixtures.keys():
		fixtures[k] = bool(fx.get(k, fixtures[k]))
	# v4.0 마이그레이션: 게시판은 기물이 됐다 / 은행 세이브엔 개구리 석상이 딸려 있었다
	if bool(b.get("board", false)):
		fixtures["board"] = true
	if not fx.has("frogstatue") and buildings.get("bank", false):
		fixtures["frogstatue"] = true
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
		# v3.9 마이그레이션: 로스터 축소 — 객원은 소유/편성에서 걷어낸다
		for k in companions_owned.keys().duplicate():
			if not COMPANIONS.has(k):
				companions_owned.erase(k)
		var pf2: Array = []
		for pid2 in party_ids:
			if COMPANIONS.has(pid2) and pf2.size() < PARTY_MAX:
				pf2.append(pid2)
		party_ids = pf2 if not pf2.is_empty() else ["hero"]
		companion_weapons = d.get("companion_weapons", {})
		companion_forge = d.get("companion_forge", {})
		new_flags = d.get("new_flags", [])
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
	arts_owned = d.get("arts_owned", [])
	equipped_art = String(d.get("equipped_art", ""))
	if equipped_art != "" and not arts_owned.has(equipped_art):
		equipped_art = ""

	thief_away = bool(d.get("thief_away", false))
	thief_return_at = float(d.get("thief_return_at", 0.0))
	sword_rock = int(d.get("sword_rock", 0))
	playtime = float(d.get("playtime", 0.0))
	deposit = int(d.get("deposit", 0))
	holy = holy_max()
	# v3.2 (v5 이하 세이브는 기본값 + 이름은 기본명으로 — 이미 논 유저에겐 안 묻는다)
	hero_name = String(d.get("hero_name", "용사" if int(d.get("version", 1)) < 6 else ""))
	tactic = String(d.get("tactic", ""))
	tactic_known = bool(d.get("tactic_known", false))
	member_tactics = d.get("member_tactics", {})
	roto_shield = bool(d.get("roto_shield", false))
	roto_helm = bool(d.get("roto_helm", false))
	silver_seen = bool(d.get("silver_seen", false))
	titles = d.get("titles", [])
	var cu: Dictionary = d.get("casino_up", {})
	for k in casino_up.keys():
		casino_up[k] = int(cu.get(k, 0))
	var st: Dictionary = d.get("stats", {})
	for k in stats.keys():
		stats[k] = int(st.get(k, 0))
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
