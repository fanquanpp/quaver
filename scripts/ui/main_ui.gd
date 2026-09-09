extends Control
## 编趣 BianQu —— 根界面
##
## UI 由代码构建（工具类应用便于迭代）；两个模式页：
##   演奏 = 屏幕大键盘（电脑键盘/鼠标弹奏 + 和弦模式）
##   编曲 = 钢琴卷帘（鼠标编辑 + 弹奏录制量化 + 幽灵音符 + 调性辅助）

const DEFAULT_DIR := "user://songs"
const AUTOSAVE_PATH := "user://autosave.bsong"

# ── 视觉令牌（全界面统一间距/描边，避免"各画各的"） ─────────────────
const GAP_X := 8      # 工具栏功能组之间的水平间距
const GAP_Y := 4      # 纵向容器行距
const COL_PANEL_BG := Color("262b33")
const COL_BORDER := Color("3a4150")
const COL_BORDER_HI := Color("4a5468")
const COL_BTN := Color("2b313b")
const COL_BTN_HOVER := Color("343c48")
const COL_BTN_DOWN := Color("232830")
const COL_TEXT := Color("dfe3ea")
const COL_TEXT_DIM := Color("8f97a6")

var song: SongModel
var transport: Transport

var keyboard: PianoKeyboard
var mini_kb: PianoKeyboard   # 编曲页底部迷你键盘（VSplit 可调区域）
var roll: PianoRoll
var analysis: AnalysisPanel
var tabs: TabContainer

var _sel_track := 0
var _chord_mode := false
var _held := {}          # midi -> true（电脑键盘按住）
var _rec_pending := {}   # midi -> note（录制中的音符）

# 控件引用
var _play_btn: Button
var _stop_btn: Button
var _rec_btn: Button
var _loop_chk: CheckButton
var _follow_chk: CheckButton
var _rain: NoteRain
var _zoom_lab: Label
var _bpm_spin: SpinBox
var _pos_label: Label
var _vol_slider: HSlider
var _status_label: Label
var _oct_label: Label
var _scale_chk: CheckButton
var _key_opt: OptionButton
var _mode_opt: OptionButton
var _chord_chk: CheckButton
var _labels_chk: CheckButton
var _snap_opt: OptionButton
var _len_spin: SpinBox
var _kb_scale: HSlider
var _kb_span: OptionButton
var _track_btns: Array[Button] = []
var _inst_opt: OptionButton
var _export_btn: Button

var _hbar: HScrollBar
var _vbar: VScrollBar

var _save_dlg: FileDialog
var _open_dlg: FileDialog
var _wav_dlg: FileDialog
var _rec_effect: AudioEffectRecord
var _exporting := false

var _icons_tex: Texture2D


func _ready() -> void:
	get_tree().auto_accept_quit = false
	_load_or_demo()
	transport = Transport.new()
	transport.song = song
	add_child(transport)
	transport.started.connect(_update_status)
	transport.stopped.connect(_on_transport_stopped)
	# 走带音符 → 发声（v0.1.3 修复"播放无声"：此前 note_fired 无人订阅）
	transport.note_fired.connect(_on_note_fired)
	_build_ui()
	_apply_scale_helper()
	_refresh_track_ui()
	_update_status()
	InstrumentBank.bank_ready.connect(_update_status)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		DirAccess.make_dir_recursive_absolute(DEFAULT_DIR)
		song.save(AUTOSAVE_PATH)
		get_tree().quit()


## ── 工程载入 ───────────────────────────────────────────────────────

func _load_or_demo() -> void:
	if FileAccess.file_exists(AUTOSAVE_PATH):
		var s := SongModel.load_from(AUTOSAVE_PATH)
		if s != null:
			song = s
			print("[Main] 已恢复上次自动保存的工程")
			return
	song = SongModel.make_demo()


func _switch_song(new_song: SongModel) -> void:
	if transport.playing:
		transport.stop()
	song = new_song
	transport.song = song
	roll.song = song
	roll.scroll_to_start()
	if analysis != null:
		analysis.song = song
		analysis.refresh()
	_bpm_spin.set_value_no_signal(song.bpm)
	_sel_track = clampi(_sel_track, 0, song.tracks.size() - 1)
	roll.track_idx = _sel_track
	_refresh_track_ui()
	transport.seek(0.0)


