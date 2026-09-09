class_name NoteRain
extends Control
## 演奏回声条（音符记录小显示）：弹过的音显示为从琴键上方升起的色块，
## 按住越长块越高，松手后整体上浮渐隐；底部命中线随按压发光。
## 设计参考 Synthesia/SeeMusic 类可视化器的"音符雨 + 命中反馈"惯例，
## 本作横置琴键 → 演化为"上升回声"。脏驱动：无音符时停止 _process。

const RISE_MS := 1500.0
const COL_BG := Color("1b1e24")
const COL_LINE := Color("0e1013")

var kb: PianoKeyboard  ## 用于对齐琴键横向位置（含黑键窄块）

var _blocks: Array = []  # {midi:int, t0:int, t1:int(0=按住中), col:Color}


func _ready() -> void:
	set_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func note_hit(midi: int, col: Color) -> void:
	_blocks.append({"midi": midi, "t0": Time.get_ticks_msec(), "t1": 0, "col": col})
	set_process(true)
	queue_redraw()


func note_lift(midi: int) -> void:
	var now := Time.get_ticks_msec()
	for b in _blocks:
		if b["midi"] == midi and b["t1"] == 0:
			b["t1"] = now
	set_process(true)
	queue_redraw()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	_blocks = _blocks.filter(func(b: Dictionary) -> bool:
		var end: int = b["t1"] if b["t1"] > 0 else now
		return now - end < RISE_MS)
	queue_redraw()
	if _blocks.is_empty():
		set_process(false)


func _draw() -> void:
	draw_rect(Rect2(0, 0, size.x, size.y), COL_BG)
	draw_rect(Rect2(0, size.y - 1.0, size.x, 1.0), COL_LINE)
	if kb == null:
		return
	var L := kb._layout()
	var now := Time.get_ticks_msec()
	var any_held := false
	for b in _blocks:
		var held: bool = b["t1"] == 0
		if held:
			any_held = true
		var midi: int = b["midi"]
		# 与键盘同宽系：白键整宽 / 黑键 0.58 窄块
		var x: float
		var w: float
		if NoteKeys.is_black(midi):
			var bw: float = L["ww"] * 0.58
			x = L["ox"] + (kb._white_index(midi) + 1) * L["ww"] - bw * 0.5 + kb.BLACK_NUDGE[midi % 12] * L["ww"]
			w = bw
		else:
			x = L["ox"] + kb._white_index(midi) * L["ww"]
			w = L["ww"] - 1.0
		# 高度 = 按住时长（上限满条）；松手后整体上浮 + 渐隐
		var grow_ms: float = float((b["t1"] if not held else now) - b["t0"])
		var h: float = clampf(grow_ms / RISE_MS, 0.06, 1.0) * (size.y - 4.0)
		var rise_ms: float = 0.0 if held else float(now - b["t1"])
		var rise: float = clampf(rise_ms / RISE_MS, 0.0, 1.0)
		# 整数像素对齐：填充矩形零锯齿
		var x_px := floorf(x)
		var w_px := maxf(ceilf(w), 2.0)
		var h_px := maxf(ceilf(h), 3.0)
		var y_px: float = floorf(size.y - h_px - rise * size.y)
		var col: Color = b["col"]
		col.a = (0.95 if held else 0.95 * (1.0 - rise))
		var r := Rect2(x_px, y_px, w_px, h_px)
		# 两段明暗造层次：顶部亮 / 主体本色 + 1px 抗锯齿描边
		var band := minf(5.0, h_px)
		draw_rect(Rect2(r.position, Vector2(r.size.x, band)), col.lightened(0.35))
		draw_rect(Rect2(r.position + Vector2(0, band), Vector2(r.size.x, r.size.y - band)), col)
		draw_rect(r, Color(0, 0, 0, 0.3), false, 1.0, true)
	# 命中线：有键按住时发光
	if any_held:
		draw_rect(Rect2(0, size.y - 3.0, size.x, 2.0), Color("4fc3f7", 0.75))
		draw_rect(Rect2(0, size.y - 1.0, size.x, 1.0), Color(1, 1, 1, 0.5))
