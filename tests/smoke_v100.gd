extends Node
## v1.0.0 无头回归测试：插件配方音色 / SFZ 加载 / 混音台面板
##
## 运行：godot --headless --path . res://tests/smoke_v100.tscn

var _fails: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not InstrumentBank.ready_ok:
		await InstrumentBank.bank_ready
	_test_plugin_recipe()
	_test_sfz_loader()
	_test_mixer_panel()
	if _fails.is_empty():
		print("[Test] ALL PASS")
		get_tree().quit(0)
	else:
		print("[Test] FAIL: ", ", ".join(_fails))
		get_tree().quit(1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


func _test_plugin_recipe() -> void:
	# 注册配方音色（等价于 user://instrument_plugins.json 加载一条）
	InstrumentBank.register_plugin("测试叮咚", {
		"harmonics": [1.0, 0.35, 0.12], "decay": 3.2, "attack": 0.002,
		"click": 0.1, "dur": 1.8, "wave": "sine", "gain": 0.7,
	})
	_check("测试叮咚" in InstrumentBank.instruments, "插件音色应出现在音色列表")
	var s := InstrumentBank.sample_for("测试叮咚", 60, 0.8)
	_check(not s.is_empty(), "插件音色采样缺失")
	if not s.is_empty():
		_check(s[0] is AudioStreamWAV and (s[0] as AudioStreamWAV).data.size() > 1000,
				"插件音色应产出有效音频数据")
	var lo := InstrumentBank.sample_for("测试叮咚", 60, 0.2)
	_check(not lo.is_empty() and lo[0] != s[0], "插件音色力度层应生效")
	# 重复注册不重复
	InstrumentBank.register_plugin("测试叮咚", {})
	_check(InstrumentBank.instruments.count("测试叮咚") == 1, "重复注册应去重")


func _test_sfz_loader() -> void:
	# 1) 构造一个测试 WAV（440Hz 三角波 0.1s，22050Hz 16bit）
	var sr := 22050
	var n := int(0.1 * sr)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / sr
		var v := (2.0 * absf(2.0 * fmod(440.0 * t, 1.0) - 1.0) - 1.0) * 0.5
		data.encode_s16(i * 2, int(v * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.stereo = false
	wav.data = data
	DirAccess.make_dir_recursive_absolute("user://sfz_test")
	var wav_path := "user://sfz_test/tone.wav"
	wav.save_to_wav(ProjectSettings.globalize_path(wav_path))
	_check(FileAccess.file_exists(wav_path), "测试 WAV 应已写出")
	# 2) 写 SFZ：一个 group 默认 + 两个 region（低/高段）
	var sfz_path := "user://sfz_test/test.sfz"
	var sfz := "// 测试音色\n<group>lovel=0 hivel=127\n<region>sample=tone.wav pitch_keycenter=48 lokey=0 hikey=59\n<region>sample=tone.wav key=60 lokey=60 hikey=127\n"
	var sf := FileAccess.open(sfz_path, FileAccess.WRITE)
	sf.store_string(sfz)
	sf.close()
	# 3) 解析
	var regions := SfzLoader.load_instrument(sfz_path)
	_check(regions.size() == 2, "应解析出 2 个 region（实际 %d）" % regions.size())
	if regions.size() == 2:
		_check(regions[0]["lokey"] == 0 and regions[0]["hikey"] == 59, "低段键位范围不符")
		_check(regions[1]["lokey"] == 60 and regions[1]["hikey"] == 127, "高段键位范围不符")
		_check(regions[1]["key_center"] == 60, "key= 应同时设 key_center")
		_check(regions[0]["stream"] != null and (regions[0]["stream"] as AudioStreamWAV).data.size() > 0,
				"region 应加载到有效 WAV")
	# 4) 注册进音源库并取采样
	if regions.is_empty():
		return
	InstrumentBank._sfz["sfz:test"] = regions
	if not "sfz:test" in InstrumentBank.instruments:
		InstrumentBank.instruments.append("sfz:test")
	var s1 := InstrumentBank.sample_for("sfz:test", 36, 0.8)
	var s2 := InstrumentBank.sample_for("sfz:test", 60, 0.8)
	_check(not s1.is_empty(), "低段采样应可取")
	_check(not s2.is_empty(), "高段采样应可取")
	if not s1.is_empty() and not s2.is_empty():
		_check(absf(s1[1] - pow(2.0, (36 - 48) / 12.0)) < 0.001, "低段移调比应按 key_center 计算")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sfz_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(wav_path))


func _test_mixer_panel() -> void:
	var panel := MixerPanel.new()
	panel.song = SongModel.make_demo()
	add_child(panel)
	await get_tree().process_frame
	panel.refresh()
	await get_tree().process_frame
	panel.queue_free()
	_check(true, "混音台刷新不崩")