## ── UI 构建 ────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = _build_theme()
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", GAP_Y)
	add_child(vb)

	vb.add_child(_build_header())
	vb.add_child(_build_options())
	_build_tabs(vb)

	_icons_tex = load("res://assets/sprites/icons.png") if ResourceLoader.exists("res://assets/sprites/icons.png") else null
	_apply_icons()
	_build_dialogs()
	Synth.set_volume(0.8)


func _icon(i: int) -> Texture2D:
	if _icons_tex == null:
		return null
	var t := AtlasTexture.new()
	t.atlas = _icons_tex
	t.region = Rect2(i * 32, 0, 32, 32)
	return t


func _apply_icons() -> void:
	if _icons_tex == null:
		return
	_play_btn.icon = _icon(0)
	_stop_btn.icon = _icon(1)
	_rec_btn.icon = _icon(2)
	_export_btn.icon = _icon(5)


func _mk_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_constant_override("icon_max_width", 20)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _mk_check(text: String, on: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(cb)
	return c


func _build_header() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)

	if ResourceLoader.exists("res://assets/sprites/logo.png"):
		var logo := TextureRect.new()
		logo.texture = load("res://assets/sprites/logo.png")
		logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		logo.custom_minimum_size = Vector2(32, 32)
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hb.add_child(logo)
	var title := Label.new()
	title.text = "编趣"
	title.add_theme_font_size_override("font_size", 16)
	hb.add_child(title)

	_play_btn = _mk_button("播放", _on_play)
	_play_btn.tooltip_text = "播放（快捷键：空格）"
	_stop_btn = _mk_button("停止", _on_stop)
	_stop_btn.tooltip_text = "停止（再按一次回到开头）"
	_rec_btn = _mk_button("录制", _on_rec_toggle)
	_rec_btn.toggle_mode = true
	_rec_btn.tooltip_text = "录制：弹奏自动量化记入当前轨"
	_loop_chk = _mk_check("循环", false, _on_loop_toggle)
	_loop_chk.tooltip_text = "到达曲末自动从头循环"

	_vol_slider = HSlider.new()
	_vol_slider.min_value = 0.0
	_vol_slider.max_value = 1.0
	_vol_slider.step = 0.05
	_vol_slider.value = 0.8
	_vol_slider.custom_minimum_size = Vector2(90, 0)
	_vol_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_vol_slider.value_changed.connect(func(v: float) -> void: Synth.set_volume(v))
	_vol_slider.tooltip_text = "总音量"

	_bpm_spin = SpinBox.new()
	_bpm_spin.min_value = 40
	_bpm_spin.max_value = 240
	_bpm_spin.step = 1
	_bpm_spin.value = song.bpm
	_bpm_spin.custom_minimum_size = Vector2(70, 0)
	_bpm_spin.value_changed.connect(func(v: float) -> void:
		song.bpm = v
		if analysis != null:
			analysis.refresh())
	_bpm_spin.tooltip_text = "速度（拍/分钟）"

	_pos_label = _mk_label("第 1 小节")
	_pos_label.custom_minimum_size = Vector2(84, 0)

	hb.add_child(_group("走带", [_play_btn, _stop_btn, _rec_btn, _loop_chk, _vol_slider]))
	hb.add_child(_group("速度", [_bpm_spin, _pos_label]))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(spacer)

	_status_label = _mk_label("音源载入中…")
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_label.custom_minimum_size = Vector2(150, 0)
	hb.add_child(_status_label)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(8, 0)
	hb.add_child(pad)
	return hb


