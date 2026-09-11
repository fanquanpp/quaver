<div align="center">

# Quaver 编趣

**Play piano with your computer keyboard. Arrange with your mouse. Pure instrumental music, zero extra hardware.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Godot](https://img.shields.io/badge/Godot-4.7-478cbf)
![Platform](https://img.shields.io/badge/Platform-Windows-blue)
![Version](https://img.shields.io/badge/Version-1.0.0-4fc3f7)

[中文](README.md) · [English](README.en.md)

</div>

---

Quaver is a lightweight desktop music workstation for **small game developers, sound designers, and total beginners**: play melodies on your QWERTY keyboard, record them into a piano roll, arrange up to 16 tracks with a drum step sequencer and bus effects, then export a WAV (whole mix or per-track) your game engine can use directly.

Out of scope by design: vocals/lyrics, MIDI hardware, VST/AU hosting, cloud collaboration, video sync. Pure instrumental, instant fun.

## Highlights

- **Play mode** — on-screen piano mapped to two keyboard rows (keycaps printed on the keys), scale-highlighting so out-of-key notes dim, one-key chord mode, **freeze mode** (latch notes one by one so 3+ notes ring together — beats the 2-3-key hardware rollover limit), rising "note echo" animation
- **Arrange mode** — up to **16 tracks** with a track list (instrument / mute / solo / volume / pan), piano roll with multi-select & box select, batch quantize/transpose/velocity, velocity lane, clipboard, ghost notes, and a **16-step × 6-voice drum step sequencer**
- **Audio engine** — per-track buses routed through Music/Drum group buses into a Master bus (EQ10 + Limiter), per-track reverb/delay sends, audio-clock-anchored transport with look-ahead scheduling
- **Soundset** — 8 built-in synthesized instruments with 3 velocity layers each (Piano / Chiptune / Pad / Bass / E-Piano / Music Box / Drum Kit…), synthesized at startup, cached to disk, zero realtime DSP
- **Instruments plugin system** — declare new instruments as synthesis recipes in `user://instrument_plugins.json`; load **SFZ sample instruments** by dropping `.sfz` + WAVs into `user://sfz/`
- **Analysis page** — statistics, Krumhansl-Schmuckler key detection, per-bar **chord detection with Roman-numeral analysis**, automatic **song section segmentation** (A/B/A), harmony & melody suggestions
- **Mixer** — dedicated mixer view: fader / pan / reverb·delay sends / M·S per track, master volume
- **Files** — `.bsong` project (zstd binary, < 10KB for 1000 notes, backward compatible), WAV export (whole mix + per-track), MIDI import/export (custom GM mapping via `user://gm_map.json`), MusicXML score export, track presets

## Getting started

1. Install [Godot 4.7+](https://godotengine.org/download) (standard build, no .NET needed)
2. Clone this repo and open `project.godot` in Godot
3. Press F5 — a *Twinkle Twinkle Little Star* demo project loads on first run

**Keys**: `Z`-row = lower octave, `Q`-row = upper octave, `↑`/`↓` shift octaves, `Space` = play/stop, `=`/`-` = zoom the piano roll, `Ctrl+Z`/`Ctrl+Y` = undo/redo. Mouse plays too (click keys, drag to glissando).

**Optional TS backend**: download [gode](https://github.com/godothub/gode/releases), drop the `gode` folder into `addons/`, enable the plugin in Project Settings, restart the editor. Without it everything still works on the GDScript fallback.

## Documentation

Full design document (requirements, audio engine, language choices, per-version iteration records): [DESIGN.md](DESIGN.md) · 中文说明：[README.md](README.md)

**Tests**: six headless smoke suites in `tests/` — run with `godot --headless --path . res://tests/smoke_v100.tscn`

## Roadmap

- [x] v0.1 play mode / piano roll / quantized recording / synthesized instruments / WAV export
- [x] v0.1.2–v0.1.4 UX upgrades / analysis page / undo-redo / MIDI round-trip / MusicXML / loop region
- [x] v0.2.0 16-track system / bus effects routing / audio-clock transport / drum step sequencer / velocity layers
- [x] v0.2.1 multi-select & batch editing / velocity lane / per-track WAV export
- [x] v0.3.0 chord detection / section analysis / harmony suggestions
- [x] v0.3.1 track presets / custom GM mapping
- [x] v1.0.0 mixer workspace / instrument plugin system / SFZ support
- [ ] v1.x realtime synth engine (GDExtension) · SF2 sample banks

## License

[MIT](LICENSE) © 2026 fanquanpp
