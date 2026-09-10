class_name AnalysisPanel
extends Control
## 分析页：乐曲统计指标 + Krumhansl-Schmuckler 调性检测 + 音级分布直方图。
##
## 数据由 SongAnalysis 静态计算；本类只负责展示与"应用到调性辅助"回调。
## 直方图为单 Control 自绘（StyleBox 圆角条，脏刷新）。

signal apply_key(root: int, minor: bool)

const COL_TEXT := Color("cfd4dc")
const COL_DIM := Color("8f97a6")
const COL_BAR := Color("4fc3f7")
const COL_BAR_OFF := Color("3a4150")
const COL_ROOT := Color("ffb74d")

var song: SongModel

var _grid: GridContainer
var _key_label: Label
var _hist: PitchHistogram
var _chords: ChordTimeline
var _sections: SectionBar
var _suggest_label: Label
var _empty_label: Label
var _apply_btn: Button
var _last: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	add_child(pad)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("20242c")
	sb.border_color = Color("3a4150")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", sb)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var title := Label.new()
	title.text = "乐曲分析"
	title.add_theme_font_size_override("font_size", 15)
	head.add_child(title)
	var sub := Label.new()
	sub.text = "统计指标 · 调性检测 · 音级分布（时长×力度加权）"
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", COL_DIM)
	head.add_child(sub)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_apply_btn = Button.new()
	_apply_btn.text = "应用到调性辅助"
	_apply_btn.tooltip_text = "把检测出的调写入「辅助」面板并启用调性高亮"
	_apply_btn.focus_mode = Control.FOCUS_NONE
	_apply_btn.pressed.connect(func() -> void:
		if not _last.is_empty():
			apply_key.emit(_last["key"]["root"], _last["key"]["minor"]))
	head.add_child(_apply_btn)

	v.add_child(HSeparator.new())

	_empty_label = Label.new()
	_empty_label.text = "工程为空——去「演奏」弹几下，或到「编曲」画些音符，分析结果会出现在这里。"
	_empty_label.add_theme_color_override("font_color", COL_DIM)
	v.add_child(_empty_label)

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 6)
	v.add_child(_grid)

	_key_label = Label.new()
	_key_label.add_theme_font_size_override("font_size", 13)
	v.add_child(_key_label)

	var hist_cap := Label.new()
	hist_cap.text = "音级分布（0 = C）"
	hist_cap.add_theme_font_size_override("font_size", 11)
	hist_cap.add_theme_color_override("font_color", COL_DIM)
	v.add_child(hist_cap)
	_hist = PitchHistogram.new()
	_hist.custom_minimum_size = Vector2(0, 120)
	_hist.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_hist)

	# ── v0.3.0：和弦进行 / 曲式结构 / 智能建议 ──
	var chord_cap := Label.new()
	chord_cap.text = "和弦进行（逐小节 · 含罗马数字功能级）"
	chord_cap.add_theme_font_size_override("font_size", 11)
	chord_cap.add_theme_color_override("font_color", COL_DIM)
	v.add_child(chord_cap)
	_chords = ChordTimeline.new()
	_chords.custom_minimum_size = Vector2(0, 56)
	v.add_child(_chords)

	var sec_cap := Label.new()
	sec_cap.text = "曲式结构（按音级轮廓相似度分段）"
	sec_cap.add_theme_font_size_override("font_size", 11)
	sec_cap.add_theme_color_override("font_color", COL_DIM)
	v.add_child(sec_cap)
	_sections = SectionBar.new()
	_sections.custom_minimum_size = Vector2(0, 34)
	v.add_child(_sections)

	_suggest_label = Label.new()
	_suggest_label.add_theme_font_size_override("font_size", 12)
	_suggest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_suggest_label.text = "智能建议：—"
	_suggest_label.add_theme_color_override("font_color", COL_TEXT)
	v.add_child(_suggest_label)


