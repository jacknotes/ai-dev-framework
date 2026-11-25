<#
.SYNOPSIS
    本机纯闭环测试环境 —— 启动（复制工程到沙箱、起前后端、等健康检查通过）

.DESCRIPTION
    幂等：重复执行会先销毁再重建，不会残留多个进程。
    安全：只监听 127.0.0.1；启动前校验无生产凭证；端口被占用则拒绝启动。

.EXAMPLE
    pwsh -File deploy/local/up.ps1
    pwsh -File deploy/local/up.ps1 -BackendPort 18081 -FrontendPort 13001
#>
[CmdletBinding()]
param(
    [int]$BackendPort = 18080,
    [int]$FrontendPort = 13000,
    [string]$ProjectRoot,
    # 业务代码源目录。省略时自动判断：框架仓库用 templates\react-python，项目仓库用项目根。
    [string]$SourceRoot,
    [switch]$SkipFrontend
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$SandboxDir = Join-Path $ProjectRoot 'sandbox'
$VenvPython = Join-Path $SandboxDir '.venv\Scripts\python.exe'
$AppDir     = Join-Path $SandboxDir 'app'
$LogDir     = Join-Path $SandboxDir 'logs'
$DataDir    = Join-Path $SandboxDir 'data'
$PidFile    = Join-Path $SandboxDir 'pids.json'

Write-Host "==> 沙箱根: $SandboxDir" -ForegroundColor Cyan

# ---------- 0. 前置校验 ----------
if (-not (Test-Path $VenvPython)) {
    throw "未找到 sandbox\.venv，请先执行：pwsh -File deploy/local/setup.ps1"
}

# 安全校验：拒绝在检测到生产凭证时启动
Write-Host "`n==> [0/4] 安全检查" -ForegroundColor Cyan
$dangerous = @()
foreach ($name in @('PROD_DB_PASSWORD','PROD_API_KEY','DATABASE_URL','PROD_SECRET')) {
    $val = [Environment]::GetEnvironmentVariable($name)
    if ($val) { $dangerous += "$name" }
}
if ($dangerous.Count -gt 0) {
    throw "检测到疑似生产凭证环境变量：$($dangerous -join ', ')。本沙箱拒绝启动，请先在当前会话 unset 它们。"
}
Write-Host "    未发现生产凭证 ✔" -ForegroundColor Green

# ---------- 1. 先清理上一次的沙箱（幂等的关键）----------
# 必须放在端口校验之前：上一次 up 起的进程还占着端口，
# 若先校验端口会被自己上次的进程误判为"端口已被占用"。
Write-Host "`n==> [1/4] 清理旧的沙箱实例" -ForegroundColor Cyan

$downScript = Join-Path $PSScriptRoot 'down.ps1'
if (Test-Path $downScript) {
    & $downScript -ProjectRoot $ProjectRoot -Quiet -KeepLogs | Out-Null
}

# 给 TIME_WAIT / 端口释放留一点时间
for ($i = 0; $i -lt 20; $i++) {
    $busy = @($BackendPort, $FrontendPort) | Where-Object {
        Get-NetTCPConnection -LocalPort $_ -State Listen -ErrorAction SilentlyContinue
    }
    if ($busy.Count -eq 0) { break }
    Start-Sleep -Milliseconds 250
}

# 端口占用校验（此时只剩"非沙箱进程"占用的情况）
function Test-PortFree([int]$port) {
    $inUse = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    return (-not $inUse)
}
foreach ($p in @($BackendPort, $FrontendPort)) {
    if (-not (Test-PortFree $p)) {
        $owner = (Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue |
                  Select-Object -First 1).OwningProcess
        $desc = if ($owner) {
            $pr = Get-CimInstance Win32_Process -Filter "ProcessId=$owner" -ErrorAction SilentlyContinue
            if ($pr) { "$($pr.Name) (PID $owner)" } else { "PID $owner" }
        } else { "未知进程" }
        throw "端口 $p 被非沙箱进程占用：$desc。请换端口（-BackendPort/-FrontendPort）或先释放它。"
    }
}
Write-Host "    端口 $BackendPort / $FrontendPort 空闲 ✔" -ForegroundColor Green

# ---------- 2. 复制工程到沙箱 ----------
Write-Host "`n==> [2/4] 准备沙箱工程副本" -ForegroundColor Cyan

if (Test-Path $AppDir) { Remove-Item -Recurse -Force $AppDir }
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

# 源目录解析：本脚本同时服务两种场景。
#   a) 在**框架仓库**里跑：业务代码在 templates/<stack>/
#   b) 在**生成的项目**里跑：业务代码就在项目根（backend/ frontend/ scripts/）
# 先用显式 -SourceRoot；否则优先 templates\react-python，其次回落到项目根。
if ($SourceRoot) {
    $srcDir = $SourceRoot
} elseif (Test-Path (Join-Path $ProjectRoot 'templates\react-python\scripts')) {
    $srcDir = Join-Path $ProjectRoot 'templates\react-python'
} else {
    $srcDir = $ProjectRoot
}

if (-not (Test-Path (Join-Path $srcDir 'scripts'))) {
    throw "未找到门禁脚本目录：$srcDir\scripts。请确认在框架仓库或生成的项目根目录执行本脚本。"
}
Write-Host "    源目录: $srcDir" -ForegroundColor Gray

foreach ($sub in @('backend', 'frontend', 'scripts')) {
    $from = Join-Path $srcDir $sub
    if (Test-Path $from) {
        Copy-Item $from (Join-Path $AppDir $sub) -Recurse -Force
    } else {
        Write-Host "    (跳过不存在的 $sub/)" -ForegroundColor DarkGray
    }
}
Write-Host "    已复制 backend/ frontend/ scripts/ 到 sandbox\app" -ForegroundColor Green

# ---------- 启动辅助：后台启动一个完全脱离的进程 ----------
# 踩过的两个坑（都表现为"up.ps1 卡住不退出"，其实环境已经就绪）：
#   1. Start-Process -RedirectStandardOutput：子进程一直持有重定向句柄，
#      父 PowerShell 退出时会等这些句柄关闭 → 挂住。
#   2. Start-Process cmd /c "... > log"：cmd 仍作为子进程挂在当前控制台上 → 挂住。
#
# 正解：用 WMI 的 Win32_Process.Create 创建进程。它不继承父进程的任何句柄、
# 不挂靠当前控制台，创建后立即返回，父进程可以安稳退出。
# 日志通过 cmd 重定向落盘（重定向发生在被创建的进程内部，不影响父进程）。
function Start-SandboxProcess {
    param(
        [string]$FilePath,
        [string[]]$ArgList,
        [string]$WorkingDir,
        [string]$OutLog,
        [string]$ErrLog
    )

    # 组装： cmd.exe /c ""<exe>" "<arg>" ... > "out.log" 2> "err.log""
    $quoted = @("`"$FilePath`"") + ($ArgList | ForEach-Object { "`"$_`"" })
    $inner = ($quoted -join ' ') + " > `"$OutLog`" 2> `"$ErrLog`""
    $cmdLine = "cmd.exe /c `"$inner`""

    $result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine      = $cmdLine
        CurrentDirectory = $WorkingDir
    }

    if ($result.ReturnValue -ne 0) {
        throw "创建进程失败（Win32_Process.Create 返回 $($result.ReturnValue)）：$FilePath"
    }
    return [int]$result.ProcessId
}

# ---------- 2. 启动后端 ----------
Write-Host "`n==> [2/4] 启动后端 (127.0.0.1:$BackendPort)" -ForegroundColor Cyan

$backendOut = Join-Path $LogDir 'backend.out.log'
$backendErr = Join-Path $LogDir 'backend.err.log'
$backendWork = Join-Path $AppDir 'backend'

$backendArgs = @(
    '-m', 'uvicorn', 'app.main:app',
    '--host', '127.0.0.1',
    '--port', "$BackendPort"
)
$backendPid = Start-SandboxProcess -FilePath $VenvPython -ArgList $backendArgs `
    -WorkingDir $backendWork -OutLog $backendOut -ErrLog $backendErr

Write-Host "    PID $backendPid" -ForegroundColor Green

# ---------- 3. 启动前端 ----------
$frontendPid = $null
if (-not $SkipFrontend) {
    Write-Host "`n==> [3/4] 启动前端 (127.0.0.1:$FrontendPort)" -ForegroundColor Cyan

    $nodeExe = Join-Path $env:USERPROFILE '.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe'
    if (-not (Test-Path $nodeExe)) {
        $n = Get-Command node -ErrorAction SilentlyContinue
        if (-not $n) { Write-Host "    !! 未找到 node，跳过前端" -ForegroundColor Yellow }
        else { $nodeExe = $n.Source }
    }

    if ($nodeExe -and (Test-Path $nodeExe)) {
        $frontendWork = Join-Path $AppDir 'frontend'
        $viteBin = Join-Path $frontendWork 'node_modules\vite\bin\vite.js'

        if (-not (Test-Path $viteBin)) {
            Write-Host "    前端依赖未安装，正在安装（首次较慢）..." -ForegroundColor Gray
            $pnpmMjs = Join-Path $env:USERPROFILE '.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\pnpm\bin\pnpm.mjs'
            $env:PATH = (Split-Path $nodeExe) + ';' + $env:PATH
            $env:npm_config_verify_deps_before_run = 'false'
            if (Test-Path $pnpmMjs) {
                & $nodeExe $pnpmMjs install --dir $frontendWork 2>&1 | Out-Null
            } else {
                Push-Location $frontendWork
                & npm install 2>&1 | Out-Null
                Pop-Location
            }
        }

        if (Test-Path $viteBin) {
            $feOut = Join-Path $LogDir 'frontend.out.log'
            $feErr = Join-Path $LogDir 'frontend.err.log'
            $frontendPid = Start-SandboxProcess -FilePath $nodeExe `
                -ArgList @($viteBin, '--host', '127.0.0.1', '--port', "$FrontendPort", '--strictPort') `
                -WorkingDir $frontendWork -OutLog $feOut -ErrLog $feErr
            Write-Host "    PID $frontendPid" -ForegroundColor Green
        } else {
            Write-Host "    !! 前端依赖安装后仍未找到 vite，跳过前端" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "`n==> [3/4] 跳过前端 (-SkipFrontend)" -ForegroundColor Gray
}

# ---------- 4. 记录 PID 并等待就绪 ----------
Write-Host "`n==> [4/4] 等待健康检查" -ForegroundColor Cyan

$pidInfo = @{
    backend      = $backendPid
    frontend     = $frontendPid
    backendPort  = $BackendPort
    frontendPort = $FrontendPort
    startedAt    = (Get-Date).ToString('o')
    projectRoot  = $ProjectRoot
}
$pidInfo | ConvertTo-Json | Set-Content -Path $PidFile -Encoding UTF8

$healthUrl = "http://127.0.0.1:$BackendPort/health"
$ready = $false
for ($i = 1; $i -le 30; $i++) {
    try {
        $r = Invoke-WebRequest -Uri $healthUrl -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
        if ($r.StatusCode -eq 200) { $ready = $true; break }
    } catch { Start-Sleep -Milliseconds 800 }
}
if (-not $ready) {
    Write-Host "    !! 后端 30 次重试仍未就绪，查看日志：$backendErr" -ForegroundColor Red
    if (Test-Path $backendErr) { Get-Content $backendErr -Tail 20 }
    throw "后端启动失败"
}
Write-Host "    后端健康检查通过 ✔  $healthUrl" -ForegroundColor Green

if ($frontendPid) {
    $feReady = $false
    for ($i = 1; $i -le 40; $i++) {
        try {
            $r = Invoke-WebRequest -Uri "http://127.0.0.1:$FrontendPort/" -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
            if ($r.StatusCode -eq 200) { $feReady = $true; break }
        } catch { Start-Sleep -Milliseconds 800 }
    }
    if ($feReady) { Write-Host "    前端就绪 ✔  http://127.0.0.1:$FrontendPort" -ForegroundColor Green }
    else { Write-Host "    !! 前端未就绪，查看日志：$(Join-Path $LogDir 'frontend.err.log')" -ForegroundColor Yellow }
}

Write-Host "`n[up] 环境已就绪" -ForegroundColor Green
Write-Host "     后端: http://127.0.0.1:$BackendPort" -ForegroundColor Gray
Write-Host "     前端: http://127.0.0.1:$FrontendPort" -ForegroundColor Gray
Write-Host "     下一步: pwsh -File deploy/local/verify.ps1" -ForegroundColor Gray
