extends Node
## 절차 합성 효과음 (임시 사운드 — 나중에 진짜 사운드 파일로 교체 가능)
## Sfx.play("coin") 식으로 사용. 창별 팡파레가 어긋나 겹치는 게 시그니처라 폴리포니 풀 사용.

const MIX_RATE := 22050
const POOL_SIZE := 16

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_idx := 0
var _gaze_player: AudioStreamPlayer      # 주시 루프 (전용 채널)
var _gaze_count := 0                     # 여러 창 겹침 대비 카운트

## 징글 = BGM보다 +2~3dB (오디오 명세 §0). 버스: Master ─ BGM/Jingle/SFX/UI (§4)
const JINGLE_NAMES := ["fanfare", "fanfare_v2", "fanfare_v3", "fanfare_v4", "fanfare_big",
	"levelup", "golden", "golden_silver", "capture", "combo", "revive", "heal", "wipe",
	"chest", "palette", "toast1", "toast2", "toast3", "pop", "warp", "boss"]
const UI_NAMES := ["blip", "click", "buy", "deny", "bump", "bank", "coin"]

func _ready() -> void:
	_make_buses()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	# 팡파레 전용 풀 4기 — 폴리포니 상한 = 시그니처 사운드의 수학 (§3)
	for i in 4:
		var fp := AudioStreamPlayer.new()
		fp.volume_db = -6.0
		fp.bus = "Jingle"
		add_child(fp)
		_fanfare_pool.append(fp)
	_gaze_player = AudioStreamPlayer.new()
	_gaze_player.volume_db = -26.0
	_gaze_player.bus = "SFX"
	add_child(_gaze_player)
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.volume_db = -6.0
	_bgm_player.bus = "BGM"
	add_child(_bgm_player)
	_build_all()
	apply_volumes()

var _bgm_player: AudioStreamPlayer
var _fanfare_pool: Array[AudioStreamPlayer] = []
var _fanfare_idx := 0

func _make_buses() -> void:
	for bus_name in ["BGM", "Jingle", "SFX", "UI"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")

func apply_volumes() -> void:
	# 옵션 슬라이더 2개 → BGM / (Jingle+SFX+UI) 매핑 (§4)
	var g := get_node_or_null("/root/Game")
	if g == null:
		return
	var bgm_db: float = g.opt_bgm_db()
	var sfx_db: float = g.opt_sfx_db()
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("BGM"), bgm_db + 6.0)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("BGM"), bgm_db <= -79.0)
	for bus_name in ["Jingle", "SFX", "UI"]:
		var bi := AudioServer.get_bus_index(bus_name)
		AudioServer.set_bus_volume_db(bi, sfx_db + 8.0 + (2.0 if bus_name == "Jingle" else 0.0))
		AudioServer.set_bus_mute(bi, sfx_db <= -79.0)

func shutdown_for_test() -> void:
	for player in _pool + _fanfare_pool + [_gaze_player, _bgm_player]:
		if player != null:
			player.stop()
			player.stream = null
	_streams.clear()

func gaze_loop(on: bool) -> void:
	# 주시 중 반짝이는 루프음 — 켜진 창이 하나라도 있으면 재생 (v3.1 §B-7-1)
	_gaze_count = maxi(0, _gaze_count + (1 if on else -1))
	if _gaze_count > 0 and not _gaze_player.playing:
		_gaze_player.stream = _streams.get("gaze_loop")
		_gaze_player.play()
	elif _gaze_count == 0 and _gaze_player.playing:
		_gaze_player.stop()

