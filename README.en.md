<div align="center">

# Bianqv 编曲趣

**Play piano with your computer keyboard. Arrange with your mouse. Pure instrumental music, zero extra hardware.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Godot](https://img.shields.io/badge/Godot-4.7-478cbf)
![Platform](https://img.shields.io/badge/Platform-Windows-blue)

[中文](README.md) · [English](README.en.md)

</div>

---

Bianqv is a lightweight desktop music tool for **small game developers, sound designers, and total beginners**: play melodies on your QWERTY keyboard, record them into a piano roll, arrange with the mouse, and export a WAV your game engine can use directly.

Out of scope by design: vocals, lyrics, MIDI hardware, professional mixing. Pure instrumental, instant fun.

## Highlights

- **Play mode** — on-screen piano mapped to two keyboard rows (keycaps printed on the keys), scale-highlighting so out-of-key notes dim, one-key chord mode, rising "note echo" animation
- **Arrange mode** — piano roll: draw/drag/erase with the mouse, quantized live recording, 2 tracks with ghost notes, zoom (`=` / `-` / Ctrl+wheel), follow-playhead
- **Synth soundset** — Piano / Chiptune / Pad / Bass, synthesized at startup (zero sample assets, cached to disk, no realtime DSP)
- **Files** — `.bsong` project (zstd binary, 78-note demo = 308 bytes) and one-click **WAV export** via live bus recording
- **Mixed language** — music-theory engine in TypeScript via [gode](https://github.com/godothub/gode) with a seamless GDScript fallback (gode is optional)

## Getting started

1. Install [Godot 4.7+](https://godotengine.org/download) (standard build, no .NET needed)
2. Clone this repo and open `project.godot` in Godot
3. Press F5 — a *Twinkle Twinkle Little Star* demo project loads on first run

**Keys**: `Z`-row = lower octave, `Q`-row = upper octave, `↑`/`↓` shift octaves, `Space` = play/stop, `=`/`-` = zoom the piano roll. Mouse plays too (click keys, drag to glissando).

**Optional TS backend**: download [gode](https://github.com/godothub/gode/releases), drop the `gode` folder into `addons/`, enable the plugin in Project Settings, restart the editor. Without it everything still works on the GDScript fallback.

## Documentation

Full design document (requirements, audio engine, language choices, plugin allocation, test records): [DESIGN.md](DESIGN.md) · 中文说明：[README.md](README.md)

## Roadmap

- [x] v0.1 play mode / 2-track piano roll / quantized recording / 4 instruments / WAV export
- [x] v0.1.2 note-echo animation / zoom / grouped toolbar / redrawn icons
- [ ] v0.2 undo · drum step track · MIDI import/export · auto-harmony
- [ ] v0.3 SF2/SFZ instruments · GPU effects · project templates

## License

[MIT](LICENSE) © 2026 fanquanpp
