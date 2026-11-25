<#
.SYNOPSIS
    Docker 方案 —— 销毁隔离环境

.DESCRIPTION
    docker compose down -v：容器、网络、匿名卷全部删除，环境回到"从未存在"。
    这是五重隔离里"一次性"的落地。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File deploy/docker/down.ps1
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$Template = 'react-python',
    [switch]$Quiet,
    [switch]$KeepImages
)

$ErrorActionPreference = 'Continue'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$SandboxRoot = Join-Path $ProjectRoot 'sandbox'
$AppDir      = Join-Path $SandboxRoot "docker-$Template"
$ComposeFile = Join-Path $AppDir 'deploy\docker-compose.yml'

function Say($msg, $color = 'Gray') { if (-not $Quiet) { Write-Host $msg -ForegroundColor $color } }

Say "===== 销毁 Docker 隔离环境 =====" White

if (-not (Test-Path $ComposeFile)) {
    Say "    未找到环境（可能未启动）" DarkGray
} else {
    Say "`n==> docker compose down -v" Cyan
    & docker compose -f $ComposeFile --profile gates --profile e2e down -v --remove-orphans 2>&1 |
        ForEach-Object { Say "    $_" DarkGray }
    if ($LASTEXITCODE -eq 0) { Say "    容器/网络/卷已删除 ✔" Green }
    else { Say "    !! down 返回非 0，请检查" Yellow }
}

if (-not $KeepImages) {
    Say "`n==> 清理本项目构建的镜像" Cyan
    $projName = if ($Template -eq 'vue-go') { 'vue-go-sandbox' } else { "$Template-sandbox" }
    $imgs = & docker images --format '{{.Repository}}:{{.Tag}}' 2>$null |
        Where-Object { $_ -match [regex]::Escape($projName) -or $_ -match 'docker-react-python|docker-vue-go' }
    foreach ($img in $imgs) {
        & docker rmi -f $img 2>&1 | Out-Null
        Say "    已删除镜像 $img" Green
    }
    if (-not $imgs) { Say "    无需清理" DarkGray }
}

# 删除沙箱副本
if (Test-Path $AppDir) {
    Remove-Item -Recurse -Force $AppDir -ErrorAction SilentlyContinue
    Say "`n    已删除沙箱副本 $AppDir" Green
}

# ---------- 断言 ----------
Say "`n==> 销毁校验" Cyan
$leftover = & docker ps -a --filter "name=$Template" --format '{{.Names}}' 2>$null
if ($leftover) {
    Say "    !! 仍有残留容器：$($leftover -join ', ')" Yellow
} else {
    Say "    无残留容器 ✔" Green
}

$nets = & docker network ls --format '{{.Name}}' 2>$null | Where-Object { $_ -match [regex]::Escape($Template) }
if ($nets) { Say "    !! 仍有残留网络：$($nets -join ', ')" Yellow }
else { Say "    无残留网络 ✔" Green }

Say "`n[down] 完成" Green
