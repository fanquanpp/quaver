class_name DrumSequencer
extends VBoxContainer
## 鼓机步进编辑器（v0.2）：16 步 × 6 声部，编辑鼓机轨的指定小节
##
## 鼓音符就是普通音符（pitch=声部音高，s=bar*16+步，l=1，v=力度），
## 因此走带/卷帘/MIDI 导出/撤销重做全部免费复用。
## 左键切换步（常规力度 0.75），右键加重音（1.0）。

signal edited

const STEPS := 16
## 声部顺序与音高（与 InstrumentBank.DRUM_VOICES 对应）
const VOICES := [[36, "底鼓"], [38, "军鼓"], [39, "拍手"], [42, "踩镲"], [45, "嗵鼓"], [46, "开镲"]]

var song: SongModel
var track_idx := 0

var _bar_spin: SpinBox
var _grid: GridContainer
var _cells := {}  # 音高 -> Array[Button]


func _ready() -> void:
	add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var cap := Label.new()
	cap.text = "鼓机步进"
	cap.add_theme_font_size_override("font_size", 10)
	cap.add_theme_color_override("font_color", Color("8f97a6"))
	head.add_child(cap)
	_bar_spin = SpinBox.new()
	_bar_spin.min_value = 1
	_bar_spin.max_value = 512
	_bar_spin.step = 1
	_bar_spin.value = 1
	_bar_spin.suffix = "小节"
	_bar_spin.custom_minimum_size = Vector2(86, 0)
	_bar_spin.value_changed.connect(func(_v: float) -> void: refresh())
	_bar_spin.tooltip_text = "编辑哪一小节的步进"
	head.add_child(_bar_spin)
	var tip := Label.new()
	tip.text = "左键开/关步 · 右键加重音"
	tip.add_theme_font_size_override("font_size", 11)
	tip.add_theme_color_override("font_color", Color("8f97a6"))
	head.add_child(tip)
	add_child(head)

	_grid = GridContainer.new()
	_grid.columns = STEPS + 1
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	add_child(_grid)

	for v in VOICES:
		var pitch: int = v[0]
		var lab := Label.new()
		lab.text = v[1]
		lab.add_theme_font_size_override("font_size", 11)
		lab.custom_minimum_size = Vector2(38, 0)
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_grid.add_child(lab)
		var row: Array = []
		for step in STEPS:
			var cell := Button.new()
			cell.toggle_mode = true
			cell.focus_mode = Control.FOCUS_NONE
			cell.custom_minimum_size = Vector2(20, 20)
			cell.tooltip_text = "%s · 第 %d 步" % [v[1], step + 1]
			cell.toggled.connect(_on_step.bind(pitch, step))
			cell.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
						and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
					_toggle_step(pitch, step, 1.0))
			_grid.add_child(cell)
			row.append(cell)
		_cells[pitch] = row
	refresh()


func _bar() -> int:
	return int(_bar_spin.value) - 1


func _note_at(pitch: int, step: int) -> Dictionary:
	if song == null or track_idx >= song.tracks.size():
		return {}
	return song.note_at(track_idx, pitch, _bar() * STEPS + step)


func _on_step(on: bool, pitch: int, step: int) -> void:
	var existing := _note_at(pitch, step)
	if not existing.is_empty():
		song.remove_note(track_idx, existing)
	elif on:
		song.add_note(track_idx, pitch, _bar() * STEPS + step, 1, 0.75)
	edited.emit()


## 右键：无 → 加重音符；有 → 力度拉满（再右键删除）
func _toggle_step(pitch: int, step: int, vel: float) -> void:
	var existing := _note_at(pitch, step)
	if existing.is_empty():
		song.add_note(track_idx, pitch, _bar() * STEPS + step, 1, vel)
	elif existing["v"] < vel - 0.01:
		existing["v"] = vel
	else:
		song.remove_note(track_idx, existing)
	refresh()
	edited.emit()


## 从模型同步全部格子状态（歌切换/撤销恢复/编辑后）
func refresh() -> void:
	if _grid == null:
		return
	for v in VOICES:
		var pitch: int = v[0]
		var row: Array = _cells[pitch]
		for step in STEPS:
			var cell: Button = row[step]
			var n := _note_at(pitch, step)
			cell.set_pressed_no_signal(not n.is_empty())
			if n.is_empty():
				cell.text = ""
			elif n["v"] >= 0.9:
				cell.text = "▲"
			else:
				cell.text = "·"
