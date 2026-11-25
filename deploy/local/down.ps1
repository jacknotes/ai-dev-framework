<#
.SYNOPSIS
    本机纯闭环测试环境 —— 销毁（杀进程 + 删数据，环境回到"从未存在"）

.DESCRIPTION
    精确按 PID 文件杀进程，不误杀其他 node/python。
    结束时断言：数据目录已删除、端口已释放。

.EXAMPLE
    pwsh -File deploy/local/down.ps1
    pwsh -File deploy/local/down.ps1 -Quiet
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [switch]$Quiet,
    [switch]$KeepLogs
)

$ErrorActionPreference = 'Continue'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$SandboxDir = Join-Path $ProjectRoot 'sandbox'
$PidFile    = Join-Path $SandboxDir 'pids.json'
$DataDir    = Join-Path $SandboxDir 'data'
$LogDir     = Join-Path $SandboxDir 'logs'

function Say($msg, $color = 'Gray') {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor $color }
}

Say "==> [down] 销毁沙箱环境" Cyan

# uvicorn / vite 会派生子进程（uvicorn 的 reloader/worker、node 的 esbuild 服务等），
# 只杀父进程会留下孤儿继续占用端口。因此统一用进程树终止（taskkill /T /F）。

function Stop-Tree([int]$procId, [string]$label) {
    if (-not $procId) { return }
    $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
    if (-not $p) {
        Say "    $label (PID $procId) 已不存在" DarkGray
        return
    }
    & taskkill.exe /PID $procId /T /F 2>$null | Out-Null
    Start-Sleep -Milliseconds 300
    if (Get-Process -Id $procId -ErrorAction SilentlyContinue) {
        Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
        Say "    $label (PID $procId) 已强制停止（taskkill 未生效）" Yellow
    } else {
        Say "    $label (PID $procId) 及其子进程已停止" Green
    }
}

# ---------- 1. 按 PID 文件终止进程树 ----------
if (Test-Path $PidFile) {
    try {
        $info = Get-Content $PidFile -Raw | ConvertFrom-Json
        foreach ($key in @('backend','frontend')) {
            Stop-Tree -procId ([int]$info.$key) -label $key
        }
    } catch {
        Say "    !! 读取 pids.json 失败：$($_.Exception.Message)" Yellow
    }
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
} else {
    Say "    无 pids.json（环境可能未启动）" DarkGray
}

# ---------- 2. 兜底：按命令行匹配沙箱路径，清理全部残留 ----------
# 比"只按端口杀"更可靠：uvicorn 子进程可能不直接监听端口，但仍然活着。
$sandboxPattern = [regex]::Escape($SandboxDir)
$stragglers = Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -match $sandboxPattern }

foreach ($s in $stragglers) {
    Stop-Tree -procId ([int]$s.ProcessId) -label "残留 $($s.Name)"
}

# 再兜一次：端口仍被占用则按端口清理（仍要求命令行含 sandbox，避免误杀）
if (Test-Path $SandboxDir) {
    foreach ($port in @(18080, 13000)) {
        $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        foreach ($c in $conns) {
            $p = Get-CimInstance Win32_Process -Filter "ProcessId=$($c.OwningProcess)" -ErrorAction SilentlyContinue
            if ($p -and $p.CommandLine -and $p.CommandLine -match $sandboxPattern) {
                Stop-Tree -procId ([int]$c.OwningProcess) -label "端口 $port 占用者"
            }
        }
    }
}

# ---------- 2. 删数据目录（不删 venv，避免每次重装依赖）----------
if (Test-Path $DataDir) {
    Remove-Item -Recurse -Force $DataDir -ErrorAction SilentlyContinue
    Say "    已删除数据目录" Green
}

# 应用副本：删除（下次 up 会重新复制）
$AppDir = Join-Path $SandboxDir 'app'
if (Test-Path $AppDir) {
    Remove-Item -Recurse -Force $AppDir -ErrorAction SilentlyContinue
    Say "    已删除工程副本 sandbox\app" Green
}

if (-not $KeepLogs -and (Test-Path $LogDir)) {
    Remove-Item -Recurse -Force $LogDir -ErrorAction SilentlyContinue
    Say "    已删除日志" Green
}

# ---------- 3. 断言销毁结果 ----------
Say "`n==> 销毁校验" Cyan
$ok = $true
if (Test-Path $DataDir) { Say "    !! 数据目录仍存在" Red; $ok = $false }
else { Say "    数据目录已清空 ✔" Green }

foreach ($port in @(18080, 13000)) {
    $inUse = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($inUse) { Say "    !! 端口 $port 仍被监听" Yellow }
    else { Say "    端口 $port 已释放 ✔" Green }
}

if ($ok) { Say "`n[down] 完成，环境已还原" Green }
else { Say "`n[down] 完成，但存在未清理项（见上）" Yellow }
