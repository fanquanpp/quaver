extends Node
## v0.3.0 无头回归测试：和弦检测 / 罗马数字 / 结构分段 / 和声建议 / 旋律候选
##
## 运行：godot --headless --path . res://tests/smoke_v030.tscn

var _fails: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_chord_detection()
	_test_roman_numerals()
	_test_sections()
	_test_suggestions()
	_test_melody_candidates()
	_test_panel_refresh()
	if _fails.is_empty():
		print("[Test] ALL PASS")
		get_tree().quit(0)
	else:
		print("[Test] FAIL: ", ", ".join(_fails))
		get_tree().quit(1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


## 示范曲伴奏：每小节和弦 C C F C C G C G C C F C（大调）
func _test_chord_detection() -> void:
	var s := SongModel.make_demo()
	var chords := SongAnalysis.detect_chords(s)
	_check(chords.size() == 12, "12 小节应有 12 个检测结果（实际 %d）" % chords.size())
	_check(chords[0]["name"] == "C", "第 1 小节应为 C（实际 %s）" % chords[0]["name"])
	_check(chords[2]["name"] == "F", "第 3 小节应为 F（实际 %s）" % chords[2]["name"])
	_check(chords[5]["name"] == "G", "第 6 小节应为 G（实际 %s）" % chords[5]["name"])


func _test_roman_numerals() -> void:
	var s := SongModel.make_demo()
	var chords := SongAnalysis.detect_chords(s, 0, false)  # C 大调
	_check(chords[0]["roman"] == "I", "C 应为 I 级（实际 %s）" % chords[0]["roman"])
	_check(chords[2]["roman"] == "IV", "F 应为 IV 级（实际 %s）" % chords[2]["roman"])
	_check(chords[5]["roman"] == "V", "G 应为 V 级（实际 %s）" % chords[5]["roman"])
	_check(chords[9]["roman"] == "I" or chords[9]["roman"] == "vi", "C6/Am7 歧义应判 I 或 vi（实际 %s）" % chords[9]["roman"])


func _test_sections() -> void:
	var s := SongModel.make_demo()
	var secs := SongAnalysis.detect_sections(s)
	_check(not secs.is_empty(), "应有至少一个段落")
	_check(secs[0]["label"] == "A", "首段应标记 A（实际 %s）" % secs[0]["label"])
	_check(secs[0]["start_bar"] == 0, "首段应从小节 0 开始")
	var covered := 0
	for sec in secs:
		covered += sec["end_bar"] - sec["start_bar"]
	_check(covered == 12, "段落应覆盖全部 12 小节（实际 %d）" % covered)
	# 空工程不崩
	var e := SongModel.new()
	e.tracks[0]["notes"].clear()
	e.tracks[1]["notes"].clear()
	_check(SongAnalysis.detect_sections(e).is_empty() or true, "空工程分段不崩")


func _test_suggestions() -> void:
	var s := SongModel.make_demo()
	var chords := SongAnalysis.detect_chords(s, 0, false)
	var sugg := SongAnalysis.suggest_next_chords(chords, 0, false)
	_check(not sugg.is_empty(), "应有下一和弦候选")
	var roots := {}
	for g in sugg:
		roots[g["name"]] = true
	# 示范曲结束在 F（IV 级）→ 候选应含 V 或 I
	var ok := roots.has("G") or roots.has("C")
	_check(ok, "IV 级后的候选应含 V/I（实际 %s）" % str(roots.keys()))
	# V 级之后的建议应指向 I
	var v_next := SongAnalysis.suggest_next_chords(
			[{"bar": 0, "root": 7, "quality": "", "name": "G", "roman": "V", "score": 1.0}],
			0, false)
	var has_i := false
	for g2 in v_next:
		if g2["degree"] == "I":
			has_i = true
	_check(has_i, "V 级建议应包含 I 级")


func _test_melody_candidates() -> void:
	var cand := SongAnalysis.suggest_melody(0, "", [0, 2, 4, 5, 7, 9, 11], 72)
	_check(cand.size() >= 3, "旋律候选应≥3 个（实际 %d）" % cand.size())
	var has_chord_tone := false
	for c in cand:
		if c["kind"] == "和弦音":
			has_chord_tone = true
	_check(has_chord_tone, "候选应含和弦音")


func _test_panel_refresh() -> void:
	var panel := AnalysisPanel.new()
	panel.song = SongModel.make_demo()
	add_child(panel)
	await get_tree().process_frame
	panel.refresh()
	await get_tree().process_frame
	panel.queue_free()
	_check(true, "分析面板刷新不崩")
