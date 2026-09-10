extends Node
## v0.2-a 无头回归测试：撤销重做 / MIDI 往返 / 循环区间 / 新音色 / UI 接线
##
## 运行：godot --headless --path . res://tests/smoke_v014.tscn
## 通过输出 [Test] ALL PASS 并以 0 退出。

var _fails: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_edit_history()
	_test_history_dirty()
	_test_midi_roundtrip()
	_test_midi_garbage()
	_test_loop_region()
	_test_transport_no_loop_stops_at_end()
	_test_sheet_music()
	_test_sheet_music_split()
	await _test_new_instruments()
	_test_synth_grab()
	await _test_ui_wiring()

	if _fails.is_empty():
		print("[Test] ALL PASS")
		get_tree().quit(0)
	else:
		print("[Test] FAIL: ", ", ".join(_fails))
		get_tree().quit(1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


## ── 1) EditHistory 基本回路 ────────────────────────────────────────

func _test_edit_history() -> void:
	var s := SongModel.make_demo()
	var h := EditHistory.new()
	h.reset(s)
	var n0 := s.track_notes(0).size()
	s.add_note(0, 80, 0, 2)
	h.push(s)
	_check(s.track_notes(0).size() == n0 + 1, "push 后音符应 +1")
	_check(h.can_undo() and not h.can_redo(), "push 后应可撤销不可重做")
	h.undo(s)
	_check(s.track_notes(0).size() == n0, "撤销后音符数应还原")
	h.redo(s)
	_check(s.track_notes(0).size() == n0 + 1, "重做后音符应回来")
	# 无效编辑（同状态 push）不产生新条目
	var idx_before := h._idx
	h.push(s)
	_check(h._idx == idx_before, "同状态重复 push 不应入栈")
	# 还原后的音符是深拷贝：改新音符不影响历史态
	var restored: Dictionary = s.track_notes(0)[0]
	restored["p"] = 99
	h.undo(s)
	_check(s.track_notes(0)[0]["p"] == 60, "历史快照不应被活模型污染")
	h.redo(s)


## ── 2) 连续修改（mark_dirty）语义 ──────────────────────────────────

func _test_history_dirty() -> void:
	var s := SongModel.make_demo()
	var h := EditHistory.new()
	h.reset(s)
	s.bpm = 132.0
	h.mark_dirty()
	_check(h.undo(s), "脏态下 undo 应先落栈再回退")
	_check(absf(s.bpm - 96.0) < 0.001, "undo 后 bpm 应回到 96")
	_check(h.redo(s), "redo 应可用")
	_check(absf(s.bpm - 132.0) < 0.001, "redo 后 bpm 应为最终值 132")


## ── 3) MIDI 导出→导入往返 ──────────────────────────────────────────

func _test_midi_roundtrip() -> void:
	var demo := SongModel.make_demo()
	var path := "user://test_midirt.mid"
	var err := MidiFile.export_song(demo, path)
	_check(err == OK, "MIDI 导出失败（%d）" % err)
	var back := MidiFile.import_file(path)
	_check(back != null, "MIDI 导入失败")
	if back == null:
		return
	_check(absf(back.bpm - demo.bpm) < 0.01, "BPM 往返不一致 %s" % back.bpm)
	_check(back.tracks.size() == demo.tracks.size(),
			"轨数不一致 %d != %d" % [back.tracks.size(), demo.tracks.size()])
	for t in mini(back.tracks.size(), demo.tracks.size()):
		var a := _note_key_list(demo.tracks[t]["notes"])
		var b := _note_key_list(back.tracks[t]["notes"])
		_check(back.tracks[t]["instrument"] == demo.tracks[t]["instrument"],
				"轨%d 音色往返不一致" % t)
		if a != b:
			_fails.append("轨%d 音符往返不一致（%d vs %d）" % [t, a.size(), b.size()])
	DirAccess.remove_absolute(path)


## (p,s,l) 多重集比较键；力度单独抽查（127 量化有舍入）
func _note_key_list(notes: Array) -> Array:
	var keys: Array = []
	for n in notes:
		keys.append("%d_%d_%d" % [n["p"], n["s"], n["l"]])
	keys.sort()
	return keys


func _test_midi_garbage() -> void:
	var path := "user://test_bad.mid"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("this is not a midi file at all........")
	f.close()
	_check(MidiFile.import_file(path) == null, "垃圾文件应返回 null")
	DirAccess.remove_absolute(path)


## ── 4) 循环区间 ────────────────────────────────────────────────────

func _test_loop_region() -> void:
	var s := SongModel.make_demo()
	var t := Transport.new()
	t.song = s  # bpm=96：0.5s = 3.2 tick
	t.loop_play = true
	t.loop_start = 16.0
	t.loop_end = 64.0
	t.play(0.0)
	_check(t.playing, "播放应启动")
	var dt := 0.5  # 0.5s = 3.2 tick；30 步 ≈ 96 tick，保证至少两次穿过 64 边界
	for i in 30:
		t._process(dt)
	_check(t.playing, "循环模式不应停止")
	_check(t.playhead >= 16.0 and t.playhead < 64.0,
			"循环应落在区间内，实际 %.2f" % t.playhead)
	t.stop()


func _test_transport_no_loop_stops_at_end() -> void:
	var s := SongModel.make_demo()
	var t := Transport.new()
	t.song = s
	t.play(0.0)
	var guard := 0
	while t.playing and guard < 20000:
		t._process(0.05)
		guard += 1
	_check(not t.playing, "非循环播放应自然停止")
	_check(t.playhead >= s.song_end_tick(), "停止时播放头应到曲末（%.1f vs %d）"
			% [t.playhead, s.song_end_tick()])


## ── 5) MusicXML 乐谱导出 ───────────────────────────────────────────

func _test_sheet_music() -> void:
	var demo := SongModel.make_demo()
	var xml := SheetMusic.build_xml(demo)
	var x := XMLParser.new()
	_check(x.open_buffer(xml.to_utf8_buffer()) == OK, "MusicXML 不是合法 XML")
	var parts := 0
	var chord_cnt := 0
	var per_minute := 0
	var cur_part := 0
	while x.read() == OK:
		if x.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		match x.get_node_name():
			"score-part":
				parts += 1
			"chord":
				chord_cnt += 1
			"per-minute":
				if x.read() == OK and x.get_node_type() == XMLParser.NODE_TEXT:
					per_minute = int(x.get_node_data().strip_edges())
			"part":
				if not x.is_empty():
					cur_part += 1
	_check(parts == 2, "MusicXML 应有 2 个声部，实际 %d" % parts)
	_check(chord_cnt == 24, "伴奏 12 组三和弦应有 24 个 <chord/>，实际 %d" % chord_cnt)
	_check(per_minute == 96, "速度元信息应为 96，实际 %d" % per_minute)
	var err := SheetMusic.export_song(demo, "user://test_score.musicxml")
	_check(err == OK, "MusicXML 落盘失败（%d）" % err)
	DirAccess.remove_absolute("user://test_score.musicxml")


func _test_sheet_music_split() -> void:
	# 时值分解：5 tick = 四分 + 16分（内部连线）；3 tick = 附点八分单值
	var d5 := SheetMusic._decompose(5)
	_check(d5.size() == 2 and d5[0]["dur"] == 4 and d5[1]["dur"] == 1, "5 tick 应分解为 4+1")
	_check(d5[0]["tie_start"] and not d5[0]["tie_end"], "首段应 tie start")
	_check(d5[1]["tie_end"] and not d5[1]["tie_start"], "末段应 tie end")
	var d3 := SheetMusic._decompose(3)
	_check(d3.size() == 1 and d3[0]["dot"], "3 tick 应为单值附点八分")
	# 跨小节切分：s=14, l=4 → 第 1 小节 [14,16) + 第 2 小节 [0,2)，两端带跨节 tie
	var segs := SheetMusic._split_measure({"s": 14, "l": 4, "pitches": [60]})
	_check(segs.size() == 2, "跨小节音符应切 2 段")
	if segs.size() == 2:
		_check(segs[0]["l"] == 2 and segs[1]["l"] == 2, "切段长度应为 2+2")
		_check(segs[0]["tie_start"] and segs[1]["tie_end"], "切段应带跨节连线")


## ── 6) Synth 声部分配（全忙时抢断最旧，但避开刚起音的声部） ─────────

func _test_synth_grab() -> void:
	if not InstrumentBank.ready_ok:
		return  # 音源未就绪时跳过（音色测试会等待）
	var now := Time.get_ticks_msec()
	# 打满全部声部（一次性衰减采样会持续播放）
	for i in Synth.POLYPHONY:
		Synth.play_note("钢琴", 40 + (i % 24), 0.3)
	var all_playing := true
	for p in Synth._players:
		if not p.playing:
			all_playing = false
			break
	_check(all_playing, "48 次连击后所有声部应在播（无丢触发）")
	for i in Synth.POLYPHONY:
		Synth._start_ms[i] = now - 1000 - i
	_check(Synth._grab() == Synth.POLYPHONY - 1, "应抢断最旧声部")
	for i in Synth.POLYPHONY:
		Synth._start_ms[i] = now - 10  # 全部刚起音 <80ms：仍必须返回有效声部
	_check(Synth._grab() >= 0, "极端连击下也必须有声部可用")
	Synth.stop_all()


## ── 7) UI 接线（撤销按钮 / 循环区同步 / MIDI 菜单存在） ────────────

func _test_ui_wiring() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	var ui: Control = ps.instantiate()
	add_child(ui)
	for i in 5:
		await get_tree().process_frame
	_check(ui.history is EditHistory, "history 未初始化")
	_check(ui._undo_btn.disabled and ui._redo_btn.disabled, "初始应不可撤销/重做")
	# 模拟一次编辑 → 按钮状态更新 → 撤销还原
	var n0: int = ui.song.track_notes(0).size()
	ui.song.add_note(0, 100, 300, 2)
	ui.history.push(ui.song)
	await get_tree().process_frame
	_check(not ui._undo_btn.disabled, "编辑后撤销按钮应可用")
	_check(ui._redo_btn.disabled, "编辑后重做按钮应不可用")
	ui._do_undo()
	await get_tree().process_frame
	_check(ui.song.track_notes(0).size() == n0, "UI 撤销后音符应还原")
	_check(not ui._redo_btn.disabled, "撤销后重做按钮应可用")
	ui._do_redo()
	await get_tree().process_frame
	_check(ui.song.track_notes(0).size() == n0 + 1, "UI 重做后音符应回来")
	# 循环区间同步：换工程后 SpinBox 覆盖整曲
	ui._switch_song(SongModel.make_demo())
	var bars := ceili(ui.song.song_end_tick() / 16.0)
	_check(int(ui._loop_b.value) == bars, "循环终点应随工程重置（%s vs %d）" % [ui._loop_b.value, bars])
	_check(absf(ui.transport.loop_end - bars * 16.0) < 0.01, "transport.loop_end 应同步")
	# 拖区间越界自纠：终点 ≤ 起点时强制 +1
	ui._loop_a.value = 3
	ui._loop_b.value = 3
	await get_tree().process_frame
	_check(ui._loop_b.value > ui._loop_a.value, "循环终点应被自动纠正到起点之后")
	_check(ui._midi_dlg != null and ui._midi_save_dlg != null, "MIDI 对话框未创建")
	_check(ui._score_dlg != null, "乐谱对话框未创建")
	# 切换音阶：自动启用辅助 + 两个键盘同步高亮（v0.2 修复"切音阶没反应"）
	ui._scale_chk.set_pressed_no_signal(false)
	ui._apply_scale_helper()
	_check(not ui.keyboard.scale_highlight, "关闭辅助后高亮应熄灭")
	ui._mode_opt.select(3)  # 五声大调
	ui._on_scale_picked()
	_check(ui._scale_chk.button_pressed, "选音阶应自动启用调性辅助")
	_check(ui.keyboard.scale_highlight and ui.mini_kb.scale_highlight, "两个键盘都应有高亮")
	_check(ui.keyboard.scale_notes == NoteKeys.SCALES["五声大调"], "音阶数据应更新")
	ui.transport.stop()
	ui.queue_free()
	await get_tree().process_frame


## ── 6) 新音色（电钢/八音盒）───────────────────────────────────────

func _test_new_instruments() -> void:
	# 首跑需全量合成（缓存版本升到 v3），给足等待
	var waited := 0.0
	while not InstrumentBank.ready_ok and waited < 90.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	_check(InstrumentBank.ready_ok, "音源库 90s 内未就绪（含新音色合成）")
	if not InstrumentBank.ready_ok:
		return
	for inst in ["电钢", "八音盒"]:
		for base in [36, 60, 84]:
			var r := InstrumentBank.sample_for(inst, base)
			_check(r.size() == 2, "音色 %s 基音 %d 无样本" % [inst, base])
	_check(InstrumentBank.INSTRUMENTS.size() == 6, "音色总数应为 6")
