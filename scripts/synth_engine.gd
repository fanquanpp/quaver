extends Node
## 自动加载 Synth —— 复音播放引擎
##
## 32 路 AudioStreamPlayer 池：空闲分配、最旧抢占；Synth 总线挂 Limiter 防削波。
## 音符均为一次性采样回放（自然衰减），键盘行为等同"踏板延音"，零 note-off 开销。

const POLYPHONY := 32
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
	p.stop()
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


func _grab() -> int:
	for i in _players.size():
		if not _players[i].playing:
			return i
	var oldest := 0
	for i in _start_ms.size():
		if _start_ms[i] < _start_ms[oldest]:
			oldest = i
	return oldest
