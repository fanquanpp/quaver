class_name NoteKeys
## 电脑键位 ↔ 音高映射、音名、音阶表（纯静态工具，零依赖）
##
## 键位布局采用 DAW 通行的两行式（物理键位，与输入法/键盘布局无关）：
##   低八度：Z S X D C V G B H N J M（+ , L . ; / 延伸）
##   高八度：Q 2 W 3 E R 5 T 6 Y 7 U I（+ 9 O 0 P 延伸）
##   ↑ / ↓ 整体升降八度

const SHARP_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

const BLACK_PCS := [1, 3, 6, 8, 10]

## 物理键码 → 相对当前八度根音(C)的半音偏移
const KEY_TO_SEMI := {
	KEY_Z: 0, KEY_S: 1, KEY_X: 2, KEY_D: 3, KEY_C: 4, KEY_V: 5,
	KEY_G: 6, KEY_B: 7, KEY_H: 8, KEY_N: 9, KEY_J: 10, KEY_M: 11,
	KEY_COMMA: 12, KEY_L: 13, KEY_PERIOD: 14, KEY_SEMICOLON: 15, KEY_SLASH: 16,
	KEY_Q: 12, KEY_2: 13, KEY_W: 14, KEY_3: 15, KEY_E: 16, KEY_R: 17,
	KEY_5: 18, KEY_T: 19, KEY_6: 20, KEY_Y: 21, KEY_7: 22, KEY_U: 23,
	KEY_I: 24, KEY_9: 25, KEY_O: 26, KEY_0: 27, KEY_P: 28,
}

## 半音偏移 → 键帽显示字符（优先 Q 行/主行，避开重复键）
const SEMI_LABELS := {
	0: "Z", 1: "S", 2: "X", 3: "D", 4: "C", 5: "V", 6: "G", 7: "B",
	8: "H", 9: "N", 10: "J", 11: "M", 12: "Q", 13: "2", 14: "W", 15: "3",
	16: "E", 17: "R", 18: "5", 19: "T", 20: "6", 21: "Y", 22: "7", 23: "U",
	24: "I", 25: "9", 26: "O", 27: "0", 28: "P",
}

## 音阶（半音集合，相对调内主音）
const SCALES := {
	"大调": [0, 2, 4, 5, 7, 9, 11],
	"自然小调": [0, 2, 3, 5, 7, 8, 10],
	"和声小调": [0, 2, 3, 5, 7, 8, 11],
	"五声大调": [0, 2, 4, 7, 9],
	"五声小调": [0, 3, 5, 7, 10],
}


static func note_name(midi: int) -> String:
	return SHARP_NAMES[midi % 12] + str(floori(midi / 12.0) - 1)


static func is_black(midi: int) -> bool:
	return midi % 12 in BLACK_PCS


static func midi_to_freq(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


static func key_label(semi_offset: int) -> String:
	return SEMI_LABELS.get(semi_offset, "")


static func in_scale(midi: int, key_root: int, scale: Array) -> bool:
	return (midi - key_root) % 12 in scale


## 指定调式一个八度内的音级列表（GDScript 回退实现，对应 TS scaleNotes）
static func scale_notes(key_root: int, scale: Array) -> Array:
	var out: Array = []
	for s in scale:
		out.append(key_root + int(s))
	return out


## 以 midi 为音级根音的调内三和弦（新手"和弦模式"核心）
## GDScript 回退实现；优先走 gode 的 TypeScript 版本（见 theory_engine.gd）
static func scale_chord(midi: int, key_root: int, scale: Array) -> Array:
	var notes: Array = []
	for oct in range(0, 11):
		for s in scale:
			var n: int = key_root + 12 * oct + s
			if n >= 0 and n <= 127:
				notes.append(n)
	notes.sort()
	var idx := -1
	for i in notes.size():
		if notes[i] <= midi and (midi - notes[i]) % 12 == 0:
			idx = i
	if idx < 0:
		return [midi]
	var out: Array = []
	for step in [0, 2, 4]:
		var v: int = notes[mini(idx + step, notes.size() - 1)]
		if not out.has(v):
			out.append(v)
	return out
