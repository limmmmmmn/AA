extends Node
## BGM 지휘자 (오디오 명세 v1.0 — 임시 절차 합성 칩튠)
## 대원칙: 이 게임의 정체성은 징글이다 — BGM은 팡파레가 겹칠 무대. 전곡 C장조/A단조 계열, 120BPM 그리드.
## 진짜 음원(FamiStudio/커미션)이 오면 _register()에 WAV만 갈아끼우면 된다. AI 음원 아님 — 코드 합성.
## NES 5채널 준수: 펄스×2(사각파) + 삼각파(베이스) + 노이즈(퍼커션). 백그라운드 스레드에서 생성.

const MIX_RATE := 22050

var _tracks: Dictionary = {}          # name → AudioStreamWAV (심리스 루프)
var _a: AudioStreamPlayer             # 크로스페이드 2기 (§4)
var _b: AudioStreamPlayer
var _active_is_a := true
var _current := ""
var _want := ""
var _thread: Thread = null
var _fade_tween: Tween = null

# 상태 (우선순위: 타이틀 > 보스 > 카지노 > 필드)
var _st_title := false
var _st_boss := false
var _st_casino := false
var _st_field := 0
var _st_night := false

func _ready() -> void:
	_a = AudioStreamPlayer.new()
	_a.bus = "BGM"
	_a.volume_db = -80.0
	add_child(_a)
	_b = AudioStreamPlayer.new()
	_b.bus = "BGM"
	_b.volume_db = -80.0
	add_child(_b)
	_thread = Thread.new()
	_thread.start(_generate_all)

func _exit_tree() -> void:
	shutdown_for_test()

func shutdown_for_test() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	_want = ""
	_current = ""
	if _a != null:
		_a.stop()
		_a.stream = null
	if _b != null:
		_b.stop()
		_b.stream = null
	_tracks.clear()

# ---------------------------------------------------------------- 외부 API

func reset() -> void:
	_st_title = false
	_st_boss = false
	_st_casino = false
	_st_night = false

func play_title() -> void:
	_st_title = true
	_resolve()

func stop_title() -> void:
	_st_title = false
	_resolve()

func play_field(f: int) -> void:
	_st_field = f
	_st_boss = false
	_resolve()

func set_night(night: bool) -> void:
	_st_night = night
	_resolve()

func set_boss(on: bool) -> void:
	_st_boss = on
	_resolve(1.0)  # 반 마디 페이드 — 급전환은 저렴해 보인다 (§4)

func set_casino(on: bool) -> void:
	_st_casino = on
	_resolve()

func _resolve(fade := 0.8) -> void:
	var name := ""
	if _st_title:
		name = "m4"
	elif _st_boss:
		name = "m2"
	elif _st_casino:
		name = "m3"
	else:
		match _st_field:
			0: name = "m1_night" if _st_night else "m1"
			1: name = "m1_night" if _st_night else "m1_forest"
			2: name = "m1_cave"
			3: name = "m1_snow"
			4: name = "m2"          # 마왕성 = M2 변주 취급 (§1 선택 조항)
			5: name = "m1_water"
			_: name = "m1"
	_want = name
	_try_play(fade)

func _try_play(fade := 0.8) -> void:
	if _want == _current or _want == "":
		return
	if not _tracks.has(_want):
		return  # 생성 대기 — _register가 다시 부른다
	_current = _want
	var from := _a if _active_is_a else _b
	var to := _b if _active_is_a else _a
	_active_is_a = not _active_is_a
	to.stream = _tracks[_current]
	to.volume_db = -80.0
	to.play()
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(to, "volume_db", -6.0, fade)
	_fade_tween.tween_property(from, "volume_db", -80.0, fade)
	_fade_tween.chain().tween_callback(from.stop)

func _register(name: String, stream: AudioStreamWAV) -> void:
	_tracks[name] = stream
	print("[MUSIC] %s 준비 (%.1fs 루프)" % [name, stream.loop_end / float(MIX_RATE)])
	if _want == name:
		_try_play()

# ---------------------------------------------------------------- 작곡 데이터 (전부 C장조/A단조 — §0)

