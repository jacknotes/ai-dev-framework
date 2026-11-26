<#
.SYNOPSIS
    一键安装测试环境：探测工具链 → 自动选择后端 → 装资源 → 启动 → 五道门禁

.DESCRIPTION
    这是"测试环境部署方法"的唯一执行入口（方法说明见 deploy/README.md）。
    约定：使用者（含 AI 智能体）读到 deploy/README.md 后，应先向用户确认是否安装；
    用户同意后再执行本脚本，一次性完成测试环境所需资源的准备、启动与验证。

    本脚本只做"编排"，资源安装/启动/门禁仍复用 deploy/docker 与 deploy/local
    两套既有脚本，不重复实现、不吞退出码、不绕过门禁。

    后端选择（-Backend）：
      auto   默认：Docker 引擎可用 → docker（真沙箱），否则 → local（本机闭环）
      docker 强制 Docker 方案
      local  强制本机方案（无 Docker / 无 WSL，只绑 127.0.0.1）

    退出码：0 = 安装并验证通过（五道门禁全绿）；非 0 = 安装或某道门禁失败。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File deploy/install.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File deploy/install.ps1 -Stack vue-go
    powershell -NoProfile -ExecutionPolicy Bypass -File deploy/install.ps1 -Backend local
#>
[CmdletBinding()]
param(
    [ValidateSet('react-python', 'vue-go', 'java-spring', 'dotnet', 'jsp-servlet')]
    [string]$Stack = 'react-python',
    [ValidateSet('auto', 'docker', 'local')]
    [string]$Backend = 'auto',
    [switch]$SkipVerify,
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

# ---------- 解析项目根 ----------
# 本脚本位于 <root>/deploy/install.ps1，向上一级即项目根。
# 同时支持：框架仓库（源在 templates/<Stack>/）与生成的项目（源在项目根）。
if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

Say "===== 测试环境一键安装 =====" White
Say "  项目根: $ProjectRoot"
Say "  技术栈: $Stack"
Say "  后端:   $Backend"

# ---------- 子脚本运行器 ----------
# setup/up/verify 是独立入口脚本，内部会调用 exit/throw；
# 必须在独立进程里运行并用 $LASTEXITCODE 读真实退出码，
# 否则子脚本里的 exit 会直接终止本编排器、且拿不到门禁结论。
function Invoke-Sub {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$Arguments = @(),
        [string]$Label = ''
    )
    if ($Label) { Say ""; Say "==> $Label" Cyan }

    $psExe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    if (-not $psExe) { $psExe = (Get-Command pwsh -ErrorAction SilentlyContinue).Source }
    if (-not $psExe) { throw "未找到 powershell.exe / pwsh" }

    $fullArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + $Arguments

    # 子脚本的输出必须导向 Host 流，绝不能混进本函数的 Success 输出流，
    # 否则 return 会把"子进程 stdout + 退出码"揉成一个数组，破坏调用方的数值比较。
    # 坑：PowerShell 5.1 下 $ErrorActionPreference='Stop' 时，子进程写 stderr 会变成
    # NativeCommandError 记录，故此处临时放宽，靠 $LASTEXITCODE 判定真实结果（同 docker/up.ps1 的做法）。
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & $psExe @fullArgs 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP

    if ($out) {
        ($out -split "`r?`n") | Where-Object { $_.Trim() } | ForEach-Object { Write-Host $_ }
    }
    if ($code -ne 0) {
        Say "    [失败] $ScriptPath 退出码 $code" Red
    }
    return $code
}

# ---------- [1/4] 探测工具链 ----------
Say "`n==> [1/4] 探测工具链" Cyan

$dockerOk = $false
$dockerSrv = ''
$dockerExe = (Get-Command docker -ErrorAction SilentlyContinue).Source
if ($dockerExe) {
    $dockerSrv = (& docker version --format '{{.Server.Version}}' 2>$null)
    $dockerOk = ($LASTEXITCODE -eq 0 -and $dockerSrv)
}
if ($dockerOk) { Say "    docker : 引擎就绪 (Server $dockerSrv)" Green }
else { Say "    docker : 不可用（$($dockerExe -or '未安装')）" Yellow }

