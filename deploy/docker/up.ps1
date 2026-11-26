<#
.SYNOPSIS
    Docker 方案 —— 启动隔离测试环境

.DESCRIPTION
    把模板复制到沙箱目录（不污染模板本身），用 docker compose 构建并启动。
    幂等：重复执行会先 down 再 up。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File deploy/docker/up.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File deploy/docker/up.ps1 -Template vue-go
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$Template = 'react-python',
    # 业务代码源目录。省略时自动判断：框架仓库用 templates\<Template>，项目仓库用项目根。
    [string]$SourceRoot,
    [switch]$WithGates,
    [switch]$WithE2E,
    [switch]$Build
)

$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$SandboxRoot = Join-Path $ProjectRoot 'sandbox'
$AppDir      = Join-Path $SandboxRoot "docker-$Template"

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

# ---------- 0. 前置校验 ----------
Say "===== 启动 Docker 隔离环境 =====" White
Say "`n==> [0/4] 前置校验" Cyan

$v = & docker version --format '{{.Server.Version}}' 2>$null
if ($LASTEXITCODE -ne 0 -or -not $v) {
    Say "!! Docker 引擎未就绪。请先执行 deploy/docker/setup.ps1" Red
    Say "   （若刚装完 WSL 功能，必须重启 Windows）" Yellow
    exit 1
}
Say "    Docker Server: $v ✔" Green

$composeV = & docker compose version --format '{{.Version}}' 2>$null
Say "    Docker Compose: $composeV ✔" Green

# 源目录解析：本脚本同时服务两种场景。
#   a) 在**框架仓库**里跑：业务代码在 templates/<Template>/
#   b) 在**生成的项目**里跑：业务代码就在项目根（backend/ frontend/ deploy/ scripts/）
if ($SourceRoot) {
    $tplDir = $SourceRoot
} elseif (Test-Path (Join-Path $ProjectRoot "templates\$Template")) {
    $tplDir = Join-Path $ProjectRoot "templates\$Template"
} else {
    $tplDir = $ProjectRoot
}
if (-not (Test-Path (Join-Path $tplDir 'scripts'))) {
    Say "!! 未找到可用源目录（缺 scripts/）：$tplDir" Red
    Say "   请确认在框架仓库或生成的项目根目录执行本脚本。" Yellow
    exit 1
}
Say "    源目录: $tplDir" Gray

# ---------- 1. 先清理旧实例 ----------
Say "`n==> [1/4] 清理旧实例" Cyan
$downScript = Join-Path $PSScriptRoot 'down.ps1'
if (Test-Path $downScript) {
    & $downScript -ProjectRoot $ProjectRoot -Template $Template -Quiet
}

# ---------- 2. 复制模板到沙箱 ----------
Say "`n==> [2/4] 复制模板到沙箱" Cyan
if (Test-Path $AppDir) { Remove-Item -Recurse -Force $AppDir }
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
New-Item -ItemType Directory -Force -Path $SandboxRoot | Out-Null

foreach ($item in @('backend','frontend','deploy','scripts','docs','tests')) {
    $src = Join-Path $tplDir $item
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $AppDir $item) -Recurse -Force
    }
}
# 复制根级文件（.dockerignore 等）
Get-ChildItem $tplDir -File -Force | ForEach-Object { Copy-Item $_.FullName (Join-Path $AppDir $_.Name) -Force }
Say "    已复制到 $AppDir ✔" Green

# ---------- 3. 构建 ----------
Say "`n==> [3/4] 构建镜像" Cyan
$composeFile = Join-Path $AppDir 'deploy\docker-compose.yml'

$buildArgs = @('compose','-f',$composeFile,'build')
if ($Build) { $buildArgs += '--no-cache' }

Push-Location $AppDir
try {
    # 关键：docker 会把构建进度和 "Image xxx Built" 写到 stderr，
    # PowerShell 会把这些当成 NativeCommandError 抛出来，且经过管道后
    # $LASTEXITCODE 会被后续命令覆盖。所以：
    #   1. 临时放宽 ErrorActionPreference，靠退出码判定而不是异常
    #   2. 用 $LASTEXITCODE 直接判断前不要插入其他管道命令
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    & docker @buildArgs 2>&1 | ForEach-Object { Say "    $_" DarkGray }
    $buildCode = $LASTEXITCODE

    $ErrorActionPreference = $prevEAP

    if ($buildCode -ne 0) {
        Say "`n!! 镜像构建失败 (exit=$buildCode)" Red
        exit 1
    }
    Say "    构建完成 ✔" Green

    # ---------- 4. 启动 ----------
    Say "`n==> [4/4] 启动服务" Cyan
    # --profile 是 compose 子命令的全局选项，必须放在 up 之前
    $upArgs = @('compose','-f',$composeFile)
    if ($WithGates) { $upArgs += @('--profile','gates') }
    if ($WithE2E)   { $upArgs += @('--profile','e2e') }
    $upArgs += @('up','-d')

    $ErrorActionPreference = 'Continue'
    & docker @upArgs 2>&1 | ForEach-Object { Say "    $_" DarkGray }
    $upCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP

    if ($upCode -ne 0) { Say "!! 启动失败 (exit=$upCode)" Red; exit 1 }

    # 等待 healthy
    # 注意：只检查**有 healthcheck 的服务**。gates 是工具容器，没有 healthcheck，
    # 其 Health 字段为空，若一并判定会被误报为"未达 healthy"。
    Say "`n    等待服务健康..." Yellow
    $allHealthy = $false
    for ($i = 1; $i -le 40; $i++) {
        $ps = & docker compose -f $composeFile ps --format '{{.Service}}|{{.Health}}' 2>$null
        $lines = @($ps | Where-Object { $_ -and $_.Trim() })
        # 只保留有健康状态的服务（形如 "service|healthy" / "service|starting"）
        $withHealth = @($lines | Where-Object { $_ -match '\|(healthy|starting|unhealthy)$' })
        $notHealthy = @($withHealth | Where-Object { $_ -notmatch '\|healthy$' })
        if ($withHealth.Count -gt 0 -and $notHealthy.Count -eq 0) { $allHealthy = $true; break }
        Start-Sleep -Seconds 3
    }

    if ($allHealthy) {
        Say "    全部带健康检查的服务 healthy ✔" Green
    } else {
        Say "    !! 部分服务未达 healthy，当前状态：" Yellow
        & docker compose -f $composeFile ps 2>&1 | ForEach-Object { Say "    $_" Yellow }
    }

    Say "`n===== 环境已启动 =====" White
    & docker compose -f $composeFile ps 2>&1 | ForEach-Object { Say "  $_" Gray }
    Say "`n说明：sandbox 网络为 internal，服务不发布端口到宿主机。" Gray
    Say "      验证请在容器内执行：powershell -File deploy/docker/verify.ps1" Gray
}
finally {
    Pop-Location
}
