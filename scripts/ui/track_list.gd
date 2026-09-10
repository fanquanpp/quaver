class_name TrackList
extends VBoxContainer
## 轨道列表（v0.2 N 轨系统）——替代旧工具栏双轨按钮
##
## 每行：色块 · 选择/名称 · 音色（鼓机轨显示"鼓组"） · 静音 M · 独奏 S
##       · 音量/声像滑杆；右键 → 重命名/清空音符/删除；底部"+ 添加轨道"。
## 混音参数改动即时生效（main_ui 收到 mix_changed 后调 Synth.apply_mix）。

signal track_selected(idx: int)
signal mix_changed(pushed: bool)  ## pushed=true：一次性编辑（需落历史快照）
signal structure_changed          ## 加轨/删轨（需重建 + 历史重置）

const COL_PANEL_BG := Color("262b33")
const COL_BORDER := Color("3a4150")
const COL_BORDER_HI := Color("4a5468")
const COL_TEXT := Color("dfe3ea")
const COL_TEXT_DIM := Color("8f97a6")

var song: SongModel
var sel := 0

var _rows_box: VBoxContainer
var _menu: PopupMenu
var _menu_row := -1


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	custom_minimum_size = Vector2(252, 0)

	_menu = PopupMenu.new()
	_menu.add_item("重命名", 1)
	_menu.add_item("清空音符", 2)
	_menu.add_item("切换 旋律/鼓机", 3)
	_menu.add_item("删除轨道", 4)
	_menu.add_separator()
	_menu.add_item("存为轨道预设", 5)
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 2)
	_rows_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_rows_box)

	var add_btn := Button.new()
	add_btn.text = "+ 添加轨道"
	add_btn.focus_mode = Control.FOCUS_NONE
	add_btn.pressed.connect(_on_add_track)
	add_child(add_btn)


func refresh() -> void:
	if song == null:
		return
	sel = clampi(sel, 0, song.tracks.size() - 1)
	for c in _rows_box.get_children():
		c.queue_free()
	for i in song.tracks.size():
		_rows_box.add_child(_build_row(i))


func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


func _build_row(i: int) -> PanelContainer:
	var trk: Dictionary = song.tracks[i]
	var selected := i == sel
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _style(
			Color("313846") if selected else COL_PANEL_BG,
			COL_BORDER_HI if selected else COL_BORDER))
	row.set_meta("idx", i)
	row.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_select(i)
		elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
			_select(i)
			_menu_row = i
			_rebuild_preset_items()
			_menu.popup(Rect2i(get_global_mouse_position(), Vector2i(1, 1))))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)

	var chip := ColorRect.new()
	chip.custom_minimum_size = Vector2(8, 0)
	chip.color = SongModel.TRACK_COLORS[trk["color"] % SongModel.TRACK_COLORS.size()]
	h.add_child(chip)

	var name_btn := Button.new()
	name_btn.text = "%d·%s" % [i + 1, trk["name"]]
	name_btn.flat = true
	name_btn.focus_mode = Control.FOCUS_NONE
	name_btn.add_theme_color_override("font_color", COL_TEXT)
	name_btn.custom_minimum_size = Vector2(74, 0)
	name_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_btn.pressed.connect(_select.bind(i))
	name_btn.tooltip_text = "点击选择轨道；右键行可重命名/删除"
	h.add_child(name_btn)

	if trk.get("type", "melody") == "drum":
		var drum_lab := Label.new()
		drum_lab.text = "鼓组"
		drum_lab.add_theme_color_override("font_color", COL_TEXT_DIM)
		drum_lab.custom_minimum_size = Vector2(52, 0)
		h.add_child(drum_lab)
	else:
		var inst_opt := OptionButton.new()
		for inst in InstrumentBank.INSTRUMENTS:
			inst_opt.add_item(inst)
		inst_opt.focus_mode = Control.FOCUS_NONE
		inst_opt.select(InstrumentBank.INSTRUMENTS.find(trk["instrument"]))
		inst_opt.custom_minimum_size = Vector2(52, 0)
		inst_opt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inst_opt.item_selected.connect(func(j: int) -> void:
			trk["instrument"] = InstrumentBank.INSTRUMENTS[j]
			mix_changed.emit(true))
		inst_opt.tooltip_text = "轨道音色"
		h.add_child(inst_opt)

	var mute_btn := _mk_ms("M", trk.get("mute", false), "静音")
	mute_btn.pressed.connect(func() -> void:
		trk["mute"] = not trk.get("mute", false)
		mute_btn.set_pressed_no_signal(trk["mute"])
		mix_changed.emit(true))
	h.add_child(mute_btn)
	var solo_btn := _mk_ms("S", trk.get("solo", false), "独奏（其余轨自动静音）")
	solo_btn.pressed.connect(func() -> void:
		trk["solo"] = not trk.get("solo", false)
		solo_btn.set_pressed_no_signal(trk["solo"])
		mix_changed.emit(true))
	h.add_child(solo_btn)

	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = trk.get("volume", 0.8)
	vol.custom_minimum_size = Vector2(46, 0)
	vol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vol.value_changed.connect(func(v: float) -> void:
		trk["volume"] = v
		mix_changed.emit(false))
	vol.drag_ended.connect(func(_changed: bool) -> void: mix_changed.emit(true))
	vol.tooltip_text = "轨道音量"
	h.add_child(vol)

	var pan := HSlider.new()
	pan.min_value = -1.0
	pan.max_value = 1.0
	pan.step = 0.1
	pan.value = trk.get("pan", 0.0)
	pan.custom_minimum_size = Vector2(40, 0)
	pan.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pan.value_changed.connect(func(v: float) -> void:
		trk["pan"] = v
		mix_changed.emit(false))
	pan.drag_ended.connect(func(_changed: bool) -> void: mix_changed.emit(true))
	pan.tooltip_text = "声像（左-右）"
	h.add_child(pan)
	return row