## 重算并刷新显示（分析开销 O(音符数)，切页/编辑后调用）
func refresh() -> void:
	if song == null:
		return
	_last = SongAnalysis.analyze(song)
	var empty: bool = _last["empty"]
	_empty_label.visible = empty
	_apply_btn.visible = not empty
	_apply_btn.disabled = empty
	for c in _grid.get_children():
		c.queue_free()
	if empty:
		_key_label.text = ""
		_hist.set_data([], [])
		_chords.set_data([], 0, -1, false)
		_sections.set_data([], 0)
		_suggest_label.text = "智能建议：—"
		return
	var d := _last
	_stat("音符总数", str(d["note_count"]))
	_stat("曲长", "%d 小节 · %.1f 秒" % [d["bars"], d["dur_secs"]])
	_stat("音域", "%s – %s（跨 %d 半音）" % [
		NoteKeys.note_name(d["pitch_min"]), NoteKeys.note_name(d["pitch_max"]), d["pitch_span"]])
	_stat("音符密度", "%.2f 音/秒" % d["density"])
	_stat("平均力度", "%.2f" % d["avg_vel"])
	_stat("平均音长", "%.1f tick（1/16）" % d["avg_len"])
	_stat("最大同时音", str(d["max_poly"]))
	_stat("速度", "%d BPM" % int(d["bpm"]))
	for t in d["per_track"]:
		_stat("轨：%s" % t["name"], "%d 音符" % t["count"])
	var k: Dictionary = d["key"]
	_key_label.text = "检测调性：%s（与次优调相关度差 %d%%）" % [k["name"], k["confidence"]]
	_key_label.add_theme_color_override("font_color", COL_TEXT)
	_hist.set_data(d["pc_profile"], k["scale_pcs"], k["root"])

	# 和弦进行 / 结构 / 建议
	var chords := SongAnalysis.detect_chords(song, k["root"], k["minor"])
	_chords.set_data(chords, d["bars"], k["root"], k["minor"])
	var sections := SongAnalysis.detect_sections(song)
	_sections.set_data(sections, d["bars"])
	var sugg := SongAnalysis.suggest_next_chords(chords, k["root"], k["minor"])
	var sugg_names: Array = []
	for s in sugg:
		sugg_names.append("%s（%s）" % [s["name"], s["why"]])
	_suggest_label.text = "智能建议：下一和弦候选  %s" % ("、".join(sugg_names)
			if not sugg_names.is_empty() else "—（素材不足）")


func _stat(k: String, v: String) -> void:
	var kl := Label.new()
	kl.text = k
	kl.add_theme_color_override("font_color", COL_DIM)
	_grid.add_child(kl)
	var vl := Label.new()
	vl.text = v
	vl.add_theme_color_override("font_color", COL_TEXT)
	_grid.add_child(vl)


## ── 音级分布直方图 ─────────────────────────────────────────────────

