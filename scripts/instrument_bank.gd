extends Node
## 自动加载 InstrumentBank —— 音源库
##
## 启动时后台线程合成 6 音色 × 4 基音 × 3 力度层（pp/mf/ff）的 AudioStreamWAV
## （22050Hz 单声道 16bit，全量约 8MB 内存），并写入 zstd 磁盘缓存；
## 二次启动直接读缓存秒开。播放期零 DSP：Synth 用 pitch_scale 在 ±6 半音内移调。
##
## 力度分层（v0.2）：缓存 key = (音色, 基音, 力度层)；力度层按触发力度选档，
## 层内再做音量连续控制（Synth volume_db）。
## 鼓组（v0.2）：6 个鼓声部按音高映射，首次使用时按需合成、仅内存缓存
## （每个声部 <0.3s 音频，不入磁盘缓存）。

signal bank_ready

const SR := 22050
const CACHE_VERSION := 4
const CACHE_PATH := "user://sample_cache_v%d.bin"
const BASE_NOTES := [36, 48, 60, 72]  # C2 C3 C4 C5
const INSTRUMENTS := ["钢琴", "芯片", "柔弦", "贝斯", "电钢", "八音盒"]
const DRUM_INST := "鼓组"
const PLUGIN_PATH := "user://instrument_plugins.json"
const SFZ_DIR := "user://sfz"
## 鼓声部：音高 → 声部名（步进编辑器与本表对应）
const DRUM_VOICES := {36: "底鼓", 38: "军鼓", 39: "拍手", 42: "踩镲", 45: "嗵鼓", 46: "开镲"}
## 力度层阈值：v < 0.45 → pp；v < 0.8 → mf；否则 ff
const VEL_THRESHOLDS := [0.45, 0.8]
const LAYER_GAIN := [0.72, 0.88, 1.0]

var ready_ok := false
## 动态音色列表（内置 + 插件配方 + SFZ）；UI 下拉一律读这里
var instruments: Array = []

var _banks := {}  # inst_name -> {base_midi: [wav_pp, wav_mf, wav_ff]}
var _drums := {}  # 声部名 -> AudioStreamWAV（懒合成）
var _sfz := {}    # "sfz:名" -> [{stream, lokey, hikey, lovel, hivel, key_center}]
var _thread: Thread = null


func _ready() -> void:
	instruments = INSTRUMENTS.duplicate()
	if _load_cache():
		ready_ok = true
		_load_plugins()
		_load_sfz_all()
		bank_ready.emit()
		print("[InstrumentBank] 缓存加载完成")
		return
	_thread = Thread.new()
	_thread.start(_generate_all)


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


## 返回 [AudioStreamWAV, pitch_scale]，无音色时返回 []
func sample_for(inst: String, midi: int, vel := 0.8) -> Array:
	if inst == DRUM_INST:
		return _drum_sample(midi)
	if inst.begins_with("sfz:"):
		return _sfz_sample(inst, midi, vel)
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
	var layers: Array = bank[best]
	return [layers[_layer_of(vel)], pow(2.0, (midi - best) / 12.0)]


func _layer_of(vel: float) -> int:
	for i in VEL_THRESHOLDS.size():
		if vel < VEL_THRESHOLDS[i]:
			return i
	return VEL_THRESHOLDS.size()


func _drum_sample(midi: int) -> Array:
	if not _drums.has(midi):
		var best := -1
		var bd := 999
		for p in DRUM_VOICES:
			var d: int = absi(midi - p)
			if d < bd:
				bd = d
				best = p
		var voice: String = DRUM_VOICES[best]
		if not _drums.has(best):
			_drums[best] = _make_stream("鼓组:" + voice, best, 2)
		_drums[midi] = _drums[best]
	return [_drums[midi], 1.0]


## ── 合成 ───────────────────────────────────────────────────────────

func _generate_all() -> void:
	for inst in INSTRUMENTS:
		var bank := {}
		for base in BASE_NOTES:
			var layers := []
			for layer in LAYER_GAIN.size():
				layers.append(_make_stream(inst, base, layer))
			bank[base] = layers
		_banks[inst] = bank
	_save_cache()
	call_deferred("_finish")


func _finish() -> void:
	_load_plugins()
	_load_sfz_all()
	ready_ok = true
	bank_ready.emit()
	print("[InstrumentBank] 音源合成完成")


## ── 插件配方音色（v1.0.0） ─────────────────────────────────────────
## user://instrument_plugins.json：
## [{"name": "我的音色", "recipe": {"harmonics": [1, 0.4], "decay": 3.0,
##   "attack": 0.003, "click": 0.1, "dur": 2.4, "wave": "sine", "gain": 0.7}}]
## 配方级插件每次启动按需合成（小体量，不入磁盘缓存）。