# 코드 사전 (midi 3화음)
const CH := {
	"C": [48, 52, 55], "G": [43, 47, 50], "F": [41, 45, 48],
	"Am": [45, 48, 52], "Dm": [50, 53, 57], "Em": [52, 55, 59], "E": [40, 44, 47],
}

# M1 메인 테마 — 초원. 16마디, 4/4, 120BPM. 밝고 한가함 (§1 최우선)
const M1_LEAD := [
	67, 64, 67, 72,   74, 72, 74, 76,   67, 64, 67, 72,   74, 72, 69, 67,
	65, 69, 72, 69,   64, 67, 72, 67,   62, 65, 69, 65,   67, 65, 64, 62,
	76, 74, 72, 67,   69, 72, 76, 74,   72, 67, 64, 67,   69, 71, 72, 74,
	76, 79, 76, 72,   74, 76, 74, 71,   72, 76, 67, 69,   67, 67, 72, 72,
]
const M1_CHORDS := ["C", "G", "C", "G", "F", "C", "Dm", "G", "Am", "F", "C", "G", "C", "G", "Am", "C"]

# M2 보스전 — 150BPM, A단조, 긴장 (§1)
const M2_LEAD := [
	69, 69, 72, 69,   76, 74, 72, 71,   69, 69, 72, 74,   76, 76, 77, 76,
	74, 72, 71, 72,   74, 76, 77, 76,   76, 74, 72, 71,   69, 69, 64, 64,
]
const M2_CHORDS := ["Am", "G", "F", "E", "Dm", "F", "E", "Am"]

# M3 카지노 — 스윙, 드퀘 카지노 오마주 톤 (§1)
const M3_LEAD := [
	72, 76, 79, 76,   81, 79, 76, 72,   74, 77, 81, 77,   79, 76, 72, 67,
	72, 76, 79, 76,   81, 84, 81, 79,   77, 74, 71, 74,   72, 72, 76, 72,
]
const M3_CHORDS := ["C", "C", "F", "G", "C", "Am", "G", "C"]

static func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)

# ---------------------------------------------------------------- 합성 (스레드 안전 — 순수 계산)

func _tone(freq: float, dur: float, vol: float, kind: String, decay: float = 3.0, vib: float = 0.0) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var f := freq
		if vib > 0.0:
			f *= 1.0 + vib * sin(TAU * 5.0 * t)  # 수중 비브라토 (M1-c)
		phase += f / MIX_RATE
		var sm := 0.0
		match kind:
			"square":
				sm = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
			"pulse25":  # NES 펄스 듀티 25%
				sm = 1.0 if fmod(phase, 1.0) < 0.25 else -1.0
			"tri":
				sm = absf(fmod(phase, 1.0) * 4.0 - 2.0) - 1.0
			"sine":
				sm = sin(phase * TAU)
			"noise":
				sm = randf() * 2.0 - 1.0
		out[i] = sm * vol * exp(-t * decay)
	return out

func _mix_into(dst: PackedFloat32Array, src: PackedFloat32Array, at_sec: float) -> void:
	var off := int(at_sec * MIX_RATE)
	for i in src.size():
		var j := off + i
		if j >= 0 and j < dst.size():
			dst[j] = clampf(dst[j] + src[i], -1.0, 1.0)

func _to_loop_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = MIX_RATE
	st.stereo = false
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = samples.size()
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	st.data = bytes
	return st

