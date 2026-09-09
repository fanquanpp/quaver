// 乐理引擎（gode / TypeScript 实现）—— 编曲趣 Bianqv 混合语言层
//
// 由 addons/gode 提供 TS 运行时；GDScript 侧通过 theory_engine.gd 门面调用，
// gode 缺失时自动回退到 NoteKeys.scale_chord 的 GDScript 实现。
// 纯计算模块：不依赖 godot API，返回基础类型/数组，跨语言开销最小。

export default class TheoryEngine {

  /** 以 midi 为根音级的调内三和弦（新手"和弦模式"） */
  scaleChord(midi: number, keyRoot: number, scale: number[]): number[] {
    const notes: number[] = []
    for (let oct = 0; oct <= 10; oct++) {
      for (const s of scale) {
        const n = keyRoot + 12 * oct + s
        if (n >= 0 && n <= 127) notes.push(n)
      }
    }
    notes.sort((a, b) => a - b)
    let idx = -1
    for (let i = 0; i < notes.length; i++) {
      if (notes[i] <= midi && (midi - notes[i]) % 12 === 0) idx = i
    }
    if (idx < 0) return [midi]
    const out: number[] = []
    for (const step of [0, 2, 4]) {
      const v = notes[Math.min(idx + step, notes.length - 1)]
      if (!out.includes(v)) out.push(v)
    }
    return out
  }

  /** midi 是否在调内 */
  inScale(midi: number, keyRoot: number, scale: number[]): boolean {
    return scale.includes((((midi - keyRoot) % 12) + 12) % 12)
  }

  /** 音名（如 "C#4"） */
  noteName(midi: number): string {
    const names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return names[midi % 12] + (Math.floor(midi / 12) - 1)
  }

  /** 指定调式一个八度内的音级列表 */
  scaleNotes(keyRoot: number, scale: number[]): number[] {
    return scale.map((s) => keyRoot + s)
  }

  /** midi → 频率（Hz） */
  midiToFreq(midi: number): number {
    return 440.0 * Math.pow(2.0, (midi - 69.0) / 12.0)
  }
}