func _load_plugins() -> void:
	if not FileAccess.file_exists(PLUGIN_PATH):
		return
	var f := FileAccess.open(PLUGIN_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Array):
		return
	for p in data:
		if p is Dictionary and p.get("name", "") != "" and p.get("recipe", {}) is Dictionary:
			register_plugin(p["name"], p["recipe"])


func register_plugin(p_name: String, recipe: Dictionary) -> void:
	if p_name in instruments:
		return
	var bank := {}
	for base in BASE_NOTES:
		var layers := []
		for layer in LAYER_GAIN.size():
			layers.append(_stream_from_buf(_synth_recipe(NoteKeys.midi_to_freq(base), recipe), layer))
		bank[base] = layers
	_banks[p_name] = bank
	instruments.append(p_name)


## 通用参数配方合成：谐波加法（可换方波/锯波）+ 起音/衰减/噪声瞬态
func _synth_recipe(freq: float, r: Dictionary) -> PackedFloat32Array:
	var dur := clampf(float(r.get("dur", 2.0)), 0.1, 6.0)
	var harmonics: Array = r.get("harmonics", [1.0])
	var decay := maxf(float(r.get("decay", 2.5)), 0.2)
	var attack := clampf(float(r.get("attack", 0.004)), 0.0, 0.5)
	var click := clampf(float(r.get("click", 0.0)), 0.0, 1.0)
	var gain := clampf(float(r.get("gain", 0.7)), 0.1, 1.0)
	var wave: String = r.get("wave", "sine")
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phases := PackedFloat64Array()
	phases.resize(harmonics.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var click_env := 1.0
	var attack_n := maxi(int(attack * SR), 1)
	for i in n:
		var t := float(i)
		var v := 0.0
		for h in harmonics.size():
			phases[h] += TAU * freq * (h + 1) / SR
			var osc := 0.0
			var ph := fmod(phases[h], TAU)
			match wave:
				"square":
					osc = 1.0 if ph < PI else -1.0
				"saw":
					osc = ph / PI - 1.0
				_:
					osc = sin(ph)
			v += osc * float(harmonics[h]) * exp(-decay * (1.0 + 0.3 * h) * t / SR)
		if i < attack_n:
			v *= float(i) / attack_n
		if click_env > 0.003 and click > 0.0:
			v += rng.randf_range(-1.0, 1.0) * click * click_env
			click_env *= exp(-80.0 / SR)
		buf[i] = v * gain
	return _normalize(buf)


## ── SFZ 采样音色（v1.0.0；SF2 二进制格式另评估） ───────────────────
## 扫描 user://sfz/*.sfz，音色名 = "sfz:文件名"

func _load_sfz_all() -> void:
	if not DirAccess.dir_exists_absolute(SFZ_DIR):
		return
	var dir := DirAccess.open(SFZ_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".sfz"):
			var regions := SfzLoader.load_instrument(SFZ_DIR + "/" + fname)
			if not regions.is_empty():
				_sfz["sfz:" + fname.get_basename()] = regions
				if not ("sfz:" + fname.get_basename()) in instruments:
					instruments.append("sfz:" + fname.get_basename())
		fname = dir.get_next()


func _sfz_sample(inst: String, midi: int, vel: float) -> Array:
	var regions: Array = _sfz.get(inst, [])
	var v127 := int(vel * 127.0)
	for r in regions:
		if midi >= r["lokey"] and midi <= r["hikey"] \
				and v127 >= r["lovel"] and v127 <= r["hivel"]:
			var key_center: int = r["key_center"]
			return [r["stream"], pow(2.0, (midi - key_center) / 12.0)]
	return []


func _make_stream(inst: String, midi: int, layer: int) -> AudioStreamWAV:
	var freq := NoteKeys.midi_to_freq(midi)
	var buf := PackedFloat32Array()
	if inst.begins_with(DRUM_INST + ":"):
		buf = _synth_drum(inst.get_slice(":", 1), midi)
	else:
		match inst:
			"钢琴": buf = _synth_piano(freq)
			"芯片": buf = _synth_chip(freq)
			"柔弦": buf = _synth_pad(freq)
			"贝斯": buf = _synth_bass(freq)
			"电钢": buf = _synth_epiano(freq)
			"八音盒": buf = _synth_musicbox(freq)
	return _stream_from_buf(buf, layer)


## 浮点缓冲 → 力度层 AudioStreamWAV（层增益 + 16bit 编码）
func _stream_from_buf(buf: PackedFloat32Array, layer: int) -> AudioStreamWAV:
	buf = _normalize(buf)
	var g: float = LAYER_GAIN[layer]
	if g < 1.0:
		for i in buf.size():
			buf[i] *= g
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SR
	wav.stereo = false
	wav.data = data
	return wav


## 鼓组合成（声部名见 DRUM_VOICES）
func _synth_drum(voice: String, midi: int) -> PackedFloat32Array:
	match voice:
		"底鼓":
			return _drum_kick(115.0, 42.0, 0.30)
		"嗵鼓":
			return _drum_kick(210.0, 120.0, 0.28)
		"军鼓":
			return _drum_noise_mix(190.0, 0.16, 0.20, 0.9)
		"拍手":
			return _drum_clap()
		"踩镲":
			return _drum_hat(0.055)
		"开镲":
			return _drum_hat(0.38)
		_:
			return _drum_kick(float(midi), 60.0, 0.25)


## 底鼓/嗵鼓：正弦下滑 + 起振click
func _drum_kick(f_start: float, f_end: float, dur: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var click := 1.0
	for i in n:
		var t := float(i) / SR
		var f := f_end + (f_start - f_end) * exp(-t * 34.0)
		phase += TAU * f / SR
		var env := exp(-t * 13.0)
		var v := sin(phase) * env
		if click > 0.01:
			v += rng.randf_range(-1.0, 1.0) * 0.5 * click
			click *= exp(-t * 900.0)
		buf[i] = v
	return buf


## 军鼓：噪声 + 鼓皮音高双成分
func _drum_noise_mix(tone_freq: float, dur: float, tone_amt: float, noise_decay: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var prev := 0.0
	var phase := 0.0
	var w := TAU * tone_freq / SR
	for i in n:
		var t := float(i)
		phase += w
		var raw := rng.randf_range(-1.0, 1.0)
		var hp := raw - prev  # 一阶差分 ≈ 高通，噪声更"沙"
		prev = raw
		var noise := hp * exp(-noise_decay * t / SR)
		var tone := sin(phase) * exp(-t * 42.0 / SR)
		buf[i] = noise * (1.0 - tone_amt * 0.5) + tone * tone_amt
	return buf


## 拍手：4 连短噪声脉冲 + 尾音
func _drum_clap() -> PackedFloat32Array:
	var n := int(0.30 * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var prev := 0.0
	var bursts := [0.0, 0.011, 0.023, 0.036]
	for i in n:
		var t := float(i) / SR
		var raw := rng.randf_range(-1.0, 1.0)
		var hp := raw - prev
		prev = raw
		var v := 0.0
		for b in bursts.size():
			var dt: float = t - bursts[b]
			if dt >= 0.0:
				var decay := 90.0 if b < bursts.size() - 1 else 18.0
				v += hp * exp(-decay * dt) * (0.6 if b < bursts.size() - 1 else 0.8)
		buf[i] = v
	return buf


## 镲：6 个不谐和方波叠 + 高通噪声（金属感），decay 控制开/闭
func _drum_hat(dur: float) -> PackedFloat32Array:
	var n := int(dur * SR)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var prev := 0.0
	var freqs := [3311.0, 4417.0, 5273.0, 6611.0, 8127.0, 9373.0]
	var phases := PackedFloat64Array()
	phases.resize(freqs.size())
	for i in n:
		var t := float(i)
		var metallic := 0.0
		for h in freqs.size():
			phases[h] += TAU * freqs[h] / SR
			metallic += 1.0 if fmod(phases[h], TAU) < PI else -1.0
		metallic /= freqs.size()
		var raw := rng.randf_range(-1.0, 1.0)
		var hp := raw - prev
		prev = raw
		buf[i] = (metallic * 0.7 + hp * 0.5) * exp(-t * 26.0 / SR)
	return buf


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
			var layers: Array = bank[base]
			f.store_8(layers.size())
			for wav in layers:
				var data: PackedByteArray = (wav as AudioStreamWAV).data
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
			var layers := []
			var nl := f.get_8()
			for l in nl:
				var size := f.get_32()
				var data := f.get_buffer(size)
				var wav := AudioStreamWAV.new()
				wav.format = AudioStreamWAV.FORMAT_16_BITS
				wav.mix_rate = SR
				wav.stereo = false
				wav.data = data
				layers.append(wav)
			bank[base] = layers
		_banks[inst] = bank
	f.close()
	return _banks.size() == INSTRUMENTS.size()
