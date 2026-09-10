extends Node
## v0.1.3 无头回归测试：分析引擎 + "点播放有声音"端到端验证
##
## 运行：godot --headless --path . res://tests/smoke_v013.tscn
## 通过输出 [Test] ALL PASS 并以 0 退出（场景模式运行，autoload 全量可用）。

var _fails: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# ── 1) 分析引擎：示范曲《小星星》应为 C 大调 78 音符 ──
	var demo := SongModel.make_demo()
	var a := SongAnalysis.analyze(demo)
	print("[Test] analysis: notes=%d bars=%d dur=%.1fs key=%s conf=%d%% poly=%d span=%d" % [
		a["note_count"], a["bars"], a["dur_secs"], a["key"]["name"],
		a["key"]["confidence"], a["max_poly"], a["pitch_span"]])
	if a["note_count"] != 78:
		_fails.append("note_count=%d != 78" % a["note_count"])
	if a["key"]["root"] != 0 or a["key"]["minor"]:
		_fails.append("key detect != C 大调 (%s)" % a["key"]["name"])
	if a["max_poly"] < 3:
		_fails.append("max_poly=%d 过小" % a["max_poly"])
	if a["dur_secs"] <= 0.0:
		_fails.append("dur_secs 未算出")

	# ── 2) 主界面端到端：点播放后 transport 触发音符且播放器池在发声 ──
	var ps: PackedScene = load("res://scenes/main.tscn")
	var ui: Control = ps.instantiate()
	add_child(ui)
	for i in 5:
		await get_tree().process_frame
	var counter := [0]
	ui.transport.note_fired.connect(func(_t: int, _p: int, _v: float) -> void:
		counter[0] += 1)
	# 播放内容用 demo 工程，不依赖本机 autosave 恢复出的工程（可能为空）
	ui._switch_song(SongModel.make_demo())
	ui._on_play()
	for i in 30:
		await get_tree().process_frame
	var any_playing := false
	for p in Synth._players:
		if p.playing:
			any_playing = true
			break
	print("[Test] playback: note_fired=%d playhead=%.1f tick any_player_playing=%s" % [
		counter[0], ui.transport.playhead, any_playing])
	if counter[0] == 0:
		_fails.append("note_fired 未触发（走带/连接断了）")
	if not any_playing:
		_fails.append("无任何播放器在发声（Synth 路由断了）")
	ui.transport.stop()
	ui.queue_free()

	if _fails.is_empty():
		print("[Test] ALL PASS")
		get_tree().quit(0)
	else:
		print("[Test] FAIL: ", ", ".join(_fails))
		get_tree().quit(1)
