class_name MixerPanel
extends ScrollContainer
## 混音台（v1.0.0）：横向通道条工作区
##
## 每轨一条通道条：轨名/音色 · 声像旋钮式滑杆 · 音量推子（竖直） ·
## Reverb/Delay 发送 · M/S；末尾 Master 条（主音量）。所有改动即时
## 写回 song.tracks 并 Synth.apply_mix；松手落历史快照。

signal mix_changed(pushed: bool)

const COL_PANEL_BG := Color("262b33")
const COL_BORDER := Color("3a4150")
const COL_BORDER_HI := Color("4a5468")
const COL_TEXT := Color("dfe3ea")
const COL_TEXT_DIM := Color("8f97a6")

var song: SongModel

var _strips_box: HBoxContainer


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_strips_box = HBoxContainer.new()
	_strips_box.add_theme_constant_override("separation", 6)
	add_child(_strips_box)


func refresh() -> void:
	if song == null:
		return
	for c in _strips_box.get_children():
		c.queue_free()
	for i in song.tracks.size():
		_strips_box.add_child(_build_strip(i))
	_strips_box.add_child(_build_master())


func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	return sb


func _push(pushed: bool) -> void:
	Synth.apply_mix(song.tracks)
	mix_changed.emit(pushed)


func _build_strip(i: int) -> PanelContainer:
	var trk: Dictionary = song.tracks[i]
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", _style(COL_PANEL_BG, COL_BORDER))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.custom_minimum_size = Vector2(96, 0)

	var name_lab := Label.new()
	name_lab.text = "%d·%s" % [i + 1, trk["name"]]
	name_lab.add_theme_color_override("font_color", COL_TEXT)
	name_lab.add_theme_font_size_override("font_size", 11)
	name_lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(name_lab)

	var inst_lab := Label.new()
	inst_lab.text = "鼓组" if trk.get("type", "melody") == "drum" else str(trk["instrument"])
	inst_lab.add_theme_color_override("font_color", COL_TEXT_DIM)
	inst_lab.add_theme_font_size_override("font_size", 10)
	v.add_child(inst_lab)

	# 音量推子（竖直）
	var fader := VSlider.new()
	fader.min_value = 0.0
	fader.max_value = 1.0
	fader.step = 0.02
	fader.value = trk.get("volume", 0.8)
	fader.custom_minimum_size = Vector2(0, 130)
	fader.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fader.value_changed.connect(func(val: float) -> void:
		trk["volume"] = val
		_push(false))
	fader.drag_ended.connect(func(_c: bool) -> void: _push(true))
	fader.tooltip_text = "轨道音量推子"
	v.add_child(fader)

	var pan := _hslider("声像", -1.0, 1.0, 0.1, trk.get("pan", 0.0),
			func(val: float) -> void:
				trk["pan"] = val
				_push(false),
			func() -> void: _push(true))
	v.add_child(pan)
	var rv := _hslider("混响", 0.0, 1.0, 0.05, trk.get("reverb", 0.0),
			func(val: float) -> void:
				trk["reverb"] = val
				_push(false),
			func() -> void: _push(true))
	v.add_child(rv)
	var dl := _hslider("延迟", 0.0, 1.0, 0.05, trk.get("delay", 0.0),
			func(val: float) -> void:
				trk["delay"] = val
				_push(false),
			func() -> void: _push(true))
	v.add_child(dl)

	var ms := HBoxContainer.new()
	ms.add_theme_constant_override("separation", 4)
	ms.alignment = BoxContainer.ALIGNMENT_CENTER
	var m := _ms_btn("M", trk.get("mute", false), func(on: bool) -> void:
		trk["mute"] = on
		_push(true))
	var s := _ms_btn("S", trk.get("solo", false), func(on: bool) -> void:
		trk["solo"] = on
		_push(true))
	ms.add_child(m)
	ms.add_child(s)
	v.add_child(ms)
	strip.add_child(v)
	return strip


func _build_master() -> PanelContainer:
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", _style(Color("20242c"), COL_BORDER_HI))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.custom_minimum_size = Vector2(96, 0)
	var lab := Label.new()
	lab.text = "Master"
	lab.add_theme_color_override("font_color", COL_TEXT_DIM)
	lab.add_theme_font_size_override("font_size", 11)
	v.add_child(lab)
	var fader := VSlider.new()
	fader.min_value = 0.0
	fader.max_value = 1.0
	fader.step = 0.02
	fader.value = 0.8
	fader.custom_minimum_size = Vector2(0, 130)
	fader.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fader.value_changed.connect(func(val: float) -> void: Synth.set_volume(val))
	fader.tooltip_text = "主音量（Master 总线）"
	v.add_child(fader)
	strip.add_child(v)
	return strip


func _hslider(cap: String, lo: float, hi: float, step: float, val: float,
		on_change: Callable, on_end: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var lab := Label.new()
	lab.text = cap
	lab.add_theme_color_override("font_color", COL_TEXT_DIM)
	lab.add_theme_font_size_override("font_size", 10)
	box.add_child(lab)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = val
	sl.custom_minimum_size = Vector2(0, 14)
	sl.value_changed.connect(on_change)
	sl.drag_ended.connect(func(_c: bool) -> void: on_end.call())
	box.add_child(sl)
	return box


func _ms_btn(letter: String, on: bool, toggled: Callable) -> Button:
	var b := Button.new()
	b.text = letter
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(34, 0)
	b.toggled.connect(toggled)
	return b
