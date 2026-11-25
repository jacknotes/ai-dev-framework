<#
.SYNOPSIS
    本机纯闭环测试环境 —— 一次性准备（建 venv、装依赖、探测工具链）

.DESCRIPTION
    幂等：可重复执行。已存在的 venv 不会重建（除非 -Force）。
    不修改系统 PATH，不污染全局 site-packages。

.EXAMPLE
    pwsh -File deploy/local/setup.ps1
    pwsh -File deploy/local/setup.ps1 -Force
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [string]$ProjectRoot,
    # 依赖源目录。省略时自动判断：框架仓库用 templates\react-python，项目仓库用项目根。
    [string]$SourceRoot
)

$ErrorActionPreference = 'Stop'

# ---------- 路径解析 ----------
if (-not $ProjectRoot) {
    # 本脚本位于 <root>/deploy/local/，向上两级即项目根
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$SandboxDir = Join-Path $ProjectRoot 'sandbox'
$VenvDir    = Join-Path $SandboxDir '.venv'
$LogDir     = Join-Path $SandboxDir 'logs'

Write-Host "==> 项目根目录: $ProjectRoot" -ForegroundColor Cyan

# ---------- 1. 探测工具链 ----------
Write-Host "`n==> [1/4] 探测工具链" -ForegroundColor Cyan

function Find-Bash {
    $candidates = @(
        'C:\Program Files\Git\bin\bash.exe',
        'C:\Program Files\Git\usr\bin\bash.exe',
        'C:\Program Files (x86)\Git\bin\bash.exe'
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    $cmd = Get-Command bash -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$BashPath = Find-Bash
if (-not $BashPath) {
    throw "未找到 bash。本环境的 scripts/*.sh 需要 Git Bash。请先安装 Git for Windows。"
}
Write-Host "    bash     : $BashPath" -ForegroundColor Green

$PythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $PythonCmd) { throw "未找到 python，请先安装 Python 3.10+。" }
Write-Host "    python   : $($PythonCmd.Source)" -ForegroundColor Green
Write-Host "    version  : $(& python --version 2>&1)" -ForegroundColor Green

# Node：优先用 DSH 内置 Node，其次系统 Node
$NodeExe = $null
$PnpmMjs = $null
$dshNode = Join-Path $env:USERPROFILE '.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe'
$dshPnpm = Join-Path $env:USERPROFILE '.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\pnpm\bin\pnpm.mjs'
if (Test-Path $dshNode) {
    $NodeExe = $dshNode
    if (Test-Path $dshPnpm) { $PnpmMjs = $dshPnpm }
} else {
    $n = Get-Command node -ErrorAction SilentlyContinue
    if ($n) { $NodeExe = $n.Source }
}
if ($NodeExe) {
    Write-Host "    node     : $NodeExe ($(& $NodeExe --version))" -ForegroundColor Green
    if (-not $PnpmMjs) {
        $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
        if ($npmCmd) { Write-Host "    package manager: npm ($($npmCmd.Source))" -ForegroundColor Green }
        else { Write-Host "    !! 未找到 npm/pnpm，前端门禁将无法执行" -ForegroundColor Yellow }
    } else {
        Write-Host "    package manager: pnpm ($PnpmMjs)" -ForegroundColor Green
    }
} else {
    Write-Host "    !! 未找到 node，前端门禁将无法执行" -ForegroundColor Yellow
}

# ---------- 2. 建目录 ----------
Write-Host "`n==> [2/4] 准备沙箱目录" -ForegroundColor Cyan
foreach ($d in @($SandboxDir, $LogDir, (Join-Path $SandboxDir 'data'))) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}
Write-Host "    $SandboxDir" -ForegroundColor Green

# ---------- 3. 建 venv 并装依赖 ----------
Write-Host "`n==> [3/4] Python 虚拟环境" -ForegroundColor Cyan

if ($Force -and (Test-Path $VenvDir)) {
    Write-Host "    -Force：删除旧 venv" -ForegroundColor Yellow
    Remove-Item -Recurse -Force $VenvDir
}

if (-not (Test-Path (Join-Path $VenvDir 'Scripts\python.exe'))) {
    Write-Host "    创建 venv ..." -ForegroundColor Gray
    & python -m venv $VenvDir
    if ($LASTEXITCODE -ne 0) { throw "创建 venv 失败" }
} else {
    Write-Host "    venv 已存在，跳过创建" -ForegroundColor Gray
}

$VenvPython = Join-Path $VenvDir 'Scripts\python.exe'
Write-Host "    venv python: $(& $VenvPython --version)" -ForegroundColor Green

Write-Host "    安装后端运行/测试依赖 ..." -ForegroundColor Gray

# 源目录解析（同 up.ps1）：框架仓库用 templates\react-python，生成的项目用项目根。
if ($SourceRoot) {
    $srcDir = $SourceRoot
} elseif (Test-Path (Join-Path $ProjectRoot 'templates\react-python\backend')) {
    $srcDir = Join-Path $ProjectRoot 'templates\react-python'
} else {
    $srcDir = $ProjectRoot
}
Write-Host "    依赖源目录: $srcDir" -ForegroundColor Gray

$reqMain = Join-Path $srcDir 'backend\requirements.txt'
$reqDev  = Join-Path $srcDir 'backend\requirements-dev.txt'

if (-not (Test-Path $reqMain)) {
    throw "未找到 $reqMain。请确认在框架仓库或生成的项目根目录执行本脚本。"
}

& $VenvPython -m pip install --quiet --disable-pip-version-check --upgrade pip
& $VenvPython -m pip install --quiet --disable-pip-version-check -r $reqMain
if ($LASTEXITCODE -ne 0) { throw "安装后端运行依赖失败" }
if (Test-Path $reqDev) {
    & $VenvPython -m pip install --quiet --disable-pip-version-check -r $reqDev
    if ($LASTEXITCODE -ne 0) { throw "安装后端测试依赖失败" }
}
& $VenvPython -m pip install --quiet --disable-pip-version-check pytest-cov
if ($LASTEXITCODE -ne 0) { throw "安装 pytest-cov 失败" }

Write-Host "    后端依赖安装完成" -ForegroundColor Green

# ---------- 4. 前端依赖 ----------
Write-Host "`n==> [4/4] 前端依赖" -ForegroundColor Cyan
$frontendDir = Join-Path $ProjectRoot 'sandbox\app\frontend'
if (-not (Test-Path $frontendDir)) {
    Write-Host "    前端尚未部署到沙箱（up.ps1 会自动复制），跳过依赖安装" -ForegroundColor Gray
} else {
    Write-Host "    前端已在沙箱，安装依赖请执行 up.ps1" -ForegroundColor Gray
}

Write-Host "`n[setup] 完成。下一步：pwsh -File deploy/local/up.ps1" -ForegroundColor Green
