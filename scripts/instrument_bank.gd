extends Node
## 自动加载 InstrumentBank —— 音源库
##
## 启动时后台线程合成 4 音色 × 4 基音的 AudioStreamWAV（22050Hz 单声道 16bit，
## 共约 1.4MB 内存），并写入 zstd 磁盘缓存；二次启动直接读缓存秒开。
## 播放期零 DSP：Synth 用 pitch_scale 在 ±6 半音内移调取最近基音。

signal bank_ready

const SR := 22050
const CACHE_VERSION := 3
const CACHE_PATH := "user://sample_cache_v%d.bin"
const BASE_NOTES := [36, 48, 60, 72]  # C2 C3 C4 C5
const INSTRUMENTS := ["钢琴", "芯片", "柔弦", "贝斯", "电钢", "八音盒"]

var ready_ok := false

var _banks := {}  # inst_name -> {base_midi: AudioStreamWAV}
var _thread: Thread = null


func _ready() -> void:
	if _load_cache():
		ready_ok = true
		bank_ready.emit()
		print("[InstrumentBank] 缓存加载完成")
		return
	_thread = Thread.new()
	_thread.start(_generate_all)


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


## 返回 [AudioStreamWAV, pitch_scale]，无音色时返回 []
func sample_for(inst: String, midi: int) -> Array:
	var bank: Dictionary = _banks.get(inst, {})
	var best := -1
	var bd := 999
	for base in bank:
		var d: int = absi(midi - base)
		if d < bd:
			bd = d
			best = base
	if best < 0:
		return []
	return [bank[best], pow(2.0, (midi - best) / 12.0)]


## ── 合成 ───────────────────────────────────────────────────────────

func _generate_all() -> void:
	for inst in INSTRUMENTS:
		var bank := {}
		for base in BASE_NOTES:
			bank[base] = _make_stream(inst, base)
		_banks[inst] = bank
	_save_cache()
	call_deferred("_finish")


func _finish() -> void:
	ready_ok = true
	bank_ready.emit()
	print("[InstrumentBank] 音源合成完成")


func _make_stream(inst: String, midi: int) -> AudioStreamWAV:
	var buf := PackedFloat32Array()
	match inst:
		"钢琴": buf = _synth_piano(NoteKeys.midi_to_freq(midi))
		"芯片": buf = _synth_chip(NoteKeys.midi_to_freq(midi))
		"柔弦": buf = _synth_pad(NoteKeys.midi_to_freq(midi))
		"贝斯": buf = _synth_bass(NoteKeys.midi_to_freq(midi))
		"电钢": buf = _synth_epiano(NoteKeys.midi_to_freq(midi))
		"八音盒": buf = _synth_musicbox(NoteKeys.midi_to_freq(midi))
	var n := buf.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.stereo = false
	wav.data = data
	return wav


## 7 次谐波加法合成 + 微失谐 + 锤击瞬态，分音区衰减
func _synth_piano(freq: float) -> PackedFloat32Array:
	var dur := clampf(4.2 - freq * 0.007, 1.2, 3.4)
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var harms := 6
	var w := PackedFloat64Array()
	var amp := PackedFloat64Array()
	var decay := PackedFloat64Array()
	w.resize(harms)
	amp.resize(harms)
	decay.resize(harms)
	for h in harms:
		var det := 1.0 + 0.0011 * h * h * (1.0 if h % 2 == 0 else -1.0)
		w[h] = TAU * freq * det / float(SR)
		amp[h] = pow(0.60, h)
		decay[h] = exp(-(2.0 + h * 1.35 + freq * 0.0045) / float(SR))
	var phase := PackedFloat64Array()
	phase.resize(harms)
	var env := PackedFloat64Array()
	for h in harms:
		env.append(1.0)
	var attack_n := maxi(int(0.004 * SR), 1)
	var click_env := 1.0
	var click_mul := exp(-110.0 / float(SR))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260910
	for i in n:
		var v := 0.0
		for h in harms:
			phase[h] += w[h]
			v += sin(phase[h]) * amp[h] * env[h]
			env[h] *= decay[h]
		if i < attack_n:
			v *= float(i) / attack_n
		if click_env > 0.003:
			v += rng.randf_range(-1.0, 1.0) * 0.22 * click_env
			click_env *= click_mul
		buf[i] = v
	return _normalize(buf)


## 25% 占空比方波两段衰减（芯片音效风格）
func _synth_chip(freq: float) -> PackedFloat32Array:
	var dur := 1.1
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var w := TAU * freq / float(SR)
	var phase := 0.0
	var attack_n := maxi(int(0.002 * SR), 1)
	for i in n:
		var t := float(i)
		phase += w
		var v := 1.0 if fmod(phase, TAU) < TAU * 0.25 else -1.0
		var env := exp(-2.0 * t / SR) if t / SR < 0.28 else exp(-0.28 * 2.0 + -7.0 * (t / SR - 0.28))
		v *= env * 0.55
		if i < attack_n:
			v *= float(i) / attack_n
		buf[i] = v
	return _normalize(buf)


