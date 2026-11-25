<#
.SYNOPSIS
    Docker 方案 —— 重启后一次性配置（镜像加速器 + WSL2 校验）

.DESCRIPTION
    必须在本机重启之后执行。它做四件事：
      1. 校验 WSL2 是否真正可用（vmcompute 驱动是否落盘）
      2. 写入 Docker 镜像加速器（Docker Hub 直连不通）
      3. 重启 Docker Desktop 使其生效
      4. 验证能真实拉取镜像

    幂等：可重复执行。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File deploy/docker/setup.ps1
#>
[CmdletBinding()]
param(
    [string]$Mirror = 'https://docker.1panel.live',
    [switch]$SkipPullTest
)

$ErrorActionPreference = 'Stop'

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

Say "===== Docker 环境配置（重启后）=====" White

# ---------- 1. 校验 WSL2 ----------
Say "`n==> [1/5] 校验 WSL2" Cyan

$vmcompute = Test-Path 'C:\Windows\System32\vmcompute.exe'
Say "    vmcompute.exe 存在: $vmcompute"
if (-not $vmcompute) {
    Say "`n!! WSL2 内核驱动尚未落盘，说明还没有重启。" Red
    Say "   请重启 Windows 后重新执行本脚本。" Yellow
    exit 2
}

$wslVersion = & 'C:\Windows\System32\wsl.exe' --version 2>&1 | Out-String
# wsl.exe 输出是 UTF-16LE，PowerShell 可能显示为乱码，这里只做"是否有输出"的判断
if ([string]::IsNullOrWhiteSpace($wslVersion)) {
    Say "!! wsl --version 无输出，WSL2 可能未就绪" Yellow
} else {
    Say "    wsl --version: 有响应 ✔" Green
}

# 确认默认版本为 2
& 'C:\Windows\System32\wsl.exe' --set-default-version 2 2>&1 | Out-Null
Say "    默认 WSL 版本已设为 2 ✔" Green

# ---------- 2. 写镜像加速器 ----------
Say "`n==> [2/5] 配置镜像加速器" Cyan

$dockerConfigDir = Join-Path $env:USERPROFILE '.docker'
if (-not (Test-Path $dockerConfigDir)) {
    New-Item -ItemType Directory -Force -Path $dockerConfigDir | Out-Null
}
$daemonJson = Join-Path $dockerConfigDir 'daemon.json'

# 备份已有配置
if (Test-Path $daemonJson) {
    $backup = "$daemonJson.bak.$(Get-Date -Format yyyyMMddHHmmss)"
    Copy-Item $daemonJson $backup
    Say "    已备份原配置到 $backup" DarkGray
}

$config = @{
    'registry-mirrors' = @($Mirror)
    'features'         = @{ 'buildkit' = $true }
    'log-driver'       = 'json-file'
    'log-opts'         = @{ 'max-size' = '10m'; 'max-file' = '3' }
}
$config | ConvertTo-Json -Depth 5 | Set-Content -Path $daemonJson -Encoding UTF8
Say "    已写入 $daemonJson" Green
Say "    registry-mirrors: $Mirror" Green

# ---------- 3. 重启 Docker Desktop ----------
Say "`n==> [3/5] 重启 Docker Desktop" Cyan

Get-Process -Name 'Docker Desktop','com.docker.backend' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

$ddExe = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
if (Test-Path $ddExe) {
    Start-Process $ddExe
    Say "    已启动 Docker Desktop，等待引擎就绪..." Yellow
} else {
    Say "!! 未找到 $ddExe" Red
    exit 1
}

# ---------- 4. 等待引擎就绪 ----------
Say "`n==> [4/5] 等待 Docker 引擎" Cyan

$ready = $false
for ($i = 1; $i -le 60; $i++) {
    $v = & docker version --format '{{.Server.Version}}' 2>$null
    if ($LASTEXITCODE -eq 0 -and $v) {
        Say "    引擎就绪（第 $i 次尝试），Server 版本 $v ✔" Green
        $ready = $true
        break
    }
    Start-Sleep -Seconds 3
    if ($i % 10 -eq 0) { Say "    仍在等待... ($i/60)" DarkGray }
}

if (-not $ready) {
    Say "`n!! Docker 引擎 3 分钟内未就绪" Red
    Say "   排查建议：" Yellow
    Say "     1) 打开 Docker Desktop 看是否报 WSL 相关错误" Yellow
    Say "     2) 确认已重启（vmcompute.exe 存在但虚拟机起不来）" Yellow
    Say "     3) 日志：$env:LOCALAPPDATA\Docker\log\host\com.docker.backend.exe.log" Yellow
    exit 1
}

# ---------- 5. 验证能拉镜像 ----------
if (-not $SkipPullTest) {
    Say "`n==> [5/5] 验证镜像拉取（走加速器）" Cyan
    $pullOk = $false
    foreach ($img in @('alpine:3.19', 'busybox:latest')) {
        Say "    尝试 $img ..." DarkGray
        & docker pull $img 2>&1 | Select-Object -Last 3 | ForEach-Object { Say "      $_" DarkGray }
        if ($LASTEXITCODE -eq 0) {
            Say "    拉取成功：$img ✔" Green
            $pullOk = $true
            & docker rmi $img 2>&1 | Out-Null
            break
        }
    }
    if (-not $pullOk) {
        Say "`n!! 镜像拉取失败。加速器可能失效，或需要登录 Docker Hub。" Red
        Say "   可改试：-Mirror https://docker.m.daocloud.io" Yellow
        exit 1
    }
} else {
    Say "`n==> [5/5] 跳过镜像拉取测试（-SkipPullTest）" DarkGray
}

Say "`n===== 配置完成 =====" Green
Say "下一步：powershell -File deploy/docker/up.ps1" Gray