## 트랙 렌더 — lead(펄스1) + 하모니 아르페지오(펄스2) + 베이스(삼각) + 퍼커션(노이즈)
func _render(lead: Array, chords: Array, opts: Dictionary) -> AudioStreamWAV:
	var spb: float = opts.get("spb", 0.5)           # 초/박 (120BPM=0.5)
	var lead_wave: String = opts.get("lead", "square")
	var lead_oct: int = opts.get("lead_oct", 0)     # 반음 시프트
	var arp_rate: float = opts.get("arp", 0.5)      # 하모니 아르페지오 박 단위
	var drums: bool = opts.get("drums", true)
	var vib: float = opts.get("vib", 0.0)
	var echo: bool = opts.get("echo", false)
	var swing: bool = opts.get("swing", false)
	var bars := chords.size()
	var total_sec := bars * 4.0 * spb
	var buf := PackedFloat32Array()
	buf.resize(int(total_sec * MIX_RATE))
	# ① 리드 (펄스 1)
	for i in lead.size():
		var beat := float(i)
		if swing:
			beat = float(i / 2 * 2) + (0.0 if i % 2 == 0 else 0.66)  # 스윙 그리드
		var m: int = lead[i]
		if m <= 0:
			continue
		var dur := spb * (0.66 if swing and i % 2 == 0 else (0.34 if swing else 0.92))
		var tn := _tone(_hz(m + lead_oct), dur, 0.24, lead_wave, 2.2, vib)
		_mix_into(buf, tn, beat * spb)
		if echo:
			_mix_into(buf, _tone(_hz(m + lead_oct), dur, 0.1, lead_wave, 2.2, vib), beat * spb + 0.18)
	# ② 하모니 아르페지오 (펄스 2, 듀티 25%)
	for b in bars:
		var tri: Array = CH[chords[b]]
		var seq := [tri[0] + 12, tri[1] + 12, tri[2] + 12, tri[1] + 12]
		var k := 0
		var t := 0.0
		while t < 4.0 - 0.01:
			var mm: int = seq[k % 4]
			_mix_into(buf, _tone(_hz(mm), spb * arp_rate * 0.9, 0.09, "pulse25", 3.5, vib), (b * 4.0 + t) * spb)
			t += arp_rate
			k += 1
	# ③ 베이스 (삼각파 — 2분음 루트)
	for b in bars:
		var root: int = CH[chords[b]][0]
		_mix_into(buf, _tone(_hz(root), spb * 1.9, 0.30, "tri", 1.2), (b * 4.0) * spb)
		_mix_into(buf, _tone(_hz(root), spb * 1.9, 0.30, "tri", 1.2), (b * 4.0 + 2.0) * spb)
	# ④ 퍼커션 (노이즈 — 킥 1·3박, 햇 2·4박)
	if drums:
		for b in bars:
			for beat_i in 4:
				var at := (b * 4.0 + beat_i) * spb
				if beat_i % 2 == 0:
					_mix_into(buf, _tone(180.0, 0.07, 0.16, "noise", 30.0), at)
				else:
					_mix_into(buf, _tone(2000.0, 0.03, 0.07, "noise", 60.0), at)
	return _to_loop_stream(buf)

func _generate_all() -> void:
	# 우선순위 순서 — M1이 먼저 나와야 게임이 노래한다 (§1)
	var jobs := [
		["m1",        M1_LEAD, M1_CHORDS, {}],
		["m4",        M1_LEAD.slice(0, 32), M1_CHORDS.slice(0, 8), {"spb": 0.8, "lead": "tri", "drums": false, "arp": 1.0}],  # 타이틀/엔딩 — 느린 서정 (§1 M4)
		["m2",        M2_LEAD, M2_CHORDS, {"spb": 0.4, "arp": 0.25, "lead_oct": 0}],  # 보스 150BPM
		["m1_night",  M1_LEAD, M1_CHORDS, {"spb": 0.667, "lead": "tri", "drums": false}],  # 밤 — 템포 -25%, 삼각파 (M1-a)
		["m3",        M3_LEAD, M3_CHORDS, {"swing": true, "arp": 1.0}],  # 카지노 스윙 (M3)
		["m1_forest", M1_LEAD, M1_CHORDS, {"arp": 0.25}],                              # 숲 = 아르페지오 (M1-b)
		["m1_cave",   M1_LEAD, M1_CHORDS, {"spb": 0.667, "lead_oct": -12, "echo": true, "drums": false}],  # 동굴 = 에코+저음
		["m1_snow",   M1_LEAD, M1_CHORDS, {"lead": "sine", "lead_oct": 12, "drums": false, "arp": 1.0}],   # 설원 = 고음 벨
		["m1_water",  M1_LEAD, M1_CHORDS, {"spb": 1.0, "vib": 0.015, "drums": false}],  # 수중 = 반속+비브라토 (M1-c)
	]
	for j in jobs:
		var stream := _render(j[1], j[2], j[3])
		call_deferred("_register", j[0], stream)
