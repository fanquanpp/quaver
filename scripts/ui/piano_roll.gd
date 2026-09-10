class_name PianoRoll
extends Control
## 钢琴卷帘：单 Control 矢量绘制（脏刷新 + 视口裁剪，千级音符流畅）。
##
## 鼠标交互（零学习成本优先）：
##   左键空白 = 新建音符并横向拖拽定长度 · 左键拖已有音符 = 移动 ·
##   抓右缘 = 改长度 · 右键 = 删除（按住扫删）· 标尺点击 = 跳播 ·
##   左侧琴键列 = 点击试听
## 滚轮 = 音高方向 · Shift+滚轮 = 时间方向 · Ctrl+滚轮 = 缩放

signal note_edited
signal audition(pitch: int)
signal scroll_changed(x: float, y: float)
signal selection_changed(has_sel: bool)

const MARGIN_L := 72.0
const MARGIN_T := 22.0
const MARGIN_B := 56.0   ## 底部力度编辑条高度（v0.2.1）
const ROW_H := 12.0
const PITCH_MAX := 107  # 顶行音高（B7）
const PITCH_MIN := 21   # 底行音高（A0）
const N_ROWS := PITCH_MAX - PITCH_MIN + 1
const GHOST_NOTE_LIMIT := 1500  ## 其他轨音符总数超过此值时本帧跳过幽灵渲染

const C := {
	"bg": Color("23272f"), "row_white": Color("262b34"), "row_black": Color("1d2129"),
	"grid16": Color("2b313c"), "gridbeat": Color("343b48"), "gridbar": Color("49536a"),
	"ruler": Color("1a1d24"), "kbd_white": Color("d8dbe0"), "kbd_black": Color("2f333c"),
	"playhead": Color("ff5252"), "text": Color("8f97a6"), "border": Color("3a4150"),
}

var song: SongModel
var transport: Transport
var track_idx := 0
var snap := 1            ## 吸附 tick 数：1=1/16, 2=1/8, 4=1/4, 8=1/2, 16=整小节, 0=关
var default_len := 1
var key_root := 0
var scale_notes: Array = [0, 2, 4, 5, 7, 9, 11]
var scale_highlight := false
var px_per_tick := 10.0
var scroll_x := 0.0
var scroll_y := 0.0

var _drag := -1          # -1无 0新建 1移动 2改长 3删除 4力度条 5框选
var _drag_dirty := false # 本次拖拽是否真的改动了数据（无效拖拽不进撤销栈）
var _temp := {}          # 新建中的音符 {p,s,l}
var _drag_orig := {}
var _drag_ref_tick := 0.0
var _drag_ref_pitch := 0
var _hover := {}         # 正在拖拽/改长的音符引用（拖拽机制用，不作悬停高亮）
var _kbd_midi := -1
var _sb_cache := {}      # 音符/琴键 StyleBox 缓存（圆角抗锯齿）

# v0.2.1 多选 / 批量 / 剪贴板 / 力度条
var _selected: Array = []        # 选中的音符引用（当前轨）
var _box_start := Vector2.ZERO   # 框选起点（视口坐标）
var _box_rect := Rect2()         # 框选矩形；size==0 表示不在框选
var _vel_target := {}            # 力度条拖拽目标音符
var _vel_ref_v := 0.0
static var _clipboard: Array = []  # 复制的音符 [{p,s,l,v}]（相对基准）
static var _clip_base := {"s": 0, "p": 60}


## 圆角音符样式（缓存按颜色；1px 深描边 + 圆角消除直角锯齿感）
func _note_style(col: Color) -> StyleBoxFlat:
	var key := col.to_html()
	if not _sb_cache.has(key):
		var s := StyleBoxFlat.new()
		s.bg_color = col
		s.border_color = Color(0, 0, 0, 0.45)
		s.set_border_width_all(1)
		s.set_corner_radius_all(3)
		s.anti_aliasing = true
		_sb_cache[key] = s
	return _sb_cache[key]