func _group(title: String, nodes: Array) -> PanelContainer:
	## FL Studio 式功能分组面板：小标题 + 面板底色 + 1px 描边，让每个控件"住在"自己的区域
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style(COL_PANEL_BG, COL_BORDER, 6,
			Vector2(10, 2), Vector2(10, 4)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	var cap := Label.new()
	cap.text = title
	cap.add_theme_font_size_override("font_size", 10)
	cap.add_theme_color_override("font_color", COL_TEXT_DIM)
	v.add_child(cap)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	v.add_child(h)
	for n in nodes:
		h.add_child(n)
	return p


## 统一的带描边圆角面板样式（边框 = 界面的"骨架"，解决控件漂浮无界感）
func _panel_style(bg: Color, border: Color, radius: int,
		margin_top_left := Vector2(8, 6), margin_bottom_right := Vector2(8, 6)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin_top_left.x
	sb.content_margin_top = margin_top_left.y
	sb.content_margin_right = margin_bottom_right.x
	sb.content_margin_bottom = margin_bottom_right.y
	return sb


## 代码构建的全局主题：按钮/标签页统一描边与配色（ professional DAW 质感的基础）
func _build_theme() -> Theme:
	var t := Theme.new()
	var btn_margin := Vector2(10, 3)
	t.set_stylebox("normal", "Button",
			_panel_style(COL_BTN, COL_BORDER, 5, btn_margin, btn_margin))
	t.set_stylebox("hover", "Button",
			_panel_style(COL_BTN_HOVER, COL_BORDER_HI, 5, btn_margin, btn_margin))
	t.set_stylebox("pressed", "Button",
			_panel_style(COL_BTN_DOWN, COL_BORDER, 5, btn_margin, btn_margin))
	var focus := StyleBoxEmpty.new()
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("hover_pressed", "Button",
			_panel_style(COL_BTN_DOWN, COL_BORDER_HI, 5, btn_margin, btn_margin))
	t.set_color("font_color", "Button", COL_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color("9fd4f4"))
	t.set_color("font_hover_pressed_color", "Button", Color("9fd4f4"))
	# 标签页：选中页与内容面板同色，形成"面板被点亮"的层次
	t.set_stylebox("panel", "TabContainer",
			_panel_style(Color("1e222a"), COL_BORDER, 0, Vector2(4, 4), Vector2(4, 4)))
	var tab_sel := _panel_style(COL_BTN, COL_BORDER, 5, Vector2(14, 4), Vector2(14, 4))
	tab_sel.corner_radius_bottom_left = 0
	tab_sel.corner_radius_bottom_right = 0
	tab_sel.border_color = COL_BORDER_HI
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	var tab_un := _panel_style(Color("171a20"), Color("2a2f38"), 5, Vector2(14, 4), Vector2(14, 4))
	tab_un.corner_radius_bottom_left = 0
	tab_un.corner_radius_bottom_right = 0
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	t.set_color("font_color", "TabContainer", COL_TEXT_DIM)
	t.set_color("font_selected_color", "TabContainer", COL_TEXT)
	return t


func _build_options() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)

	_scale_chk = _mk_check("启用", false, _on_scale_changed)
	_scale_chk.tooltip_text = "调性辅助：调外键变暗，新手不易弹错"
	_key_opt = OptionButton.new()
	for k in ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]:
		_key_opt.add_item(k)
	_key_opt.focus_mode = Control.FOCUS_NONE
	_key_opt.tooltip_text = "调（主音）"
	_key_opt.item_selected.connect(func(_i: int) -> void: _on_scale_changed(true))
	_mode_opt = OptionButton.new()
	for s in NoteKeys.SCALES:
		_mode_opt.add_item(s)
	_mode_opt.focus_mode = Control.FOCUS_NONE
	_mode_opt.tooltip_text = "音阶"
	_mode_opt.item_selected.connect(func(_i: int) -> void: _on_scale_changed(true))
	_chord_chk = _mk_check("和弦", false, func(on: bool) -> void: _chord_mode = on)
	_chord_chk.tooltip_text = "和弦模式：按一个键自动补齐调内三和弦"
	_labels_chk = _mk_check("键帽", true, _on_labels_toggled)
	_labels_chk.tooltip_text = "在琴键上显示电脑键帽字母"
	hb.add_child(_group("辅助", [_scale_chk, _key_opt, _mode_opt, _chord_chk, _labels_chk]))

	_snap_opt = OptionButton.new()
	for s in ["1/16", "1/8", "1/4", "1/2", "1小节", "关"]:
		_snap_opt.add_item(s)
	_snap_opt.focus_mode = Control.FOCUS_NONE
	_snap_opt.item_selected.connect(_on_snap_changed)
	_snap_opt.tooltip_text = "网格吸附（卷帘编辑 / 录制量化）"
	_len_spin = SpinBox.new()
	_len_spin.min_value = 1
	_len_spin.max_value = 16
	_len_spin.step = 1
	_len_spin.value = 1
	_len_spin.custom_minimum_size = Vector2(60, 0)
	_len_spin.value_changed.connect(func(v: float) -> void: roll.default_len = int(v))
	_len_spin.tooltip_text = "新音符默认长度（1 = 1/16 音符）"
	_follow_chk = _mk_check("跟随", true, func(_on: bool) -> void: pass)
	_follow_chk.tooltip_text = "播放时卷帘自动跟随播放头滚动"
	var zoom_out := _mk_button("−", _on_zoom_out)
	zoom_out.tooltip_text = "缩小（快捷键 -）"
	_zoom_lab = _mk_label("100%")
	_zoom_lab.custom_minimum_size = Vector2(44, 0)
	var zoom_in := _mk_button("+", _on_zoom_in)
	zoom_in.tooltip_text = "放大（快捷键 =）"
	hb.add_child(_group("编辑", [_snap_opt, _len_spin, _follow_chk, zoom_out, _zoom_lab, zoom_in]))

	for i in 2:
		var tb := Button.new()
		tb.toggle_mode = true
		tb.focus_mode = Control.FOCUS_NONE
		tb.button_pressed = i == 0
		tb.tooltip_text = "选择第 %d 轨（卷帘编辑与录制目标）" % (i + 1)
		tb.toggled.connect(_on_track_toggled.bind(i))
		_track_btns.append(tb)
	_inst_opt = OptionButton.new()
	for inst in InstrumentBank.INSTRUMENTS:
		_inst_opt.add_item(inst)
	_inst_opt.focus_mode = Control.FOCUS_NONE
	_inst_opt.item_selected.connect(_on_inst_changed)
	_inst_opt.tooltip_text = "当前轨的音色"
	hb.add_child(_group("轨道", [_track_btns[0], _track_btns[1], _inst_opt]))

	_export_btn = _mk_button("导出WAV", _on_export)
	_export_btn.tooltip_text = "把整曲实时录制成 WAV 文件（游戏引擎可直接用）"
	var save_btn := _mk_button("保存", _on_save)
	save_btn.tooltip_text = "保存工程（.bsong）"
	var open_btn := _mk_button("打开", _on_open)
	open_btn.tooltip_text = "打开工程（.bsong）"
	var demo_btn := _mk_button("示范曲", _on_demo)
	demo_btn.tooltip_text = "重新载入《小星星》示范工程"
	hb.add_child(_group("文件", [_export_btn, save_btn, open_btn, demo_btn]))
	return hb


