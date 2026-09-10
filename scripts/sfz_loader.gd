class_name SfzLoader
extends RefCounted
## SFZ 采样音色加载器（v1.0.0）——文本格式的采样映射（SFZ v1 常用子集）
##
## 支持的操作码：sample、key、pitch_keycenter、lokey/hikey、lovel/hivel；
## <group> 内的操作码作为其后 <region> 的默认值；一行可带多个 opcode。
## WAV 用 AudioStreamWAV.load_from_file 直接读。
## 返回 regions 数组：[{stream, lokey, hikey, lovel, hivel, key_center}]。
## SF2（二进制 RIFF）解析器不在 v1.0 范围，另行评估。

const DEFAULT_LOKEY := 0
const DEFAULT_HIKEY := 127
const DEFAULT_LOVEL := 0
const DEFAULT_HIVEL := 127


static func load_instrument(sfz_path: String) -> Array:
	if not FileAccess.file_exists(sfz_path):
		return []
	var f := FileAccess.open(sfz_path, FileAccess.READ)
	if f == null:
		return []
	var base_dir := sfz_path.get_base_dir()
	var regions: Array = []
	var defaults := {}   # <group> 级默认
	var current := {}    # 当前 <region> 的操作码
	var have_region := false
	while not f.eof_reached():
		var line := _clean_line(f.get_line())
		if line == "":
			continue
		var is_region := line.begins_with("<region>")
		var is_group := line.begins_with("<group>")
		if is_region or is_group:
			_flush(current, regions, base_dir)
			if is_region:
				current = defaults.duplicate()
				have_region = true
			else:
				current = {}
				defaults = {}
				have_region = false
			line = _strip_tag(line)
			if line == "":
				continue
		var ops := _parse_opcodes(line)
		for op in ops:
			if have_region:
				current[op] = ops[op]
			else:
				defaults[op] = ops[op]
	_flush(current, regions, base_dir)
	f.close()
	return regions


static func _clean_line(raw: String) -> String:
	var line := raw
	var comment := line.find("//")
	if comment >= 0:
		line = line.substr(0, comment)
	return line.strip_edges()


static func _strip_tag(line: String) -> String:
	var end := line.find(">")
	if end < 0:
		return ""
	return line.substr(end + 1).strip_edges()


## 解析一行内的多个 opcode："sample=a.wav key=60" → {sample:"a.wav", key:"60"}
## 未带 = 的后续 token 并入上一个值（带空格的路径）
static func _parse_opcodes(line: String) -> Dictionary:
	var out := {}
	var cur_op := ""
	for token in line.split(" ", false):
		if token.contains("="):
			var eq := token.find("=")
			cur_op = token.substr(0, eq).strip_edges().to_lower()
			var val := token.substr(eq + 1)
			if cur_op != "" and val != "":
				out[cur_op] = val
		elif cur_op != "":
			out[cur_op] = out[cur_op] + " " + token
	return out


static func _flush(current: Dictionary, regions: Array, base_dir: String) -> void:
	if current.is_empty() or not current.has("sample"):
		return
	var sample_path: String = current["sample"]
	if not sample_path.is_absolute_path():
		sample_path = base_dir + "/" + sample_path
	var stream := AudioStreamWAV.load_from_file(sample_path)
	if stream == null:
		return
	var key_val: int = int(current.get("key", 60))
	regions.append({
		"stream": stream,
		"lokey": int(current.get("lokey", key_val if current.has("key") else DEFAULT_LOKEY)),
		"hikey": int(current.get("hikey", key_val if current.has("key") else DEFAULT_HIKEY)),
		"lovel": int(current.get("lovel", DEFAULT_LOVEL)),
		"hivel": int(current.get("hivel", DEFAULT_HIVEL)),
		"key_center": int(current.get("pitch_keycenter", key_val)),
	})
