# Quaver 异常覆盖/悬浮物诊断脚本
# 用途：当游戏画面出现来历不明的红色覆盖、"点击特效"、猫形贴纸等异常视觉时，
#       立刻双击运行本脚本（或在终端 powershell -File diag_overlay.ps1）。
# 输出：桌面截图 + 分层/置顶窗口清单 + 光标信息，保存在脚本同目录 diag_result/ 下。
# 原理：编趣 Quaver 的界面全部为程序内矢量绘制，任何"叠在游戏画面上的半透明
#       图层"都来自外部悬浮程序（桌面歌词/点击特效/桌宠/远程控制光标等）。
#       本脚本在异常发生的瞬间抓取现场，即可锁定是哪个进程画的。

$ErrorActionPreference = "SilentlyContinue"
$outDir = Join-Path $PSScriptRoot "diag_result"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"

Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class Diag {
  [DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
  [DllImport("user32.dll")] public static extern bool GetCursorInfo(out CURSORINFO pci);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lp);
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lp);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
  [StructLayout(LayoutKind.Sequential)]
  public struct CURSORINFO { public int cbSize; public int flags; public IntPtr hCursor; public POINT pt; }
  [StructLayout(LayoutKind.Sequential)]
  public struct POINT { public int X; public int Y; }
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int L; public int T; public int R; public int B; }
}
'@

# 1) 全屏截图（含所有悬浮层）
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen 2>$null
$sw = 2560; $sh = 1600
try {
  Add-Type -AssemblyName System.Windows.Forms
  $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $sw = $b.Width; $sh = $b.Height
} catch {}
$bmp = New-Object System.Drawing.Bitmap $sw, $sh
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
$g.Dispose()
$png = Join-Path $outDir "screen_$stamp.png"
$bmp.Save($png)
$bmp.Dispose()
Write-Output "[1] 全屏截图已保存: $png"

# 2) 光标信息
$ci = New-Object Diag+CURSORINFO
$ci.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($ci)
[Diag]::GetCursorInfo([ref]$ci) | Out-Null
Write-Output ("[2] 光标: 位置={0},{1} 显示中={2} 句柄=0x{3:X}（若句柄图案与异常物一致，即为自定义光标方案）" -f `
  $ci.pt.X, $ci.pt.Y, ($ci.flags -band 1), $ci.hCursor)

# 3) 全部可见窗口（含分层 L / 置顶 T / 工具窗 W），按面积降序
$rows = New-Object System.Collections.ArrayList
$cb = [Diag+EnumWindowsProc]{
  param($h, $l)
  if ([Diag]::IsWindowVisible($h)) {
    $sb = New-Object System.Text.StringBuilder 256
    [Diag]::GetWindowText($h, $sb, 256) | Out-Null
    $p = 0
    [Diag]::GetWindowThreadProcessId($h, [ref]$p) | Out-Null
    $r = New-Object Diag+RECT
    [Diag]::GetWindowRect($h, [ref]$r) | Out-Null
    $w = $r.R - $r.L; $hh = $r.B - $r.T
    if ($w -gt 10 -and $hh -gt 10) {
      $ex = [Diag]::GetWindowLong($h, -20)
      $fl = ""
      if ($ex -band 0x80000) { $fl += "分层" }
      if ($ex -band 0x8) { $fl += "置顶" }
      if ($ex -band 0x80) { $fl += "工具窗" }
      $proc = (Get-Process -Id $p -ErrorAction SilentlyContinue)
      [void]$rows.Add([PSCustomObject]@{
        进程 = $proc.ProcessName; 路径 = $proc.Path
        标题 = $sb.ToString(); 矩形 = ("{0},{1} {2}x{3}" -f $r.L, $r.T, $w, $hh); 标志 = $fl
      })
    }
  }
  return $true
}
[Diag]::EnumWindows($cb, [IntPtr]::Zero) | Out-Null
$txt = Join-Path $outDir "windows_$stamp.txt"
$rows | Sort-Object { [int]($_.矩形 -replace ',.*| x.*|,.*' -as [string]) } -Descending |
  Format-Table 进程, 标题, 矩形, 标志, 路径 -AutoSize -Wrap | Out-String -Width 240 |
  Set-Content $txt
Write-Output "[3] 窗口清单已保存: $txt（共 $($rows.Count) 个可见窗口）"
Write-Output ""
Write-Output "判读方法：打开全屏截图，把异常图层的位置对照窗口清单——"
Write-Output "  · 若异常区域与某个非 Quaver 窗口的矩形重合 → 该进程的悬浮层就是元凶"
Write-Output "  · 若清单里没有任何窗口与异常重合 → 元凶是无 HWND 的合成层（驱动/桌宠/输入法皮肤），"
Write-Output "    请同时留意 光标信息 一行，并回忆刚装过什么鼠标美化/桌宠/直播工具"
Write-Output "完成。把 diag_result 整个文件夹发给排查者即可。"
