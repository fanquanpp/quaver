class_name SongAnalysis
extends RefCounted
## 乐曲静态分析（纯计算，无副作用）：统计指标 + 调性检测 + 音级时长分布。
##
## 调性检测采用 Krumhansl-Schmuckler 算法（Krumhansl-Kessler 音级权重剖面 +
## Pearson 相关），输入为按音级加权的时长向量，输出最相关的 24 个大小调之一。
## 属"纯计算"模块：v0.1.3 以 GDScript 落地（与 SongModel 字典数据零转换成本、
## 不依赖 gode 编译服务）；接口稳定后可平移到 theory.ts，调用方不变。

## Krumhansl-Kessler 音级权重剖面（大调 / 自然小调）
const KK_MAJOR := [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
const KK_MINOR := [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]


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
