extends Node
## 절차 합성 효과음 (임시 사운드 — 나중에 진짜 사운드 파일로 교체 가능)
## Sfx.play("coin") 식으로 사용. 창별 팡파레가 어긋나 겹치는 게 시그니처라 폴리포니 풀 사용.

const MIX_RATE := 22050
const POOL_SIZE := 16

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_idx := 0

func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_pool.append(p)
	_build_all()

func play(name: String, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	if not _streams.has(name):
		return
	var p := _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % POOL_SIZE
	p.stop()
	p.stream = _streams[name]
	p.pitch_scale = pitch
	p.volume_db = -8.0 + vol_db
	p.play()

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
	# 승리 팡파레 (짧게 — 어긋나 겹치는 게 시그니처)
	_streams["fanfare"] = _to_stream(_melody([[523.0, 0.09], [659.0, 0.09], [784.0, 0.09], [1047.0, 0.24]], "square", 0.4))
	# 대형 팡파레 (보스/영입)
	_streams["fanfare_big"] = _to_stream(_melody([
		[523.0, 0.1], [523.0, 0.1], [523.0, 0.1], [659.0, 0.28], [0.0, 0.03],
		[587.0, 0.1], [659.0, 0.1], [784.0, 0.36]], "square", 0.42))
	# 전투창 팝
	_streams["window"] = _to_stream(_concat([_tone(392.0, 0.05, 0.35, "square"), _tone(523.0, 0.08, 0.35, "square")]))
	# 황금 슬라임 등장 (샤랑~)
	_streams["golden"] = _to_stream(_melody([[1568.0, 0.06], [1976.0, 0.06], [2637.0, 0.06], [3136.0, 0.18]], "tri", 0.4))
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
	# 상자
	_streams["chest"] = _to_stream(_concat([_tone(392.0, 0.07, 0.35, "square"), _tone(494.0, 0.07, 0.35, "square"), _tone(587.0, 0.12, 0.35, "square")]))
	# 팔레트 전환 (세계가 물든다)
	_streams["palette"] = _to_stream(_melody([[262.0, 0.14], [330.0, 0.14], [392.0, 0.14], [523.0, 0.14], [659.0, 0.4]], "tri", 0.4))
