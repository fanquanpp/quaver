class_name SongModel
extends RefCounted
## 工程数据模型：BPM + 多轨 + 音符，zstd 二进制序列化（.bsong）
##
## 时间单位：1 tick = 1/16 音符（4 ticks = 1 拍，16 ticks = 1 小节）。
## 音符为轻量 Dictionary {p:音高, s:起始tick, l:长度tick, v:力度0-1}，
## 引用语义便于钢琴卷帘拖拽时原地修改；存盘时平铺为整型流再压缩。
##
## v0.2 轨道模型（VERSION = 2）：
##   type     "melody" | "drum"（鼓机步进轨）
##   volume   0-1 轨道音量（对应轨道 Bus 增益）
##   pan      -1..1 声像（轨道 Bus Panner）
##   mute/solo 静音/独奏（独奏激活时非独奏轨等效静音）
##   reverb/delay 辅助发送量 0-1（Reverb/Delay Bus）
##   effects  效果链参数快照 [{type, params}]（JSON 序列化）
##   automation 预留（v0.3 自动化曲线）
## 读到 v1 工程自动迁移：新字段填默认值。

const MAGIC := 0x42535131  # "BSQ1"
const VERSION := 2
const TICKS_PER_BEAT := 4
const MAX_TRACKS := 16

const DEFAULT_VOLUME := 0.8

const TRACK_COLORS := [
	Color("4fc3f7"), Color("ffb74d"), Color("aed581"),
	Color("ce93d8"), Color("ff8a80"), Color("80cbc4"),
]

var bpm := 90.0
## 每轨: {name, instrument, color, notes, type, volume, pan, mute, solo,
##        reverb, delay, effects, automation}
var tracks: Array[Dictionary] = []


func _init() -> void:
	if tracks.is_empty():
		add_track("旋律", "钢琴")
		add_track("伴奏", "芯片")


## 一条轨道的完整字段（v2）；旧代码只读前四个字段不受影响
static func make_track(t_name: String, instrument: String, color: int, type := "melody") -> Dictionary:
	return {
		"name": t_name,
		"instrument": instrument,
		"color": color,
		"notes": [],
		"type": type,
		"volume": DEFAULT_VOLUME,
		"pan": 0.0,
		"mute": false,
		"solo": false,
		"reverb": 0.0,
		"delay": 0.0,
		"effects": [],
		"automation": [],
	}


func add_track(t_name: String, instrument: String, type := "melody") -> int:
	tracks.append(make_track(t_name, instrument, tracks.size() % TRACK_COLORS.size(), type))
	return tracks.size() - 1


## 删除轨道（至少保留 1 条）；返回被删轨道名，越界返回 ""
func remove_track(i: int) -> String:
	if i < 0 or i >= tracks.size() or tracks.size() <= 1:
		return ""
	var name: String = tracks[i]["name"]
	tracks.remove_at(i)
	return name


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
## v1 轨道布局：name/instrument/color/notes；v2 在 color 后追加混音字段

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
		_store_track_v2(f, trk)
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


static func _store_track_v2(f: FileAccess, trk: Dictionary) -> void:
	f.store_pascal_string(trk.get("type", "melody"))
	f.store_16(int(round(trk.get("volume", DEFAULT_VOLUME) * 1000.0)))
	f.store_16(int(round((clampf(trk.get("pan", 0.0), -1.0, 1.0) + 1.0) * 1000.0)))
	var flags := 0
	if trk.get("mute", false):
		flags |= 1
	if trk.get("solo", false):
		flags |= 2
	f.store_8(flags)
	f.store_16(int(round(trk.get("reverb", 0.0) * 1000.0)))
	f.store_16(int(round(trk.get("delay", 0.0) * 1000.0)))
	f.store_pascal_string(JSON.stringify(trk.get("effects", [])))
	f.store_pascal_string(JSON.stringify(trk.get("automation", [])))


static func load_from(path: String) -> SongModel:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null or f.get_32() != MAGIC:
		return null
	var version := f.get_16()
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
		if version >= 2:
			_load_track_v2(f, trk)
		else:
			# v1 → v2 迁移：新字段填默认值
			trk.merge(make_track(trk["name"], trk["instrument"], trk["color"]))
		var count := f.get_32()
		for i in count:
			trk["notes"].append({
				"p": f.get_16(), "s": f.get_32(),
				"l": f.get_16(), "v": f.get_16() / 100.0,
			})
		s.tracks.append(trk)
	f.close()
	return s


static func _load_track_v2(f: FileAccess, trk: Dictionary) -> void:
	trk["type"] = f.get_pascal_string()
	trk["volume"] = clampf(f.get_16() / 1000.0, 0.0, 1.5)
	trk["pan"] = clampf(f.get_16() / 1000.0 - 1.0, -1.0, 1.0)
	var flags := f.get_8()
	trk["mute"] = (flags & 1) != 0
	trk["solo"] = (flags & 2) != 0
	trk["reverb"] = clampf(f.get_16() / 1000.0, 0.0, 1.0)
	trk["delay"] = clampf(f.get_16() / 1000.0, 0.0, 1.0)
	var fx: Variant = JSON.parse_string(f.get_pascal_string())
	trk["effects"] = fx if fx is Array else []
	var auto: Variant = JSON.parse_string(f.get_pascal_string())
	trk["automation"] = auto if auto is Array else []