$bashPath = 'C:\Program Files\Git\bin\bash.exe'
$bashOk = Test-Path $bashPath
$pythonOk = [bool](Get-Command python -ErrorAction SilentlyContinue)
Say "    bash   : $(if ($bashOk) { $bashPath } else { '未找到 (Git Bash)' })" $(if ($bashOk) { 'Green' } else { 'Yellow' })
Say "    python : $(if ($pythonOk) { (Get-Command python).Source } else { '未找到' })" $(if ($pythonOk) { 'Green' } else { 'Yellow' })

# ---------- [2/4] 选择后端 ----------
Say "`n==> [2/4] 选择后端" Cyan
$useDocker = $false
switch ($Backend) {
    'docker' {
        if (-not $dockerOk) { throw "指定了 Docker 方案，但引擎不可用。请先启动 Docker Desktop，或改用 -Backend local" }
        $useDocker = $true
    }
    'local' { $useDocker = $false }
    default {
        $useDocker = $dockerOk
        if (-not $useDocker) { Say "    Docker 不可用，自动降级为本机方案" Yellow }
    }
}

if ($useDocker) {
    Say "    使用 Docker 方案（真沙箱：internal 网络 + 只读根文件系统 + 资源限额）" Green
} else {
    Say "    使用本机方案（无 Docker 降级：独立 venv + 独立进程 + 只绑 127.0.0.1）" Green
    if (-not $bashOk) { throw "本机方案需要 Git Bash，未找到：$bashPath" }
    if (-not $pythonOk) { throw "本机方案需要 python，未找到" }
    if ($Stack -ne 'react-python' -and (Test-Path (Join-Path $ProjectRoot 'templates'))) {
        Say "    提示：本机方案的框架内源目录固定为 templates/react-python，其他栈请用生成的项目目录或 Docker 方案" Yellow
    }
}

# ---------- [3/4] 安装资源并启动 ----------
$upCode = 1
if ($useDocker) {
    if (-not $dockerOk) {
        # 引擎不可用但用户强制 docker 时已在上一步 throw；这里兜底
        throw "Docker 引擎不可用"
    }
    # 引擎就绪则跳过 setup（setup 会重启 Docker Desktop，仅在首次配置时执行一次）
    Say "`n==> [3/4] Docker 引擎已就绪，跳过 setup（首次配置请单独执行 deploy/docker/setup.ps1）" Cyan
    $upCode = Invoke-Sub -ScriptPath (Join-Path $PSScriptRoot 'docker\up.ps1') `
        -Arguments @('-ProjectRoot', $ProjectRoot, '-Template', $Stack) `
        -Label "构建并启动 Docker 隔离环境（$Stack）"
} else {
    $setupCode = Invoke-Sub -ScriptPath (Join-Path $PSScriptRoot 'local\setup.ps1') `
        -Arguments @('-ProjectRoot', $ProjectRoot) `
        -Label '本机环境准备（venv + 前后端依赖）'
    if ($setupCode -ne 0) {
        Say "`n[install] 本机环境准备失败（exit=$setupCode）" Red
        exit $setupCode
    }
    $upCode = Invoke-Sub -ScriptPath (Join-Path $PSScriptRoot 'local\up.ps1') `
        -Arguments @('-ProjectRoot', $ProjectRoot) `
        -Label '启动本机环境（backend 18080 / frontend 13000）'
}

if ($upCode -ne 0) {
    Say "`n[install] 环境启动失败（exit=$upCode）" Red
    exit $upCode
}

# ---------- [4/4] 门禁验证 ----------
if ($SkipVerify) {
    Say "`n==> [4/4] 按 -SkipVerify 跳过门禁" Yellow
    Say "`n[install] 环境已就绪（未验证门禁）" Green
    exit 0
}

if ($useDocker) {
    $verifyCode = Invoke-Sub -ScriptPath (Join-Path $PSScriptRoot 'docker\verify.ps1') `
        -Arguments @('-ProjectRoot', $ProjectRoot, '-Template', $Stack) `
        -Label '容器内执行五道门禁'
} else {
    $verifyCode = Invoke-Sub -ScriptPath (Join-Path $PSScriptRoot 'local\verify.ps1') `
        -Arguments @('-ProjectRoot', $ProjectRoot) `
        -Label '本机执行五道门禁'
}

if ($verifyCode -ne 0) {
    Say "`n[install] 门禁验证失败（exit=$verifyCode）" Red
    exit $verifyCode
}

Say "`n===== 一键安装完成：资源就绪 + 五道门禁全绿 =====" Green
exit 0
