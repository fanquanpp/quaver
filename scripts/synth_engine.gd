extends Node
## 自动加载 Synth —— 复音播放引擎 + 音频总线路由（v0.2）
##
## 播放器池：空闲分配、最旧抢占（快速重复触发硬化见 v0.1 注释）；
## 池大小随轨道数动态增长 max(32, 轨道数×8)，上限 128。
##
## 总线拓扑（v0.2）：
##   Master → [EQ10, Limiter]
##   ├─ Music → [EQ6]          （旋律/和声轨集合）
##   └─ Drum  → [Compressor]   （鼓机轨集合）
##   Track0..15 → [Panner, EQ6, Compressor, Reverb, Delay] → Music/Drum
##
## 辅助发送：Godot 4 移除了带发送量的 AudioEffectSend（Godot 3 专有），
## 改用插入式实现——轨道总线上常驻 Reverb/Delay，wet 电平即"发送量"
## （dry 恒为 1 保证干声直通）。发送量 0 时 wet=0，效果器直通。
##
## 快速重复触发硬化：不先 stop() 再 play()（godot#37148 丢启动），
## play() 本身就是"从头重启"；抢断避开 <80ms 新起音的声部。

const MIN_POLYPHONY := 32
const MAX_POLYPHONY := 128
const MAX_TRACKS := 16

var _players: Array[AudioStreamPlayer] = []
var _start_ms: Array[int] = []
var _track_fx := {}  # 轨道总线 idx -> {"pan": Panner, "rv": Reverb, "dl": Delay}


func _ready() -> void:
	_setup_group_buses()
	_grow_pool(MIN_POLYPHONY)


## ── 总线拓扑 ───────────────────────────────────────────────────────

func _setup_group_buses() -> void:
	# Master 在默认总线 0 上追加（保持 bus 0 = Master 的既有约定）
	AudioServer.add_bus_effect(0, AudioEffectEQ10.new())
	AudioServer.add_bus_effect(0, AudioEffectLimiter.new())
	_mk_group_bus("Music", AudioEffectEQ6.new())
	_mk_group_bus("Drum", AudioEffectCompressor.new())


func _mk_group_bus(bus_name: String, fx: AudioEffect) -> void:
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	AudioServer.add_bus_effect(idx, fx)


func track_bus_name(track: int) -> String:
	return "Track%d" % clampi(track, 0, MAX_TRACKS - 1)


## 轨道总线懒创建；返回总线 idx
func _ensure_track_bus(i: int) -> int:
	var bus_name := track_bus_name(i)
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Music")
		AudioServer.add_bus_effect(idx, AudioEffectPanner.new())
		AudioServer.add_bus_effect(idx, AudioEffectEQ6.new())
		AudioServer.add_bus_effect(idx, AudioEffectCompressor.new())
		var rv := AudioEffectReverb.new()
		rv.dry = 1.0
		rv.wet = 0.0
		rv.room_size = 0.6
		AudioServer.add_bus_effect(idx, rv)
		var dl := AudioEffectDelay.new()
		dl.tap1_delay_ms = 240.0
		dl.tap1_active = false
		AudioServer.add_bus_effect(idx, dl)
	return idx


## 按类型取轨道总线上的效果器（类型查找，避免缓存 idx 失效）
func _track_fx_of(idx: int, type: Object) -> AudioEffect:
	var cache: Dictionary = _track_fx.get_or_add(idx, {})
	var key := type.to_string()
	if cache.has(key):
		return cache[key]
	for e in AudioServer.get_bus_effect_count(idx):
		var fx: AudioEffect = AudioServer.get_bus_effect(idx, e)
		if is_instance_of(fx, type):
			cache[key] = fx
			return fx
	return null


