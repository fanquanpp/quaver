class_name SheetMusic
extends RefCounted
## 乐谱导出：把工程生成为 MusicXML（score-partwise 4.0）纯文本。
##
## 调研结论（2026-09）：Godot 生态没有可用的记谱/制谱插件（Asset Library 与 GitHub
## 均无维护中的 MusicXML 渲染器；OpenSheetMusicDisplay 是 Web/JS 方案，引入需
## WebView 桥接，成本高）。因此走标准交换格式：MusicXML → MuseScore（免费）等
## 记谱软件打开即得可打印乐谱，后续也可接 OpenSheetMusicDisplay 渲染内置预览。
##
## 转换规则：1 tick = 1/16 音符；divisions=4（四分音符 4 divisions，1 tick = 1）。
## 拍号固定 4/4（模型无小节线概念，按 16 tick 切）。调号取分析检测结果（低置信
## 回落 C 大调）。音高全部用升号拼写。跨小节音符拆成连线段；时值分解为
## 附点全音符/二分/四分/八分组合，贪婪取最大。同起同长的音符合并为和弦。

const TICKS_PER_MEASURE := 16
const DIVISIONS := 4

## 时值（tick 数）→ [type 名, 是否附点]，覆盖 1..16 全部可单一拼写值
const TYPE_OF := {
	16: ["whole", false], 12: ["half", true], 8: ["half", false],
	6: ["quarter", true], 4: ["quarter", false], 3: ["eighth", true],
	2: ["eighth", false], 1: ["16th", false],
}
## 音级 → [音名, 变音记号]（升号拼写）
const PC_TO_STEP := [
	["C", 0], ["C", 1], ["D", 0], ["D", 1], ["E", 0], ["F", 0],
	["F", 1], ["G", 0], ["G", 1], ["A", 0], ["A", 1], ["B", 0],
]
const MAJOR_FIFTHS := {0: 0, 7: 1, 2: 2, 9: 3, 4: 4, 11: 5, 6: 6, 5: -1, 10: -2, 3: -3, 8: -4, 1: -5}
const MINOR_FIFTHS := {9: 0, 4: 1, 11: 2, 6: 3, 1: 4, 8: 5, 3: 6, 2: -1, 7: -2, 0: -3, 5: -4, 10: -5}


