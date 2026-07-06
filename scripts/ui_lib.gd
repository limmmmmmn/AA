class_name UILib
## 드퀘식 UI 헬퍼 + 커서 4종 (커서는 코드 생성 — 나중에 png로 교체하면 됨)
## v3.5 리팩터: 스타일의 원본은 이제 에디터에서 편집하는 리소스/컴포넌트다.
##  - 폰트/버튼/패널 기본값 → res://assets/ui/theme.tres (프로젝트 전역 테마)
##  - 도트 렌더링(AA 끔) → 폰트 임포트 설정 (DungGeunMo.ttf.import)
##  - 이중 테두리 창 → DQPanel 컴포넌트 (scripts/dq_panel.gd, 에디터 배치 가능)
## 아래 헬퍼들은 "코드에서 동적으로 만들 때"의 얇은 편의 함수일 뿐이다.

const FONT := preload("res://assets/fonts/DungGeunMo.ttf")
const FS := 10  # 기본 폰트 크기 — 10px + AA 끔이 1배수 도트와 가장 잘 어울린다

static var FONT_PX: FontFile = FONT  # 하위 호환 별칭 — AA 끔은 임포트 설정이 담당

# v3.7 팔레트 확정 (GDD v3.5 §B — "드퀘의 문법, Titanium Court의 연기")
const COL_WHITE := Color("f4f0e0")             # 크림 — 본문/인셋 보더
const COL_GOLD := Color("f5c542")              # 금색 — 강조
const COL_GRAY := Color("8b8fa3")              # 흐린 청회색 — 비활성/잠금
const COL_BG := Color(0.102, 0.11, 0.173, 0.93)  # #1a1c2c 짙은 남색 (필드가 은은히 비침)
const COL_RED := Color("ef476f")               # 경고/위험
const COL_GREEN := Color("8ac926")             # HP바 라임

## 전투창 계열색 (§B — 아트보드 04의 다채색, 중명도·고채도 팝)
const FAMILY_COLORS := {
	"slime": Color("3fb8af"),   # 슬라임계 청록
	"beast": Color("9b5de5"),   # 야수/박쥐계 퍼플
	"plant": Color("8ac926"),   # 식물계 라임
	"undead": Color("5c6b9e"),  # 언데드계 재색 남보라
	"fire": Color("ff9f2e"),    # 화염/마족계 주황
	"water": Color("4fc4f7"),   # 수중계 하늘
}

static func family_color(fam: String) -> Color:
	return FAMILY_COLORS.get(fam, FAMILY_COLORS["slime"])

## 동료 직업색 (v3.8 §B-1)
const CLASS_COLORS := {
	"hero": "f5c542", "knight": "4fc4f7", "priest": "f7e08a",
	"mage": "9b5de5", "thief": "3fb8af", "monkf": "ff9f2e", "warrior": "8ac926",
}

# ---------------------------------------------------------------- 자동 채색 (v3.8 §B-1 — 수동 태그가 아니라 시스템)

static var _rx_gold: RegEx = null
static var _rx_taken: RegEx = null
static var _name_map: Array = []   # [[이름, 헥사색]] — 긴 이름 먼저

static func _ensure_colorizer() -> void:
	if _rx_gold != null:
		return
	_rx_gold = RegEx.new()
	_rx_gold.compile(r"(\+?\d[\d,]*)\s*G\b")
	_rx_taken = RegEx.new()
	_rx_taken.compile(r"에게 (\d+)!")
	# 이름 사전 — 몬스터(계열색) + 동료(직업색). 긴 이름부터 치환해야 부분 매칭 사고가 없다
	var entries: Array = []
	for md in Game.MONSTER_DEFS:
		entries.append([String(md["name"]), family_color(String(md.get("family", "slime"))).to_html(false)])
	for bn in Game.BOSS_NAMES:
		entries.append([String(bn), FAMILY_COLORS["undead"].to_html(false)])
	entries.append(["황금 슬라임", COL_GOLD.to_html(false)])
	entries.append(["은빛 슬라임", "c7ccd8"])
	for cid in Game.COMPANIONS.keys():
		var col: String = CLASS_COLORS.get(cid, "f4f0e0")
		entries.append([String(Game.COMPANIONS[cid]["name"]), col])
	entries.sort_custom(func(a, b): return String(a[0]).length() > String(b[0]).length())
	_name_map = entries

