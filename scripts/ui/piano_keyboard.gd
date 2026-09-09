class_name PianoKeyboard
extends Control
## 演奏大键盘 v2：真钢琴比例 + 立体层次 + 按压动画。
##
## 视觉结构（自上而下）：上盖板(带八度标注) → 白键区(渐变键面/侧影/前缘) → 前条；
## 黑键带投影、左受光面、顶部亮面；按压时键面下沉（深度动画）并染色。
## 键宽上限 58px、键盘块水平居中、高度按真钢琴长宽比收敛，不再撑满整窗。

signal note_on(midi: int)
signal note_off(midi: int)

const WHITE_PCS := [0, 2, 4, 5, 7, 9, 11]
const W_IDX := {0: 0, 2: 1, 4: 2, 5: 3, 7: 4, 9: 5, 11: 6}
const BLACK_NUDGE := {1: -0.10, 3: 0.10, 6: -0.14, 8: 0.0, 10: 0.14}

# 键盘整体
const COL_BODY := Color("1b1e24")        # 控件底（琴体外）
const COL_FALLBOARD := Color("262a31")   # 上盖板
const COL_FALL_EDGE := Color("14161a")
const COL_RAIL := Color("17191d")        # 前条
const COL_RAIL_TOP := Color("2c313a")
# 白键
const W_TOP := Color("f1f3f7")
const W_MID := Color("e9ebee")
const W_BOT := Color("dde0e6")
const W_EDGE_L := Color("ffffff")
const W_EDGE_R := Color("c3c8d1")
const W_FRONT := Color("9ba1ac")
# 白键按下
const W_ON_TOP := Color("cfe9fa")
const W_ON_MID := Color("9fd4f4")
const W_ON_BOT := Color("6fb3e0")
const W_ON_FRONT := Color("4a90c2")
# 黑键
const B_BODY := Color("2a2d34")
const B_LEFT := Color("383c45")
const B_RIGHT := Color("1e2126")
const B_CAP := Color("4a505b")
const B_OUT := Color("121417")
const B_ON_BODY := Color("20232a")
const B_ON_CAP := Color("3a4048")
const B_ON_GLOW := Color("6fb3e0")
# 调内高亮
const W_SCALE := Color("dbead9")
const B_SCALE := Color("3f5347")
const SCALE_DIM := Color("6a7078")

const MAX_WHITE_W := 64.0
const KEY_SCALE_MIN := 0.6
const KEY_SCALE_MAX := 1.6

var base_octave := 4
var octaves := 2
## 键宽缩放（1.0 = 上限 64px/白键；演奏页滑杆 / Ctrl+滚轮调节）
var key_scale := 1.0
var pressed := {}
var show_labels := true
var key_root := 0
var scale_notes: Array = [0, 2, 4, 5, 7, 9, 11]
var scale_highlight := false

var _mouse_midi := -1
var _hover_midi := -1
var _depth := {}   # midi -> 0..1 按压深度（动画）
var _target := {}  # midi -> 目标深度


func _init() -> void:
	set_process(false)


## ── 几何 ───────────────────────────────────────────────────────────

func _layout() -> Dictionary:
	var whites := 7 * octaves + 1
	var ww: float = minf(size.x / float(whites), MAX_WHITE_W * key_scale)
	var kb_w := ww * whites
	var kb_h: float = minf(size.y - 8.0, ww * 6.2)
	# 全部取整到整数像素：自绘键面/分隔线不再有亚像素锯齿
	var ox := floorf((size.x - kb_w) * 0.5)
	var oy := floorf(maxf(6.0, (size.y - kb_h) * 0.5))
	var fall_h: float = floorf(clampf(kb_h * 0.09, 12.0, 24.0))
	var rail_h := 7.0
	var keys_h: float = floorf(kb_h - fall_h - rail_h)
	return {
		"ww": ww, "kb_w": kb_w, "ox": ox, "oy": oy,
		"fall_h": fall_h, "rail_h": rail_h, "keys_h": keys_h,
		"keys_top": oy + fall_h,
	}