static func export_song(song: SongModel, path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(build_xml(song))
	var err := f.get_error()
	f.close()
	return err


static func build_xml(song: SongModel) -> String:
	var key := SongAnalysis.analyze(song)["key"] as Dictionary
	var fifths := 0
	if key["confidence"] >= 25:
		var tab: Dictionary = MINOR_FIFTHS if key["minor"] else MAJOR_FIFTHS
		fifths = tab.get(key["root"], 0)
	var out := ""
	out += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	out += "<!DOCTYPE score-partwise PUBLIC \"-//Recordare//DTD MusicXML 4.0 Partwise//EN\" \"http://www.musicxml.org/dtds/partwise.dtd\">\n"
	out += "<score-partwise version=\"4.0\">\n"
	out += "\t<work><work-title>编趣 Quaver 导出</work-title></work>\n"
	out += "\t<part-list>\n"
	for t in song.tracks.size():
		var trk: Dictionary = song.tracks[t]
		out += "\t\t<score-part id=\"P%d\"><part-name>%s</part-name></score-part>\n" % [
			t + 1, _esc(trk["name"])]
	out += "\t</part-list>\n"
	var measures := maxi(ceili(float(_max_end(song)) / TICKS_PER_MEASURE), 1)
	for t in song.tracks.size():
		out += _part_xml(song, t, measures, fifths)
	out += "</score-partwise>\n"
	return out


## ── 单个声部（轨） ─────────────────────────────────────────────────

static func _part_xml(song: SongModel, trk: int, measures: int, fifths: int) -> String:
	var avg_pitch := 0.0
	var note_count := 0
	for n in song.track_notes(trk):
		avg_pitch += n["p"]
		note_count += 1
	avg_pitch = avg_pitch / note_count if note_count > 0 else 60.0
	var clef := "\t\t\t\t<clef><sign>G</sign><line>2</line></clef>\n" if avg_pitch >= 57.0 \
			else "\t\t\t\t<clef><sign>F</sign><line>4</line></clef>\n"

	var groups := _chord_groups(song.track_notes(trk))
	# 按小节切段：每小节内收集 [起始tick, 时值, 音高数组]
	var seg_by_measure := {}
	for g in groups:
		for seg in _split_measure(g):
			var m := int(seg["m"])
			if not seg_by_measure.has(m):
				seg_by_measure[m] = []
			seg_by_measure[m].append(seg)

	var out := "\t<part id=\"P%d\">\n" % (trk + 1)
	for m in measures:
		out += "\t\t<measure number=\"%d\">\n" % (m + 1)
		if m == 0:
			out += "\t\t\t<attributes>\n"
			out += "\t\t\t\t<divisions>%d</divisions>\n" % DIVISIONS
			out += "\t\t\t\t<key><fifths>%d</fifths></key>\n" % fifths
			out += "\t\t\t\t<time><beats>4</beats><beat-type>4</beat-type></time>\n"
			out += clef
			out += "\t\t\t</attributes>\n"
			var bpm := int(round(song.bpm))
			out += "\t\t\t<direction placement=\"above\"><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>%d</per-minute></metronome></direction-type><sound tempo=\"%d\"/></direction>\n" % [bpm, bpm]
		var segs: Array = seg_by_measure.get(m, [])
		segs.sort_custom(func(a, b): return a["s"] < b["s"])
		var cursor := 0  # 小节内 tick 偏移
		for seg in segs:
			var s: int = seg["s"]
			if s < cursor:
				continue  # 重叠音符：无声部语义下跳过渲染（数据不动）
			if s > cursor:
				out += _note_xml(-1, s - cursor, {"tie_start": false, "tie_end": false}, [])
			out += _note_xml(seg["pitches"][0], seg["l"], seg, seg["pitches"].slice(1))
			cursor = s + seg["l"]
		if cursor < TICKS_PER_MEASURE:
			out += _note_xml(-1, TICKS_PER_MEASURE - cursor, {"tie_start": false, "tie_end": false}, [])
		if m == measures - 1:
			out += "\t\t\t<barline location=\"right\"><bar-style>light-heavy</bar-style></barline>\n"
		out += "\t\t</measure>\n"
	out += "\t</part>\n"
	return out


## 同一起始且同一长度的音符合并为和弦组 {s, l, pitches:[升序]}
static func _chord_groups(notes: Array) -> Array:
	var sorted := notes.duplicate()
	sorted.sort_custom(func(a, b): return a["s"] < b["s"] if a["s"] != b["s"] else a["p"] < b["p"])
	var groups: Array = []
	for n in sorted:
		if not groups.is_empty():
			var g: Dictionary = groups[-1]
			if g["s"] == n["s"] and g["l"] == n["l"]:
				g["pitches"].append(n["p"])
				continue
		groups.append({"s": n["s"], "l": n["l"], "pitches": [n["p"]]})
	return groups


## 和弦组跨小节时切成段：{m:小节号, s:小节内偏移, l:段长, pitches, tie_start, tie_end}
static func _split_measure(g: Dictionary) -> Array:
	var out: Array = []
	var s: int = g["s"]
	var remain: int = g["l"]
	var first := true
	while remain > 0:
		var m := int(floor(float(s) / TICKS_PER_MEASURE))
		var off := s - m * TICKS_PER_MEASURE
		var in_measure: int = mini(remain, TICKS_PER_MEASURE - off)
		out.append({
			"m": m, "s": off, "l": in_measure, "pitches": g["pitches"],
			"tie_start": in_measure < remain, "tie_end": not first,
		})
		first = false
		s += in_measure
		remain -= in_measure
	return out


## 时值分解：贪婪取最大可拼写值，段间内部 tie（首段 tie_end、末段 tie_start）
static func _decompose(l: int) -> Array:
	var sizes := TYPE_OF.keys()
	sizes.sort_custom(func(a, b): return a > b)
	var pieces: Array = []
	var remain := l
	while remain > 0:
		for v in sizes:
			if v <= remain:
				pieces.append(v)
				remain -= v
				break
	var out: Array = []
	for i in pieces.size():
		var spec: Array = TYPE_OF[pieces[i]]
		out.append({
			"dur": pieces[i], "type": spec[0], "dot": spec[1],
			"tie_start": i < pieces.size() - 1,
			"tie_end": i > 0,
		})
	return out


## 音符/休止符 XML。
## seg = {tie_start:向右跨小节连, tie_end:承接左连线}；chord_extra = 和弦成员
## （带 <chord/>，与主音同时值同连线）
static func _note_xml(pitch: int, dur_ticks: int, seg: Dictionary, chord_extra: Array) -> String:
	var pieces := _decompose(dur_ticks)
	var out := ""
	for i in chord_extra.size() + 1:
		var p: int = pitch if i == 0 else chord_extra[i - 1]
		for j in pieces.size():
			var piece: Dictionary = pieces[j]
			var tie_s: bool = piece["tie_start"] or (j == pieces.size() - 1 and seg["tie_start"])
			var tie_e: bool = piece["tie_end"] or (j == 0 and seg["tie_end"])
			out += "\t\t\t<note>\n"
			if i > 0:
				out += "\t\t\t\t<chord/>\n"
			if p < 0:
				out += "\t\t\t\t<rest/>\n"
			else:
				var step: Array = PC_TO_STEP[p % 12]
				out += "\t\t\t\t<pitch>\n"
				out += "\t\t\t\t\t<step>%s</step>\n" % step[0]
				if step[1] != 0:
					out += "\t\t\t\t\t<alter>%d</alter>\n" % step[1]
				out += "\t\t\t\t\t<octave>%d</octave>\n" % (floori(p / 12.0) - 1)
				out += "\t\t\t\t</pitch>\n"
			out += "\t\t\t\t<duration>%d</duration>\n" % piece["dur"]
			if tie_s:
				out += "\t\t\t\t<tie type=\"start\"/>\n"
			if tie_e:
				out += "\t\t\t\t<tie type=\"stop\"/>\n"
			out += "\t\t\t\t<type>%s</type>\n" % piece["type"]
			if piece["dot"]:
				out += "\t\t\t\t<dot/>\n"
			if tie_s or tie_e:
				out += "\t\t\t\t<notations>\n"
				if tie_e:
					out += "\t\t\t\t\t<tied type=\"stop\"/>\n"
				if tie_s:
					out += "\t\t\t\t\t<tied type=\"start\"/>\n"
				out += "\t\t\t\t</notations>\n"
			out += "\t\t\t</note>\n"
	return out


static func _max_end(song: SongModel) -> int:
	var t := 0
	for trk in song.tracks:
		for n in trk["notes"]:
			t = maxi(t, n["s"] + n["l"])
	return t


static func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
