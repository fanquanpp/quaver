# 编趣 Quaver — 功能设计文档

> 纯电脑键盘弹奏 + 鼠标点击编曲的桌面端纯音乐工具。
> 技术栈：Godot 4.7（GDScript）· 音频：运行时合成引擎 · 美术：Aseprite 像素资产

---

## 1. 产品定位

| 维度 | 决策 |
|---|---|
| 目标用户 | 小型游戏开发者（要音效/BGM）、音效制作者、纯音乐编曲爱好者、音乐学习新手、娱乐用户 |
| 输入方式 | **仅电脑键盘弹奏 + 鼠标点击/拖拽**，不接 MIDI 键盘等任何外设 |
| 内容范围 | 纯器乐（旋律/和声/节奏），**不做歌词、演唱、录音、混音级 DAW 功能** |
| 平台 | 仅 Windows 桌面端（Godot 天然可扩展 mac/linux） |
| 核心体验 | 打开就能弹、随手就能录、点几下就能排、新手不用懂乐理也能写对音 |

### 竞品/参考调研结论（2026-09 联网调研）

- **FL Studio Piano Roll** 的 *Scale Highlighting（调性高亮）+ Chord Stamp（和弦戳）* 是新手钢琴卷帘的黄金组合：调外音变暗后"几乎不可能写错音"（参考 [EDMProd](https://www.edmprod.com/fl-studio-piano-roll/)、[FL 官方手册](https://www.image-line.com/fl-studio-learning/fl-studio-beta-online-manual/html/pianoroll.htm)）→ 本作全套借鉴。
- **Godot 4 原生 `InputEventMIDI`** 已支持 MIDI 输入（[官方文档](https://docs.godotengine.org/en/4.4/classes/class_inputeventmidi.html)），但按需求本作走"键盘即琴键"路线，MIDI 仅作为未来可选扩展。
- GitHub 可借鉴项目：[SeleDreams/Godot-PianoRoll](https://github.com/SeleDreams/Godot-PianoRoll)（Godot 3 卷帘实现，思路参考）、[sfzinstruments/SalamanderGrandPiano](https://github.com/sfzinstruments/SalamanderGrandPiano)（免费钢琴采样，未来采样音源）、Asset Library 的 [Clef Midi](https://store.godotengine.org/asset/star-weaver/clef-midi/)（Godot 4.6+ 的 SF2 SoundFont 实时合成插件，未来音源升级方向）、[nlaha/godot-midi](https://github.com/nlaha/godot-midi)（MIDI 文件解析参考）。
- 音频架构选型参考：Godot 论坛/GitHub Issue 关于 [AudioStreamPolyphonic 的实践](https://github.com/godotengine/godot-docs/issues/9488) —— 本作采用**预渲染采样 + 播放器池**（见 §4），规避实时 DSP 的延迟与 GC 抖动。

---

## 2. 用户故事 → 功能映射

| 用户 | 故事 | 对应功能 |
|---|---|---|
| 新手 | "我不懂乐理，也想弹得好听" | 调性辅助：调外键变灰不可"难按错"；**和弦模式**（按一个键出整个三和弦） |
| 新手 | "我不知道哪个电脑键对应哪个琴键" | 屏幕键盘上直接印电脑键帽字母，实时高亮按下状态 |
| 娱乐用户 | "我想随便弹着玩" | 演奏模式：全屏大键盘，即时发声，八度一键切换 |
| 编曲用户 | "我弹的东西想留下来" | 录制模式：弹奏实时落入钢琴卷帘，自动量化到 1/16 |
| 编曲用户 | "我想用鼠标精细修" | 铅笔工具：左键画音符拖长度、拖动移位、右键删除；对齐网格可调 |
| 游戏开发者 | "我要把成品导出给引擎用" | 一键导出 WAV（实时总线录制）；工程文件极小（zstd 二进制） |
| 游戏开发者 | "我想要芯片音效风格" | 内置音色组：钢琴 / 芯片方波 / 柔弦 Pad / 贝斯（纯合成，0 采样体积） |
| 所有人 | "打开别是空的" | 内置示范曲《小星星》双轨工程，首次启动自动加载 |

**明确不做**（范围控制）：歌词/演唱/麦克风、VST 支持、多轨混音台、自动化包络、乐谱打印。

---

## 3. 功能设计

### 3.1 演奏模式（Play）
- 屏幕大键盘 2 个八度（C3–C5），支持**鼠标点击弹奏**与**电脑键盘弹奏**并行。
- 电脑键位（FL Studio 惯例布局，物理键位布局无关）：
  - 低八度白键 `Z X C V B N M , . /`，黑键 `S D G H J L ;`
  - 高八度白键 `Q W E R T Y U I O P`，黑键 `2 3 5 6 7 9 0`
  - `↑ / ↓` 整体升降八度（1–7），当前八度在键盘上标注 C4 等音名
- **调性辅助**：选择"调 + 音阶"后，调内键帽高亮，帮助新手建立肌肉记忆。
- **和弦模式**：按下单键自动补齐该调内的三和弦（根音+三音+五音），一键出和声。
- 键帽提示开关（默认开，印字在琴键上）。

### 3.2 编曲模式（Arrange）
- **钢琴卷帘**：横向为时间（1 tick = 1/16 音符），纵向为音高（A0–C8 共 88 键），左侧内嵌迷你琴键列（可点击试听），顶部标尺（小节号，点击跳播）。
- 鼠标交互（零学习成本优先）：
  - 左键空白 = 新建音符，**横向拖拽定长度**（实时预览+试听）
  - 左键按住已有音符 = 移动（音高+时间）；抓住右缘 = 改长度
  - 右键 = 删除（按住扫删）
  - 滚轮 = 上下（音高）；Shift+滚轮 = 左右（时间）；Ctrl+滚轮 = 缩放
  - 全程网格吸附（1/16、1/8、1/4、整拍、关闭可选）
- **多轨**：v0.1 两轨（主旋律 / 和弦伴奏），每轨独立音色；未选中轨以"幽灵音符"半透明显示（FL Studio ghost notes 惯例）。
- **调性辅助**：同演奏模式共享调/音阶设置，卷帘中调外行整行变暗。
- 传输条：播放 / 停止 / 循环 / BPM(40–240) / 录制（弹奏即录入，自动量化）。
- 工程：保存/打开 `.bsong`（见 §6）、导出 WAV、重载示范曲。

### 3.3 音色（合成器音源）
| 音色 | 合成方式 | 用途 |
|---|---|---|
| 钢琴 | 7 次谐波加法合成 + 频率微失谐 + 锤击噪声瞬态 + 分音区衰减 | 主旋律 |
| 芯片 | 25% 占空比方波 + 两段衰减 | 游戏音效/BGM |
| 柔弦 | 正弦对（±0.3% 失谐合唱）+ 慢起音 | 铺底和弦 |
| 贝斯 | 正弦 + 二次谐波 | 低音 |

---

## 4. 音频引擎架构（性能核心）

```
InputEventKey ─┐
鼠标/卷帘 ─────┼─→ MainUI(事件路由) ─→ Synth.play_note(inst, midi, vel)
录制 ──────────┘                          │
                                          ▼
InstrumentBank(后台线程预渲染):            播放器池 ×32 AudioStreamPlayer
  每音色×4个基音(C2/C3/C4/C5)              ├─ 空闲分配 / 最旧抢占
  AudioStreamWAV(22050Hz 单声道 16bit)     ├─ note-off: 0.12s 淡出(延续自然衰减)
  ~1.4MB 内存, 首次生成后 zstd 磁盘缓存    └─ Synth 总线: Limiter 防削波
```

**关键决策：预渲染采样而非实时合成**
- `AudioStreamGenerator` 每 _process 从 GDScript 填缓冲 → 帧率波动直接变音频抖动，且键盘实时弹奏延迟敏感，**否决**。
- 每音符实时 DSP → GDScript 每秒百万级浮点运算，多复音必卡，**否决**。
- **预渲染 4 基音 + `pitch_scale` 移调**（±6 半音内）→ 播放期零 DSP，只有采样回放；内存 ~1.4MB；启动后台线程生成，二次启动读缓存秒开。

**延迟**：Windows WASAPI 共享模式，Godot 默认输出延迟 ~15ms（人类"边弹边听"可接受阈值内，与入门 MIDI 接口相当）；工程保留 `audio/driver/output_latency` 调优口。

## 5. 渲染性能设计

- 钢琴卷帘/键盘全部为**单个 Control 的 `_draw()` 矢量绘制**，不用每音符一个节点 → 千级音符也只走一个 canvas item。
- 脏标记：只在模型变化、滚动/缩放、播放推进时 `queue_redraw()`；静止时零重绘。
- 绘制前按可视区间**裁剪**（音符、网格线都只画视口内的）。
- 播放推进的 playhead 重绘频率 = 帧率，但绘制范围被裁剪后单帧成本 O(可见音符数)。

## 6. 存储与空间优化

- 工程文件 `.bsong`：`FileAccess.open_compressed(ZSTD)` 二进制，音符按 `PackedInt32Array` 平铺 `[pitch,start,len,vel]×n` → 千音符工程 **< 10KB**（对比 JSON 数百 KB）。
- 采样缓存 `user://sample_cache_v2.bin`：ZSTD 压缩合成波形（正弦类压缩率 ~40-50%），二次启动免合成。
- 无外部音频文件：4 音色全合成，**安装包音频体积 = 0**；美术仅 3 张小 PNG（logo/图标/应用图标，共 < 10KB）。
- 导出 WAV（16bit 44.1k）供游戏引擎直接使用；未来可加 OGG 导出。

## 7. 语言选型分析：GDScript + gode/TypeScript 混合开发（v0.1 实际采用）

| 方案 | 结论 | 理由 |
|---|---|---|
| **GDScript（主体）** | ✅ UI / 音频 / 数据全量使用 | 性能瓶颈（音频）已用"预渲染采样"架构消解，播放期无热循环；UI/编舞逻辑 GDScript 足够；无导出依赖，迭代最快 |
| **gode / TypeScript（混合层，已接入）** | ✅ 乐理引擎 | 经调研 [gode 2.4.4](https://github.com/godothub/gode)（[文档](https://godothub.com/oss/gode)）：Godot 官方脚本体系内的 JS/TS 语言插件（GDExtension 实现，自带 Node 运行时，无需安装 Node.js）。TS 脚本可与 GDScript 双向互操作、可做 autoload。分工：**纯计算、重数据变换的乐理模块（音阶/和弦/音名）用 TS**（未来可直接接入 npm 音乐理论生态），UI 与音频实时路径保持 GDScript |
| C# | ❌ 不用 | 引入 .NET 运行时体积（安装包 +100MB 级），与"存储优化"目标冲突；已有 gode 覆盖混合语言需求 |
| GDExtension 自研 (C++) | ⏸ 预留 | 触发条件：① 需要 SF2/SFZ 实时解码合成音源；② 低延迟效果器链。届时只替换 InstrumentBank/Synth 内核，接口不变 |

**混合语言架构（带优雅降级）**：

```
调用方（main_ui 等）
   │ Theory.scale_chord(...)
   ▼
theory_engine.gd（门面 autoload）
   ├─ 检测 addons/gode 存在 且 load("res://scripts/theory.ts") 成功
   │    → 实例化 TypeScriptScript（set_script 方式），后端 = gode-typescript
   └─ 否则 → 回退 NoteKeys.gd 同逻辑实现，后端 = gdscript
（两后端行为一致，调用方无感知；插件缺失/损坏不影响运行）
```

**gode 注意事项**（实测踩坑）：
- 从 GitHub Releases 下载 `gode.zip`（224MB 压缩 / 全平台解压 711MB）。按"存储优化"原则只解压 `binary/windows`，其余平台二进制按需补充；全量本地安装约 **234MB**（2026-09-10 实测）。
- **仓库层面 `/addons/gode/` 已被 .gitignore 整体排除**（超 GitHub 单文件限制），克隆不含插件也能完整运行（Theory 门面自动回退 GDScript）；手动安装步骤见 README。
- 插件启用需重启编辑器（TS 编译服务随编辑器插件加载；游戏运行时 GDExtension 独立生效）。
- `TypeScriptScript` 资源**不支持 `.new()`**，须用 `Node.new()` + `set_script(ts_script)` 实例化。
- gode 启用后会自动注册 `EventLoop` autoload 与 `[native_extensions]` 配置，勿手动删除。
- 上条的两处自动注册只存在于**本地** project.godot——它们指向被忽略的插件文件，**提交前必须剥离**（仓库版不含 EventLoop autoload 与 [native_extensions] 两节，否则无插件环境启动报错），提交后在本地恢复。README「维护者注意」有同款说明。

**插件策略**：引擎原生 API 全覆盖 UI/音频；混合语言用 gode；未来音源升级优先评估 [Clef Midi](https://store.godotengine.org/asset/star-weaver/clef-midi/)（SF2 合成）而非自研 GDExtension。

### 7.5 godothub 生态插件分工（2026-09-10 评估）

| 插件 | 定位 | 分工决策 |
|---|---|---|
| [Gode](https://github.com/godothub/gode) | Godot 的 JS/TS 语言支持 | ✅ **已接入**：TS 乐理引擎（§7），GDScript 缺失自动回退 |
| [Godot-ECS](https://github.com/godothub/godot-ecs) | 纯 GDScript ECS：直通/并行双模式、DAG 依赖调度、带版本迁移的序列化 | ⏸ **v0.2 引入**：v0.2 的鼓机步进轨 + 多轨并行事件调度用其 scheduled 模式；序列化系统用于工程版本迁移。v0.1 音符量 <2k，线性事件表更简单，强行 ECS 反而增加间接层 |
| [Compute-Flow](https://github.com/godothub/compute-flow) | GPU 计算着色器可视化编排（AudioBuffer 节点可对接音频播放器） | ⏸ **v0.3 评估**：实时 DSP 效果器（混响/均衡/压缩）的候选实现路径；要求 Vulkan 后端，需将本项目从 D3D12 切换并验证兼容性后再定 |
| [Gmui](https://github.com/godothub/gmui) | MVVM UI 框架（.gmui 标记文件 + g-model 双向绑定） | ⏸ **局部预留**：适合"设置页/新手引导/关于页"等表单型页面；主工作区是 60fps 走带同步的自绘卷帘/键盘，数据绑定不匹配，保持代码构建 |
| [Konado](https://github.com/godothub/konado) | 视觉小说对话框架 | ❌ **不适用**：纯音乐工具无对话/剧情/立绘需求 |

> 分工原则：插件服务于"下一个版本的真实需求"才引入；每个引入都要有退出成本评估（本作对安装包体积敏感）。

## 8. 美术管线（Aseprite）

`aseprite/*.aseprite`（源文件）→ MCP 导出 → `assets/sprites/*.png`：
- `logo.png` 64×64 像素钢琴图标（标题栏 + 关于）
- `icons.png` 6×16×16 图集：播放/停止/录制/保存/打开/导出（工具栏，TextureRegion 切片）
- `icon64.png` 应用图标（替换 Godot 默认 icon.svg）

像素画全部 1x 绘制、UI 中 `TEXTURE_FILTER_NEAREST` 保持锐利。

## 9. 项目结构

```
res://
├── DESIGN.md              # 本文档
├── scenes/main.tscn       # 唯一场景（UI 由 main_ui.gd 代码构建，便于迭代）
├── scripts/
│   ├── instrument_bank.gd # 自动加载：音色合成/缓存
│   ├── synth_engine.gd    # 自动加载：播放器池/总线
│   ├── song_model.gd      # class_name SongModel：数据模型+序列化
│   ├── note_keys.gd       # class_name NoteKeys：键位表/音名/音阶（含 GDScript 乐理回退）
│   ├── theory_engine.gd   # 自动加载 Theory：乐理门面（TS 优先/回退）
│   ├── theory.ts          # gode/TypeScript 乐理引擎实现
│   ├── transport.gd       # class_name Transport：走带/调度/录制时钟
│   └── ui/
│       ├── main_ui.gd     # 根界面：布局/模式/文件/录制路由
│       ├── piano_keyboard.gd # 演奏大键盘
│       └── piano_roll.gd  # 钢琴卷帘
├── assets/sprites/        # Aseprite 导出产物（logo/icons 图集/应用图标）
├── aseprite/              # Aseprite 源文件
└── addons/gode/           # gode 2.4.4（本地安装约 234MB；.gitignore 排除，不入库）
```

## 10. 路线图

- **v0.1（本版，已实现并通过自检）**：演奏模式 / 双轨钢琴卷帘 / 录制量化 / 4 音色 / bsong 存取 / WAV 导出 / 示范曲 / gode TS 乐理引擎
- **v0.2**：撤销重做、drum 轨（鼓机步进）、MIDI 文件导入导出、循环区间、更多音色、自动和声（旋律→ chords 建议）
- **v0.3**：SF2/SFZ 采样音源（评估 Clef Midi 或 GDExtension）、复音数上限策略、工程模板

## 11. v0.1 验证记录（2026-09-10，Godot 4.7.2 stable 实测）

| 项 | 结果 |
|---|---|
| 启动 | 无报错；音源缓存命中时秒开（`[InstrumentBank] 缓存加载完成`） |
| 乐理引擎后端 | `gode-typescript` 生效；缺失插件时自动回退 `gdscript`（已验证两条路径） |
| TS 互操作 | `Theory.scale_chord(60, C大调)=[60,64,67]`、`(64)=[64,67,71]`（TS 计算，GDScript 调用） |
| 走带精度 | 96 BPM 播放 2.5s → playhead=16.0 tick（恰 1 小节），音符触发 11 个 ✓ |
| 存档往返 | 2 轨 78 音符（旋律42+伴奏36）保存→读档逐项一致；**.bsong 仅 308 字节** |
| 双页渲染 | 截图目检：演奏页全宽键盘+键帽字母；编曲页卷帘渲染示范曲（含幽灵音符/标尺/播放头） |
| 资产 | Aseprite 源文件 3 个（logo/icon64/icons 图集）→ PNG 导入并生效（标题栏/按钮图标可见） |
| 窗口关闭自动保存 | 关窗 → user://autosave.bsong → 下次启动恢复（实测生效） |

自检中发现并修复的问题（留档）：白键序号八度偏移公式、`Control.scale` 成员名冲突、`TypeScriptScript` 不支持 `.new()`、.bsong 读档漏读版本号 2 字节导致字段错位、和弦音域收集过窄。

## 12. v0.1.1 界面升级（2026-09-10，依据 DAW 布局设计调研）

**钢琴键盘 v2（层次感/按压动画/比例修正）**：
- 真钢琴长宽比（白键宽 ≤58px、键盘块高≈宽÷5.8）并在控件内**水平+垂直居中**，不再拉伸撑满整窗
- 立体结构：上盖板（印 C4/C5/C6 八度标注）→ 白键区（三段渐变键面 + 左高光/右暗缘 + 前缘）→ 前条；黑键带**投影**、左受光面/右暗面/顶部亮面 + 描边
- **按压动画**：键面下沉（白键下沉 4px 露出铰链阴影槽 + 蓝色渐变染色；黑键下沉 3px + 底部发光条），指数平滑 ~100ms，静止后停止 `_process`（脏驱动不空转）
- 电脑键盘/鼠标弹奏均走同一动画路径

**操作界面（布局清晰/交互易懂）**：
- 工具栏改为 **FL Studio 式功能分组面板**：走带 / 速度 / 辅助 / 编辑 / 轨道 / 文件，每组小标题 + 圆角底色，一眼定位功能区域
- 全部控件加中文 tooltip（悬停即得说明）；新增 **空格 = 播放/停止** 快捷键
- 卷帘新增 **跟随播放头**（播放时自动滚动，可关）
- 布局设计依据：DAW 惯例（卷帘=左侧键盘列+网格、工具栏按功能分组、自动滚动类开关常驻可见），参考 [Ableton Arrangement View 手册](https://www.ableton.com/en/manual/arrangement-view/)、[FL Studio 工具栏文档](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/toolbar_panels.htm)、[音乐界面设计原则](https://medium.com/swlh/designing-musical-user-interfaces-4f30b41d7a83)（声音本身是反馈闭环的一部分：按下即发声+视觉反馈）

## 13. v0.1.2 演奏/编曲体验升级（2026-09-10）

**Bug 修复**：
- 编曲单击音符长度 4 → **1 tick**（默认单个 1/16 块；长度仍可在工具栏 1–16 调整）
- **"点播放没声音"**：根因是上一次播放自然结束后播放头停在曲末，再点播放从曲末瞬间越界停止。修复：播放时若 playhead ≥ 曲末自动回卷到 0（回归测试通过）

**演奏页 — 音符记录回声条（NoteRain）**：
- 参考 Synthesia / SeeMusic / [ekkx/notefall](https://github.com/ekkx/notefall) 的"音符雨+命中反馈"惯例；本作横置琴键 → 演化为**上升回声**：按住越长色块越高，松手整体上浮渐隐（1.5s），底部命中线随按压发光
- 色块横向精确对位琴键（白键全宽/黑键 0.58 窄块，含偏移微调），颜色跟随当前轨色
- 键盘新增**悬停微亮**动效；白键宽上限 58→64px、长宽比 5.8→6.2（占比更接近真钢琴视觉）

**编曲页 — 缩放**：
- 工具栏 `− / 100% / +` 控件（基准 100% = 10px/tick，范围 3–48），围绕视口中心缩放；快捷键 `=` / `-`；Ctrl+滚轮以光标为锚缩放保留
- 播放头自动跟随（可关）上一版已加

**图标 v2（Aseprite 重绘，风格不变加边框与层次）**：
- 按钮图集 16px → **32×32@2x**：1px 深色描边 + 上亮下暗双色 + 柱顶高光；运行时 `icon_max_width=20` 显示（HiDPI 下仍清晰）
- 应用图标重绘：圆角底板 + 边框 + 内顶高光 + 三段立体白键 + 描边双色音符

**Godot 分辨率/自适应（调研结论落地）**：
- 本作已有的 `stretch=canvas_items + aspect=expand` 即[官方文档](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html)推荐组合：原生分辨率渲染保证文字/矢量 UI 在 HiDPI 清晰，多余空间交给锚点布局
- `allow_hidpi`（4.x 默认开）+ 自绘控件全部按 `size` 动态布局（键盘/回声条/卷帘随窗口缩放重排）；位图图标走 2x 素材缩小显示抗模糊；参考 [Chickensoft 桌面缩放实践](https://chickensoft.games/blog/display-scaling)

**性能/内存/存储/导入现状**：低处理器模式 + 脏重绘（键盘动画、回声条、卷帘均无音符时停止 `_process`）；回声条块自动回收；采样 zstd 磁盘缓存（二次启动免合成）；.bsong zstd（78 音符 308 字节）；PNG 走 Godot 默认无损压缩导入；32 复音池零运行时节点分配。

## 14. v0.1.3 播放修复 + 分析页 + 专业布局与绘制质量（2026-09-10）

**Bug 修复（关键）**：
- **编曲播放彻底无声的真正根因**：`Transport.note_fired` 信号只发出、全工程无任何订阅者——v0.1.2 修的"播放头停在曲末"只是前置条件，事件表正确触发了音符但从未路由到 `Synth`。修复：`MainUI` 订阅 `note_fired` → `Synth.play_note` + NoteRain 回声反馈（回归测试：示范曲播放有声、回声条随轨道色升起）

**分析页（新标签页）**：
- `song_analysis.gd`（class SongAnalysis，纯静态计算）：音符总数/曲长(小节+秒)/音域/密度/平均力度/平均音长/最大同时音/分轨统计；**Krumhansl-Schmuckler 调性检测**（KK 大小调权重剖面 × 24 旋转 × Pearson 相关，置信度=与次优调的相关差）
- `analysis_panel.gd`（AnalysisPanel）：统计网格 + 音级分布直方图（时长×力度加权，检测调内音级高亮、主音橙色标记，StyleBox 圆角条缓存）；「应用到调性辅助」一键写入调/音阶并启用高亮
- 刷新时机：切到分析页、音符编辑、BPM 变更、换工程
- 语言选型说明：分析属"纯计算"，按约定候选 TS 化；本版以 GDScript 落地（与 SongModel 字典零转换、不依赖 gode 编译服务），接口稳定后平移 `theory.ts` 调用方无感

**演奏键盘大小调节**（此前"不能调整大小"）：
- 键宽滑杆 60%–160%（`key_scale`，基准上限 64px/白键）+ 1–4 八度跨度选择 + 键盘上 Ctrl+滚轮缩放（±8%/格）
- 编曲页新增**底部迷你弹奏键盘**（无键帽字，与主键盘同步按压视觉；`set_pressed_silent` 只同步视觉不发信号，杜绝双键盘信号回环导致的重复发声/重复录制）

**专业布局（区域可调）**：
- 编曲页改 **VSplitContainer**：卷帘区（占满剩余空间）/ 迷你键盘区（最小 150px），分隔条拖动即调；边播边弹更顺手
- 全局代码主题 `_build_theme()`：Button normal/hover/pressed 描边样式、TabContainer 选中页与内容面板同色层次、去默认焦点虚线框
- 视觉令牌统一：`GAP_X/GAP_Y` 间距、面板底色/描边色常量；功能分组面板补 1px 描边（"控件有边界"）

**绘制质量（锯齿/边框/精度）**：
- 键盘/卷帘/回声条所有自绘矩形**整数像素对齐**（filled rect 对齐后零锯齿），白键缝隙改为"整宽键 + 精确 1px 键缝"，键体外框 1px 抗锯齿描边
- 卷帘音符改 **StyleBoxFlat 圆角(3px)+深色描边+抗锯齿**（按颜色缓存，力度档量化 0.05 防缓存膨胀）；悬停高亮改 2px 白描边；网格/分隔线**对齐半像素**（1px 线锐利不闪）；播放头对齐整数 2px；左侧琴键列圆角小键
- 默认窗口 1280×768 → **1440×900**（最小 1024×640）：更大画布精度，`canvas_items+expand` 自适应保持

**工程卫生**：`docs/` 加 `.gdignore`（截图不再被引擎导入，清掉误生成的 .import）。

**布局调研依据**：DAW 通用三区结构（走带/参数工具栏 + 主编辑区 + 常驻演奏输入）+ 可拖分隔的工作区（Ableton/FL Studio 惯例，见 §12 引用）；绘制细节依据 Godot 官方 2D 抗锯齿行为（`draw_rect/draw_line` 默认无 AA、亚像素坐标是锯齿主因）与 StyleBox 抗锯齿圆角能力。联网搜索服务本日限流，文档结论以官方文档+既往调研（§1/§12）交叉验证。

## 15. v0.1.4 移除悬停高亮 + 插件目录排除文档化（2026-09-10）

**移除悬停触发效果（用户反馈：触发太过频繁）**：
- 演奏键盘：删除"悬停微亮"（白键 8% / 黑键 6% 叠色）及 `_hover_midi` 追踪——鼠标滑过不再触发重绘
- 编曲卷帘：删除音符悬停描边（此前似"选中高亮"，扫过即闪）；空闲鼠标移动不再做命中测试与重绘（顺带的性能收益）
- **保留**的反馈全部需要真实交互：按压下沉/染色（键盘）、按住拖拽/新建预览描边（卷帘）、走带播放头。后续迭代不要以"悬停"作为视觉反馈触发条件

**文档**：README/DESIGN 补记 `/addons/gode/` 的 .gitignore 排除策略（全量约 234MB）、未安装时 GDScript 回退不受影响，以及 project.godot 本地两行（EventLoop autoload / `[native_extensions]`）"提交前剥离、提交后恢复"的维护流程。

## 16. v0.1.4-beta 品牌更名与测试版发布（2026-09-10）

**更名**：编曲趣 Bianqv → **编趣 Quaver**（Quaver = 八分音符音乐术语，开头 Qu 保留"编趣"拼音首字母；更名链 编曲趣 Bianqv → 编趣 BianQu → 编趣 Quaver，同日两次）；GitHub 仓库 `fanquanpp/bianqv` → `fanquanpp/quaver`（gh repo rename，旧名自动重定向）。品牌字符串全量替换（project.godot / README×2 / DESIGN / main_ui 标题与 .bsong 过滤器描述），本地目录名不变（仅为临时名）。**仓库 About 描述与话题标签（godot/music/piano/sequencer/chiptune）同步更新**——repo rename 不会自动改 About，需 `gh repo edit --description/--add-topic` 单独处理。

**发布管线**：
- `export_presets.cfg` 入库（.gitignore 移除该项）：Windows Desktop 预设，`embed_pck=true` 单文件、排除 `addons/gode/*` 与 `tests/*`（导出包走 GDScript 乐理回退，实测 `[Theory] 后端: gdscript` 正常）、打包 D3D12 运行库；产品名"编趣 Quaver"
- 构建命令：`Godot_v4.7.2-stable_win64.exe --headless --path . --export-release "Windows Desktop" build/windows/Quaver.exe`（编辑器版本须与已装导出模板 4.7.2.stable 严格一致；**输出目录必须预先存在**，Godot 不会自建）
- **必须在干净副本中导出**（`git worktree add ../quaver-build HEAD` 后在副本执行）：本机安装的 gode 会在每次编辑器实例启动时把 `[native_extensions]` 写回 project.godot 并把插件二进制拷进导出目录——即使导出前手动剥离也会被写回。副本不含被 gitignore 的 addons/gode，天然干净；导出包实测无 UID 报错、走 GDScript 乐理回退
- 产物：`Quaver.exe` 约 109MB（zip 后 38MB），无头启动自检通过；发布为 GitHub Release **v0.1.4-beta**（prerelease）

**「红色覆盖琴键区」排查结论（非本程序 Bug）**：
- 现象：演奏页回声条+琴键整体被红色覆盖，鼠标活动时"频繁触发"，用户疑为悬停效果
- 证据链：① 两轮全量源码检索无任何红色绘制/歌词代码；② 截图中出现手写体歌词文本——本作是纯音乐工具，全工程无歌词功能；③ 进程与窗口枚举发现 `cloudmusic.exe` 持有标题为**「桌面歌词」的顶层窗口**（网易云音乐）
- 结论：红色层为**网易云音乐桌面歌词悬浮窗**叠在游戏窗口上方（其样式即红底手写字），随歌词刷新/鼠标活动而变化，被误认为程序内悬停效果。程序内悬停逻辑 v0.1.4 已按需求收敛：仅工具栏按钮保留描边式悬停，琴键/布局区域无任何悬停触发

## 17. v0.2.0 N 轨系统 + 总线路由 + 走带时钟迁移（2026-09-11）

**数据模型 v2（.bsong VERSION=2）**：轨道新增 `type/volume/pan/mute/solo/reverb/delay/effects/automation` 字段（`SongModel.make_track` 默认值）；读 v1 工程自动迁移填默认（`load_from` 按版本分支）；`remove_track`（保底 1 轨）与 `MAX_TRACKS=16` 上限。EditHistory 快照改整轨 `duplicate(true)` 深拷贝，混音字段入快照；状态比较扩展 volume/pan/mute/solo/type/effects。

**音频总线路由（Synth 重构）**：Master=[EQ10,Limiter] ← Music=[EQ6] / Drum=[Compressor] ← Track0..15 轨道总线（懒创建）=[Panner,EQ6,Compressor,Reverb,Delay]。轨道音量→`set_bus_volume_db`、声像→Panner、静音/独奏→`set_bus_mute`（独奏激活时非独奏轨等效静音，走带与总线双重过滤）。**辅助发送采用插入式实现**（Godot 4 移除了带发送量的 AudioEffectSend，属 Godot 3）：轨道常驻 Reverb/Delay，wet 电平=发送量，dry=1 干声直通。发声 API 升级 `play_note_on_track(track,…)` 按轨路由；播放器池动态 `max(32,轨数×8)` 上限 128。

**走带时钟迁移（Transport 重构）**：playhead 由音频混音时钟锚定——`墙钟 + (get_time_since_last_mix() − get_output_latency())×1000`（减延迟补回扬声器侧，playhead=可听位置），混音未发生（headless）自动回退墙钟；音符 look-ahead=输出延迟（play() 起音到出声恰隔一个延迟，提前触发即对齐出声时刻）；`clock_override` Callable 注入时钟供测试帧步进。**修复旧版循环边界丢失**：回卷时剩余事件绝对 tick 平移一个循环跨度（旧版 [end, end+提前量) 音符每圈被丢）。`use_audio_clock=false` 为风险矩阵保留的回退开关。

**轨道列表 UI（新 TrackList）**：编曲页左侧 N 轨面板替代工具栏双轨按钮——色块/选择/音色/M/S/音量/声像滑杆，右键重命名/清空/切旋律·鼓机/删除，底部"+ 添加轨道"；混音参数即时生效（`mix_changed`→apply_mix，滑杆拖动 mark_dirty、松手 push）。

**鼓机步进轨**：`type="drum"` 的轨道复用普通音符存储（pitch=声部音高、s=bar×16+步、l=1），走带/卷帘/MIDI/撤销全部免费复用；DrumSequencer 面板 16 步×6 声部（底鼓36/军鼓38/拍手39/踩镲42/嗵鼓45/开镲46），左键开关步（v=0.75）右键重音（v=1.0），选中鼓轨自动显示。音源库新增"鼓组"懒合成音色（kick 下扫正弦/军鼓噪声+鼓皮/拍手四连脉冲/镲不谐和方波叠）。

**力度分层（缓存 v4）**：缓存 key 扩展为 (音色,基音,力度层)，pp/mf/ff 三档（阈值 0.45/0.8，层增益 0.72/0.88/1.0），`sample_for(inst,midi,vel)` 按力度选层、层内音量连续控制。

**测试**：新增 `smoke_v020.gd`（v2 往返、v1 迁移、轨上限、混音快照、总线状态/独奏、力度分层、鼓组、循环边界、鼓轨端到端）；smoke_v013/v014 全过（v014 走带测试迁移到注入时钟）。gode 升至 2.4.4（Signal<T>/interface[] 检查器等，不触及本项目 TS 用法）。

## 18. v0.2.1 卷帘增强：多选/批量/力度条/分轨导出（2026-09-11）

**多选与框选**：Shift+拖空白 = 矩形框选；Shift+点音符 = 加/减选；Ctrl+A 全选、Esc 取消、Delete 删除选区。拖动选区内任一音符 = 整组同位移批量移动；右键扫删后选区自动剪枝（滤掉已删引用）。

**批量操作浮动栏**：选区非空时卷帘下方浮现操作栏——量化（吸附当前网格）、移调 ♭/♯、力度 ±0.1、复制/剪切/粘贴到播放头/删除/取消选择。粘贴以播放头（吸附网格）为基准平移时间、保持原音高；剪贴板为类级静态（跨工程可用）。

**力度编辑条**：卷帘底部 56px 力度条，柱高=力度、顶部亮帽；左键/拖拽按绝对高度设定目标音符力度（目标在选区 → 整组同增量联动）；选中音符柱全亮。

**幽灵音符密度限制**：其他轨音符先做视口 X 裁剪；总数超过 GHOST_NOTE_LIMIT(1500) 时整帧跳过幽灵渲染，防 16 轨大工程渲染爆炸。

**分轨导出 WAV**：文件组新增"分轨导出"——逐轨独占（其余轨临时静音）+ 录制器挂到该轨总线实时录制，产物 `<基准>_轨号_轨名.wav`（含该轨总线效果/发送；非法文件名字符清洗）；导出为状态机（循环临时关闭、结束后恢复原 mute/循环状态）。

**快捷键**：Ctrl+C/X/V（复制/剪切/粘贴）、Ctrl+A（全选）、Delete（删除选区）、Esc（取消选择）。

## 19. v0.3.0 和声分析 + 曲式分段 + 智能建议（2026-09-11）

**和弦进行检测**（SongAnalysis.detect_chords）：逐小节音级时长向量 ×（12 根音 × 7 模板：大三/小三/属七/小七/大七/减/挂四）匹配打分。三个关键修正防止模板误判：①四音模板需第 7 音证据 ≥ 模板内权重 25%，否则倾向三和弦；②尺寸归一化 + 根音权重加成防"同音集异根"误判（G vs Em7）；③每小节最低音音级额外加权（低音指示根音）。输出含罗马数字功能级（大调 I–vii°/小调 i–VII，非调内级留空）。ChordTimeline 自绘时间轴逐小节显示"名称 + 罗马数字"，主和弦橙色高亮。

**曲式结构分段**（detect_sections）：每小节音级轮廓的余弦相似度低于 0.82 或密度跳变 >2× 即切边界（最短段 2 小节）；段落与已有段落轮廓相似度 ≥0.9 复用字母标记（A/B/A），否则分配新字母。SectionBar 色块条显示。

**智能建议**：suggest_next_chords 按功能和声进行表（大调 I→IV/V/vi、V→I、ii→V…；小调对应表）给下一和弦候选（含级数与理由）；suggest_melody 在上一旋律音邻域生成和弦音/调内经过音候选。分析页"智能建议"行显示候选。

**实时合成引擎（GDExtension）明确延期**：需要 C++ 工具链（编译器 + godot-cpp 绑定）与独立构建管线，v0.3.0 范围内不具备条件；采样模式仍是唯一且完全可用的音源路径（力度分层已覆盖表现力需求大头）。列入 v0.3.2+ 重估项。

**测试**：smoke_v030（和弦检测/罗马数字/分段覆盖/和声建议/旋律候选/面板刷新），demo 曲断言：第 1/3/6 小节 C/F/G，IV→候选含 V/I，V→必含 I。

## 20. v0.3.1 轨道预设 + MIDI 自定义映射 + 体验打磨（2026-09-11）

**轨道预设系统**（TrackPresets）：轨道条（音色/类型/音量/声像/静音/独奏/发送）存为具名 JSON 预设（user://track_presets.json，音符不入预设）；轨道列表右键"存为轨道预设"，弹出菜单动态生成"预设 ▸ 名称"加载项，应用时保留轨名/音符/颜色。SF2/SFZ 级音色插件留待 v1.0 评估（见 §21）。

**MIDI 导入自定义映射**：user://gm_map.json 覆盖内置 GM 启发式——`{"chan9": "鼓组", "programs": {"0": "贝斯"}}`；打击乐通道优先于程序号映射；非法音色值自动回退启发式；映射结果缓存（改文件后重启生效）。

**体验打磨**：播放头跟随新增"居中"模式（播放头恒居中 vs 页面滚动跟随）；Ctrl+0 重置缩放并回卷视图。原计划的 1–4 工具切换键不适用（本作卷帘为无模式交互：上下文即工具），如实裁剪。

## 21. v1.0.0 混音台工作区 + 音色插件 + SFZ 采样音源（2026-09-11）

**混音台工作区**（新"混音"标签页，MixerPanel）：横向通道条 = 每轨（音量推子/声像/混响·延迟发送/M·S）+ Master 主音量条；改动即时写回轨道并 apply_mix（与轨道列表双向联动），滑杆拖动 mark_dirty、松手落快照。

**音色插件系统 v1（参数配方级）**：user://instrument_plugins.json 声明 `[{name, recipe}]`，配方含 harmonics（谐波幅度表）/wave（sine·square·saw）/decay/attack/click/dur/gain——通用配方合成器在启动时生成全力度层采样并注册进动态音色列表（InstrumentBank.instruments，UI 下拉自动收录）；插件不入磁盘缓存（小体量按需合成）。v1 定位为"参数配方级"插件：SFZ 采样与内置合成统一在 sample_for 接口下，SFZ 采样音色力度层由 region lovel/hivel 承担。

**SFZ 采样音源**（SfzLoader）：扫描 user://sfz/*.sfz 注册为 "sfz:文件名" 音色。支持 SFZ v1 常用子集：sample/key/pitch_keycenter/lokey/hikey/lovel/hivel，<group> 默认值、行内多 opcode、// 注释；WAV 经 AudioStreamWAV.load_from_file 直接读取，pitch_keycenter 定移调基准、lovel/hivel 参与力度选区。**SF2（二进制 RIFF 采样库）解析器如实延期**——需独立的 RIFF/sample chunk 解析与压缩格式（如 cwsdram/24bit 打包）支持，工作量与测试面不在 v1.0 收口范围内，待有真实 SF2 资产需求时重估（Clef Midi 插件路线亦保留观察）。

**测试**：smoke_v100（插件注册/去重/力度层、SFZ 双 region 解析+移调比、混音台刷新）；六套件全过。

## 22. 附：外部悬浮物误报排查规程（2026-09-12 更新）

「游戏画面出现红色覆盖 / 点击特效 / 猫形贴纸」类报告，**先查外部悬浮层再查代码**。本作界面全部为程序内矢量绘制，演奏页不存在任何红色绘制路径；v0.1.4 与 v1.0.0 两次同类现象的排查结论：

- **v0.1.4 一次**：曾定位为网易云音乐「桌面歌词」悬浮窗（cloudmusic.exe）。
- **v1.0.0 这次复现时 cloudmusic 并未运行**——说明诱因不止一个，凡"跟随光标的点击特效/桌宠/悬浮层"皆可造成。本次实测证据：① 新启动游戏 + 交互，画面完全正常（内部渲染排除）；② 异常截图像素分析 = 约 50% 透明度的鲑红色半透明层叠在**正确渲染的游戏像素之上**（外部合成特征，颜色接近 Material Red A100 #ff8a80）；③ 异常物（白色猫形贴纸 + 青色箭头）出现在光标尖端且**没有对应的顶层 HWND**——系无窗口的合成层（DirectComposition/驱动级桌宠或输入法皮肤类），瞬态出现，常规 EnumWindows 抓不到。本机常驻的 Wallpaper Engine、UU 远程（gvInput 虚拟输入驱动）等均有嫌疑，具体元凶待下一次出现时用诊断脚本现场锁定。
- **新增诊断脚本 `tools/diag_overlay.ps1`**：异常出现时运行，自动保存全屏截图 + 全部可见窗口清单（含分层/置顶/工具窗标志 + 进程路径）+ 光标信息到 `tools/diag_result/`，对照即可锁定元凶进程。

## 23. v1.0.1 冻结模式：破解键盘多键同按的硬件限制（2026-09-12）

**问题**：电脑键盘为薄膜矩阵，同按 3 个及以上琴键时第三键信号在键盘矩阵层被吞（防串扰设计），信号根本到不了操作系统——软件无法恢复硬件丢的键，这是上游物理限制。

**解法：冻结（锁音）模式**——辅助面板新增「冻结」开关：
- 开启后依次按下的音逐个**冻结**（键盘保持按下高亮、回声条保持满高块）；
- 每按一个**新**键，已冻结的音以 0.6 力度**一起再响**——多音在同一个瞬间齐鸣，等效多键同按的和弦；音序构建、和弦齐响；
- 再按已冻结的键 = 解除该音（不发声）；关闭开关 = 解除全部；
- 冻结中的音抬起不松（`_live_note_off` 早退），录制时音符长度在解除/关开关时才定长（`_finalize_rec_note` 抽取共用）；
- 与和弦模式正交叠加（和弦补齐的音不进入冻结集，只冻结实际按下的键）。

**测试**：smoke_v014 新增 `_test_freeze_latch`（锁 3 音 / 抬起不松 / 再按解除 / 关开关全解）。
