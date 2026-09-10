class_name MidiFile
extends RefCounted
## 标准 MIDI 文件（SMF）导入导出 —— 纯静态模块，无 UI 依赖。
##
## 量化约定：1 bsong tick = 1/16 音符；导出用 PPQ=480（1 tick = 30 MIDI tick），
## 导入按文件自己的 division 换算并四舍五入回 1/16 网格。
## 导出：格式 1，轨 0 = 速度/拍号元信息，其后每工程轨一个 MIDI 轨（轨名 + 程序变更）。
## 导入：格式 0/1 均可；按 (轨, 通道) 分组还原为工程轨，GM 程序号启发式映射回本软件音色，
##       通道 10（打击乐）也保留（映射到「芯片」，丢音符不如先存下来）。

const PPQ := 480
const TICKS_PER_QUANTA := 30  # PPQ / 16分音符数每四分音符
const GM_MAP_PATH := "user://gm_map.json"

static var _gm_map := {}
static var _gm_map_loaded := false

## 本软件音色 → GM 程序号（大钢琴/方波主音/暖垫/指弹贝斯/电钢/八音盒）
const INST_TO_PROGRAM := {
	"钢琴": 0, "芯片": 80, "柔弦": 89, "贝斯": 33, "电钢": 4, "八音盒": 10,
}