static func colorize(text: String) -> String:
	# 규칙 기반 자동 채색 — 이미 태그가 든 문장은 연출 우선이라 손대지 않는다
	if text.contains("[color") or text.contains("[slam"):
		return text
	_ensure_colorizer()
	var out := text
	# 파티 피격 숫자 = 빨강
	out = _rx_taken.sub(out, "에게 [color=#ef476f]$1[/color]!", true)
	# 골드 = 금
	out = _rx_gold.sub(out, "[color=#f5c542]$1 G[/color]", true)
	# 이름 채색 (몬스터=계열색, 동료=직업색)
	for e in _name_map:
		var nm: String = e[0]
		if out.contains(nm):
			out = out.replace(nm, "[color=#%s]%s[/color]" % [e[1], nm])
			break  # 한 문장 = 주인공 하나 (남발 방지)
	# 키워드 — 해금·성장은 금, 위험은 빨강, 회복은 초록
	for kw in ["레벨", "훈장", "열쇠", "손에 넣었다", "해방", "합체기"]:
		if out.contains(kw) and not out.contains("[color=#f5c542]" + kw):
			out = out.replace(kw, "[color=#f5c542]%s[/color]" % kw)
			break
	for kw in ["쓰러졌다", "전멸", "도망쳐", "위험"]:
		if out.contains(kw):
			out = out.replace(kw, "[color=#ef476f]%s[/color]" % kw)
			break
	for kw in ["아문다", "회복", "되살아났다"]:
		if out.contains(kw):
			out = out.replace(kw, "[color=#8ac926]%s[/color]" % kw)
			break
	return out

static func make_rich(text: String, size: int = FS) -> RichTextLabel:
	# 텍스트 연기(演技)용 — [shake]/[wave] 내장 + [slam]/[whisper] 커스텀 (v3.7 §E)
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.install_effect(SlamFX.new())
	r.install_effect(WhisperFX.new())
	if size != FS:
		r.add_theme_font_size_override("normal_font_size", size)
	r.text = text
	return r

static func panel_style(border: Color = COL_WHITE, bg: Color = COL_BG) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(3)
	s.set_content_margin_all(6)
	return s

static func make_panel(border: Color = COL_WHITE) -> DQPanel:
	# 동적 생성용 — 에디터에선 DQPanel 노드를 직접 배치하면 된다
	var p := DQPanel.new()
	p.border_color = border
	return p

static func make_label(text: String, size: int = FS, color: Color = COL_WHITE) -> Label:
	var l := Label.new()
	l.text = text
	if size != FS:
		l.add_theme_font_size_override("font_size", size)
	if color != COL_WHITE:
		l.add_theme_color_override("font_color", color)
	return l

static func make_button(text: String, size: int = FS) -> Button:
	# 스타일은 전역 테마(theme.tres)가 입힌다
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if size != FS:
		b.add_theme_font_size_override("font_size", size)
	return b

# ---------------------------------------------------------------- 커서 4종

static var _cursor_tex := {}
static var _cursor_hot := {}
static var _cursor_mode := ""

const _PAL := {
	"K": Color("1a1a24"), "W": Color("f2f2ea"), "B": Color("b07038"),
	"D": Color("6a4420"), "G": Color("ffd54a"), "U": Color("4a90d9"),
	"M": Color("8a5a30"), "P": Color("f2a0b4"), "S": Color("9aa0aa"),
	"R": Color("d24040"),
}

const _CURSOR_BOOT := [
	"................",
	"....KKK.........",
	"...KBBBK........",
	"...KBBBK........",
	"...KBBBK........",
	"...KBBBK........",
	"...KBBBK........",
	"...KBBBBK.......",
	"...KBBBBBKK.....",
	"...KBBBBBBBKK...",
	"...KBBBBBBBBBK..",
	"..KDBBBBBBBBBK..",
	"..KDDDDDDDDDDK..",
	"..KDDDDDDDDDDK..",
	"...KKKKKKKKKK...",
	"................",
]