func _build_tabs(parent: Control) -> void:
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.tab_changed.connect(_on_tab_changed)
	parent.add_child(tabs)

	# ── 演奏页 ──
	var play := VBoxContainer.new()
	play.name = "演奏"
	play.add_theme_constant_override("separation", GAP_Y)
	var hint := Label.new()
	hint.text = "电脑键盘 = 琴键：Z 行低八度 · Q 行高八度（键帽字母印在琴键上）· ↑/↓ 切换八度 · 鼠标点击/滑奏可弹 · 「和弦模式」按一键出整个和弦 · 空格=播放/停止 · 键盘上 Ctrl+滚轮缩放"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.custom_minimum_size = Vector2(0, 30)
	play.add_child(hint)
	var kb_row := HBoxContainer.new()
	kb_row.add_theme_constant_override("separation", 6)
	_kb_scale = HSlider.new()
	_kb_scale.min_value = 60
	_kb_scale.max_value = 160
	_kb_scale.step = 5
	_kb_scale.value = 100
	_kb_scale.custom_minimum_size = Vector2(140, 0)
	_kb_scale.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_kb_scale.value_changed.connect(_on_kb_scale_changed)
	_kb_scale.tooltip_text = "演奏键盘大小：白键最大宽度百分比（60%–160%）"
	var _kb_scale_lab := _mk_label("键宽 100%")
	_kb_scale_lab.custom_minimum_size = Vector2(86, 0)
	_kb_scale_lab.tooltip_text = _kb_scale.tooltip_text
	_kb_scale.set_meta("label", _kb_scale_lab)
	_kb_span = OptionButton.new()
	for i in 4:
		_kb_span.add_item("%d 八度" % (i + 1))
	_kb_span.select(1)
	_kb_span.focus_mode = Control.FOCUS_NONE
	_kb_span.item_selected.connect(_on_kb_span_changed)
	_kb_span.tooltip_text = "演奏键盘跨度（1–4 个八度）"
	kb_row.add_child(_group("键盘大小", [_mk_label("键宽"), _kb_scale, _kb_scale_lab, _mk_label("跨度"), _kb_span]))
	var kb_spacer := Control.new()
	kb_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kb_row.add_child(kb_spacer)
	play.add_child(kb_row)
	_oct_label = _mk_label("八度：C4 – C6")
	play.add_child(_oct_label)
	_rain = NoteRain.new()
	_rain.custom_minimum_size = Vector2(0, 96)
	_rain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.add_child(_rain)
	keyboard = PianoKeyboard.new()
	keyboard.size_flags_vertical = Control.SIZE_EXPAND_FILL
	keyboard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keyboard.note_on.connect(_live_note_on)
	keyboard.note_off.connect(_live_note_off)
	_rain.kb = keyboard
	play.add_child(keyboard)
	tabs.add_child(play)

	# ── 编曲页（VSplit：卷帘区 / 迷你键盘区，分隔条可拖 = 布局区域可调） ──
	var arrange := VBoxContainer.new()
	arrange.name = "编曲"
	arrange.add_theme_constant_override("separation", 2)
	var vsplit := VSplitContainer.new()
	vsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vsplit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vsplit.split_offset = 10000  # 先给底部最小高度，其余全给卷帘
	var roll_area := VBoxContainer.new()
	roll_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roll_area.add_theme_constant_override("separation", 2)
	var center := HBoxContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roll = PianoRoll.new()
	roll.song = song
	roll.transport = transport
	roll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roll.note_edited.connect(func() -> void:
		transport.refresh()
		if analysis != null:
			analysis.refresh())
	roll.audition.connect(func(p: int) -> void:
		Synth.play_note(song.tracks[_sel_track]["instrument"], p, 0.8))
	roll.scroll_changed.connect(_on_roll_scrolled)
	center.add_child(roll)
	_vbar = VScrollBar.new()
	_vbar.focus_mode = Control.FOCUS_NONE
	_vbar.value_changed.connect(func(v: float) -> void: roll.set_scroll(roll.scroll_x, v, false))
	center.add_child(_vbar)
	roll_area.add_child(center)
	_hbar = HScrollBar.new()
	_hbar.focus_mode = Control.FOCUS_NONE
	_hbar.value_changed.connect(func(v: float) -> void: roll.set_scroll(v, roll.scroll_y, false))
	roll_area.add_child(_hbar)
	vsplit.add_child(roll_area)

	var kb_area := VBoxContainer.new()
	kb_area.custom_minimum_size = Vector2(0, 150)
	kb_area.add_theme_constant_override("separation", 2)
	var kb_tip := Label.new()
	kb_tip.text = "弹奏键盘（拖动上方分隔条调整本区域高度 · 电脑键盘弹奏同样录入当前轨）"
	kb_tip.add_theme_font_size_override("font_size", 11)
	kb_tip.add_theme_color_override("font_color", COL_TEXT_DIM)
	kb_area.add_child(kb_tip)
	mini_kb = PianoKeyboard.new()
	mini_kb.show_labels = false
	mini_kb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mini_kb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mini_kb.note_on.connect(_live_note_on)
	mini_kb.note_off.connect(_live_note_off)
	kb_area.add_child(mini_kb)
	vsplit.add_child(kb_area)
	arrange.add_child(vsplit)
	tabs.add_child(arrange)

	# ── 分析页 ──
	var ana := VBoxContainer.new()
	ana.name = "分析"
	ana.add_theme_constant_override("separation", GAP_Y)
	analysis = AnalysisPanel.new()
	analysis.song = song
	analysis.size_flags_vertical = Control.SIZE_EXPAND_FILL
	analysis.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	analysis.apply_key.connect(_on_apply_detected_key)
	ana.add_child(analysis)
	tabs.add_child(ana)