func _mk_ms(letter: String, on: bool, tip: String) -> Button:
	var b := Button.new()
	b.text = letter
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(22, 0)
	b.tooltip_text = tip
	return b


func _select(i: int) -> void:
	if sel == i:
		refresh()
		return
	sel = i
	refresh()
	track_selected.emit(i)


func _on_add_track() -> void:
	if song == null or song.tracks.size() >= SongModel.MAX_TRACKS:
		return
	song.add_track("轨%d" % (song.tracks.size() + 1), "芯片")
	sel = song.tracks.size() - 1
	refresh()
	structure_changed.emit()


## 右键弹出前重建"加载预设"动态项（id 100+i）
func _rebuild_preset_items() -> void:
	var ids_to_remove: Array = []
	for i in _menu.item_count:
		var id := _menu.get_item_id(i)
		if id >= 100:
			ids_to_remove.append(id)
	# 从后往前删，索引不失效
	ids_to_remove.reverse()
	for id in ids_to_remove:
		_menu.remove_item(_menu.get_item_index(id))
	var presets := TrackPresets.list_all()
	if presets.is_empty():
		return
	_menu.add_separator()
	var names := presets.keys()
	names.sort()
	for i in names.size():
		_menu.add_item("预设 ▸ %s" % names[i], 100 + i)


func _on_menu(id: int) -> void:
	var i := _menu_row
	_menu_row = -1
	if id >= 100:
		_load_preset(i, id - 100)
		return
	if i < 0 or i >= song.tracks.size():
		return
	match id:
		1:
			_begin_rename(i)
		2:
			song.tracks[i]["notes"].clear()
			mix_changed.emit(true)
			structure_changed.emit()
		3:
			var trk: Dictionary = song.tracks[i]
			trk["type"] = "drum" if trk.get("type", "melody") != "drum" else "melody"
			mix_changed.emit(true)
			structure_changed.emit()
		4:
			if song.tracks.size() <= 1:
				return
			song.remove_track(i)
			sel = clampi(sel, 0, song.tracks.size() - 1)
			refresh()
			structure_changed.emit()
		5:
			if i < song.tracks.size():
				TrackPresets.save_track(song.tracks[i])


func _load_preset(row: int, preset_idx: int) -> void:
	if row < 0 or row >= song.tracks.size():
		return
	var presets := TrackPresets.list_all()
	var names := presets.keys()
	names.sort()
	if preset_idx >= names.size():
		return
	TrackPresets.apply_to(song.tracks[row], names[preset_idx])
	mix_changed.emit(true)
	structure_changed.emit()


## 行内重命名：名称按钮换成 LineEdit，回车/失焦提交
func _begin_rename(i: int) -> void:
	var trk: Dictionary = song.tracks[i]
	var edit := LineEdit.new()
	edit.text = trk["name"]
	edit.custom_minimum_size = Vector2(74, 0)
	edit.select_all_on_focus = true
	var row := _rows_box.get_child(i) as PanelContainer
	var slot := (row.get_child(0) as HBoxContainer).get_child(1)
	var parent := slot.get_parent()
	var idx := slot.get_index()
	parent.remove_child(slot)
	slot.queue_free()
	parent.add_child(edit)
	parent.move_child(edit, idx)
	edit.grab_focus()
	edit.text_submitted.connect(func(t: String) -> void:
		trk["name"] = t if t.strip_edges() != "" else trk["name"]
		refresh()
		structure_changed.emit())
	edit.editing_toggled.connect(_rename_cancel)


## 行内编辑被取消（焦点离开未提交）：直接重建即可
func _rename_cancel(_editing: bool) -> void:
	if is_inside_tree():
		refresh.call_deferred()
