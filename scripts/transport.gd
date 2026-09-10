class_name Transport
extends Node
## 走带：播放推进、音符调度（事件预排序 + 指针扫描 + look-ahead 提前触发）、循环、录制时钟
##
## v0.2 时钟迁移：playhead 用音频时钟锚定，消除帧级推进的 ~16ms 抖动——
##   clock_msec = 墙钟 + (get_time_since_last_mix() - get_output_latency()) × 1000
##   playhead = anchor_tick + (clock_msec - anchor_clock_msec) / 1000 / secs_per_tick
## （减 output_latency 补回扬声器侧延迟，playhead 即"当前可听位置"）
##
## 音符 look-ahead：play() 起音到出声恰隔一个输出延迟，故事件在
## "目标出声时刻 - latency"触发，实际出声时刻对齐目标 tick。
##
## 循环回卷：剩余事件的绝对 tick 平移一个循环跨度，修复旧版边界
## [end, end+提前量) 内音符被跳过的丢失问题。
## use_audio_clock 是风险矩阵保留的回退开关（异常时可切回纯墙钟）。

signal tick_changed(tick: float)
signal note_fired(track: int, pitch: int, vel: float)
signal started
signal stopped

var song: SongModel
var playing := false
var recording := false
var loop_play := false
var loop_start := 0.0   ## 循环区间起点（tick）
var loop_end := 0.0     ## 循环区间终点（tick）；0 = 跟随曲末（整体循环）
var playhead := 0.0
var use_audio_clock := true
## 时钟注入（测试用）：返回毫秒的 Callable；为空用真实音频时钟
var clock_override: Callable = Callable()

var _events: Array = []  # {t:float, tr:int, p:int, v:float} 按 t 升序
var _ptr := 0
var _anchor_tick := 0.0
var _anchor_clock := 0.0


func _clock_msec() -> float:
	if clock_override.is_valid():
		return clock_override.call()
	if use_audio_clock:
		# 混音尚未发生（如 headless 无声卡）时回退墙钟，避免时钟停滞
		var since := AudioServer.get_time_since_last_mix()
		if since > 0.0:
			return Time.get_ticks_msec() + (since - AudioServer.get_output_latency()) * 1000.0
	return float(Time.get_ticks_msec())


func _reanchor() -> void:
	_anchor_tick = playhead
	_anchor_clock = _clock_msec()


## look-ahead 提前量（tick）：一个输出延迟 + 1ms 余量
func _lookahead_ticks() -> float:
	if not use_audio_clock:
		return 0.0
	return (AudioServer.get_output_latency() + 0.001) / song.secs_per_tick()


func _process(_delta: float) -> void:
	if not playing:
		return
	playhead = _anchor_tick \
			+ maxf(_clock_msec() - _anchor_clock, 0.0) / 1000.0 / song.secs_per_tick()
	var end := _loop_end_tick() if loop_play else float(maxi(song.song_end_tick() + 8, 32))
	if loop_play and playhead >= end:
		# 循环回卷：剩余事件平移一个跨度（绝对 tick → 下一圈相对 tick）
		var span := maxf(end - loop_start, 1.0)
		for i in range(_ptr, _events.size()):
			if _events[i]["t"] >= end:
				_events[i]["t"] -= span
		playhead -= span
		_reanchor()
		_sync_ptr()
	var horizon := playhead + _lookahead_ticks()
	if loop_play:
		horizon = minf(horizon, end)  # 越界事件待回卷平移后触发，禁止提前
	_fire_until(horizon)
	if not loop_play and playhead >= end:
		stop()
		return
	tick_changed.emit(playhead)


## 循环边界：loop_end <= 0 时跟随曲末（保留旧"曲末 +8 tick 缓冲"行为）
func _loop_end_tick() -> float:
	if loop_end > 0.0:
		return loop_end
	return float(maxi(song.song_end_tick() + 8, 32))


func play(from_tick := -1.0) -> void:
	if playing:
		return
	if from_tick >= 0.0:
		playhead = from_tick
	_build_events()
	_sync_ptr()
	_reanchor()
	playing = true
	started.emit()


func stop() -> void:
	if not playing:
		return
	playing = false
	recording = false
	stopped.emit()
	tick_changed.emit(playhead)


## 模型变化后重建事件表并保持播放位置（支持边播边编）
func refresh() -> void:
	if playing:
		_build_events()
		_sync_ptr()
		_reanchor()


func seek(tick: float) -> void:
	playhead = maxf(tick, 0.0)
	if playing:
		_sync_ptr()
		_reanchor()
	tick_changed.emit(playhead)


func _build_events() -> void:
	_events.clear()
	for trk in song.tracks.size():
		if song.tracks[trk].get("mute", false):
			continue
		if _any_solo() and not song.tracks[trk].get("solo", false):
			continue
		for n in song.tracks[trk]["notes"]:
			_events.append({"t": float(n["s"]), "tr": trk, "p": n["p"], "v": n["v"]})
	_events.sort_custom(func(a, b): return a["t"] < b["t"])


func _any_solo() -> bool:
	for trk in song.tracks:
		if trk.get("solo", false):
			return true
	return false


func _sync_ptr() -> void:
	_ptr = 0
	while _ptr < _events.size() and _events[_ptr]["t"] < playhead:
		_ptr += 1


func _fire_until(horizon: float) -> void:
	while _ptr < _events.size() and _events[_ptr]["t"] <= horizon:
		var e: Dictionary = _events[_ptr]
		note_fired.emit(e["tr"], e["p"], e["v"])
		_ptr += 1