func _build_dialogs() -> void:
	_save_dlg = FileDialog.new()
	_save_dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dlg.access = FileDialog.ACCESS_FILESYSTEM
	_save_dlg.filters = PackedStringArray(["*.bsong ; 编趣工程"])
	_save_dlg.file_selected.connect(_on_saved)
	add_child(_save_dlg)
	_open_dlg = FileDialog.new()
	_open_dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dlg.access = FileDialog.ACCESS_FILESYSTEM
	_open_dlg.filters = PackedStringArray(["*.bsong ; 编趣工程"])
	_open_dlg.file_selected.connect(_on_opened)
	add_child(_open_dlg)
	_wav_dlg = FileDialog.new()
	_wav_dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_wav_dlg.access = FileDialog.ACCESS_FILESYSTEM
	_wav_dlg.filters = PackedStringArray(["*.wav ; WAV 音频"])
	_wav_dlg.file_selected.connect(_on_wav_path)
	add_child(_wav_dlg)


func _mk_label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _mk_vsep() -> VSeparator:
	return VSeparator.new()


## ── 传输控制 ───────────────────────────────────────────────────────

func _on_play() -> void:
	# 播放头在曲末时自动回卷，避免「点了播放却无声」
	if transport.playhead >= song.song_end_tick():
		transport.seek(0.0)
	transport.play()


