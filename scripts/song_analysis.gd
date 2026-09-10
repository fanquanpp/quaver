class_name SongAnalysis
extends RefCounted
## 乐曲静态分析（纯计算，无副作用）：统计指标 + 调性检测 + 音级时长分布
## + 和弦进行检测 + 曲式结构分段 + 和声/旋律建议（v0.3.0）。
##
## 调性检测采用 Krumhansl-Schmuckler 算法（Krumhansl-Kessler 音级权重剖面 +
## Pearson 相关），输入为按音级加权的时长向量，输出最相关的 24 个大小调之一。
## 属"纯计算"模块：v0.1.3 以 GDScript 落地（与 SongModel 字典数据零转换成本、
## 不依赖 gode 编译服务）；接口稳定后可平移到 theory.ts，调用方不变。

## Krumhansl-Kessler 音级权重剖面（大调 / 自然小调）
const KK_MAJOR := [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
const KK_MINOR := [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

## 和弦模板：pcs = 相对根音的音级集合，q = 质量后缀
const CHORD_TEMPLATES := [
	{"q": "", "pcs": [0, 4, 7]},
	{"q": "m", "pcs": [0, 3, 7]},
	{"q": "7", "pcs": [0, 4, 7, 10]},
	{"q": "m7", "pcs": [0, 3, 7, 10]},
	{"q": "maj7", "pcs": [0, 4, 7, 11]},
	{"q": "dim", "pcs": [0, 3, 6]},
	{"q": "sus4", "pcs": [0, 5, 7]},
]
## 大调/自然小调的音级 → 功能级罗马数字（非调内音级回退 ""）
const ROMAN_MAJOR := {0: "I", 2: "ii", 4: "iii", 5: "IV", 7: "V", 9: "vi", 11: "vii°"}
const ROMAN_MINOR := {0: "i", 2: "ii°", 3: "III", 5: "iv", 7: "v", 8: "VI", 10: "VII"}
## 功能和声进行表（大调，按当前和弦的功能级给候选）
const NEXT_DEGREE_MAJOR := {
	"I": ["IV", "V", "vi"], "ii": ["V"], "iii": ["vi", "IV"],
	"IV": ["V", "I"], "V": ["I", "vi"], "vi": ["ii", "IV"], "vii°": ["I"],
}
const NEXT_DEGREE_MINOR := {
	"i": ["iv", "V", "VI"], "ii°": ["V"], "III": ["VI", "iv"],
	"iv": ["V", "i"], "v": ["i", "VI"], "VI": ["iv", "VII"], "VII": ["i"],
}


## 全量分析。返回：
## {
##   note_count, per_track: [{name, color, count}], empty,
##   dur_ticks, dur_secs, bars, bpm,
##   pitch_min, pitch_max, pitch_span,
##   avg_vel, avg_len, density, max_poly,
##   pc_profile: Array[12]（音级时长权重，C 起始）,
##   key: {root, minor, r, name, confidence, scale_pcs}
## }
static func analyze(song: SongModel) -> Dictionary:
	var note_count := 0
	var per_track: Array = []
	var pitch_min := 127
	var pitch_max := 0
	var vel_sum := 0.0
	var len_sum := 0
	var pc: Array = []
	pc.resize(12)
	for i in 12:
		pc[i] = 0.0
	# 事件扫描（同时音数 + 音级权重）
	var ev: Array = []  # [tick, ±1]
	for trk in song.tracks:
		var cnt := 0
		for n in trk["notes"]:
			cnt += 1
			note_count += 1
			var p: int = n["p"]
			pitch_min = mini(pitch_min, p)
			pitch_max = maxi(pitch_max, p)
			vel_sum += n["v"]
			len_sum += n["l"]
			var w: float = n["l"] * n["v"]  # 时长×力度加权
			pc[p % 12] += w
			ev.append([float(n["s"]), 1])
			ev.append([float(n["s"] + n["l"]), -1])
		per_track.append({"name": trk["name"], "color": trk["color"], "count": cnt})
	var dur_ticks := song.song_end_tick()
	var dur_secs := dur_ticks * song.secs_per_tick()
	var bars := ceili(dur_ticks / 16.0)
	ev.sort_custom(func(a, b): return a[0] < b[0])
	var cur := 0
	var max_poly := 0
	for e in ev:
		cur += e[1]
		max_poly = maxi(max_poly, cur)
	var key := detect_key(pc)
	return {
		"note_count": note_count,
		"per_track": per_track,
		"empty": note_count == 0,
		"dur_ticks": dur_ticks,
		"dur_secs": dur_secs,
		"bars": bars,
		"bpm": song.bpm,
		"pitch_min": pitch_min if note_count > 0 else 60,
		"pitch_max": pitch_max if note_count > 0 else 60,
		"pitch_span": (pitch_max - pitch_min) if note_count > 0 else 0,
		"avg_vel": vel_sum / note_count if note_count > 0 else 0.0,
		"avg_len": len_sum / float(note_count) if note_count > 0 else 0.0,
		"density": note_count / dur_secs if dur_secs > 0.0 else 0.0,
		"max_poly": max_poly,
		"pc_profile": pc,
		"key": key,
	}


## Krumhansl-Schmuckler：音级时长向量与 24 个旋转 KK 剖面求 Pearson 相关，
## 相关最高者为检测结果。confidence = (best_r - second_r) 映射到 0-100。
static func detect_key(pc: Array) -> Dictionary:
	var total := 0.0
	for v in pc:
		total += v
	if total <= 0.0001:
		return {"root": 0, "minor": false, "r": 0.0, "name": "—", "confidence": 0, "scale_pcs": [0, 2, 4, 5, 7, 9, 11]}
	var best_r := -2.0
	var second_r := -2.0
	var best_root := 0
	var best_minor := false
	for minor in [false, true]:
		var prof: Array = KK_MINOR if minor else KK_MAJOR
		for root in 12:
			var rotated: Array = []
			rotated.resize(12)
			for i in 12:
				rotated[i] = prof[(i - root + 12) % 12]
			var r := _pearson(pc, rotated)
			if r > best_r:
				second_r = best_r
				best_r = r
				best_root = root
				best_minor = minor
			elif r > second_r:
				second_r = r
	var conf := int(round(clampf((best_r - second_r) * 4.0, 0.0, 1.0) * 100.0))
	var scale: Array = NoteKeys.SCALES["自然小调" if best_minor else "大调"]
	return {
		"root": best_root,
		"minor": best_minor,
		"r": best_r,
		"name": "%s%s" % [NoteKeys.SHARP_NAMES[best_root], " 小调" if best_minor else " 大调"],
		"confidence": conf,
		"scale_pcs": scale,
	}


static func _pearson(a: Array, b: Array) -> float:
	var n := a.size()
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += a[i]
		mb += b[i]
	ma /= n
	mb /= n
	var num := 0.0
	var da := 0.0
	var db := 0.0
	for i in n:
		num += (a[i] - ma) * (b[i] - mb)
		da += pow(a[i] - ma, 2.0)
		db += pow(b[i] - mb, 2.0)
	if da <= 0.000001 or db <= 0.000001:
		return 0.0
	return num / sqrt(da * db)


## ── 和弦进行检测（v0.3.0） ─────────────────────────────────────────
## 逐小节把音级时长向量与（12 根音 × 模板）匹配：模板内权重占比 − 模板外惩罚。
## 返回 [{bar, root, quality, name, roman, score}]；roman 相对 key_root
## （key_root < 0 或非调内级时 roman=""）。

static func detect_chords(song: SongModel, key_root := -1, minor := false) -> Array:
	var bars := maxi(ceili(song.song_end_tick() / 16.0), 1)
	var out: Array = []
	for bar in bars:
		var v: Array = []
		v.resize(12)
		for i in 12:
			v[i] = 0.0
		var total := 0.0
		var lowest := 128
		for trk in song.tracks:
			for n in trk["notes"]:
				var s0: int = n["s"]
				var s1: int = n["s"] + n["l"]
				var ov: int = mini(s1, (bar + 1) * 16) - maxi(s0, bar * 16)
				if ov > 0:
					var w: float = ov * n["v"]
					v[n["p"] % 12] += w
					total += w
					lowest = mini(lowest, n["p"])
		if total <= 0.0001:
			out.append({"bar": bar, "root": -1, "quality": "", "name": "—", "roman": "", "score": 0.0})
			continue
		# 低音加权：最低音的音级额外 +35%（低音强烈指示和弦根音）
		if lowest <= 127:
			v[lowest % 12] += total * 0.15
		var best_score := -1e9
		var best_root := 0
		var best_q := ""
		for root in 12:
			for tpl in CHORD_TEMPLATES:
				var inside := 0.0
				var outside := 0.0
				for i in 12:
					if (i - root + 12) % 12 in tpl["pcs"]:
						inside += v[i]
					else:
						outside += v[i]
				# 四音模板（七和弦）需第 7 音证据充足，否则倾向三和弦
				if tpl["pcs"].size() >= 4:
					var w7: float = v[(root + tpl["pcs"][3]) % 12]
					if w7 < 0.25 * inside:
						continue
				# 尺寸归一化防多音模板占优 + 根音权重加成防同集异根误判
				var size_f := float(tpl["pcs"].size())
				var score: float = (inside - 0.7 * outside) / size_f + 0.35 * float(v[root]) / size_f
				if score > best_score:
					best_score = score
					best_root = root
					best_q = tpl["q"]
		var name := "%s%s" % [NoteKeys.SHARP_NAMES[best_root], best_q]
		var roman := _roman_of(best_root, key_root, minor)
		out.append({"bar": bar, "root": best_root, "quality": best_q,
				"name": name, "roman": roman, "score": best_score / total})
	return out


static func _roman_of(root: int, key_root: int, minor: bool) -> String:
	if key_root < 0:
		return ""
	var table: Dictionary = ROMAN_MINOR if minor else ROMAN_MAJOR
	return table.get((root - key_root + 12) % 12, "")


## ── 曲式结构分段（v0.3.0） ─────────────────────────────────────────
## 每小节特征 = 音级时长向量；相邻小节余弦相似度低于阈值或密度跳变 > 2×
## 即切段（最短 2 小节）；段落按与已有段落的相似度聚类命名 A/B/A/B…
## 返回 [{start_bar, end_bar, label, profile}]（end 为开区间小节号）。

static func detect_sections(song: SongModel, sim_threshold := 0.82) -> Array:
	var bars := maxi(ceili(song.song_end_tick() / 16.0), 1)
	var profiles: Array = []
	var density: Array = []
	for bar in bars:
		var v: Array = []
		v.resize(12)
		for i in 12:
			v[i] = 0.0
		var cnt := 0
		for trk in song.tracks:
			for n in trk["notes"]:
				var ov: int = mini(n["s"] + n["l"], (bar + 1) * 16) - maxi(n["s"], bar * 16)
				if ov > 0:
					v[n["p"] % 12] += ov
					cnt += ov / float(maxi(n["l"], 1))
		profiles.append(v)
		density.append(cnt)
	if bars == 0:
		return []
	# 切边界
	var cuts: Array = [0]
	var bar := 2  # 最短段 2 小节：从第 3 小节起才允许切
	while bar < bars:
		var sim := _cosine(profiles[bar], profiles[bar - 1])
		var dens_jump: bool = density[bar - 1] > 0 and (density[bar] > density[bar - 1] * 2.0
				or density[bar] * 2.0 < density[bar - 1])
		if sim < sim_threshold or dens_jump:
			cuts.append(bar)
			bar += 2
		else:
			bar += 1
	# 分段并命名（与已有段落相似 → 复用字母）
	var letters := "ABCDEFGH"
	var sections: Array = []
	var sec_profiles: Array = []
	var sec_labels: Array = []
	for i in cuts.size():
		var start: int = cuts[i]
		var end: int = cuts[i + 1] if i + 1 < cuts.size() else bars
		var prof := _merge_profiles(profiles, start, end)
		var label := ""
		for j in sec_profiles.size():
			if _cosine(prof, sec_profiles[j]) >= 0.9:
				label = sec_labels[j]
				break
		if label == "":
			label = letters[mini(sec_labels.size(), letters.length() - 1)]
			sec_profiles.append(prof)
			sec_labels.append(label)
		sections.append({"start_bar": start, "end_bar": end, "label": label, "profile": prof})
	return sections


static func _merge_profiles(profiles: Array, start: int, end: int) -> Array:
	var v: Array = []
	v.resize(12)
	for i in 12:
		v[i] = 0.0
	for b in range(start, end):
		for i in 12:
			v[i] += profiles[b][i]
	return v


static func _cosine(a: Array, b: Array) -> float:
	var dot := 0.0
	var na := 0.0
	var nb := 0.0
	for i in a.size():
		dot += a[i] * b[i]
		na += a[i] * a[i]
		nb += b[i] * b[i]
	if na <= 0.000001 or nb <= 0.000001:
		return 0.0
	return dot / sqrt(na * nb)


## ── 智能建议（v0.3.0） ─────────────────────────────────────────────
## 下一和弦候选：功能和声进行表（大调 I→IV/V/vi、V→I…）。
## 输入当前最后一个和弦（root + 判断其功能级）；返回候选数组
## [{degree, root, quality, name, why}]。

static func suggest_next_chords(chords: Array, key_root: int, minor := false) -> Array:
	var last := {}
	for c in chords:
		if c["root"] >= 0:
			last = c
	if last.is_empty() or key_root < 0:
		return []
	var table: Dictionary = NEXT_DEGREE_MINOR if minor else NEXT_DEGREE_MAJOR
	# 当前和弦的功能级：优先用已算好的 roman，否则现算
	var deg: String = last["roman"]
	if deg == "":
		deg = _roman_of(last["root"], key_root, minor)
	var candidates: Array = table.get(deg, ["I" if not minor else "i"])
	# 调内各级三和弦的根音音级与质量（大调：I ii iii IV V vi vii°）
	var scale_degrees: Array = [
		{"deg": "I", "root_pc": 0, "q": ""}, {"deg": "ii", "root_pc": 2, "q": "m"},
		{"deg": "iii", "root_pc": 4, "q": "m"}, {"deg": "IV", "root_pc": 5, "q": ""},
		{"deg": "V", "root_pc": 7, "q": ""}, {"deg": "vi", "root_pc": 9, "q": "m"},
		{"deg": "vii°", "root_pc": 11, "q": "dim"},
	]
	var minor_degrees: Array = [
		{"deg": "i", "root_pc": 0, "q": "m"}, {"deg": "ii°", "root_pc": 2, "q": "dim"},
		{"deg": "III", "root_pc": 3, "q": ""}, {"deg": "iv", "root_pc": 5, "q": "m"},
		{"deg": "v", "root_pc": 7, "q": "m"}, {"deg": "VI", "root_pc": 8, "q": ""},
		{"deg": "VII", "root_pc": 10, "q": ""},
	]
	var degrees: Array = minor_degrees if minor else scale_degrees
	var out: Array = []
	for want in candidates:
		for d in degrees:
			if d["deg"] == want:
				out.append({
					"degree": want,
					"root": (key_root + d["root_pc"]) % 12,
					"quality": d["q"],
					"name": "%s%s" % [NoteKeys.SHARP_NAMES[(key_root + d["root_pc"]) % 12], d["q"]],
					"why": "%s → %s" % [deg, want],
				})
	return out


## 旋律建议：给定和弦（root/quality）与调内音级，在 last_pitch 附近一个八度内
## 生成候选音高（和弦音优先，穿插调内经过音）。返回 [{pitch, note, kind}]
static func suggest_melody(chord_root: int, chord_quality: String,
		scale_pcs: Array, last_pitch := 72) -> Array:
	var chord_pcs: Array = [0, 4, 7]
	for tpl in CHORD_TEMPLATES:
		if tpl["q"] == chord_quality:
			chord_pcs = tpl["pcs"]
	var out: Array = []
	var seen := {}
	for iv in range(-5, 8):  # last_pitch ±半八度内的调内音
		var p := last_pitch + iv
		if p < 21 or p > 107:
			continue
		var pc: int = (p - chord_root + 12) % 12
		if pc in chord_pcs:
			out.append({"pitch": p, "note": NoteKeys.note_name(p), "kind": "和弦音"})
			seen[p] = true
	for iv2 in range(-7, 9):
		var p2 := last_pitch + iv2
		if p2 < 21 or p2 > 107 or seen.has(p2):
			continue
		if (p2 - chord_root + 12) % 12 in scale_pcs and absi(iv2) <= 7:
			out.append({"pitch": p2, "note": NoteKeys.note_name(p2), "kind": "经过音"})
	return out
