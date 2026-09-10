extends Node
## v0.3.1 无头回归测试：轨道预设存取 / MIDI 自定义映射
##
## 运行：godot --headless --path . res://tests/smoke_v031.tscn

var _fails: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_track_presets()
	_test_gm_map_override()
	if _fails.is_empty():
		print("[Test] ALL PASS")
		get_tree().quit(0)
	else:
		print("[Test] FAIL: ", ", ".join(_fails))
		get_tree().quit(1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


func _test_track_presets() -> void:
	# 清理旧文件，保证测试确定性
	if FileAccess.file_exists(TrackPresets.PATH):
		DirAccess.remove_absolute(TrackPresets.PATH)
	var trk := SongModel.make_track("我的弦乐", "柔弦", 2)
	trk["volume"] = 0.55
	trk["pan"] = -0.4
	trk["reverb"] = 0.7
	trk["delay"] = 0.2
	var name := TrackPresets.save_track(trk)
	_check(name == "我的弦乐", "保存应返回预设名")
	var all := TrackPresets.list_all()
	_check(all.has("我的弦乐"), "预设应已落盘")
	_check(all["我的弦乐"]["instrument"] == "柔弦", "预设音色不符")
	_check(absf(all["我的弦乐"]["reverb"] - 0.7) < 0.001, "预设发送量不符")
	# 应用到另一轨：保留 name/notes/color
	var target := SongModel.make_track("目标", "芯片", 0)
	target["notes"] = [{"p": 60, "s": 0, "l": 4, "v": 0.8}]
	_check(TrackPresets.apply_to(target, "我的弦乐"), "应用预设应成功")
	_check(target["name"] == "目标", "应用不应改轨名")
	_check((target["notes"] as Array).size() == 1, "应用不应动音符")
	_check(target["instrument"] == "柔弦" and absf(target["pan"] - (-0.4)) < 0.001,
			"应用后音色/声像应来自预设")
	_check(TrackPresets.apply_to(target, "不存在") == false, "应用不存在的预设应失败")
	TrackPresets.delete_preset("我的弦乐")
	_check(not TrackPresets.list_all().has("我的弦乐"), "删除预设后应消失")
	if FileAccess.file_exists(TrackPresets.PATH):
		DirAccess.remove_absolute(TrackPresets.PATH)


func _test_gm_map_override() -> void:
	# 清理残留映射（保证"无映射"基线成立）
	if FileAccess.file_exists(MidiFile.GM_MAP_PATH):
		DirAccess.remove_absolute(MidiFile.GM_MAP_PATH)
	MidiFile._gm_map_loaded = false
	MidiFile._gm_map = {}
	# 无映射文件 → 内置启发式
	_check(MidiFile._program_to_inst(0, 0) == "钢琴", "无映射时 prog0 应为钢琴")
	_check(MidiFile._program_to_inst(0, 9) == "芯片", "无映射时通道 10 应为芯片")
	# 写映射文件：chan9 → 鼓组；prog 0 → 贝斯；非法值应回退
	var f := FileAccess.open(MidiFile.GM_MAP_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"chan9": "鼓组",
		"programs": {"0": "贝斯", "200": "不存在的音色"},
	}))
	f.close()
	# 重置静态缓存（重新加载）
	MidiFile._gm_map_loaded = false
	MidiFile._gm_map = {}
	_check(MidiFile._program_to_inst(0, 9) == "鼓组", "映射后通道 10 应为鼓组")
	_check(MidiFile._program_to_inst(0, 0) == "贝斯", "映射后 prog0 应为贝斯")
	_check(MidiFile._program_to_inst(200, 0) == "钢琴",
			"非法映射值应回退启发式（实际 %s）" % MidiFile._program_to_inst(200, 0))
	_check(MidiFile._program_to_inst(4, 0) == "电钢", "未映射程序号仍走启发式")
	# 清理
	DirAccess.remove_absolute(MidiFile.GM_MAP_PATH)
	MidiFile._gm_map_loaded = false
	MidiFile._gm_map = {}
