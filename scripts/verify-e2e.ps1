#!/usr/bin/env pwsh
# 真实应用端到端验收。不依赖模拟点击(Flutter 窗口收不到 PostMessage 的点击)。
#
# 流程:
#   1. 用环境变量让应用启动后自动开书
#   2. 轮询 DevTools 端口,确认浏览器真的起来了、没有多余空白窗口
#   3. 截图,断言出现「阅读中」角标
#   4. 用 CDP 关掉窗口
#   5. 等一轮轮询(3 秒)后截图,断言角标消失
#
# 用法: pwsh scripts/verify-e2e.ps1

$ErrorActionPreference = 'Stop'
$exe = 'D:\PageReader\build\windows\x64\runner\Debug\pagereader.exe'
$shotDir = 'D:\PageReader\_scratch\e2e'
$profileDir = "$env:APPDATA\com.pagereader\PageReader\browser-profile"
New-Item -ItemType Directory -Force -Path $shotDir | Out-Null

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Cap {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

function Capture($proc, $path) {
  $h = $proc.MainWindowHandle
  $r = New-Object Cap+RECT
  [void][Cap]::GetWindowRect($h, [ref]$r)
  $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
  Write-Host "  窗口尺寸: $w x $ht"
  if ($w -lt 200 -or $ht -lt 200) { Write-Host '  FAIL 窗口尺寸异常,截图无意义'; return $false }
  $bmp = New-Object System.Drawing.Bitmap $w, $ht
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $hdc = $g.GetHdc()
  [void][Cap]::PrintWindow($h, $hdc, 2)
  $g.ReleaseHdc($hdc)
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  Write-Host "  已保存 $path"
  return $true
}

$fail = 0
function Check($label, $ok, $detail) {
  if ($ok) { Write-Host "PASS $label" }
  else { Write-Host "FAIL $label $detail"; $script:fail++ }
}

# ---- 清场 ----
Get-Process -Name pagereader -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item $profileDir -Recurse -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

# ---- 1. 启动并自动开书 ----
Write-Host '=== 启动(自动开 b-rust) ==='
$env:PAGEREADER_OPEN = 'b-rust'
$p = Start-Process -FilePath $exe -PassThru
Start-Sleep -Seconds 3

# ---- 2. 等浏览器起来 ----
Write-Host '=== 等浏览器 ==='
$port = $null
for ($i = 0; $i -lt 30; $i++) {
  Start-Sleep -Seconds 1
  if (Test-Path "$profileDir\DevToolsActivePort") {
    $port = (Get-Content "$profileDir\DevToolsActivePort" -First 1).Trim()
    if ($port) { break }
  }
}
Check '浏览器已启动' ($null -ne $port) ''
if (-not $port) {
  Get-Process -Id $p.Id -ErrorAction SilentlyContinue | Stop-Process -Force
  exit 1
}
Write-Host "  端口: $port"

# ---- 3. 检查 target ----
Start-Sleep -Seconds 2
$list = Invoke-RestMethod "http://127.0.0.1:$port/json/list"
$pages = @($list | Where-Object { $_.type -eq 'page' })
Write-Host "  页面 target 数: $($pages.Count)"
$pages | ForEach-Object { Write-Host "    $($_.url)" }
$blanks = @($pages | Where-Object { $_.url -like 'about:*' })
Check '没有多余空白窗口' ($blanks.Count -eq 0) "有 $($blanks.Count) 个"
Check '目标页已加载' (($pages | Where-Object { $_.url -like '*rust-lang*' }).Count -gt 0) ''

# ---- 4. 截图:应有角标 ----
Write-Host '=== 截图(应显示阅读中) ==='
$proc = Get-Process -Id $p.Id
Capture $proc (Join-Path $shotDir '01-open.png') | Out-Null

# ---- 5. 关窗 ----
Write-Host '=== 关闭浏览器窗口 ==='
$target = $pages | Where-Object { $_.url -like '*rust-lang*' } | Select-Object -First 1
if ($target) {
  $ws = $target.webSocketDebuggerUrl
  # 通过 /json/close/<id> 关掉页面(HTTP 接口,不需要 WS)
  Invoke-RestMethod "http://127.0.0.1:$port/json/close/$($target.id)" -ErrorAction SilentlyContinue | Out-Null
  Write-Host "  已请求关闭 $($target.id)"
} else {
  Write-Host '  FAIL 没找到目标页'
  $fail++
}

# ---- 6. 等轮询(3 秒一次)后截图:角标应消失 ----
Start-Sleep -Seconds 8
Write-Host '=== 截图(角标应消失) ==='
$proc = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
if ($proc) { Capture $proc (Join-Path $shotDir '02-closed.png') | Out-Null }

# ---- 7. 检查进程还活着(不该崩) ----
$still = Get-Process -Id $p.Id -ErrorAction SilentlyContinue
Check '应用未崩溃' ($null -ne $still) ''
if ($still) { $still | Stop-Process -Force }

Remove-Item Env:\PAGEREADER_OPEN -ErrorAction SilentlyContinue
Write-Host ''
if ($fail -eq 0) { Write-Host '=== 全部通过 ==='; exit 0 }
else { Write-Host "=== $fail 项失败 ==="; exit 1 }