class PitchHistogram extends Control:
	var _profile: Array = []
	var _scale_pcs: Array = []
	var _root := 0
	var _sb := {}  # color -> StyleBoxFlat（圆角条缓存）

	func set_data(profile: Array, scale_pcs: Array, root := 0) -> void:
		_profile = profile
		_scale_pcs = scale_pcs
		_root = root
		queue_redraw()

	func _style(col: Color) -> StyleBoxFlat:
		var key := col.to_html()
		if not _sb.has(key):
			var s := StyleBoxFlat.new()
			s.bg_color = col
			s.set_corner_radius_all(3)
			s.anti_aliasing = true
			_sb[key] = s
		return _sb[key]

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("1b1e24"))
		if _profile.is_empty() or size.x < 40.0:
			return
		var peak := 0.0001
		for v in _profile:
			peak = maxf(peak, v)
		var m_l := 6.0
		var m_b := 18.0
		var m_t := 6.0
		var gap := 5.0
		var bw: float = (size.x - m_l * 2.0 - gap * 11.0) / 12.0
		var base_y: float = size.y - m_b
		var font := ThemeDB.fallback_font
		for i in 12:
			var h: float = maxf(2.0, _profile[i] / peak * (base_y - m_t))
			var x: float = m_l + i * (bw + gap)
			var col := COL_BAR if i in _scale_pcs else COL_BAR_OFF
			if i == _root:
				col = COL_ROOT
			draw_style_box(_style(col), Rect2(x, base_y - h, bw, h))
			var pc_name: String = NoteKeys.SHARP_NAMES[i]
			var tw := font.get_string_size(pc_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			var tcol := Color("dfe3ea") if i == _root else Color("8f97a6")
			draw_string(font, Vector2(x + bw * 0.5 - tw * 0.5, size.y - 5.0),
					pc_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, tcol)
		draw_rect(Rect2(0, 0, size.x, size.y), Color("3a4150"), false, 1.0, true)


## ── 和弦进行时间轴（v0.3.0） ───────────────────────────────────────

class ChordTimeline extends Control:
	var _chords: Array = []
	var _bars := 0
	var _key_root := -1
	var _minor := false

	func set_data(chords: Array, bars: int, key_root: int, minor: bool) -> void:
		_chords = chords
		_bars = bars
		_key_root = key_root
		_minor = minor
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("1b1e24"))
		if _chords.is_empty() or _bars <= 0 or size.x < 40.0:
			return
		var cw: float = size.x / _bars
		var font := ThemeDB.fallback_font
		for c in _chords:
			if c["root"] < 0:
				continue
			var r := Rect2(c["bar"] * cw + 1.0, 6.0, maxf(cw - 2.0, 4.0), size.y - 18.0)
			var is_tonic: bool = _key_root >= 0 and c["root"] == _key_root
			var col := Color("ffb74d") if is_tonic else Color("4fc3f7")
			col.a = 0.18
			draw_rect(r, col, true)
			draw_rect(r, Color(0, 0, 0, 0.4), false, 1.0, true)
			if cw > 26.0:
				draw_string(font, Vector2(r.position.x + 3.0, r.position.y + 13.0),
						c["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("dfe3ea"))
				if c["roman"] != "" and cw > 34.0:
					draw_string(font, Vector2(r.position.x + 3.0, r.position.y + 25.0),
							c["roman"], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("8f97a6"))
		# 小节号（每 4 小节标一次）
		var step := maxi(ceili(4.0 / (cw / 40.0)) * 4, 4)
		for b in range(0, _bars, step):
			draw_string(font, Vector2(b * cw + 2.0, size.y - 3.0), str(b + 1),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("5c6472"))
		draw_rect(Rect2(0, 0, size.x, size.y), Color("3a4150"), false, 1.0, true)


## ── 曲式结构条（v0.3.0） ───────────────────────────────────────────

class SectionBar extends Control:
	const LETTER_COLORS := [
		Color("4fc3f7"), Color("aed581"), Color("ffb74d"), Color("ce93d8"),
		Color("ff8a80"), Color("80cbc4"), Color("fff176"), Color("b0bec5"),
	]
	var _sections: Array = []
	var _bars := 0

	func set_data(sections: Array, bars: int) -> void:
		_sections = sections
		_bars = bars
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("1b1e24"))
		if _sections.is_empty() or _bars <= 0 or size.x < 40.0:
			draw_string(ThemeDB.fallback_font, Vector2(6.0, size.y * 0.6),
					"素材不足，无法分段", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("5c6472"))
			return
		var cw: float = size.x / _bars
		var font := ThemeDB.fallback_font
		for s in _sections:
			var x0: float = s["start_bar"] * cw
			var x1: float = s["end_bar"] * cw
			var letter: String = s["label"]
			var ci := 0
			for i in letter.length():
				ci = (ci * 31 + letter.unicode_at(i)) % LETTER_COLORS.size()
			var col: Color = LETTER_COLORS[ci]
			col.a = 0.55
			draw_rect(Rect2(x0 + 1.0, 4.0, maxf(x1 - x0 - 2.0, 3.0), size.y - 8.0), col, true)
			if x1 - x0 > 18.0:
				draw_string(font, Vector2(x0 + 5.0, size.y * 0.62), letter,
						HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("10131a"))
		draw_rect(Rect2(0, 0, size.x, size.y), Color("3a4150"), false, 1.0, true)
