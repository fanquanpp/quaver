extends Node
## 自动加载 Theory —— 乐理引擎门面（混合语言入口）
##
## 优先加载 gode 的 TypeScript 实现（res://scripts/theory.ts），
## gode 插件缺失或加载失败时无缝回退 GDScript 内置实现（NoteKeys）。
## 调用方无感知：Theory.scale_chord(...) 两个后端行为一致。

const TS_PATH := "res://scripts/theory.ts"

var _ts: Node = null
var backend := "gdscript"


func _ready() -> void:
	if FileAccess.file_exists("res://addons/gode/plugin.cfg"):
		var script: Script = load(TS_PATH)
		if script != null and script.can_instantiate():
			# TypeScriptScript 不支持 .new()，按标准方式挂载脚本实例化
			_ts = Node.new()
			_ts.set_script(script)
			add_child(_ts)
			backend = "gode-typescript"
	print("[Theory] 乐理引擎后端: %s" % backend)


func _use_ts(method: String) -> bool:
	return _ts != null and _ts.has_method(method)


func scale_chord(midi: int, key_root: int, scale: Array) -> Array:
	if _use_ts("scale_chord"):
		return _ts.call("scale_chord", midi, key_root, scale)
	return NoteKeys.scale_chord(midi, key_root, scale)


func in_scale(midi: int, key_root: int, scale: Array) -> bool:
	if _use_ts("in_scale"):
		return _ts.call("in_scale", midi, key_root, scale)
	return NoteKeys.in_scale(midi, key_root, scale)


func note_name(midi: int) -> String:
	if _use_ts("note_name"):
		return _ts.call("note_name", midi)
	return NoteKeys.note_name(midi)


func scale_notes(key_root: int, scale: Array) -> Array:
	if _use_ts("scale_notes"):
		return _ts.call("scale_notes", key_root, scale)
	return NoteKeys.scale_notes(key_root, scale)


func midi_to_freq(midi: float) -> float:
	if _use_ts("midi_to_freq"):
		return _ts.call("midi_to_freq", midi)
	return NoteKeys.midi_to_freq(midi)