func _on_stop() -> void:
	if transport.playing:
		transport.stop()
	else:
		transport.seek(0.0)


func _on_rec_toggle(on: bool) -> void:
	transport.recording = on
	if on and not transport.playing:
		transport.play(0.0)


func _on_loop_toggle(on: bool) -> void:
	transport.loop_play = on


## 播放自然结束/手动停止：收尾录制与导出
func _on_transport_stopped() -> void:
	_rec_btn.set_pressed_no_signal(false)
	transport.recording = false
	for midi in _rec_pending:
		var n: Dictionary = _rec_pending[midi]
		n["l"] = maxi(_snap_tick(transport.playhead) - n["s"], 1)
	_rec_pending.clear()
	if _exporting:
		_finish_export()


## ── 键盘弹奏 / 录制路由 ────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _typing_focus():
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if (k.physical_keycode == KEY_EQUAL or k.physical_keycode == KEY_MINUS) and k.pressed and not k.echo:
			roll.set_zoom(roll.px_per_tick * (1.25 if k.physical_keycode == KEY_EQUAL else 1.0 / 1.25))
			_update_zoom_lab()
			return
		if k.physical_keycode == KEY_SPACE and k.pressed and not k.echo:
			if transport.playing:
				_on_stop()
			else:
				_on_play()
			return
		if k.physical_keycode == KEY_UP and k.pressed and not k.echo:
			_shift_octave(1)
			return
		if k.physical_keycode == KEY_DOWN and k.pressed and not k.echo:
			_shift_octave(-1)
			return
		var semi: int = NoteKeys.KEY_TO_SEMI.get(k.physical_keycode, -1)
		if semi < 0:
			return
		var midi := (keyboard.base_octave + 1) * 12 + semi
		if k.pressed and not k.echo:
			if not _held.has(midi):
				_held[midi] = true
				_live_note_on(midi)
		elif not k.pressed and _held.has(midi):
			_held.erase(midi)
			_live_note_off(midi)


func _typing_focus() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit or f is SpinBox


## ── 演奏键盘大小调节 ───────────────────────────────────────────────

func _on_kb_scale_changed(v: float) -> void:
	keyboard.key_scale = v / 100.0
	keyboard.queue_redraw()
	var lab: Label = _kb_scale.get_meta("label")
	lab.text = "键宽 %d%%" % int(v)


func _on_kb_span_changed(i: int) -> void:
	keyboard.octaves = i + 1
	_update_oct_label()
	keyboard.queue_redraw()


func _update_oct_label() -> void:
	_oct_label.text = "八度：C%d – C%d" % [keyboard.base_octave, keyboard.base_octave + keyboard.octaves]


## 走带音符触发（编曲播放）：发声 + 回声条可视化反馈
func _on_note_fired(trk: int, pitch: int, vel: float) -> void:
	Synth.play_note(song.tracks[trk]["instrument"], pitch, vel)
	_rain.note_hit(pitch, SongModel.TRACK_COLORS[song.tracks[trk]["color"] % SongModel.TRACK_COLORS.size()])


