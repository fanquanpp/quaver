extends Node
## 自动加载 Synth —— 复音播放引擎
##
## 48 路 AudioStreamPlayer 池：空闲分配、最旧抢占；Synth 总线挂 Limiter 防削波。
## 音符均为一次性采样回放（自然衰减），键盘行为等同"踏板延音"，零 note-off 开销。
##
## 快速重复触发硬化（v0.2）：不再先 stop() 再 play() —— Godot 同帧 stop() 可能被
## 音频线程丢弃（godot#37148），play() 本身就是"从头重启"，直接调用即可；
## 抢断时避开刚起音 <80ms 的声部，防止把刚弹的新音偷掉造成"无声"感。

const POLYPHONY := 48
const BUS_NAME := "Synth"

var _players: Array[AudioStreamPlayer] = []
var _start_ms: Array[int] = []


func _ready() -> void:
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, BUS_NAME)
	AudioServer.set_bus_send(idx, "Master")
	var lim := AudioEffectLimiter.new()
	AudioServer.add_bus_effect(idx, lim)
	for i in POLYPHONY:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_NAME
		add_child(p)
		_players.append(p)
		_start_ms.append(0)


func play_note(inst: String, midi: int, vel := 0.8, pitch_bias := 0.0) -> void:
	if not InstrumentBank.ready_ok:
		return
	var s := InstrumentBank.sample_for(inst, midi)
	if s.is_empty():
		return
	var idx := _grab()
	var p := _players[idx]
	# 不调 stop()：play() 自带"从头重启"；同帧 stop()+play() 在 Godot 里会丢启动
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
