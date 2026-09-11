<div align="center">

# 编趣 Quaver · 献GAY老猫————我的挚爱

**纯电脑键盘弹奏 + 鼠标点击编曲的桌面端纯音乐工具**

不需要 MIDI 键盘，不需要乐理基础 —— 打开就能弹，弹完就能存，存完就能导出给游戏引擎用。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Godot](https://img.shields.io/badge/Godot-4.7-478cbf)
![Platform](https://img.shields.io/badge/Platform-Windows-blue)
![Version](https://img.shields.io/badge/Version-1.0.2-4fc3f7)

[中文](README.md) · [English](README.en.md)

![演奏界面](docs/screenshots/play.png)

</div>

---

## 这是什么

给三类人做的音乐工具：

| 你是 | 你能得到 |
|---|---|
| 🎮 小型游戏开发者 | 多轨编曲台 + 整曲/分轨导出 WAV，直接扔进游戏引擎 |
| 🔊 音效制作者 | 合成音色 + SFZ 采样 + 总线效果，快速出 BGM 与音效小样 |
| 🎹 音乐新手 / 娱乐玩家 | 电脑键盘就是钢琴，调外键变暗、一键出和弦，弹不出错音 |

**明确不做**：歌词/演唱、外接 MIDI 设备、VST/AU 插件托管、云端协作、视频同步。纯器乐，轻量上手。

## 特性

### 🎹 演奏模式
- 电脑键盘 = 琴键（两行式布局，键帽字母直接印在屏幕琴键上）
- **调性辅助**：选调 + 音阶后，调外键自动变暗，新手不易弹错
- **和弦模式**：按一个键自动补齐调内三和弦
- **冻结模式**：破解键盘"最多同按 2-3 键"的硬件限制——依次按下的音逐个冻结保持，每按一个新键，已冻结的音**一起再响**，等效多键同奏；再按已冻结的键解除该音，关掉开关解除全部
- **回声条动效**：弹过的音在键盘上方化作升起的色块，按住越长块越高
- **键盘大小随意调**：键宽滑杆（60%–160%）/ 1–4 八度跨度 / 键盘上 Ctrl+滚轮缩放

### 🎼 编曲模式（N 轨 + 卷帘）
- **最多 16 轨**：左侧轨道列表管理（音色/静音 M/独奏 S/音量/声像/右键菜单），加轨删轨随时
- 钢琴卷帘：左键画音符拖长度 / 拖动移位 / 右键扫删，网格吸附 1/16–整小节
- **多选与批量操作**：Shift+拖框选 / Shift+点选 / Ctrl+A 全选，量化、移调、力度增减一键套用
- **力度编辑条**：卷帘底部柱状力度，拖拽即改，选区联动
- **剪贴板**：Ctrl+C / X / V（粘贴对齐播放头）
- **幽灵音符**：其他轨半透明显示，对位写作不抓瞎（超量自动降级保帧率）
- **鼓机步进编辑器**：16 步 × 6 声部（底鼓/军鼓/拍手/踩镲/嗵鼓/开镲），左键开关、右键重音
- **录制**：演奏模式弹什么，自动量化落进当前轨
- 缩放（`=` / `-` / Ctrl+滚轮 / Ctrl+0 重置）、跟随播放头（页面滚动 / 固定居中两种模式）

### 🔊 音频引擎
- **总线混音架构**：Master（EQ10 + Limiter）← Music / Drum 集合总线 ← 每轨独立总线（音量/声像/EQ/压缩）
- **辅助发送**：每轨独立的混响 / 延迟发送量（插入式效果实现）
- **8 种内置音色**，全部纯合成、力度分层（pp/mf/ff 三档）：钢琴（谐波加法+锤击瞬态）/ 芯片（25% 占空比方波）/ 柔弦（失谐正弦对）/ 贝斯 / 电钢 / 八音盒 / 鼓组（6 声部独立合成：底鼓扫频、军鼓噪声+鼓皮、镲不谐和方波叠…）
- **音色插件**（参数配方级）：`user://instrument_plugins.json` 声明谐波/波形/包络配方即可新增音色
- **SFZ 采样音源**：把 `.sfz` + WAV 采样丢进 `user://sfz/` 即可作为音色使用（key / pitch_keycenter / lovel·hivel 力度分区）
- 启动时后台线程合成采样并落盘缓存（二次启动秒开），播放期纯采样回放，零实时 DSP

### 📊 分析页
- 一键体检：音符数 / 曲长 / 音域 / 密度 / 力度 / 最大同时音 / 分轨统计
- **调性检测**（Krumhansl-Schmuckler 算法），一键"应用到调性辅助"
- **和弦进行时间轴**：逐小节识别和弦 + 罗马数字功能级（I / IV / V…）
- **曲式结构分段**：按音级轮廓自动划分段落并标记 A / B / A
- **智能建议**：基于功能和声的下一和弦候选、旋律候选音

### 🎚️ 混音台
- 独立混音页：每轨通道条（推子 / 声像 / 混响·延迟发送 / M·S）+ Master 主音量
- 与轨道列表实时联动，改动即时生效

### 💾 文件
- 工程文件 `.bsong`：zstd 压缩二进制，千音符工程 < 10KB，v2 格式向后兼容 v1
- **导出 WAV**：整曲实时总线录制；**分轨导出**：每轨各一个独立 WAV（含该轨效果）
- **导出 MIDI** / **导入 MIDI**（GM 启发式映射，`user://gm_map.json` 可自定义音色映射）
- **导出 MusicXML 乐谱**：用 MuseScore（免费）打开查看 / 打印
- **轨道预设**：把音色/音量/声像/发送存为预设，随时复用
- 关窗自动保存，下次启动自动恢复

## 快速开始

> 不想配环境？直接在 [Releases](https://github.com/fanquanpp/quaver/releases) 下载 Windows 测试版（单文件免安装）。

1. 安装 [Godot 4.7+](https://godotengine.org/download)（标准版即可，无需 .NET）
2. 克隆本仓库，用 Godot 打开 `project.godot`
3. 按 F5 运行 —— 首次启动自带《小星星》示范曲

### 弹奏键位

```
高八度  Q 2 W 3 E   R 5 T 6 Y 7 U   I 9 O 0 P
        │ │ │ │ │   │ │ │ │ │ ││   │ │ │ │ │
低八度  Z S X D C V G B H N J M , L . ; /
        └白└黑└白└黑└白┘ └白└黑└白└黑└白┘
```

| 按键 | 功能 |
|---|---|
| `Z` 行 / `Q` 行 | 低 / 高八度琴键（黑键在错落位） |
| `↑` / `↓` | 整体升降八度 |
| `空格` | 播放 / 停止 |
| `=` / `-` | 编曲卷帘放大 / 缩放（`Ctrl+0` 重置） |
| `Ctrl+Z` / `Ctrl+Y` | 撤销 / 重做 |
| `Ctrl+C` / `X` / `V` / `A` | 复制 / 剪切 / 粘贴 / 全选（卷帘选区） |
| `Delete` / `Esc` | 删除选区 / 取消选择 |
| `Ctrl+滚轮`（键盘上） | 演奏键盘整体缩放 |

鼠标同样可弹：点击琴键发声，按住滑动可滑奏。

### 编曲鼠标操作

| 操作 | 效果 |
|---|---|
| 左键点空白 + 横向拖 | 新建音符并定长度 |
| 左键拖已有音符 | 移动（音高 + 时间；选区内整体批量移动） |
| 抓住音符右缘拖 | 改长度 |
| 右键 | 删除（按住扫删） |
| Shift + 拖空白 | 框选音符 |
| Shift + 点音符 | 加 / 减选 |
| 底部力度条拖拽 | 修改音符力度 |
| 滚轮 / Shift+滚轮 / Ctrl+滚轮 | 音高 / 时间 / 缩放 |
| 点击顶部标尺 | 跳转播放位置 |

### 可选：TypeScript 乐理后端（gode）

乐理计算（音阶/和弦）有双后端：默认 **GDScript** 即可完整运行；安装 [gode](https://github.com/godothub/gode)（godothub 的 Godot TS 语言插件）后自动切换 TypeScript 后端：

> 该插件体积大（全量安装约 234MB），仓库已通过 [.gitignore](.gitignore) 的 `/addons/gode/` 规则**整体排除**——克隆仓库不会包含它，也不要把它提交进仓库。未安装时项目照常运行（乐理自动回退 GDScript，功能完全一致）。

1. 从 [gode Releases](https://github.com/godothub/gode/releases) 下载 `gode.zip`
2. 解压出 `gode` 文件夹放入项目 `addons/` 目录（只保留你所用平台的 `binary/` 即可）
3. 用 Godot 打开项目 → 项目设置 → 插件 → 勾选启用 → 重启编辑器

启动日志出现 `[Theory] 乐理引擎后端: gode-typescript` 即生效；未安装时显示 `gdscript`，功能完全一致。

> **维护者注意**：启用 gode 后，编辑器会自动往本地 `project.godot` 写入 `EventLoop` autoload 与 `[native_extensions]` 两处配置。这两处指向被忽略的插件文件，**提交前须剥离**（仓库版不含它们，否则无插件的环境启动会报错）；提交后在本地恢复即可。

## 架构一瞥

```
键盘 / 鼠标 / 卷帘 / 鼓机步进 / 混音台
      │
  MainUI（事件路由 · 轨道列表 · 四标签页 · 文件）
      │                    │
 Synth 播放引擎          Transport 走带
 播放器池 32–128          音频时钟锚定 · look-ahead 提前触发
 总线路由：               事件调度 · 循环 · 录制时钟
 Master←Music/Drum          │
   ←Track0..15         InstrumentBank
      │                预渲染采样(力度分层)+缓存
 AudioEffectPanner      插件配方 · SFZ · 鼓组
 /EQ/压缩/混响/延迟          │
      │                   SongModel
      └──────── .bsong 读写 · 16 轨数据 ─────────┘

      Theory 乐理引擎（TS 优先 / GDScript 回退）· SongAnalysis 和声/曲式分析
```

- **性能**：预渲染采样而非实时 DSP，播放期零热循环；卷帘/键盘/回声条/分析图均为单 Control 矢量绘制 + 脏刷新 + 视口裁剪
- **存储**：`.bsong` zstd 二进制（千音符 < 10KB）；采样磁盘缓存（力度分层）；无外部音频文件
- **测试**：`tests/smoke_v*.tscn` 六套无头回归（模型 / 走带 / 音频 / 分析 / 插件 / UI 接线），`godot --headless --path . res://tests/smoke_v100.tscn` 即跑
- 完整设计文档（需求分析 / 音频引擎 / 语言选型 / 版本迭代记录）见 [DESIGN.md](DESIGN.md)

## 项目结构

```
├── DESIGN.md              # 设计文档（功能/架构/选型/逐版本迭代记录）
├── scenes/main.tscn       # 入口场景
├── scripts/               # GDScript（音频/数据/走带/分析/乐理门面）
│   ├── theory.ts          # TypeScript 乐理引擎（gode 后端）
│   ├── sfz_loader.gd      # SFZ 采样音色加载
│   ├── track_presets.gd   # 轨道预设存取
│   └── ui/                # 主界面 / 轨道列表 / 卷帘 / 键盘 / 鼓机 / 分析 / 混音台
├── tests/                 # 六套无头回归测试
├── aseprite/              # Aseprite 像素画源文件
├── assets/sprites/        # 导出的 PNG（logo/图标集/应用图标）
└── docs/screenshots/      # 界面截图
```

## 路线图

- [x] v0.1 演奏 / 卷帘 / 录制量化 / 合成音色 / 存取 / WAV 导出 / gode 混合语言
- [x] v0.1.2–v0.1.4 体验升级 / 分析页 / 撤销重做 / MIDI 往返 / MusicXML / 循环区间
- [x] v0.2.0 N 轨系统（16 轨）/ 总线效果路由 / 走带音频时钟 / 鼓机步进轨 / 力度分层
- [x] v0.2.1 卷帘多选批量 / 力度编辑条 / 分轨导出 WAV
- [x] v0.3.0 和弦进行检测 / 曲式分段 / 智能建议
- [x] v0.3.1 轨道预设 / MIDI 自定义映射
- [x] v1.0.0 混音台工作区 / 音色插件系统 / SFZ 采样音源
- [ ] v1.x 实时合成引擎（GDExtension）· SF2 采样库 · 按需重估

## 协议

[MIT](LICENSE) © 2026 fanquanpp

## 致谢

- [Godot Engine](https://godotengine.org) · [godothub/gode](https://github.com/godothub/gode)
- 设计参考：[FL Studio Piano Roll](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/pianoroll.htm)（调性高亮/和弦戳/幽灵音符）、[Ableton](https://www.ableton.com/en/manual/arrangement-view/)（编曲视图）、[Synthesia](https://synthesiagame.com/) / [SeeMusic](https://www.seemusicapp.com/) / [notefall](https://github.com/ekkx/notefall)（音符可视化）
