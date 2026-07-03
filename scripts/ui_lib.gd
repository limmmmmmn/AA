class_name UILib
## 드퀘식 UI 헬퍼 + 커서 4종 (전부 코드 생성 — 나중에 png로 교체하면 됨)

const FONT := preload("res://assets/fonts/DungGeunMo.ttf")
const FS := 10  # 기본 폰트 크기 — 10px + AA 끔이 1배수 도트와 가장 잘 어울린다

static var FONT_PX: FontFile = _make_px_font()

static func _make_px_font() -> FontFile:
	var f: FontFile = FONT.duplicate()
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NORMAL
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return f

const COL_WHITE := Color(0.95, 0.95, 0.92)
const COL_GOLD := Color(1.0, 0.83, 0.29)
const COL_GRAY := Color(0.55, 0.55, 0.55)
const COL_BG := Color(0.03, 0.03, 0.08, 0.94)
const COL_RED := Color(0.95, 0.35, 0.3)
const COL_GREEN := Color(0.4, 0.9, 0.5)

static func panel_style(border: Color = COL_WHITE, bg: Color = COL_BG) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(2)
	s.set_content_margin_all(4)
	return s

static func make_panel(border: Color = COL_WHITE) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(border))
	return p

static func make_label(text: String, size: int = FS, color: Color = COL_WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT_PX)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func make_button(text: String, size: int = FS) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", FONT_PX)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", COL_WHITE)
	b.add_theme_color_override("font_hover_color", COL_GOLD)
	b.add_theme_color_override("font_pressed_color", COL_GOLD)
	b.add_theme_color_override("font_disabled_color", COL_GRAY)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.08, 0.14, 0.9)
	normal.set_content_margin_all(4)
	normal.set_corner_radius_all(2)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color(0.2, 0.18, 0.05, 0.95)
	hover.border_color = COL_GOLD
	hover.set_border_width_all(1)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", normal)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
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