const _CURSOR_POINT := [
	".....KK.........",
	"....KWWK........",
	"....KWWK........",
	"....KWWK........",
	"....KWWKK.......",
	"....KWWKWKK.....",
	"....KWWKWKWKK...",
	".KK.KWWWWWWWWK..",
	"KWWKKWWWWWWWWK..",
	"KWWWKWWWWWWWWK..",
	".KWWWWWWWWWWWK..",
	"..KWWWWWWWWWWK..",
	"..KWWWWWWWWWK...",
	"...KWWWWWWWWK...",
	"....KKKKKKKK....",
	"................",
]

const _CURSOR_EYE := [
	"................",
	"................",
	"................",
	".....KKKKKK.....",
	"...KKWWWWWWKK...",
	"..KWWWWWWWWWWK..",
	".KWWWKKKKKWWWWK.",
	"KWWWKUUUUUKWWWWK",
	"KWWWKUUKKUKWWWWK",
	".KWWWKUUUKWWWWK.",
	"..KWWWKKKWWWWK..",
	"...KKWWWWWWKK...",
	".....KKKKKK.....",
	"................",
	"................",
	"................",
]

const _CURSOR_HAND := [
	"......G.........",
	".....GGG...G....",
	"......G.........",
	"...KK.KK.KK.....",
	"..KWWKWWKWWKK...",
	"..KWWKWWKWWKWK..",
	"..KWWWWWWWWKWWK.",
	".KKWWWWWWWWWWWK.",
	"KWWKWWWWWWWWWWK.",
	"KWWWWWWWWWWWWWK.",
	".KWWWWWWWWWWWK..",
	"..KWWWWWWWWWWK..",
	"..KWWWWWWWWWK...",
	"...KWWWWWWWK....",
	"....KKKKKKK.....",
	"................",
]

static func _grid_to_tex(rows: Array, scale: int = 2) -> ImageTexture:
	var h := rows.size()
	var w: int = rows[0].length()
	var img := Image.create(w * scale, h * scale, false, Image.FORMAT_RGBA8)
	for y in h:
		var row: String = rows[y]
		for x in w:
			var c := row[x]
			if c == ".":
				continue
			var col: Color = _PAL.get(c, Color.MAGENTA)
			for sy in scale:
				for sx in scale:
					img.set_pixel(x * scale + sx, y * scale + sy, col)
	return ImageTexture.create_from_image(img)

static func _ensure_cursors() -> void:
	if not _cursor_tex.is_empty():
		return
	_cursor_tex["boot"] = _grid_to_tex(_CURSOR_BOOT)
	_cursor_hot["boot"] = Vector2(16, 16)
	_cursor_tex["point"] = _grid_to_tex(_CURSOR_POINT)
	_cursor_hot["point"] = Vector2(12, 2)
	_cursor_tex["eye"] = _grid_to_tex(_CURSOR_EYE)
	_cursor_hot["eye"] = Vector2(16, 16)
	_cursor_tex["hand"] = _grid_to_tex(_CURSOR_HAND)
	_cursor_hot["hand"] = Vector2(16, 18)

static func set_cursor(mode: String) -> void:
	if mode == _cursor_mode:
		return
	_ensure_cursors()
	_cursor_mode = mode
	Input.set_custom_mouse_cursor(_cursor_tex[mode], Input.CURSOR_ARROW, _cursor_hot[mode])

# ---------------------------------------------------------------- 16×16 아이콘 (계획도/재건 패널용)

const ASSIST_GRIDS := {
	"monkey": [
		".KKKKK..",
		"KMMMMMK.",
		"KMKMKMK.",
		"KMMMMMK.",
		".KMMMK.K",
		"..KMK.KK",
		"..K.K...",
		"........",
	],
	"keeper": [
		"KK...KK.",
		"KSK.KSK.",
		".KSSSK..",
		"KSKSKSK.",
		"KSSSSSK.",
		".KSSSK..",
		"..K.K...",
		"........",
	],
	"pig": [
		"........",
		".KKKKK..",
		"KPPPPPK.",
		"KPKPKPK.",
		"KPPRPPK.",
		".KPPPK..",
		"..K.K...",
		"........",
	],
}