func play(name: String, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	# J1 승리 팡파레 — 미세 변주 4벌 랜덤 + 전용 풀 4기(초과분은 자연 교체) (§3)
	if name == "fanfare":
		name = ["fanfare", "fanfare_v2", "fanfare_v3", "fanfare_v4"][randi() % 4]
		if not _streams.has(name):
			name = "fanfare"
		var fp := _fanfare_pool[_fanfare_idx]
		_fanfare_idx = (_fanfare_idx + 1) % _fanfare_pool.size()
		fp.stop()
		fp.stream = _streams[name]
		fp.pitch_scale = pitch
		fp.play()
		return
	if not _streams.has(name):
		return
	var p := _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % POOL_SIZE
	p.stop()
	p.stream = _streams[name]
	p.pitch_scale = pitch
	p.volume_db = -8.0 + vol_db
	p.bus = "Jingle" if name in JINGLE_NAMES else ("UI" if name in UI_NAMES else "SFX")
	p.play()

func title_bgm(on: bool) -> void:
	# 하위 호환 — 이제 Music 오토로드가 BGM을 지휘한다 (오디오 명세 §1)
	var mus := get_node_or_null("/root/Music")
	if mus != null:
		if on:
			mus.play_title()
		else:
			mus.stop_title()

func refresh_bgm_volume() -> void:
	apply_volumes()

# ---------------------------------------------------------------- synthesis

func _tone(freq: float, dur: float, vol: float = 0.5, kind: String = "square", slide: float = 0.0, decay: float = -1.0) -> PackedFloat32Array:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	if decay < 0.0:
		decay = 6.0 / maxf(dur, 0.01)
	for i in n:
		var t := float(i) / MIX_RATE
		var f := freq + slide * t
		phase += f / MIX_RATE
		var s := 0.0
		match kind:
			"square":
				s = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
			"saw":
				s = fmod(phase, 1.0) * 2.0 - 1.0
			"sine":
				s = sin(phase * TAU)
			"tri":
				s = absf(fmod(phase, 1.0) * 4.0 - 2.0) - 1.0
			"noise":
				s = randf() * 2.0 - 1.0
		out[i] = s * vol * exp(-t * decay)
	return out

func _silence(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(dur * MIX_RATE))
	return out

func _concat(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in parts:
		out.append_array(p)
	return out

func _mix(a: PackedFloat32Array, b: PackedFloat32Array, offset_sec: float = 0.0) -> PackedFloat32Array:
	var off := int(offset_sec * MIX_RATE)
	var n: int = maxi(a.size(), off + b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in a.size():
		out[i] = a[i]
	for i in b.size():
		out[off + i] = clampf(out[off + i] + b[i], -1.0, 1.0)
	return out

func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = MIX_RATE
	s.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	s.data = bytes
	return s

func _melody(notes: Array, kind: String = "square", vol: float = 0.45) -> PackedFloat32Array:
	# notes: [[freq, dur], ...]  freq 0 = 쉼표
	var parts: Array = []
	for nt in notes:
		if nt[0] <= 0.0:
			parts.append(_silence(nt[1]))
		else:
			parts.append(_tone(nt[0], nt[1], vol, kind, 0.0, 7.0))
	return _concat(parts)

# ---------------------------------------------------------------- sound bank

func _build_all() -> void:
	# 범프 (툭)
	_streams["bump"] = _to_stream(_tone(140.0, 0.07, 0.4, "square"))
	# 항아리 (쨍그랑)
	_streams["pot"] = _to_stream(_mix(_tone(0.0, 0.16, 0.0), _mix(
		_tone(2400.0, 0.12, 0.30, "noise"),
		_tone(1046.0, 0.10, 0.25, "square", -3000.0), 0.02)))
	# 코인 (삐링↑)
	_streams["coin"] = _to_stream(_concat([_tone(988.0, 0.06, 0.35, "square"), _tone(1319.0, 0.14, 0.35, "square")]))
	# 큰 골드 (분수)
	_streams["gold_big"] = _to_stream(_melody([[784.0, 0.07], [988.0, 0.07], [1175.0, 0.07], [1568.0, 0.2]], "square", 0.4))
	# 타격
	_streams["hit"] = _to_stream(_mix(_tone(200.0, 0.08, 0.35, "noise"), _tone(160.0, 0.08, 0.3, "square", -400.0)))
	# 회심의 일격
	_streams["crit"] = _to_stream(_mix(_tone(300.0, 0.15, 0.4, "noise"), _tone(880.0, 0.12, 0.35, "saw", -2000.0)))
	# 아군 피격 (퍽)
	_streams["hurt"] = _to_stream(_tone(110.0, 0.12, 0.45, "square", -200.0))
	# J1 승리 팡파레 — C장조 상행 "빰빠밤~". 어느 시점에 겹쳐도 화음 (오디오 명세 §3)
	# 미세 변주 4벌: 유니즌 뭉침 방지 → "합창" 질감
	_streams["fanfare"] = _to_stream(_melody([[523.0, 0.09], [659.0, 0.09], [784.0, 0.09], [1047.0, 0.24]], "square", 0.4))
	_streams["fanfare_v2"] = _to_stream(_melody([[659.0, 0.09], [784.0, 0.09], [1047.0, 0.09], [1319.0, 0.24]], "square", 0.34))
	_streams["fanfare_v3"] = _to_stream(_melody([[523.0, 0.09], [659.0, 0.09], [784.0, 0.09], [1047.0, 0.24]], "tri", 0.5))
	_streams["fanfare_v4"] = _to_stream(_mix(
		_melody([[523.0, 0.09], [659.0, 0.09], [784.0, 0.09], [1047.0, 0.24]], "square", 0.3),
		_melody([[392.0, 0.09], [523.0, 0.09], [659.0, 0.09], [784.0, 0.24]], "square", 0.2), 0.0))
	# J7 획득 토스트음 3종 — 훈장/메달/기타 (음색만 다르게)
	_streams["toast1"] = _to_stream(_melody([[784.0, 0.07], [1047.0, 0.16]], "square", 0.35))
	_streams["toast2"] = _to_stream(_melody([[784.0, 0.07], [1047.0, 0.16]], "tri", 0.45))
	_streams["toast3"] = _to_stream(_melody([[784.0, 0.07], [1047.0, 0.16]], "sine", 0.45))
	# J12 대장간 타격 3종 — 판정별 음정 상승
	_streams["forge1"] = _to_stream(_mix(_tone(392.0, 0.1, 0.35, "square"), _tone(300.0, 0.08, 0.3, "noise"), 0.0))
	_streams["forge2"] = _to_stream(_mix(_tone(523.0, 0.1, 0.35, "square"), _tone(300.0, 0.08, 0.3, "noise"), 0.0))
	_streams["forge3"] = _to_stream(_mix(_melody([[659.0, 0.07], [784.0, 0.12]], "square", 0.4), _tone(300.0, 0.08, 0.3, "noise"), 0.0))
	# 대형 팡파레 (보스/영입)
	_streams["fanfare_big"] = _to_stream(_melody([
		[523.0, 0.1], [523.0, 0.1], [523.0, 0.1], [659.0, 0.28], [0.0, 0.03],
		[587.0, 0.1], [659.0, 0.1], [784.0, 0.36]], "square", 0.42))
	# 전투창 팝
	_streams["window"] = _to_stream(_concat([_tone(392.0, 0.05, 0.35, "square"), _tone(523.0, 0.08, 0.35, "square")]))
	# J4 황금 슬라임 등장 (샤랑~) / 은빛 = 동일 프레이즈 반음계 변형
	_streams["golden"] = _to_stream(_melody([[1568.0, 0.06], [1976.0, 0.06], [2637.0, 0.06], [3136.0, 0.18]], "tri", 0.4))
	_streams["golden_silver"] = _to_stream(_melody([[1480.0, 0.06], [1865.0, 0.06], [2489.0, 0.06], [2960.0, 0.18]], "tri", 0.4))
	# 물컹 (문지르기)
	_streams["squish"] = _to_stream(_tone(340.0, 0.09, 0.5, "sine", -1600.0))
	# 포획 성공
	_streams["capture"] = _to_stream(_melody([[784.0, 0.06], [988.0, 0.06], [1175.0, 0.06], [1568.0, 0.06], [1976.0, 0.06], [2349.0, 0.3]], "square", 0.42))
	# 도주
	_streams["flee"] = _to_stream(_melody([[880.0, 0.07], [740.0, 0.07], [622.0, 0.07], [523.0, 0.12]], "tri", 0.35))
	# 유령 (누군가 쓰러짐)
	_streams["ghost"] = _to_stream(_melody([[440.0, 0.12], [415.0, 0.12], [370.0, 0.28]], "tri", 0.4))
	# 전멸
	_streams["wipe"] = _to_stream(_melody([[294.0, 0.2], [277.0, 0.2], [247.0, 0.2], [220.0, 0.5]], "square", 0.4))
	# 부활
	_streams["revive"] = _to_stream(_melody([[523.0, 0.09], [659.0, 0.09], [784.0, 0.09], [1047.0, 0.09], [1319.0, 0.26]], "tri", 0.4))
	# 회복 (여관)
	_streams["heal"] = _to_stream(_melody([[659.0, 0.08], [784.0, 0.08], [988.0, 0.2]], "tri", 0.38))
	# 레벨업
	_streams["levelup"] = _to_stream(_melody([[659.0, 0.07], [784.0, 0.07], [880.0, 0.07], [1175.0, 0.2]], "square", 0.4))
	# 구매
	_streams["buy"] = _to_stream(_concat([_tone(1175.0, 0.05, 0.35, "square"), _tone(880.0, 0.1, 0.35, "square")]))
	# 실패/불가 (붑-)
	_streams["deny"] = _to_stream(_concat([_tone(220.0, 0.09, 0.4, "square"), _tone(185.0, 0.14, 0.4, "square")]))
	# 발굴 (석-석)
	_streams["dig"] = _to_stream(_concat([_tone(700.0, 0.06, 0.3, "noise"), _silence(0.06), _tone(500.0, 0.08, 0.3, "noise")]))
	# 건설 (뚝-딱)
	_streams["build"] = _to_stream(_concat([_tone(500.0, 0.07, 0.4, "square"), _silence(0.08), _tone(600.0, 0.07, 0.4, "square"), _silence(0.08), _tone(800.0, 0.14, 0.4, "square")]))
	# 루라 (휭↑)
	_streams["warp"] = _to_stream(_tone(300.0, 0.4, 0.4, "tri", 2400.0))
	# 보스 등장 (두둥)
	_streams["boss"] = _to_stream(_melody([[131.0, 0.25], [0.0, 0.06], [123.0, 0.5]], "saw", 0.5))
	# 클릭 (깃발)
	_streams["click"] = _to_stream(_tone(660.0, 0.04, 0.25, "square"))
	# 타자기 블립 (전투 로그 한 글자)
	_streams["blip"] = _to_stream(_tone(1100.0, 0.018, 0.18, "square"))
	# 상자
	_streams["chest"] = _to_stream(_concat([_tone(392.0, 0.07, 0.35, "square"), _tone(494.0, 0.07, 0.35, "square"), _tone(587.0, 0.12, 0.35, "square")]))
	# 팔레트 전환 (세계가 물든다)
	_streams["palette"] = _to_stream(_melody([[262.0, 0.14], [330.0, 0.14], [392.0, 0.14], [523.0, 0.14], [659.0, 0.4]], "tri", 0.4))
	# 뾱 — 오프닝 팝인 (v3.8 §B-4. pitch 인자로 계단 음정)
	_streams["pop"] = _to_stream(_mix(_tone(520.0, 0.09, 0.4, "sine", 300.0), _tone(1040.0, 0.05, 0.15, "tri"), 0.01))
	# 주시 루프 (은은한 샤라락 — 루프 재생용)
	var gz := _mix(_tone(1568.0, 0.5, 0.10, "sine", 0.0, 1.5), _tone(2093.0, 0.5, 0.07, "sine", 0.0, 1.5), 0.25)
	var gz_stream := _to_stream(gz)
	gz_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	gz_stream.loop_end = gz.size()
	_streams["gaze_loop"] = gz_stream
	# 합체기 발동 (부오옹↑ + 팡)
	_streams["combo"] = _to_stream(_mix(_tone(180.0, 0.5, 0.4, "saw", 700.0), _melody([[784.0, 0.08], [1047.0, 0.08], [1568.0, 0.3]], "square", 0.4), 0.35))
	# 입금/출금 (짤랑짤랑)
	_streams["bank"] = _to_stream(_concat([_tone(1319.0, 0.05, 0.3, "square"), _silence(0.04), _tone(1568.0, 0.05, 0.3, "square"), _silence(0.04), _tone(1976.0, 0.12, 0.3, "square")]))
	# 벽 속 목소리 (우웅…)
	_streams["voice"] = _to_stream(_tone(196.0, 0.6, 0.3, "sine", 40.0, 2.0))
	# 타이틀 테마 — 새벽 어레인지 (조용한 트라이앵글 아르페지오, 루프)
	var theme_notes := [
		[262.0, 0.42], [330.0, 0.42], [392.0, 0.42], [523.0, 0.84],
		[494.0, 0.42], [392.0, 0.42], [330.0, 0.42], [294.0, 0.84],
		[262.0, 0.42], [330.0, 0.42], [440.0, 0.42], [523.0, 0.84],
		[494.0, 0.42], [440.0, 0.42], [392.0, 0.42], [392.0, 0.84],
		[0.0, 0.6],
	]
	var theme := _melody(theme_notes, "tri", 0.22)
	# 5도 아래 패드를 얇게 겹친다 — 새벽의 공기
	theme = _mix(theme, _melody([[131.0, 3.3], [147.0, 3.3], [131.0, 3.4]], "sine", 0.10), 0.0)
	var theme_stream := _to_stream(theme)
	theme_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	theme_stream.loop_end = theme.size()
	_streams["title_theme"] = theme_stream