## 正弦对 ±0.3% 失谐（合唱感）慢起音铺底
func _synth_pad(freq: float) -> PackedFloat32Array:
	var dur := 3.0
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var w1 := TAU * freq * 0.997 / float(SR)
	var w2 := TAU * freq * 1.003 / float(SR)
	var w3 := TAU * freq * 2.0 / float(SR)
	var attack_n := maxi(int(0.18 * SR), 1)
	var p1 := 0.0
	var p2 := 1.7
	var p3 := 0.5
	for i in n:
		var t := float(i)
		p1 += w1
		p2 += w2
		p3 += w3
		var env := exp(-1.1 * t / SR)
		if i < attack_n:
			env *= float(i) / attack_n
		buf[i] = (sin(p1) + sin(p2) + 0.25 * sin(p3)) * env * 0.4
	return _normalize(buf)


## 正弦 + 二次谐波贝斯
func _synth_bass(freq: float) -> PackedFloat32Array:
	var dur := 1.6
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var w1 := TAU * freq / float(SR)
	var attack_n := maxi(int(0.005 * SR), 1)
	for i in n:
		var t := float(i)
		var env := exp(-3.2 * t / SR)
		var v := (sin(w1 * t) + 0.4 * sin(2.0 * w1 * t) + 0.12 * sin(3.0 * w1 * t)) * env
		if i < attack_n:
			v *= float(i) / attack_n
		buf[i] = v
	return _normalize(buf)


## 电钢（Rhodes 风）：基频正弦主体 + ×3 泛音"叮"头 + 轻微敲击瞬态
func _synth_epiano(freq: float) -> PackedFloat32Array:
	var dur := 2.8
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var w1 := TAU * freq / float(SR)
	var w3 := TAU * freq * 3.0 / float(SR)
	var attack_n := maxi(int(0.003 * SR), 1)
	var p1 := 0.0
	var p3 := 0.9
	for i in n:
		var t := float(i)
		p1 += w1
		p3 += w3
		var body := sin(p1) * exp(-1.6 * t / SR)
		var bell := sin(p3) * exp(-16.0 * t / SR) * 0.30
		var v := body + bell
		if i < attack_n:
			v *= float(i) / attack_n
		buf[i] = v * 0.75
	return _normalize(buf)


## 八音盒：亮正弦 + 二/三次泛音，极快衰减（金属拨片质感）
func _synth_musicbox(freq: float) -> PackedFloat32Array:
	var dur := 1.8
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var w := TAU * freq / float(SR)
	var attack_n := maxi(int(0.0015 * SR), 1)
	var phases := [0.0, 2.1, 0.4]
	var mults := [1.0, 2.0, 3.02]
	var amps := [1.0, 0.35, 0.12]
	var decays := [2.8, 4.2, 6.5]
	for i in n:
		var t := float(i)
		var v := 0.0
		for h in 3:
			phases[h] += w * mults[h]
			v += sin(phases[h]) * amps[h] * exp(-decays[h] * t / SR)
		if i < attack_n:
			v *= float(i) / attack_n
		buf[i] = v * 0.7
	return _normalize(buf)


func _normalize(buf: PackedFloat32Array) -> PackedFloat32Array:
	var peak := 0.0
	for i in buf.size():
		peak = maxf(peak, absf(buf[i]))
	if peak > 0.0001:
		var g := 0.85 / peak
		for i in buf.size():
			buf[i] *= g
	return buf


## ── zstd 采样缓存 ──────────────────────────────────────────────────

func _cache_path() -> String:
	return CACHE_PATH % CACHE_VERSION


func _save_cache() -> void:
	var f := FileAccess.open_compressed(_cache_path(), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return
	f.store_16(CACHE_VERSION)
	f.store_16(INSTRUMENTS.size())
	for inst in INSTRUMENTS:
		var bank: Dictionary = _banks[inst]
		f.store_pascal_string(inst)
		f.store_16(bank.size())
		for base in bank:
			f.store_16(base)
			var data: PackedByteArray = (bank[base] as AudioStreamWAV).data
			f.store_32(data.size())
			f.store_buffer(data)
	f.close()


func _load_cache() -> bool:
	if not FileAccess.file_exists(_cache_path()):
		return false
	var f := FileAccess.open_compressed(_cache_path(), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null or f.get_16() != CACHE_VERSION:
		return false
	var count := f.get_16()
	for c in count:
		var inst := f.get_pascal_string()
		var bank := {}
		var nb := f.get_16()
		for b in nb:
			var base := f.get_16()
			var size := f.get_32()
			var data := f.get_buffer(size)
			var wav := AudioStreamWAV.new()
			wav.format = AudioStreamWAV.FORMAT_16_BITS
			wav.mix_rate = SR
			wav.stereo = false
			wav.data = data
			bank[base] = wav
		_banks[inst] = bank
	f.close()
	return _banks.size() == INSTRUMENTS.size()
