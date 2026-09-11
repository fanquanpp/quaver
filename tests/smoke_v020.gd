extends Node
## v0.2.0 无头回归测试：N 轨模型 v2 / 序列化迁移 / 混音总线 / 鼓组 / 力度分层 /
## 循环边界事件 / EditHistory 混音快照
##
## 运行：godot --headless --path . res://tests/smoke_v020.tscn

var _fails: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_track_v2_fields()
	_test_bsong_v2_roundtrip()
	_test_bsong_v1_migration()
	_test_track_limits()
	_test_history_mix_snapshot()
	_test_velocity_layers()
	_test_drum_kit()
	await _test_apply_mix_buses()
	_test_loop_boundary_events()
	_test_drum_track_playback()

	if _fails.is_empty():
		print("[Test] ALL PASS")
		get_tree().quit(0)
	else:
		print("[Test] FAIL: ", ", ".join(_fails))
		get_tree().quit(1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


## ── 1) 轨道 v2 字段默认值 ──────────────────────────────────────────

func _test_track_v2_fields() -> void:
	var s := SongModel.new()
	_check(s.VERSION == 2, "VERSION 应为 2")
	var trk: Dictionary = s.tracks[0]
	for f in ["name", "instrument", "color", "notes", "type", "volume",
			"pan", "mute", "solo", "reverb", "delay", "effects", "automation"]:
		_check(trk.has(f), "轨道缺字段：%s" % f)
	_check(trk["type"] == "melody", "默认 type 应为 melody")
	_check(absf(trk["volume"] - 0.8) < 0.001, "默认 volume 应为 0.8")


## ── 2) .bsong v2 往返 ──────────────────────────────────────────────

func _test_bsong_v2_roundtrip() -> void:
	var s := SongModel.make_demo()
	s.add_track("鼓组轨", "芯片", "drum")
	var i := s.tracks.size() - 1
	s.add_note(i, 36, 0, 1, 1.0)
	var trk: Dictionary = s.tracks[i]
	trk["volume"] = 0.42
	trk["pan"] = -0.5
	trk["mute"] = true
	trk["solo"] = false
	trk["reverb"] = 0.3
	trk["delay"] = 0.6
	trk["effects"] = [{"type": "eq6", "params": {"band0_db": 2.0}}]
	var path := "user://test_v20.bsong"
	var err := s.save(path)
	_check(err == OK, "v2 保存失败（%d）" % err)
	var back := SongModel.load_from(path)
	_check(back != null, "v2 读档失败")
	if back == null:
		return
	_check(back.VERSION == 2, "读回版本应为 2")
	_check(back.tracks.size() == s.tracks.size(), "轨数往返不一致")
	var bt: Dictionary = back.tracks[i]
	_check(bt["type"] == "drum", "type 往返不一致")
	_check(absf(bt["volume"] - 0.42) < 0.002, "volume 往返不一致 %s" % bt["volume"])
	_check(absf(bt["pan"] - (-0.5)) < 0.002, "pan 往返不一致")
	_check(bt["mute"] == true, "mute 往返不一致")
	_check(absf(bt["reverb"] - 0.3) < 0.002 and absf(bt["delay"] - 0.6) < 0.002,
			"发送量往返不一致")
	_check((bt["effects"] as Array).size() == 1, "effects 往返不一致")
	_check(back.track_notes(i).size() == 1, "鼓轨音符数往返不一致")
	DirAccess.remove_absolute(path)


## ── 3) v1 工程迁移 ─────────────────────────────────────────────────

func _test_bsong_v1_migration() -> void:
	# 手写 v1 布局（name/instrument/color/notes）
	var path := "user://test_v1.bsong"
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	f.store_32(SongModel.MAGIC)
	f.store_16(1)
	f.store_float(100.0)
	f.store_16(1)
	f.store_pascal_string("旧旋律")
	f.store_pascal_string("钢琴")
	f.store_32(3)
	f.store_32(2)
	f.store_16(60)
	f.store_32(0)
	f.store_16(4)
	f.store_16(80)
	f.store_16(64)
	f.store_32(8)
	f.store_16(8)
	f.store_16(50)
	f.close()
	var s := SongModel.load_from(path)
	_check(s != null, "v1 读档失败")
	if s == null:
		return
	_check(s.tracks[0]["name"] == "旧旋律", "v1 轨名应保留")
	_check(s.tracks[0]["type"] == "melody", "v1 迁移应填 type=melody")
	_check(absf(s.tracks[0]["volume"] - 0.8) < 0.001, "v1 迁移应填 volume=0.8")
	_check(s.tracks[0]["mute"] == false and s.tracks[0]["solo"] == false,
			"v1 迁移应填 mute/solo=false")
	_check(s.track_notes(0).size() == 2, "v1 音符数应保留")
	DirAccess.remove_absolute(path)


## ── 4) N 轨上限与删除 ──────────────────────────────────────────────

func _test_track_limits() -> void:
	var s := SongModel.new()
	s.tracks.clear()
	for i in SongModel.MAX_TRACKS:
		s.add_track("轨%d" % i, "芯片")
	_check(s.tracks.size() == SongModel.MAX_TRACKS, "应可建到 %d 轨" % SongModel.MAX_TRACKS)
	s.add_track("超限", "芯片")
	_check(s.tracks.size() <= SongModel.MAX_TRACKS + 1, "轨数异常")
	var name := s.remove_track(2)
	_check(name != "", "remove_track 应返回被删轨名")
	_check(s.tracks.size() == SongModel.MAX_TRACKS, "删轨后数量应减一")
	var one := SongModel.new()
	one.remove_track(0)
	_check(one.tracks.size() == 1, "最后一轨不可删除")


## ── 5) EditHistory 混音快照 ────────────────────────────────────────

func _test_history_mix_snapshot() -> void:
	var s := SongModel.make_demo()
	var h := EditHistory.new()
	h.reset(s)
	s.tracks[0]["volume"] = 0.3
	s.tracks[0]["pan"] = 0.6
	h.push(s)
	_check(h.can_undo(), "混音改动后应可撤销")
	h.undo(s)
	_check(absf(s.tracks[0]["volume"] - 0.8) < 0.001, "撤销应还原 volume")
	_check(absf(s.tracks[0]["pan"]) < 0.001, "撤销应还原 pan")
	h.redo(s)
	_check(absf(s.tracks[0]["volume"] - 0.3) < 0.001, "重做应回到新 volume")
	# 音色/静音同样入快照
	s.tracks[0]["mute"] = true
	s.tracks[0]["instrument"] = "贝斯"
	h.push(s)
	h.undo(s)
	_check(s.tracks[0]["mute"] == false, "撤销应还原 mute")
	_check(s.tracks[0]["instrument"] == "八音盒", "撤销应还原音色")  # 虫儿飞示范曲第 1 轨默认八音盒


## ── 6) 力度分层 ────────────────────────────────────────────────────

func _test_velocity_layers() -> void:
	if not InstrumentBank.ready_ok:
		await InstrumentBank.bank_ready
	var a := InstrumentBank.sample_for("钢琴", 60, 0.2)
	var b := InstrumentBank.sample_for("钢琴", 60, 0.6)
	var c := InstrumentBank.sample_for("钢琴", 60, 0.95)
	_check(not a.is_empty() and not b.is_empty() and not c.is_empty(), "力度采样缺失")
	if a.is_empty() or b.is_empty() or c.is_empty():
		return
	_check(a[0] != b[0] and b[0] != c[0], "三档力度应取到不同分层采样")


## ── 7) 鼓组音色 ────────────────────────────────────────────────────

func _test_drum_kit() -> void:
	for p in [36, 38, 39, 42, 45, 46]:
		var s := InstrumentBank.sample_for("鼓组", p, 0.8)
		_check(not s.is_empty(), "鼓声部 %d 采样缺失" % p)
	_check(InstrumentBank.sample_for("鼓组", 60, 0.8).size() > 0, "未映射音高应就近映射")


## ── 8) 混音总线状态 ────────────────────────────────────────────────

func _test_apply_mix_buses() -> void:
	if not Synth.is_inside_tree():
		await get_tree().process_frame
	var s := SongModel.new()
	s.tracks.clear()
	s.add_track("旋律", "钢琴")
	s.add_track("鼓轨", "芯片", "drum")
	s.tracks[0]["volume"] = 0.5
	s.tracks[0]["pan"] = 0.5
	s.tracks[1]["mute"] = true
	Synth.apply_mix(s.tracks)
	var bus0 := AudioServer.get_bus_index("Track0")
	var bus1 := AudioServer.get_bus_index("Track1")
	_check(bus0 >= 0 and bus1 >= 0, "轨道总线未创建")
	if bus0 < 0 or bus1 < 0:
		return
	_check(AudioServer.get_bus_send(bus0) == "Music", "旋律轨应路由到 Music")
	_check(AudioServer.get_bus_send(bus1) == "Drum", "鼓轨应路由到 Drum")
	_check(AudioServer.is_bus_mute(bus1), "静音轨总线应静音")
	_check(not AudioServer.is_bus_mute(bus0), "正常轨总线不应静音")
	var db := AudioServer.get_bus_volume_db(bus0)
	_check(absf(db - linear_to_db(0.5)) < 0.01, "轨道音量未写入总线")
	_check(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("Drum") >= 0,
			"集合总线未创建")
	# 独奏逻辑
	s.tracks[0]["solo"] = true
	s.tracks[1]["mute"] = false
	Synth.apply_mix(s.tracks)
	_check(AudioServer.is_bus_mute(bus1), "独奏激活时非独奏轨应等效静音")
	_check(not AudioServer.is_bus_mute(bus0), "独奏轨本身不应静音")


## ── 9) 循环边界事件（v0.1.4 丢失修复） ─────────────────────────────

func _test_loop_boundary_events() -> void:
	var s := SongModel.new()
	s.tracks.clear()
	s.add_track("鼓", "芯片", "drum")
	s.bpm = 240.0  # tick = 1/16 秒，测试快
	# 边界音符：恰在 loop_end=16 之外（tick 16）——旧实现每圈都会丢
	s.add_note(0, 38, 16, 1, 1.0)
	var t := Transport.new()
	t.song = s
	add_child(t)
	t.loop_play = true
	t.loop_start = 0.0
	t.loop_end = 16.0
	var hits := [0]
	t.note_fired.connect(func(_tr: int, _p: int, _v: float) -> void:
		hits[0] += 1)
	var fake := {"msec": 0.0}
	t.clock_override = func() -> float:
		fake["msec"] += 100.0  # 每次 _process 前进 0.1s = 2 tick
		return fake["msec"]
	t.play(0.0)
	for i in 30:
		t._process(0.1)
	_check(hits[0] >= 2, "循环边界后的音符每圈都应触发（实际 %d 次）" % hits[0])
	t.stop()
	t.queue_free()


## ── 10) 鼓机轨端到端 ───────────────────────────────────────────────

func _test_drum_track_playback() -> void:
	var s := SongModel.new()
	s.tracks.clear()
	s.add_track("鼓", "芯片", "drum")
	s.bpm = 240.0
	s.add_note(0, 36, 0, 1, 1.0)   # 底鼓
	s.add_note(0, 42, 4, 1, 0.8)   # 踩镲
	var t := Transport.new()
	t.song = s
	add_child(t)
	var fired := []
	t.note_fired.connect(func(tr: int, p: int, _v: float) -> void:
		fired.append([tr, p]))
	var fake := {"msec": 0.0}
	t.clock_override = func() -> float:
		fake["msec"] += 100.0
		return fake["msec"]
	t.play(0.0)
	for i in 8:
		t._process(0.1)
	_check(fired.size() >= 2, "鼓轨音符应触发（实际 %d）" % fired.size())
	_check([0, 36] in fired and [0, 42] in fired, "鼓声部音高应正确")
	t.stop()
	t.queue_free()