## 把工程轨道状态刷到总线（音量/声像/静音/独奏/类型路由/发送量）
func apply_mix(tracks: Array) -> void:
	var solo := false
	for trk in tracks:
		if trk.get("solo", false):
			solo = true
	_grow_pool(maxi(MIN_POLYPHONY, mini(MAX_POLYPHONY, tracks.size() * 8)))
	for i in mini(tracks.size(), MAX_TRACKS):
		var trk: Dictionary = tracks[i]
		var idx := _ensure_track_bus(i)
		AudioServer.set_bus_send(idx, "Drum" if trk.get("type", "melody") == "drum" else "Music")
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(trk.get("volume", 0.8), 0.0001)))
		AudioServer.set_bus_mute(idx, trk.get("mute", false) or (solo and not trk.get("solo", false)))
		var pan: AudioEffect = _track_fx_of(idx, AudioEffectPanner)
		if pan != null:
			(pan as AudioEffectPanner).pan = clampf(trk.get("pan", 0.0), -1.0, 1.0)
		# 辅助发送（插入式）：wet 电平 = 发送量
		var rv: AudioEffect = _track_fx_of(idx, AudioEffectReverb)
		if rv != null:
			(rv as AudioEffectReverb).wet = clampf(trk.get("reverb", 0.0), 0.0, 1.0)
		var dl: AudioEffect = _track_fx_of(idx, AudioEffectDelay)
		if dl != null:
			var amount := clampf(trk.get("delay", 0.0), 0.0, 1.0)
			var delay := dl as AudioEffectDelay
			delay.tap1_active = amount > 0.001
			delay.tap1_level_db = linear_to_db(maxf(amount, 0.001))
	# 空槽轨道总线静音，防止删轨后残留发声
	for i in range(tracks.size(), MAX_TRACKS):
		var idx := AudioServer.get_bus_index(track_bus_name(i))
		if idx >= 0:
			AudioServer.set_bus_mute(idx, true)


## ── 发声 ───────────────────────────────────────────────────────────

func polyphony() -> int:
	return _players.size()


func play_note(inst: String, midi: int, vel := 0.8, pitch_bias := 0.0) -> void:
	play_note_on_track(0, inst, midi, vel, pitch_bias)


## 按轨发声：路由到该轨总线（音量/声像/静音/发送随轨生效）
func play_note_on_track(track: int, inst: String, midi: int, vel := 0.8, pitch_bias := 0.0) -> void:
	if not InstrumentBank.ready_ok:
		return
	var s := InstrumentBank.sample_for(inst, midi, vel)
	if s.is_empty():
		return
	var idx := _grab()
	var p := _players[idx]
	# 不调 stop()：play() 自带"从头重启"；同帧 stop()+play() 在 Godot 里会丢启动
	p.bus = track_bus_name(track)
	p.stream = s[0]
	p.pitch_scale = s[1] * pow(2.0, pitch_bias / 12.0)
	p.volume_db = linear_to_db(clampf(vel, 0.05, 1.0))
	p.play()
	_start_ms[idx] = Time.get_ticks_msec()


func stop_all() -> void:
	for p in _players:
		p.stop()


## 主总线音量（线性 0-1）
func set_volume(linear: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(linear, 0.0001)))


## 分配策略：空闲 → 已自然播完 → 最旧；仅在全部声部都是 80ms 内新起音时才允许
## 偷新音（保证再快的连击也必有声，而不是丢触发）
func _grab() -> int:
	for i in _players.size():
		if not _players[i].playing:
			return i
	var now := Time.get_ticks_msec()
	var oldest := -1
	var fallback := 0
	for i in _start_ms.size():
		if _start_ms[i] < _start_ms[fallback]:
			fallback = i
		if now - _start_ms[i] < 80:
			continue
		if oldest < 0 or _start_ms[i] < _start_ms[oldest]:
			oldest = i
	return oldest if oldest >= 0 else fallback


func _grow_pool(n: int) -> void:
	n = clampi(n, MIN_POLYPHONY, MAX_POLYPHONY)
	while _players.size() < n:
		var p := AudioStreamPlayer.new()
		p.bus = track_bus_name(0)
		add_child(p)
		_players.append(p)
		_start_ms.append(0)