## 分析页：把检测调性写入「辅助」面板并启用高亮
func _on_apply_detected_key(root: int, minor: bool) -> void:
	_key_opt.select(root)
	_mode_opt.select(1 if minor else 0)
	_scale_chk.set_pressed_no_signal(true)
	_apply_scale_helper()
	_update_status("已应用检测调性：%s%s" % [NoteKeys.SHARP_NAMES[root], " 小调" if minor else " 大调"])


func _shift_octave(dir: int) -> void:
	keyboard.base_octave = clampi(keyboard.base_octave + dir, 1, 6)
	_update_oct_label()
	keyboard.queue_redraw()


## 弹奏（键盘/鼠标共用）：发声 + 和弦模式 + 录制（两个键盘同步按压动画）
func _live_note_on(midi: int) -> void:
	var inst: String = song.tracks[_sel_track]["instrument"]
	Synth.play_note(inst, midi, 0.85)
	_rain.note_hit(midi, SongModel.TRACK_COLORS[song.tracks[_sel_track]["color"] % SongModel.TRACK_COLORS.size()])
	if _chord_mode:
		for c in Theory.scale_chord(midi, _key_root(), _scale_semis()):
			if c != midi:
				Synth.play_note(inst, c, 0.6)
	for kb in _all_keyboards():
		kb.set_pressed_silent(midi, true)
	if transport.playing and transport.recording:
		var t := _snap_tick(transport.playhead)
		var n := song.add_note(_sel_track, midi, t, maxi(roll.default_len, 1), 0.85)
		_rec_pending[midi] = n
		transport.refresh()
		roll.queue_redraw()


func _live_note_off(midi: int) -> void:
	for kb in _all_keyboards():
		kb.set_pressed_silent(midi, false)
	_rain.note_lift(midi)
	if _rec_pending.has(midi):
		var n: Dictionary = _rec_pending[midi]
		_rec_pending.erase(midi)
		var end_tick := _snap_tick(transport.playhead)
		n["l"] = maxi(end_tick - n["s"], 1)
		transport.refresh()
		roll.queue_redraw()


func _all_keyboards() -> Array:
	return [keyboard, mini_kb] if mini_kb != null else [keyboard]


func _snap_tick(t: float) -> int:
	var s := roll.snap
	if s <= 0:
		s = 1
	return maxi(int(floor(t / s)) * s, 0)


## ── 调性辅助 ───────────────────────────────────────────────────────

func _key_root() -> int:
	return _key_opt.selected


func _scale_semis() -> Array:
	return NoteKeys.SCALES.values()[_mode_opt.selected]


func _on_scale_changed(_on: bool) -> void:
	_apply_scale_helper()


func _apply_scale_helper() -> void:
	var on := _scale_chk.button_pressed
	for widget in [keyboard, roll]:
		widget.key_root = _key_root()
		widget.scale_notes = _scale_semis()
		widget.scale_highlight = on
		widget.queue_redraw()


func _on_labels_toggled(on: bool) -> void:
	keyboard.show_labels = on
	keyboard.queue_redraw()


## ── 编曲页控件 ─────────────────────────────────────────────────────

func _on_snap_changed(i: int) -> void:
	roll.snap = [1, 2, 4, 8, 16, 0][i]


func _on_zoom_in() -> void:
	roll.set_zoom(roll.px_per_tick * 1.25)
	_update_zoom_lab()


func _on_zoom_out() -> void:
	roll.set_zoom(roll.px_per_tick / 1.25)
	_update_zoom_lab()


func _update_zoom_lab() -> void:
	_zoom_lab.text = "%d%%" % int(round(roll.px_per_tick / 10.0 * 100.0))


func _on_track_toggled(on: bool, idx: int) -> void:
	if not on:
		if _sel_track == idx:
			_track_btns[idx].set_pressed_no_signal(true)
		return
	_sel_track = idx
	roll.track_idx = idx
	for i in _track_btns.size():
		if i != idx:
			_track_btns[i].set_pressed_no_signal(false)
	_refresh_track_ui()


func _on_inst_changed(i: int) -> void:
	song.tracks[_sel_track]["instrument"] = InstrumentBank.INSTRUMENTS[i]
	_refresh_track_ui()