## ── 示范曲：《虫儿飞》完整改编（陈光荣曲，C 调，♩=96） ────────────
## 按 EveryonePiano 全谱（1=F 转C调）逐句转录：旋律在高音区，
## 「虫儿飞」为 6→3̇→2̇ 上行跳进；曲式 = 前奏4 + 主歌8 + 连接1 + 主歌8 + 副歌11 = 32 小节；
## 伴奏为分解和弦琶音（低音-五音-根-三度 ×2/小节），半小节和声切换处按谱拆分。

static func make_demo() -> SongModel:
	var s := SongModel.new()
	s.tracks.clear()
	s.add_track("旋律", "八音盒")
	s.add_track("伴奏", "钢琴")
	s.bpm = 96.0
	var mel: Array = []
	# ── 前奏（4 小节）：高音 mi–do 交替，第 3 小节附点装饰 ──
	mel += [
		[76, 0, 8], [72, 8, 8],
		[76, 16, 8], [72, 24, 8],
		[72, 32, 6], [72, 38, 2], [76, 40, 8],
		[76, 48, 8], [72, 56, 8],
	]
	# ── 主歌乐段（8 小节）：黑黑的天空低垂 / 亮亮的繁星相随 / 虫儿飞×2 / 你在思念谁 ──
	var verse := func(base: int) -> Array:
		return [
			[76, base, 4], [76, base + 4, 2], [76, base + 6, 2], [77, base + 8, 4], [79, base + 12, 4],
			[76, base + 16, 8], [74, base + 24, 8],
			[72, base + 32, 4], [72, base + 36, 2], [72, base + 38, 2], [74, base + 40, 4], [76, base + 44, 4],
			[76, base + 48, 8], [71, base + 56, 8],
			[69, base + 64, 4], [76, base + 68, 4], [74, base + 72, 8],
			[69, base + 80, 4], [76, base + 84, 4], [74, base + 88, 8],
			[69, base + 96, 4], [76, base + 100, 4], [74, base + 104, 6], [72, base + 110, 2],
			[72, base + 112, 16],
		]
	mel += verse.call(64)                 # 主歌 1（tick 64 = 第 5 小节）
	mel += [[72, 192, 8], [72, 200, 8]]   # 连接小节（一房子）
	mel += verse.call(208)                # 主歌 2（天上的星星流泪 / 冷风吹 只要有你陪）
	# ── 副歌（11 小节）：虫儿飞 花儿睡 / 一双又一对才美 / 不怕天黑只怕心碎 / 不管累不累 也不管东南西北 ──
	mel += [
		[72, 336, 8], [76, 344, 4], [74, 348, 4],
		[79, 352, 12], [77, 364, 2], [76, 366, 2],
		[74, 368, 12], [79, 380, 2], [77, 382, 2],
		[76, 384, 4], [77, 388, 2], [79, 390, 2], [76, 396, 4],
		[74, 400, 8],
		[69, 416, 4], [76, 420, 4], [74, 424, 6], [72, 430, 2],
		[67, 432, 4], [74, 436, 4], [72, 440, 4], [72, 444, 4],
		[77, 448, 2], [76, 450, 2], [77, 452, 2], [76, 454, 2], [72, 456, 8],
		[77, 464, 2], [76, 466, 2], [77, 468, 2], [76, 470, 2], [72, 472, 6], [74, 478, 2],
		[72, 480, 16], [72, 496, 16],
	]
	for m: Array in mel:
		s.add_note(0, m[0], m[1], m[2], 0.85)
	# ── 伴奏：分解和弦琶音（低音-五音-根音-三度 ×2/小节，1 tick = 1/16）──
	var chords := {
		"C": [48, 55, 60, 64], "G": [43, 50, 55, 59],
		"Am": [45, 52, 57, 60], "Em": [40, 47, 52, 55],
		"F": [41, 48, 53, 57], "Dm": [38, 45, 50, 53],
	}
	# 每小节 1-2 个和弦（"|" = 半小节处切换）
	var prog := [
		"C", "C", "C", "C",
		"C", "G", "Am", "Em", "F|G", "F|G", "F|G", "Am|G", "Am",
		"C", "G", "Am", "Em", "F|G", "F|G", "F|G", "Am|G",
		"Am|Em", "C", "G", "Am|F", "G", "F|G", "C|Am", "Dm|F", "Dm|F", "C|G", "C",
	]
	for bar in prog.size():
		var parts: PackedStringArray = (prog[bar] as String).split("|")
		for h in parts.size():
			var tones: Array = chords[parts[h]]
			var t0: int = bar * 16 + h * 8
			# 单和弦小节音型走两遍，双和弦各占半小节一遍
			for rep in (2 if parts.size() == 1 else 1):
				for step in 4:
					s.add_note(1, tones[step % 4], t0 + (rep * 4 + step) * 2, 2, 0.45)
	return s