const _ICON_GRIDS := {
	"atk": [  # 검
		"......KK", ".....KWK", "....KWK.", "...KWK..", "KK.WK...", "KWKK....",
		"KKWK....", ".KK.....",
	],
	"battle_speed": [  # 시계
		"..KKKK..", ".KWWWWK.", "KWWKWWWK", "KWWKWWWK", "KWWKKWWK", "KWWWWWWK",
		".KWWWWK.", "..KKKK..",
	],
	"max_hp": [  # 하트
		".KK.KK..", "KRRKRRK.", "KRRRRRK.", "KRRRRRK.", ".KRRRK..", "..KRK...",
		"...K....", "........",
	],
	"win_cap": [  # 전투창
		"KKKKKKKK", "KWWWWWWK", "KWKKKKWK", "KWKKKKWK", "KWKKKKWK", "KWWKKWWK",
		"KWWWWWWK", "KKKKKKKK",
	],
	"speed": [  # 부츠
		"..KKK...", "..KBBK..", "..KBBK..", "..KBBK..", "..KBBBK.", "..KBBBBK",
		".KDDDDDK", ".KKKKKKK",
	],
	"shovel": [  # 삽
		"...KK...", "...KK...", "...KK...", "...KK...", "..KWWK..", ".KWWWWK.",
		".KWWWWK.", "..KKKK..",
	],
	"intuition": [  # 눈
		"........", ".KKKKKK.", "KWWWWWWK", "KWKUUKWK", "KWKUUKWK", "KWWWWWWK",
		".KKKKKK.", "........",
	],
	"density": [  # 무리 (점 셋)
		"........", ".KK..KK.", "KUUKKUUK", "KUUKKUUK", ".KK.KKK.", "..KUUK..",
		"..KUUK..", "...KK...",
	],
	"bard": [  # 음표
		"....KK..", "....KWK.", "....KWK.", "....KW..", "....KW..", ".KKKKW..",
		"KWWWKW..", ".KKK....",
	],
	"casino": [  # 7
		"KKKKKKK.", "KGGGGGK.", "KKKKGGK.", "...KGGK.", "..KGGK..", ".KGGK...",
		".KGGK...", ".KKKK...",
	],
	"board": [  # 게시판
		"KKKKKKKK", "KWWKWWKK", "KWWKWWKK", "KKKKKKKK", "..K..K..", "..K..K..",
		"..K..K..", "........",
	],
}

static var _icon_cache := {}

static func icon(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var tex: Texture2D = null
	match id:
		"gold_mult":
			tex = load("res://assets/objects/gold.png")
		"radius":
			tex = load("res://assets/objects/world.png")
		"field1":
			tex = load("res://assets/objects/forest 2.png")
		"field2":
			tex = load("res://assets/objects/cave.png")
		"field3":
			tex = load("res://assets/objects/hill.png")
		"field4":
			tex = load("res://assets/objects/castle.png")
		"smith":
			tex = load("res://assets/objects/whetstone.png")
		"church":
			tex = load("res://assets/objects/shrine.png")
		"inn":
			tex = load("res://assets/objects/inn.png")
		"chest":
			var a := AtlasTexture.new()
			a.atlas = load("res://assets/objects/chest_1.png")
			a.region = Rect2(0, 0, 16, 18)
			tex = a
		"pots", "pot":
			var a2 := AtlasTexture.new()
			a2.atlas = load("res://assets/objects/pot.png")
			a2.region = Rect2(0, 0, 14, 15)
			tex = a2
		"monkey", "keeper", "pig":
			tex = _grid_to_tex(ASSIST_GRIDS[id], 2)
		_:
			if _ICON_GRIDS.has(id):
				tex = _grid_to_tex(_ICON_GRIDS[id], 2)
			else:
				tex = load("res://assets/objects/gold.png")
	_icon_cache[id] = tex
	return tex
