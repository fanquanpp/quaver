extends SceneTree
## 临时调试：MIDI 往返各环节独立检查（-s 脚本模式，纯静态类无需 autoload）

func _init() -> void:
	var demo := SongModel.make_demo()
	var path := "user://dbg.mid"
	var err := MidiFile.export_song(demo, path)
	print("export err=", err)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("READ OPEN FAILED: ", FileAccess.get_open_error())
		quit(1)
		return
	var data := f.get_buffer(f.get_length())
	f.close()
	print("size=", data.size(), " magic=", char(data[0]), char(data[1]), char(data[2]), char(data[3]))
	var raw := MidiFile._parse(data)
	print("parse empty=", raw.is_empty())
	if not raw.is_empty():
		print("tempos=", raw["tempos"])
		print("tracks=", (raw["tracks"] as Array).size())
		var s := MidiFile.import_file(path)
		print("import null=", s == null)
		if s != null:
			print("bpm=", s.bpm, " notes=", s.track_notes(0).size(), "/", s.track_notes(1).size())
	quit(0)
