class_name TrackPresets
extends RefCounted
## 轨道预设（v0.3.1）：把轨道条（音色/类型/音量/声像/发送）存为具名预设，
## JSON 落盘 user://track_presets.json；音符不入预设。

const PATH := "user://track_presets.json"
## 预设包含的字段（不含 name/notes/color）
const FIELDS := ["instrument", "type", "volume", "pan", "mute", "solo", "reverb", "delay"]


## 返回 {预设名: {field: value}}
static func list_all() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return data if data is Dictionary else {}


## 以轨道名保存/覆盖预设
static func save_track(trk: Dictionary) -> String:
	var all := list_all()
	var p := {}
	for k in FIELDS:
		p[k] = trk.get(k, null)
	all[trk["name"]] = p
	_write(all)
	return trk["name"]


static func delete_preset(p_name: String) -> void:
	var all := list_all()
	all.erase(p_name)
	_write(all)


## 把预设应用到轨道字典（保留 name/notes/color）
static func apply_to(trk: Dictionary, p_name: String) -> bool:
	var all := list_all()
	if not all.has(p_name):
		return false
	var p: Dictionary = all[p_name]
	for k in FIELDS:
		if p.has(k) and p[k] != null:
			trk[k] = p[k]
	return true


static func _write(all: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(all, "  "))
	f.close()