func _hover_style() -> StyleBoxFlat:
	var key := "hover"
	if not _sb_cache.has(key):
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0, 0, 0, 0)
		s.border_color = Color(1, 1, 1, 0.9)
		s.set_border_width_all(2)
		s.set_corner_radius_all(4)
		s.anti_aliasing = true
		_sb_cache[key] = s
	return _sb_cache[key]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


## ── 坐标换算 ───────────────────────────────────────────────────────

func _tick_at(x: float) -> float:
	return (x - MARGIN_L + scroll_x) / px_per_tick


func _pitch_at(y: float) -> int:
	return PITCH_MAX - int((y - MARGIN_T + scroll_y) / ROW_H)


func _x_of_tick(t: float) -> float:
	return MARGIN_L + t * px_per_tick - scroll_x


func _y_of_pitch(p: int) -> float:
	return MARGIN_T + (PITCH_MAX - p) * ROW_H - scroll_y


func _snapped(v: float) -> int:
	if snap <= 0:
		return int(floor(v))
	return int(floor(v / snap)) * snap


func _note_color(track: int, alpha := 1.0) -> Color:
	var c: Color = SongModel.TRACK_COLORS[song.tracks[track]["color"] % SongModel.TRACK_COLORS.size()]
	c.a = alpha
	return c


## ── 滚动 ───────────────────────────────────────────────────────────

func _max_scroll_x() -> float:
	var content := float(song.song_end_tick() + 48) * px_per_tick
	return maxf(0.0, content - (size.x - MARGIN_L))


func _max_scroll_y() -> float:
	return maxf(0.0, N_ROWS * ROW_H - (size.y - MARGIN_T - MARGIN_B))


func set_scroll(x: float, y: float, emit := true) -> void:
	scroll_x = clampf(x, 0.0, _max_scroll_x())
	scroll_y = clampf(y, 0.0, _max_scroll_y())
	if emit:
		scroll_changed.emit(scroll_x, scroll_y)
	queue_redraw()


func scroll_to_start() -> void:
	set_scroll(0.0, _y_center_offset(), false)


func _y_center_offset() -> float:
	# 初始视图对准 C3 附近
	return clampf((PITCH_MAX - 72) * ROW_H - (size.y - MARGIN_T) * 0.5, 0.0, _max_scroll_y())


## ── 输入 ───────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_mouse_motion(event as InputEventMouseMotion)