## 第 wi 个白键的整数像素矩形（右缘留 1px 键缝，缝隙精确 1px 不闪烁）
func _white_rect(wi: int, L: Dictionary) -> Rect2:
	var x0: float = L["ox"] + floorf(wi * L["ww"])
	var x1: float = L["ox"] + floorf((wi + 1) * L["ww"])
	return Rect2(x0, L["keys_top"], maxf(x1 - x0 - 1.0, 2.0), L["keys_h"])


func _first_midi() -> int:
	return (base_octave + 1) * 12


func _white_index(midi: int) -> int:
	var pc := midi % 12
	if pc in NoteKeys.BLACK_PCS:
		pc -= 1  # 黑键映射到左侧相邻白键
	return (floori(midi / 12.0) - base_octave - 1) * 7 + W_IDX[pc]


func _white_midi(wi: int) -> int:
	var total := 7 * octaves + 1
	if wi < 0 or wi >= total:
		return -1
	if wi == 7 * octaves:
		return _first_midi() + 12 * octaves
	return _first_midi() + floori(wi / 7.0) * 12 + WHITE_PCS[wi % 7]


func _black_rect(midi: int, L: Dictionary) -> Rect2:
	var ww: float = L["ww"]
	var bw := ww * 0.58
	var bh: float = L["keys_h"] * 0.60
	var x: float = L["ox"] + (_white_index(midi) + 1) * ww - bw * 0.5 + BLACK_NUDGE[midi % 12] * ww
	var y: float = L["keys_top"] + _depth.get(midi, 0.0) * 3.0
	return Rect2(x, y, bw, bh)


## 黑键的整数像素矩形（绘制用，消除亚像素边缘锯齿；命中测试仍用浮点版）
func _black_rect_px(midi: int, L: Dictionary) -> Rect2:
	var r := _black_rect(midi, L)
	return Rect2(floorf(r.position.x), floorf(r.position.y), floorf(r.size.x), floorf(r.size.y))


func _hit(pos: Vector2) -> int:
	var L := _layout()
	var lx: float = pos.x - L["ox"]
	if lx < 0.0 or lx >= L["kb_w"] or pos.y < L["keys_top"]:
		return -1
	if pos.y > L["keys_top"] + L["keys_h"]:
		return -1
	var first := _first_midi()
	var count := 12 * octaves + 1
	for midi in range(first, first + count):
		if NoteKeys.is_black(midi):
			var r := _black_rect(midi, L)
			if pos.x >= r.position.x and pos.x < r.end.x and pos.y < r.end.y:
				return midi
	return _white_midi(int(lx / L["ww"]))


## ── 输入 ───────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed and mb.ctrl_pressed:
				# Ctrl+滚轮：整琴缩放
				var f := 1.08 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.08
				key_scale = clampf(key_scale * f, KEY_SCALE_MIN, KEY_SCALE_MAX)
				queue_redraw()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var m := _hit(mb.position)
				if m >= 0:
					_mouse_midi = m
					_press(m)
			elif _mouse_midi >= 0:
				_release(_mouse_midi)
				_mouse_midi = -1
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var hov := _hit(mm.position)
		if hov != _hover_midi:
			_hover_midi = hov
			queue_redraw()
		if _mouse_midi >= 0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var m := _hit(mm.position)
			if m >= 0 and m != _mouse_midi:
				_release(_mouse_midi)
				_press(m)
				_mouse_midi = m


func set_pressed(midi: int, on: bool) -> void:
	if on:
		_press(midi)
	else:
		_release(midi)


## 仅更新按压视觉，不触发 note_on/off 信号（多键盘同步专用，避免信号回环重复发声）
func set_pressed_silent(midi: int, on: bool) -> void:
	if on:
		if pressed.has(midi):
			return
		pressed[midi] = true
		_target[midi] = 1.0
	else:
		if not pressed.erase(midi):
			return
		_target[midi] = 0.0
	set_process(true)
	queue_redraw()


func _press(midi: int) -> void:
	if pressed.has(midi):
		return
	pressed[midi] = true
	_target[midi] = 1.0
	set_process(true)
	note_on.emit(midi)
	queue_redraw()