func _refresh_track_ui() -> void:
	for i in _track_btns.size():
		var trk: Dictionary = song.tracks[i]
		_track_btns[i].text = "轨%d %s" % [i + 1, trk["name"]]
		_track_btns[i].set_pressed_no_signal(i == _sel_track)
	_inst_opt.select(InstrumentBank.INSTRUMENTS.find(song.tracks[_sel_track]["instrument"]))


func _on_tab_changed(idx: int) -> void:
	_sync_scrollbars.call_deferred()
	if tabs.get_tab_title(idx) == "分析":
		analysis.refresh.call_deferred()


func _on_roll_scrolled(x: float, y: float) -> void:
	_hbar.set_value_no_signal(x)
	_vbar.set_value_no_signal(y)


func _sync_scrollbars() -> void:
	if roll.size.x <= 0:
		return
	_hbar.max_value = roll._max_scroll_x() + roll.size.x - PianoRoll.MARGIN_L
	_hbar.page = roll.size.x - PianoRoll.MARGIN_L
	_vbar.max_value = roll._max_scroll_y() + roll.size.y - PianoRoll.MARGIN_T
	_vbar.page = roll.size.y - PianoRoll.MARGIN_T
	_hbar.set_value_no_signal(roll.scroll_x)
	_vbar.set_value_no_signal(roll.scroll_y)


## ── 文件 ───────────────────────────────────────────────────────────

func _on_save() -> void:
	DirAccess.make_dir_recursive_absolute(DEFAULT_DIR)
	_save_dlg.current_file = "未命名.bsong"
	_save_dlg.popup_centered(Vector2i(720, 480))


func _on_saved(path: String) -> void:
	var err := song.save(path)
	_update_status("已保存：%s" % path if err == OK else "保存失败（%d）" % err)


func _on_open() -> void:
	_open_dlg.popup_centered(Vector2i(720, 480))


func _on_opened(path: String) -> void:
	var s := SongModel.load_from(path)
	if s == null:
		_update_status("打开失败：%s" % path)
		return
	_switch_song(s)
	_update_status("已打开：%s" % path)


func _on_demo() -> void:
	_switch_song(SongModel.make_demo())
	_update_status("已加载示范曲《小星星》")


## ── WAV 导出（实时总线录制）────────────────────────────────────────

func _on_export() -> void:
	if _exporting:
		transport.stop()  # stopped 回调里收尾
		return
	if transport.playing:
		transport.stop()
	if _rec_effect == null:
		_rec_effect = AudioEffectRecord.new()
		AudioServer.add_bus_effect(0, _rec_effect)
	_exporting = true
	_export_btn.text = "停止并保存"
	_rec_effect.set_recording_active(true)
	transport.play(0.0)
	_update_status("导出中：正在实时录制总线…")


func _finish_export() -> void:
	_rec_effect.set_recording_active(false)
	_exporting = false
	_export_btn.text = "导出 WAV"
	var rec := _rec_effect.get_recording()
	if rec == null or rec.data.is_empty():
		_update_status("导出失败：没有录到音频")
		return
	_wav_dlg.current_file = "导出.wav"
	_wav_dlg.set_meta("rec", rec)
	_wav_dlg.popup_centered(Vector2i(720, 480))


func _on_wav_path(path: String) -> void:
	var rec: AudioStreamWAV = _wav_dlg.get_meta("rec")
	var err := rec.save_to_wav(path)
	_update_status("WAV 已导出：%s" % path if err == OK else "WAV 导出失败（%d）" % err)


## ── 状态栏 ─────────────────────────────────────────────────────────

func _update_status(msg := "") -> void:
	if msg != "":
		_status_label.text = msg
		return
	var bank := "音源✓" if InstrumentBank.ready_ok else "音源载入中"
	var be := "TS" if Theory.backend == "gode-typescript" else "GD"
	_status_label.text = "%s %s ×%d" % [bank, be, Synth.POLYPHONY]


func _process(_delta: float) -> void:
	if transport.playing:
		var bar := int(transport.playhead / 16.0) + 1
		var beat := int(fmod(transport.playhead, 16.0) / 4.0) + 1
		_pos_label.text = "第 %d 小节 %d/4" % [bar, beat]
		if _follow_chk.button_pressed:
			roll.follow_playhead()
		roll.queue_redraw()
