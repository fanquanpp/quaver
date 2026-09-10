class_name Transport
extends Node
## 走带：播放推进、音符调度（事件预排序 + 指针扫描）、循环、录制时钟
##
## 调度精度为帧级（~16ms 抖动），对编曲监听足够；v0.2 计划迁移到
## AudioServer 混音时钟 + look-ahead 提前触发（见 DESIGN.md 路线图）。

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

var _events: Array = []  # {t:float, tr:int, p:int, v:float} 按 t 升序
var _ptr := 0


func _process(delta: float) -> void:
	if not playing:
		return
	playhead += delta / song.secs_per_tick()
	# 循环时终点取区间（区间未设置则曲末）；非循环永远停在曲末
	var end := _loop_end_tick() if loop_play else float(maxi(song.song_end_tick() + 8, 32))
	if playhead >= end:
		if loop_play:
			var span := maxf(end - loop_start, 1.0)
			playhead = loop_start + fmod(playhead - loop_start, span)
			_sync_ptr()
		else:
			stop()
			return
	_fire_due()
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


func seek(tick: float) -> void:
	playhead = maxf(tick, 0.0)
	if playing:
		_sync_ptr()
	tick_changed.emit(playhead)


func _build_events() -> void:
	_events.clear()
	for trk in song.tracks.size():
		for n in song.tracks[trk]["notes"]:
			_events.append({"t": float(n["s"]), "tr": trk, "p": n["p"], "v": n["v"]})
	_events.sort_custom(func(a, b): return a["t"] < b["t"])


func _sync_ptr() -> void:
	_ptr = 0
	while _ptr < _events.size() and _events[_ptr]["t"] < playhead:
		_ptr += 1


func _fire_due() -> void:
	while _ptr < _events.size() and _events[_ptr]["t"] <= playhead:
		var e: Dictionary = _events[_ptr]
		note_fired.emit(e["tr"], e["p"], e["v"])
		_ptr += 1