static func export_song(song: SongModel, path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.big_endian = true  # MIDI 是大端；Godot store_32/16 默认小端
	f.store_32(0x4D546864)  # "MThd"
	f.store_32(6)
	f.store_16(1)  # 格式 1
	f.store_16(song.tracks.size() + 1)
	f.store_16(PPQ)
	_write_chunk(f, _tempo_track_bytes(song.bpm))
	for t in song.tracks.size():
		_write_chunk(f, _track_bytes(song, t))
	var err := f.get_error()
	f.close()
	return err


## 解析失败返回 null；成功返回新 SongModel（轨按 MIDI 内容重建）
static func import_file(path: String) -> SongModel:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var data := f.get_buffer(f.get_length())
	f.close()
	var tracks_raw := _parse(data)
	if tracks_raw.is_empty():
		return null
	var s := SongModel.new()
	s.tracks.clear()
	if not tracks_raw["tempos"].is_empty():
		s.bpm = tracks_raw["tempos"][0]
	for trk in tracks_raw["tracks"]:
		if trk["notes"].is_empty():
			continue
		var idx := s.add_track(trk["name"], trk["instrument"])
		for n in trk["notes"]:
			s.add_note(idx, n["p"], n["s"], n["l"], n["v"])
	if s.tracks.is_empty():
		s.add_track("旋律", "钢琴")
	return s


## ── 导出 ───────────────────────────────────────────────────────────

static func _tempo_track_bytes(bpm: float) -> PackedByteArray:
	var evs: Array = []
	var us := int(round(60_000_000.0 / bpm))
	var name_b := PackedByteArray([0xFF, 0x03])
	name_b.append_array(_vlq(6))
	name_b.append_array("Quaver".to_ascii_buffer())
	evs.append([0.0, -2, name_b])
	evs.append([0.0, -1, PackedByteArray([0xFF, 0x51, 0x03,
			(us >> 16) & 0xFF, (us >> 8) & 0xFF, us & 0xFF])])
	evs.append([0.0, 0, PackedByteArray([0xFF, 0x58, 0x04, 4, 2, 24, 8])])  # 4/4
	return _encode_events(evs)


static func _track_bytes(song: SongModel, trk_idx: int) -> PackedByteArray:
	var trk: Dictionary = song.tracks[trk_idx]
	var ch := trk_idx % 16
	var evs: Array = []
	var name_bytes := String(trk["name"]).to_utf8_buffer()
	var name_b := PackedByteArray([0xFF, 0x03])
	name_b.append_array(_vlq(name_bytes.size()))
	name_b.append_array(name_bytes)
	evs.append([0.0, -1, name_b])
	var prog: int = INST_TO_PROGRAM.get(trk["instrument"], 0)
	evs.append([0.0, -1, PackedByteArray([0xC0 | ch, prog])])
	for n in trk["notes"]:
		var vel := int(round(clampf(n["v"], 0.05, 1.0) * 127.0))
		var p: int = clampi(n["p"], 0, 127)
		evs.append([float(n["s"]) * TICKS_PER_QUANTA, 0, PackedByteArray([0x90 | ch, p, vel])])
		# 关闭音排在开启音前，同 tick 重复触发不断音
		evs.append([float(n["s"] + n["l"]) * TICKS_PER_QUANTA, -1,
				PackedByteArray([0x80 | ch, p, 0])])
	return _encode_events(evs)


## 事件按 (tick, 序) 排序后差分编码；末尾自动补 EOT
static func _encode_events(evs: Array) -> PackedByteArray:
	evs.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	var out := PackedByteArray()
	var last := 0.0
	for e in evs:
		out.append_array(_vlq(int(round(e[0] - last))))
		out.append_array(e[2])
		last = e[0]
	out.append_array(PackedByteArray([0x00, 0xFF, 0x2F, 0x00]))
	return out


static func _vlq(value: int) -> PackedByteArray:
	var bytes: Array = [value & 0x7F]
	value >>= 7
	while value > 0:
		bytes.append((value & 0x7F) | 0x80)
		value >>= 7
	var out := PackedByteArray()
	for i in range(bytes.size() - 1, -1, -1):
		out.append(bytes[i])
	return out


static func _write_chunk(f: FileAccess, body: PackedByteArray) -> void:
	f.store_32(0x4D54726B)  # "MTrk"
	f.store_32(body.size())
	f.store_buffer(body)


## ── 导入 ───────────────────────────────────────────────────────────
## 返回 {tempos:[bpm...], tracks:[{name, instrument, notes:[bsong音符]}]}

static func _parse(data: PackedByteArray) -> Dictionary:
	if data.size() < 14 or data[0] != 0x4D or data[1] != 0x54:
		return {}
	var pos := 8
	var division := _u16(data, pos + 4)
	if division & 0x8000:
		return {}  # SMPTE 时间格式不支持
	pos += 6
	var tempos: Array = []
	var groups := {}       # "mtrk:通道" -> {name, prog, chan, notes:[{p,s,l,v}]}
	var g_order: Array = []
	var mtrk_names: Array = []
	var open := {}         # "g:音高" -> 绝对起始 tick
	var g_idx := -1
	while pos + 8 <= data.size():
		if data[pos] != 0x4D or data[pos + 1] != 0x54:
			break
		var body_len := _u32(data, pos + 4)
		var body := pos + 8
		g_idx += 1
		mtrk_names.append("")
		var p := body
		var end_p := body + body_len
		var abs_tick := 0
		var running := -1
		while p < end_p:
			var delta := 0
			while p < end_p:
				var b := data[p]
				p += 1
				delta = (delta << 7) | (b & 0x7F)
				if b & 0x80 == 0:
					break
			if p >= end_p:
				break
			abs_tick += delta
			var st := data[p]
			if st & 0x80:
				p += 1
				running = st
			else:
				st = running
				if st < 0:
					break
			if st == 0xFF:  # 元事件
				if p + 2 > end_p:
					break
				var meta_type := data[p]
				p += 1
				var mlen := _vlq_at(data, p)
				p += _vlq_size(data, p)
				if meta_type == 0x51 and mlen == 3:
					var us := (data[p] << 16) | (data[p + 1] << 8) | data[p + 2]
					if us > 0:
						tempos.append(roundf(60_000_000.0 / float(us)))
				elif meta_type == 0x03:
					mtrk_names[g_idx] = data.slice(p, p + mlen).get_string_from_utf8()
				elif meta_type == 0x2F:
					break
				p += mlen
			elif st == 0xF0 or st == 0xF7:  # 系统独占：跳过
				var slen := _vlq_at(data, p)
				p += _vlq_size(data, p) + slen
			else:
				var kind := st & 0xF0
				var chan := st & 0x0F
				var nbytes := 1 if kind in [0xC0, 0xD0] else 2
				if p + nbytes > end_p:
					break
				var g := "%d:%d" % [g_idx, chan]
				if kind == 0x90 and data[p + 1] > 0:
					if not groups.has(g):
						groups[g] = {"name": "", "prog": -1, "chan": chan, "notes": []}
						g_order.append(g)
					open[g + ":" + str(data[p])] = [abs_tick, data[p + 1]]
				elif kind == 0x80 or (kind == 0x90 and data[p + 1] == 0):
					var key := g + ":" + str(data[p])
					if open.has(key):
						var on: Array = open[key]
						open.erase(key)
						var grp: Dictionary = groups[g]
						grp["notes"].append({
							"p": int(data[p]),
							"s": int(round(on[0] / float(TICKS_PER_QUANTA))),
							"l": maxi(int(round(float(abs_tick - on[0]) / TICKS_PER_QUANTA)), 1),
							"v": clampf(on[1] / 127.0, 0.05, 1.0),
						})
				elif kind == 0xC0:
					if not groups.has(g):
						groups[g] = {"name": "", "prog": -1, "chan": chan, "notes": []}
						g_order.append(g)
					groups[g]["prog"] = data[p]
				p += nbytes
		pos = end_p
	# 组 → 工程轨（轨名取该 MTrk 的最终元事件值）
	var tracks: Array = []
	for g in g_order:
		var grp: Dictionary = groups[g]
		if grp["notes"].is_empty():
			continue
		grp["name"] = mtrk_names[int(g.split(":")[0])]
		if grp["name"] == "":
			grp["name"] = "轨 %d" % (tracks.size() + 1)
		tracks.append({
			"name": grp["name"],
			"instrument": _program_to_inst(grp["prog"], grp["chan"]),
			"notes": grp["notes"],
		})
	return {"tempos": tempos, "tracks": tracks}


static func _program_to_inst(prog: int, chan: int) -> String:
	var m := _load_gm_map()
	# 打击乐通道优先（语义独立于程序号）
	if chan == 9:
		var drum: String = m.get("chan9", "芯片")
		return drum if _inst_valid(drum) else "芯片"
	# v0.3.1：用户自定义映射优先（user://gm_map.json，见 _load_gm_map）
	if not m.is_empty():
		var programs: Dictionary = m.get("programs", {})
		if programs.has(str(int(prog))):
			var inst: String = programs[str(int(prog))]
			if _inst_valid(inst):
				return inst
	if prog == 4:
		return "电钢"
	if prog == 8 or prog == 10:
		return "八音盒"
	if prog >= 32 and prog <= 39:
		return "贝斯"
	if (prog >= 40 and prog <= 54) or (prog >= 88 and prog <= 95):
		return "柔弦"
	if (prog >= 80 and prog <= 87) or (prog >= 96 and prog <= 103):
		return "芯片"
	return "钢琴"


## 自定义映射表：{"chan9": "鼓组", "programs": {"0": "贝斯", ...}}
## 值必须是有效音色（InstrumentBank 音色或"鼓组"），非法值回退内置启发式
static func _load_gm_map() -> Dictionary:
	if _gm_map_loaded:
		return _gm_map
	_gm_map_loaded = true
	if not FileAccess.file_exists(GM_MAP_PATH):
		return {}
	var f := FileAccess.open(GM_MAP_PATH, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	_gm_map = data if data is Dictionary else {}
	return _gm_map


static func _inst_valid(inst: String) -> bool:
	return inst == InstrumentBank.DRUM_INST or inst in InstrumentBank.INSTRUMENTS


static func _u16(d: PackedByteArray, i: int) -> int:
	return (d[i] << 8) | d[i + 1]


static func _u32(d: PackedByteArray, i: int) -> int:
	return (d[i] << 24) | (d[i + 1] << 16) | (d[i + 2] << 8) | d[i + 3]


static func _vlq_at(d: PackedByteArray, i: int) -> int:
	var v := 0
	while i < d.size():
		var b := d[i]
		v = (v << 7) | (b & 0x7F)
		if b & 0x80 == 0:
			break
		i += 1
	return v


static func _vlq_size(d: PackedByteArray, i: int) -> int:
	var n := 1
	while i < d.size() and d[i] & 0x80:
		n += 1
		i += 1
	return n
