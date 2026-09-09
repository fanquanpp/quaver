class_name SongModel
extends RefCounted
## 工程数据模型：BPM + 多轨 + 音符，zstd 二进制序列化（.bsong）
##
## 时间单位：1 tick = 1/16 音符（4 ticks = 1 拍，16 ticks = 1 小节）。
## 音符为轻量 Dictionary {p:音高, s:起始tick, l:长度tick, v:力度0-1}，
## 引用语义便于钢琴卷帘拖拽时原地修改；存盘时平铺为整型流再压缩。

const MAGIC := 0x42535131  # "BSQ1"
const VERSION := 1
const TICKS_PER_BEAT := 4

const TRACK_COLORS := [
	Color("4fc3f7"), Color("ffb74d"), Color("aed581"),
	Color("ce93d8"), Color("ff8a80"), Color("80cbc4"),
]

var bpm := 90.0
## 每轨: {name:String, instrument:String, color:int, notes:Array[Dictionary]}
var tracks: Array[Dictionary] = []


func _init() -> void:
	if tracks.is_empty():
		add_track("旋律", "钢琴")
		add_track("伴奏", "芯片")


func add_track(t_name: String, instrument: String) -> int:
	tracks.append({
		"name": t_name,
		"instrument": instrument,
		"color": tracks.size() % TRACK_COLORS.size(),
		"notes": [],
	})
	return tracks.size() - 1


func track_notes(i: int) -> Array:
	return tracks[i]["notes"]


func add_note(track: int, pitch: int, start: int, length: int, vel := 0.8) -> Dictionary:
	var n := {
		"p": clampi(pitch, 0, 127),
		"s": maxi(start, 0),
		"l": maxi(length, 1),
		"v": clampf(vel, 0.05, 1.0),
	}
	track_notes(track).append(n)
	return n


func remove_note(track: int, note: Dictionary) -> void:
	track_notes(track).erase(note)


## 命中测试：pitch 行上、tick 落在 [s, s+l) 内的音符
func note_at(track: int, pitch: int, tick: int) -> Dictionary:
	for n in track_notes(track):
		if n["p"] == pitch and tick >= n["s"] and tick < n["s"] + n["l"]:
			return n
	return {}


func song_end_tick() -> int:
	var t := 0
	for trk in tracks:
		for n in trk["notes"]:
			t = maxi(t, n["s"] + n["l"])
	return t


func secs_per_tick() -> float:
	return 60.0 / bpm / float(TICKS_PER_BEAT)


## ── 序列化 ─────────────────────────────────────────────────────────
## .bsong：zstd 压缩二进制，千音符工程 < 10KB

func save(path: String) -> Error:
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return FileAccess.get_open_error()
	f.store_32(MAGIC)
	f.store_16(VERSION)
	f.store_float(bpm)
	f.store_16(tracks.size())
	for trk in tracks:
		f.store_pascal_string(trk["name"])
		f.store_pascal_string(trk["instrument"])
		f.store_32(trk["color"])
		var notes: Array = trk["notes"]
		f.store_32(notes.size())
		for n in notes:
			f.store_16(n["p"])
			f.store_32(n["s"])
			f.store_16(n["l"])
			f.store_16(int(round(n["v"] * 100.0)))
	var err := f.get_error()
	f.close()
	return err


static func load_from(path: String) -> SongModel:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null or f.get_32() != MAGIC:
		return null
	f.get_16()  # 版本号（当前固定为 1，向前兼容预留）
	var s := SongModel.new()
	s.tracks.clear()
	s.bpm = f.get_float()
	var n_tracks := f.get_16()
	for t in n_tracks:
		var trk := {
			"name": f.get_pascal_string(),
			"instrument": f.get_pascal_string(),
			"color": f.get_32(),
			"notes": [],
		}
		var count := f.get_32()
		for i in count:
			trk["notes"].append({
				"p": f.get_16(), "s": f.get_32(),
				"l": f.get_16(), "v": f.get_16() / 100.0,
			})
		s.tracks.append(trk)
	f.close()
	return s


## ── 示范曲：《小星星》双轨 ────────────────────────────────────────

static func make_demo() -> SongModel:
	var s := SongModel.new()
	s.tracks.clear()
	s.add_track("旋律", "钢琴")
	s.add_track("伴奏", "柔弦")
	s.bpm = 96.0
	# 主旋律（C 大调，1 tick = 1/16，四分音符 = 4 ticks）
	var mel := [
		[60, 0], [60, 4], [67, 8], [67, 12], [69, 16], [69, 20], [67, 24, 8],
		[65, 32], [65, 36], [64, 40], [64, 44], [62, 48], [62, 52], [60, 56, 8],
		[67, 64], [67, 68], [65, 72], [65, 76], [64, 80], [64, 84], [62, 88, 8],
		[67, 96], [67, 100], [65, 104], [65, 108], [64, 112], [64, 116], [62, 120, 8],
		[60, 128], [60, 132], [67, 136], [67, 140], [69, 144], [69, 148], [67, 152, 8],
		[65, 160], [65, 164], [64, 168], [64, 172], [62, 176], [62, 180], [60, 184, 8],
	]
	for m in mel:
		s.add_note(0, m[0], m[1], m[2] if m.size() > 2 else 4, 0.85)
	# 和弦伴奏（每小节一个三和弦垫底：C C F C C G C G C C F C）
	var prog := [48, 48, 53, 48, 48, 55, 48, 55, 48, 48, 53, 48]
	for bar in prog.size():
		var root: int = prog[bar]
		for iv in [0, 4, 7]:
			s.add_note(1, root + iv, bar * 16, 16, 0.55)
	return s