func _release(midi: int) -> void:
	if not pressed.erase(midi):
		return
	_target[midi] = 0.0
	set_process(true)
	note_off.emit(midi)
	queue_redraw()


## 按压深度动画：指数平滑，静止后停止处理（脏驱动，不空转）
func _process(delta: float) -> void:
	var busy := false
	for m in _target.keys():
		var t: float = _target[m]
		var d: float = _depth.get(m, 0.0)
		var nd: float = lerpf(d, t, minf(1.0, delta * 16.0))
		if absf(nd - t) < 0.02:
			nd = t
		else:
			busy = true
		_depth[m] = nd
		if nd == 0.0 and t == 0.0:
			_target.erase(m)
			_depth.erase(m)
	queue_redraw()
	if not busy:
		set_process(false)


## ── 绘制 ───────────────────────────────────────────────────────────

func _draw() -> void:
	var L := _layout()
	var ox: float = L["ox"]
	var oy: float = L["oy"]
	var ww: float = L["ww"]
	var kb_w: float = L["kb_w"]
	var kb_h: float = L["fall_h"] + L["keys_h"] + L["rail_h"]
	var keys_top: float = L["keys_top"]
	var keys_h: float = L["keys_h"]

	draw_rect(Rect2(0, 0, size.x, size.y), COL_BODY)

	var first := _first_midi()
	var count := 12 * octaves + 1

	# 1. 白键（渐变键面 + 侧缘 + 前缘，按压下沉；整数像素对齐）
	for midi in range(first, first + count):
		if NoteKeys.is_black(midi):
			continue
		_draw_white_key(midi, _white_rect(_white_index(midi), L))

	# 2. 黑键投影 → 黑键（左受光/右暗/顶亮面，按压下沉）
	for midi in range(first, first + count):
		if NoteKeys.is_black(midi):
			var br := _black_rect_px(midi, L)
			draw_rect(Rect2(br.position.x + 2.0, br.end.y, br.size.x, 6.0), Color(0, 0, 0, 0.18))
	for midi in range(first, first + count):
		if NoteKeys.is_black(midi):
			_draw_black_key(midi, _black_rect_px(midi, L))

	# 3. 上盖板（压在键顶之上，制造"琴体在键后面"的层次）
	draw_rect(Rect2(ox, oy, kb_w, L["fall_h"]), COL_FALLBOARD)
	draw_rect(Rect2(ox, oy + L["fall_h"] - 2.0, kb_w, 2.0), COL_FALL_EDGE)
	var font := ThemeDB.fallback_font
	for midi in range(first, first + count, 12):
		var wi := _white_index(midi)
		var name_txt: String = "C%d" % (floori(midi / 12.0) - 1)
		var wr := _white_rect(wi, L)
		var tw := font.get_string_size(name_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, Vector2(wr.position.x + wr.size.x * 0.5 - tw * 0.5, oy + L["fall_h"] - 6.0),
				name_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("9aa3b2"))

	# 4. 前条
	draw_rect(Rect2(ox, keys_top + keys_h, kb_w, L["rail_h"]), COL_RAIL)
	draw_rect(Rect2(ox, keys_top + keys_h, kb_w, 1.0), Color("0e1013"))
	draw_rect(Rect2(ox, keys_top + keys_h + L["rail_h"] - 1.0, kb_w, 1.0), COL_RAIL_TOP)
	# 琴体外框：一圈 1px 描边收束轮廓（抗锯齿）
	draw_rect(Rect2(ox - 1.0, oy - 1.0, kb_w + 2.0, kb_h + 2.0), Color("0b0d10"), false, 1.0, true)

	# 5. 键帽字母
	if show_labels:
		for midi in range(first, first + count):
			var lbl: String = NoteKeys.SEMI_LABELS.get(midi - first, "")
			if lbl == "":
				continue
			var ts := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
			if NoteKeys.is_black(midi):
				var br2 := _black_rect_px(midi, L)
				draw_string(font, Vector2(br2.position.x + br2.size.x * 0.5 - ts.x * 0.5,
						br2.end.y - 6.0 - _depth.get(midi, 0.0) * 3.0), lbl,
						HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("cfd4dc"))
			else:
				var wr2 := _white_rect(_white_index(midi), L)
				draw_string(font, Vector2(wr2.position.x + wr2.size.x * 0.5 - ts.x * 0.5,
						keys_top + keys_h - 6.0), lbl,
						HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("5c6068"))