func _mouse_button(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_press_left(mb.position)
		else:
			_release_left()
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		_drag = 3
		_drag_dirty = false
		_delete_at(mb.position)
	elif mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		var step := -64.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 64.0
		if mb.ctrl_pressed:
			var mx := mb.position.x
			var under := _tick_at(mx)
			px_per_tick = clampf(px_per_tick * (1.12 if step < 0 else 1.0 / 1.12), 3.0, 48.0)
			set_scroll(under * px_per_tick - (mx - MARGIN_L), scroll_y)
		elif mb.shift_pressed:
			set_scroll(scroll_x + step, scroll_y)
		else:
			set_scroll(scroll_x, scroll_y + step)


func _press_left(pos: Vector2) -> void:
	_drag_dirty = false
	if pos.y < MARGIN_T:  # 标尺：跳播
		if transport != null:
			transport.seek(maxf(0.0, _tick_at(pos.x)))
		return
	if pos.x < MARGIN_L:  # 琴键列试听
		var p := _pitch_at(pos.y)
		if p >= PITCH_MIN and p <= PITCH_MAX:
			_kbd_midi = p
			audition.emit(p)
		return
	if pos.y >= size.y - MARGIN_B:  # 力度编辑条
		_drag = 4
		_drag_dirty = false
		_vel_target = _nearest_note_at_x(pos.x)
		if not _vel_target.is_empty():
			_vel_ref_v = _set_vel_at(pos.y, _vel_target)
		return
	var tick := _snapped(maxf(_tick_at(pos.x), 0.0))
	var pitch := _pitch_at(pos.y)
	if pitch < PITCH_MIN or pitch > PITCH_MAX:
		return
	var note := song.note_at(track_idx, pitch, tick)
	if not note.is_empty():
		if Input.is_key_pressed(KEY_SHIFT) and not _selected.is_empty():
			_toggle_selected(note)
			_drag = -1
			selection_changed.emit(has_selection())
			queue_redraw()
			return
		var end_x := _x_of_tick(note["s"] + note["l"])
		if absf(pos.x - end_x) <= 6.0:
			_drag = 2
		else:
			_drag = 1
		_drag_orig = {"p": note["p"], "s": note["s"], "l": note["l"]}
		_drag_ref_tick = _tick_at(pos.x)
		_drag_ref_pitch = pitch
		_hover = note
		# 点选未选中的音符 = 重新单选；拖动已选音符 = 整组批量移动
		if not _selected.has(note):
			if not Input.is_key_pressed(KEY_SHIFT):
				_selected = [note]
			else:
				_selected.append(note)
		selection_changed.emit(has_selection())
	else:
		if Input.is_key_pressed(KEY_SHIFT):  # Shift+空白 = 框选起点
			_drag = 5
			_box_start = pos
			_box_rect = Rect2(pos, Vector2.ZERO)
			queue_redraw()
			return
		if not _selected.is_empty():
			_selected = []
			selection_changed.emit(false)
		_drag = 0
		_temp = {"p": pitch, "s": tick, "l": maxi(default_len, 1)}
		audition.emit(pitch)
	queue_redraw()


func _release_left() -> void:
	_kbd_midi = -1
	if _drag == 0 and not _temp.is_empty():
		song.add_note(track_idx, _temp["p"], _temp["s"], _temp["l"])
		_temp = {}
		note_edited.emit()
	elif _drag == 1 or _drag == 2:
		if _drag_dirty:
			note_edited.emit()
	elif _drag == 3:
		if _drag_dirty:
			_prune_selection()
			note_edited.emit()
	elif _drag == 4:
		if _drag_dirty:
			note_edited.emit()
	elif _drag == 5:
		_finish_box_select()
	_drag = -1
	queue_redraw()


func _mouse_motion(pos_m: InputEventMouseMotion) -> void:
	var pos := pos_m.position
	if _drag == -1:
		return  # 无拖拽时鼠标移动不触发重绘（悬停高亮已按用户要求移除）
	if _drag == 5:  # 框选
		_box_rect = Rect2(_box_start, pos - _box_start).abs()
		queue_redraw()
		return
	if pos.x < MARGIN_L:
		return
	var tick_f := maxf(_tick_at(pos.x), 0.0)
	match _drag:
		0:
			if _temp.is_empty():
				return
			_temp["l"] = maxi(_snapped(tick_f) - _temp["s"], maxi(snap, 1))
			queue_redraw()
		1:
			var note: Dictionary = _hover
			if note.is_empty():
				return
			var dtick := _snapped(tick_f) - _snapped(_drag_ref_tick)
			var dpitch := _pitch_at(pos.y) - _drag_ref_pitch
			var np: int = clampi(_drag_orig["p"] + dpitch, PITCH_MIN, PITCH_MAX)
			var ns: int = maxi(_drag_orig["s"] + dtick, 0)
			if np != note["p"] or ns != note["s"]:
				# 批量移动：目标音符在选区 → 整组按同一位移移动
				if _selected.has(note):
					var moved := false
					for sel in _selected:
						var sp: int = clampi(int(sel["p"]) + dpitch, PITCH_MIN, PITCH_MAX)
						var ss: int = maxi(int(sel["s"]) + dtick, 0)
						if sp != sel["p"] or ss != sel["s"]:
							sel["p"] = sp
							sel["s"] = ss
							moved = true
					_drag_orig = {"p": np, "s": ns, "l": note["l"]}
					_drag_ref_tick = tick_f
					_drag_ref_pitch = _pitch_at(pos.y)
				else:
					note["p"] = np
					note["s"] = ns
				_drag_dirty = true
				audition.emit(np)
				queue_redraw()
		2:
			var note2: Dictionary = _hover
			if note2.is_empty():
				return
			var nl: int = maxi(_snapped(tick_f) - note2["s"], maxi(snap, 1))
			if nl != note2["l"]:
				note2["l"] = nl
				_drag_dirty = true
				queue_redraw()
		3:
			_delete_at(pos)
		4:  # 力度条：绝对高度设定；若目标在选区则整组同增量
			if _vel_target.is_empty():
				return
			var nv := _set_vel_at(pos.y, _vel_target)
			if _selected.has(_vel_target):
				var delta: float = nv - _vel_ref_v
				for sel in _selected:
					if sel != _vel_target:
						sel["v"] = clampf(sel["v"] + delta, 0.05, 1.0)
			_vel_ref_v = nv
			_drag_dirty = true
			queue_redraw()


func _delete_at(pos: Vector2) -> void:
	if pos.x < MARGIN_L or pos.y < MARGIN_T:
		return
	var tick := _snapped(maxf(_tick_at(pos.x), 0.0))
	var pitch := _pitch_at(pos.y)
	var n := song.note_at(track_idx, pitch, tick)
	if not n.is_empty():
		song.remove_note(track_idx, n)
		_drag_dirty = true
		_hover = {}
		queue_redraw()


## 撤销/换轨后清拖拽状态（原引用已随快照还原失效）
func clear_drag_state() -> void:
	_drag = -1
	_hover = {}
	_temp = {}
	_selected = []
	_box_rect = Rect2()
	_vel_target = {}
	selection_changed.emit(false)


## ── 选择 / 剪贴板 / 批量操作（v0.2.1） ─────────────────────────────

func has_selection() -> bool:
	return not _selected.is_empty()


func select_all() -> void:
	_selected = song.track_notes(track_idx).duplicate()
	selection_changed.emit(has_selection())
	queue_redraw()


func clear_selection() -> void:
	_selected = []
	selection_changed.emit(false)
	queue_redraw()


func _toggle_selected(note: Dictionary) -> void:
	if _selected.has(note):
		_selected.erase(note)
	else:
		_selected.append(note)


## 拖删后把已失效引用清出选区
func _prune_selection() -> void:
	var notes := song.track_notes(track_idx)
	_selected = _selected.filter(func(n: Dictionary) -> bool: return notes.has(n))
	selection_changed.emit(has_selection())


func _finish_box_select() -> void:
	var sel: Array = []
	if _box_rect.size.x > 2.0 or _box_rect.size.y > 2.0:
		var t0 := minf(_tick_at(_box_rect.position.x), _tick_at(_box_rect.end.x))
		var t1 := maxf(_tick_at(_box_rect.position.x), _tick_at(_box_rect.end.x))
		var p_hi := _pitch_at(maxf(_box_rect.position.y, _box_rect.end.y))
		var p_lo := _pitch_at(minf(_box_rect.position.y, _box_rect.end.y))
		for n in song.track_notes(track_idx):
			if n["p"] >= p_lo and n["p"] <= p_hi \
					and n["s"] + n["l"] > t0 and n["s"] < t1:
				sel.append(n)
	_box_rect = Rect2()
	_selected = sel
	selection_changed.emit(has_selection())
	queue_redraw()


func copy_selection() -> bool:
	if _selected.is_empty():
		return false
	_copy_notes(_selected)
	return true


func cut_selection() -> bool:
	if _selected.is_empty():
		return false
	_copy_notes(_selected)
	delete_selection()
	return true


static func _copy_notes(notes: Array) -> void:
	var clip := []
	var min_s := 99999999
	var min_p := 127
	for n in notes:
		clip.append({"p": n["p"], "s": n["s"], "l": n["l"], "v": n["v"]})
		min_s = mini(min_s, n["s"])
		min_p = mini(min_p, n["p"])
	_clipboard = clip
	_clip_base = {"s": min_s, "p": min_p}


## 粘贴到播放头（吸附网格）：保持原音高，仅平移时间；粘贴后选区指向新音符
func paste_at_playhead() -> bool:
	if _clipboard.is_empty():
		return false
	var base_tick := 0.0
	if transport != null:
		base_tick = maxf(transport.playhead, 0.0)
	var d_s: int = _snapped(base_tick) - _clip_base["s"]
	var pasted := []
	for n in _clipboard:
		pasted.append(song.add_note(track_idx, n["p"],
				maxi(n["s"] + d_s, 0), n["l"], n["v"]))
	_selected = pasted
	selection_changed.emit(true)
	note_edited.emit()
	queue_redraw()
	return true


func delete_selection() -> bool:
	if _selected.is_empty():
		return false
	for n in _selected:
		song.remove_note(track_idx, n)
	_selected = []
	selection_changed.emit(false)
	note_edited.emit()
	queue_redraw()
	return true


## 选区量化到当前网格
func quantize_selection() -> bool:
	if _selected.is_empty():
		return false
	var g := maxi(snap, 1)
	for n in _selected:
		n["s"] = int(round(n["s"] / float(g))) * g
	note_edited.emit()
	queue_redraw()
	return true


func transpose_selection(semis: int) -> bool:
	if _selected.is_empty():
		return false
	for n in _selected:
		n["p"] = clampi(n["p"] + semis, PITCH_MIN, PITCH_MAX)
	audition.emit(_selected[0]["p"])
	note_edited.emit()
	queue_redraw()
	return true


func nudge_selection_velocity(delta: float) -> bool:
	if _selected.is_empty():
		return false
	for n in _selected:
		n["v"] = clampf(n["v"] + delta, 0.05, 1.0)
	note_edited.emit()
	queue_redraw()
	return true


## 力度条：找 x 附近最近起音的音符；返回设定后的力度
func _nearest_note_at_x(px: float) -> Dictionary:
	var notes := song.track_notes(track_idx)
	if notes.is_empty():
		return {}
	var best := {}
	var bd := 1e9
	for n in notes:
		var d: float = absf(_x_of_tick(n["s"]) - px)
		if d < bd:
			bd = d
			best = n
	return best


func _set_vel_at(pos_y: float, note: Dictionary) -> float:
	var lane_top := size.y - MARGIN_B
	var v := clampf(1.0 - (pos_y - lane_top) / (MARGIN_B - 6.0), 0.05, 1.0)
	note["v"] = v
	queue_redraw()
	return v


## 设置横向缩放（px/tick），围绕指定 tick（默认视口中心）缩放
func set_zoom(f: float, focus_tick := -1.0) -> void:
	var t := focus_tick if focus_tick >= 0.0 else _tick_at(MARGIN_L + (size.x - MARGIN_L) * 0.5)
	px_per_tick = clampf(f, 3.0, 48.0)
	set_scroll(maxf(t * px_per_tick - (size.x - MARGIN_L) * 0.5, 0.0), scroll_y)


## 播放时让播放头保持在可视区内（跟随）。centered=true = 播放头固定居中，
## false = 页面滚动跟随（到边缘才滚动）
func follow_playhead(centered := false) -> void:
	if transport == null or not transport.playing:
		return
	var view := size.x - MARGIN_L
	var px := transport.playhead * px_per_tick - scroll_x
	if centered:
		set_scroll(maxf(transport.playhead * px_per_tick - view * 0.5, 0.0), scroll_y)
	elif px > view - 100.0 or px < 0.0:
		set_scroll(maxf(transport.playhead * px_per_tick - view * 0.3, 0.0), scroll_y)


## ── 绘制 ───────────────────────────────────────────────────────────

func _draw() -> void:
	var w := size.x
	var h := size.y
	var note_h := h - MARGIN_B  # 音符区底边（下方是力度条）
	draw_rect(Rect2(0, 0, w, h), C["bg"])
	var view_h := note_h - MARGIN_T
	var p_hi: int = clampi(PITCH_MAX - int(scroll_y / ROW_H), PITCH_MIN, PITCH_MAX)
	var p_lo: int = clampi(PITCH_MAX - int((scroll_y + view_h) / ROW_H) - 1, PITCH_MIN, PITCH_MAX)
	var t0: float = maxf(_tick_at(MARGIN_L), 0.0)
	var t1: float = _tick_at(w)

	# 1. 行背景（黑键行更暗 + 调外行压暗；行坐标取整防亚像素缝）
	for p in range(p_lo, p_hi + 1):
		var y := floorf(_y_of_pitch(p))
		draw_rect(Rect2(MARGIN_L, y, w - MARGIN_L, ROW_H - 1.0),
				C["row_black"] if NoteKeys.is_black(p) else C["row_white"])
		if scale_highlight and not Theory.in_scale(p, key_root, scale_notes):
			draw_rect(Rect2(MARGIN_L, y, w - MARGIN_L, ROW_H - 1.0), Color(0, 0, 0, 0.28))

	# 2. 竖向网格（小节/拍/16分，按缩放裁剪密度；对齐半像素保证 1px 线锐利无锯齿）
	var bar := 16
	if px_per_tick >= 5.0:
		for t in range(int(t0), int(t1) + 1):
			if t % bar == 0:
				continue
			var x := floorf(_x_of_tick(t)) + 0.5
			var col: Color = C["gridbeat"] if t % 4 == 0 else C["grid16"]
			draw_line(Vector2(x, MARGIN_T), Vector2(x, note_h), col, 1.0)
	for b in range(int(t0 / bar), int(t1 / bar) + 1):
		var xb := floorf(_x_of_tick(b * bar)) + 0.5
		draw_line(Vector2(xb, MARGIN_T), Vector2(xb, note_h), C["gridbar"], 1.0)

	# 2.5 循环区间着色 + 边界线（走带开着循环时显示）
	if transport != null and transport.loop_play:
		var ls: float = transport.loop_start
		var le: float = transport.loop_end if transport.loop_end > 0.0 else float(song.song_end_tick())
		if le > ls:
			var lx0 := maxf(_x_of_tick(ls), MARGIN_L)
			var lx1 := minf(_x_of_tick(le), w)
			if lx1 > lx0:
				draw_rect(Rect2(lx0, MARGIN_T, lx1 - lx0, note_h - MARGIN_T),
						Color(0.35, 0.6, 1.0, 0.045))
				draw_rect(Rect2(lx0, 0, lx1 - lx0, MARGIN_T), Color(0.35, 0.6, 1.0, 0.18))
				for xl in [lx0, lx1]:
					if xl >= MARGIN_L and xl <= w:
						draw_line(Vector2(floorf(xl) + 0.5, MARGIN_T),
								Vector2(floorf(xl) + 0.5, note_h), Color(0.45, 0.65, 1.0, 0.55), 1.0)

	# 3. 幽灵音符（其他轨，半透明；视口裁剪 + 密度上限防 N 轨渲染爆炸）
	var ghost_total := 0
	for trk in song.tracks.size():
		if trk != track_idx:
			ghost_total += (song.tracks[trk]["notes"] as Array).size()
	if ghost_total <= GHOST_NOTE_LIMIT:
		for trk2 in song.tracks.size():
			if trk2 == track_idx:
				continue
			for n in song.tracks[trk2]["notes"]:
				var gx := _x_of_tick(n["s"])
				if gx > w or gx + n["l"] * px_per_tick < MARGIN_L:
					continue
				_draw_note(n, trk2, 0.20)

	# 4. 当前轨音符（力度档位量化到 0.05；选中描白边）
	for n2 in song.track_notes(track_idx):
		var alpha := 0.55 + 0.45 * snappedf(n2["v"], 0.05)
		_draw_note(n2, track_idx, alpha, _selected.has(n2))

	# 4.5 框选矩形
	if _box_rect.size != Vector2.ZERO:
		draw_rect(_box_rect, Color(0.45, 0.65, 1.0, 0.10), true)
		draw_rect(_box_rect, Color(0.45, 0.65, 1.0, 0.7), false, 1.0, true)

	# 5. 新建预览
	if not _temp.is_empty():
		_draw_note(_temp, track_idx, 0.45, true)

	# 6. 播放头（整数对齐 2px 竖线 + 三角标记，锐利不闪）
	if transport != null:
		var xh := floorf(_x_of_tick(transport.playhead))
		if xh >= MARGIN_L and xh <= w:
			draw_line(Vector2(xh, MARGIN_T), Vector2(xh, note_h), C["playhead"], 2.0)
			draw_colored_polygon(PackedVector2Array([
				Vector2(xh - 5, MARGIN_T), Vector2(xh + 5, MARGIN_T), Vector2(xh, MARGIN_T + 6)
			]), C["playhead"])

	# 6.5 力度编辑条（当前轨；柱高=力度，选中音符柱加亮）
	draw_rect(Rect2(0, note_h, w, MARGIN_B), Color("1a1d24"))
	draw_line(Vector2(0, note_h + 0.5), Vector2(w, note_h + 0.5), C["border"], 1.0)
	var lane_h := MARGIN_B - 14.0
	draw_string(ThemeDB.fallback_font, Vector2(4, note_h + 12), "力度",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C["text"])
	for n3 in song.track_notes(track_idx):
		var vx := _x_of_tick(n3["s"])
		if vx < MARGIN_L - 4.0 or vx > w:
			continue
		var bh: float = maxf(n3["v"] * lane_h, 2.0)
		var sel_col := _note_color(track_idx, 1.0) if _selected.has(n3) \
				else _note_color(track_idx, 0.55)
		draw_rect(Rect2(floorf(vx), note_h + MARGIN_B - 4.0 - bh, 4.0, bh), sel_col)
		draw_rect(Rect2(floorf(vx) - 1.0, note_h + MARGIN_B - 4.0 - bh - 1.0, 6.0, 2.0),
				_note_color(track_idx, 1.0))

	# 7. 左侧琴键列
	draw_rect(Rect2(0, MARGIN_T, MARGIN_L - 2.0, view_h), C["bg"])
	for p2 in range(p_lo, p_hi + 1):
		var y2 := floorf(_y_of_pitch(p2))
		var black := NoteKeys.is_black(p2)
		var kw := MARGIN_L * (0.62 if black else 1.0) - 2.0
		var kcol: Color = Color("7fd3ff") if _kbd_midi == p2 else (C["kbd_black"] if black else C["kbd_white"])
		draw_style_box(_kbd_style(kcol), Rect2(0, y2, kw, ROW_H - 1.0))
		if p2 % 12 == 0:
			var font := ThemeDB.fallback_font
			draw_string(font, Vector2(kw - 20.0, y2 + ROW_H - 3.0), Theory.note_name(p2),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("6a7078") if not black else Color("9aa3b2"))

	# 8. 顶部标尺
	draw_rect(Rect2(MARGIN_L, 0, w - MARGIN_L, MARGIN_T), C["ruler"])
	var font2 := ThemeDB.fallback_font
	for b2 in range(int(t0 / bar), int(t1 / bar) + 1):
		var xb2 := _x_of_tick(b2 * bar)
		draw_string(font2, Vector2(xb2 + 3.0, 14), str(b2 + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C["text"])
	draw_rect(Rect2(0, 0, w, h), C["border"], false, 1.0, true)
	draw_line(Vector2(0, MARGIN_T + 0.5), Vector2(w, MARGIN_T + 0.5), C["border"], 1.0)
	draw_line(Vector2(MARGIN_L - 2.0 + 0.5, 0), Vector2(MARGIN_L - 2.0 + 0.5, h), C["border"], 1.0)


## 琴键列小键样式（圆角 2px）
func _kbd_style(col: Color) -> StyleBoxFlat:
	var key := "kbd_" + col.to_html()
	if not _sb_cache.has(key):
		var s := StyleBoxFlat.new()
		s.bg_color = col
		s.set_corner_radius_all(2)
		s.anti_aliasing = true
		_sb_cache[key] = s
	return _sb_cache[key]


func _draw_note(n: Dictionary, track: int, alpha: float, highlight := false) -> void:
	var x := _x_of_tick(n["s"])
	var y := _y_of_pitch(n["p"])
	if y < MARGIN_T - ROW_H or y > size.y or x > size.x:
		return
	var wpx: float = maxf(n["l"] * px_per_tick - 1.0, 3.0)
	var r := Rect2(floorf(x), floorf(y), wpx, ROW_H - 1.0)
	draw_style_box(_note_style(_note_color(track, alpha)), r)
	if highlight:
		draw_style_box(_hover_style(), r)
