class_name EditHistory
extends RefCounted
## 撤销重做：快照式历史栈（时间机器模型）。
##
## 音符是引用语义 Dictionary，拖拽时原地修改，无法做增量命令反转；
## 工程体量极小（千音符 < 10KB），整曲深拷贝快照是零风险方案。
## 约定：每次「编辑完成」后调用 push()（存的是已修改后的状态），
## undo() 回到上一个快照，redo() 前进。reset() 在载入新工程时重置基线。

signal history_changed(can_undo: bool, can_redo: bool)

const MAX_STATES := 100

var _states: Array = []   # [{bpm:float, tracks:[深拷贝轨]}]
var _idx := -1
var _dirty := false       # 连续修改（如速度拖动）中：撤销前先把当前态落栈


func reset(song: SongModel) -> void:
	_states = [_snapshot(song)]
	_idx = 0
	_dirty = false
	history_changed.emit(false, false)


## 连续型修改（SpinBox 拖动等）只标脏，不逐格落快照；
## 真正的 undo()/push() 到来时才固化，redo 因此能回到最终值
func mark_dirty() -> void:
	_dirty = true


## 编辑完成后落快照；与栈顶相同（无效编辑）则跳过
func push(song: SongModel) -> void:
	_dirty = false
	var cur := _snapshot(song)
	if _idx >= 0 and _states_equal(_states[_idx], cur):
		return
	_states.resize(_idx + 1)
	_states.append(cur)
	if _states.size() > MAX_STATES:
		_states.pop_front()
	_idx = _states.size() - 1
	history_changed.emit(can_undo(), can_redo())


func undo(song: SongModel) -> bool:
	if _dirty:
		push(song)
	if not can_undo():
		return false
	_idx -= 1
	_restore(song, _states[_idx])
	history_changed.emit(can_undo(), can_redo())
	return true


func redo(song: SongModel) -> bool:
	if _dirty:
		push(song)
	if not can_redo():
		return false
	_idx += 1
	_restore(song, _states[_idx])
	history_changed.emit(can_undo(), can_redo())
	return true


func can_undo() -> bool:
	return _idx > 0


func can_redo() -> bool:
	return _idx < _states.size() - 1


## ── 快照 / 还原（双向深拷贝，杜绝历史态与活模型共享引用） ──────────

static func _snapshot(song: SongModel) -> Dictionary:
	return {"bpm": song.bpm, "tracks": _copy_tracks(song.tracks)}


static func _copy_tracks(tracks: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for trk in tracks:
		var notes: Array = []
		for n in trk["notes"]:
			notes.append({"p": n["p"], "s": n["s"], "l": n["l"], "v": n["v"]})
		out.append({
			"name": trk["name"], "instrument": trk["instrument"],
			"color": trk["color"], "notes": notes,
		})
	return out


static func _restore(song: SongModel, st: Dictionary) -> void:
	song.bpm = st["bpm"]
	song.tracks = _copy_tracks(st["tracks"])


static func _states_equal(a: Dictionary, b: Dictionary) -> bool:
	if absf(a["bpm"] - b["bpm"]) > 0.0001 or a["tracks"].size() != b["tracks"].size():
		return false
	for t in a["tracks"].size():
		var ta: Dictionary = a["tracks"][t]
		var tb: Dictionary = b["tracks"][t]
		if ta["name"] != tb["name"] or ta["instrument"] != tb["instrument"] \
				or ta["color"] != tb["color"] or ta["notes"].size() != tb["notes"].size():
			return false
		for i in ta["notes"].size():
			var na: Dictionary = ta["notes"][i]
			var nb: Dictionary = tb["notes"][i]
			if na["p"] != nb["p"] or na["s"] != nb["s"] \
					or na["l"] != nb["l"] or absf(na["v"] - nb["v"]) > 0.0001:
				return false
	return true