func _draw_white_key(midi: int, r: Rect2) -> void:
	var on := pressed.has(midi)
	var d: float = _depth.get(midi, 0.0)
	var sink := d * 4.0
	var face := Rect2(r.position.x, r.position.y + sink, r.size.x, r.size.y - sink)
	# 按压时顶部露出"铰链阴影"槽
	if sink > 0.5:
		draw_rect(Rect2(r.position.x, r.position.y, r.size.x, sink), Color(0, 0, 0, 0.30))
	# 三段渐变键面
	var top_c := W_ON_TOP if on else W_TOP
	var mid_c := W_ON_MID if on else W_MID
	var bot_c := W_ON_BOT if on else W_BOT
	if scale_highlight and not on:
		if Theory.in_scale(midi, key_root, scale_notes):
			top_c = W_SCALE
			mid_c = W_SCALE.lerp(W_MID, 0.4)
		else:
			top_c = W_TOP.lerp(SCALE_DIM, 0.35)
			mid_c = W_MID.lerp(SCALE_DIM, 0.35)
			bot_c = W_BOT.lerp(SCALE_DIM, 0.35)
	draw_rect(Rect2(face.position, Vector2(face.size.x, face.size.y * 0.4)), top_c)
	draw_rect(Rect2(face.position + Vector2(0, face.size.y * 0.4), Vector2(face.size.x, face.size.y * 0.35)), mid_c)
	draw_rect(Rect2(face.position + Vector2(0, face.size.y * 0.75), Vector2(face.size.x, face.size.y * 0.25 + 1.0)), bot_c)
	# 侧缘 + 前缘
	draw_rect(Rect2(face.position, Vector2(1.0, face.size.y)), W_EDGE_L)
	draw_rect(Rect2(face.position.x + face.size.x - 1.0, face.position.y, 1.0, face.size.y), W_EDGE_R)
	draw_rect(Rect2(face.position.x, face.end.y - 2.0, face.size.x, 2.0), W_ON_FRONT if on else W_FRONT)
	# 悬停微亮（动效反馈）
	if not on and midi == _hover_midi:
		draw_rect(face, Color(1, 1, 1, 0.08))


func _draw_black_key(midi: int, r: Rect2) -> void:
	var on := pressed.has(midi)
	var body := B_ON_BODY if on else B_BODY
	var cap := B_ON_CAP if on else B_CAP
	if scale_highlight and not on and Theory.in_scale(midi, key_root, scale_notes):
		body = B_SCALE
	# 键身三分面（左受光/中/右暗）
	draw_rect(Rect2(r.position, Vector2(r.size.x * 0.16, r.size.y)), B_LEFT if not on else body.lightened(0.04))
	draw_rect(Rect2(r.position + Vector2(r.size.x * 0.16, 0), Vector2(r.size.x * 0.68, r.size.y)), body)
	draw_rect(Rect2(r.position + Vector2(r.size.x * 0.84, 0), Vector2(r.size.x * 0.16, r.size.y)), B_RIGHT)
	# 顶部亮面 + 描边（抗锯齿，轮廓干净）
	draw_rect(Rect2(r.position, Vector2(r.size.x, maxf(r.size.y * 0.10, 4.0))), cap)
	draw_rect(r, B_OUT, false, 1.0, true)
	# 悬停微亮（动效反馈）
	if not on and midi == _hover_midi:
		draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5)), Color(1, 1, 1, 0.06))
	# 按下时底部发光反馈
	if on:
		draw_rect(Rect2(r.position.x + 1.0, r.end.y - 2.0, r.size.x - 2.0, 2.0), B_ON_GLOW)
