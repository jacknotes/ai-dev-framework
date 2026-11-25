<#
.SYNOPSIS
    Docker 方案 —— 在容器内执行五道门禁并汇总

.DESCRIPTION
    所有门禁都在 gates 容器内执行（不是宿主机），保证与 CI 口径一致。
    退出码即结论：0 = 全部通过，非 0 = 有失败项。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File deploy/docker/verify.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File deploy/docker/verify.ps1 -SkipE2E
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$Template = 'react-python',
    [switch]$SkipE2E,
    [switch]$Json
)

$ErrorActionPreference = 'Continue'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$AppDir      = Join-Path (Join-Path $ProjectRoot 'sandbox') "docker-$Template"
$ComposeFile = Join-Path $AppDir 'deploy\docker-compose.yml'
$LogDir      = Join-Path (Join-Path $ProjectRoot 'sandbox') 'docker-logs'

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

if (-not (Test-Path $ComposeFile)) {
    Say "!! 未找到环境，请先执行 deploy/docker/up.ps1" Red
    exit 1
}
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }

$results = New-Object System.Collections.ArrayList

# 在 gates 容器内执行一条命令
function Invoke-InGates {
    param(
        [string]$Name,
        [string]$Command,
        [int]$TimeoutSec = 900
    )
    $marker = "[$Name]"
    Say "`n$marker 容器内执行：$Command" Cyan

    $job = Start-Job -ScriptBlock {
        param($compose, $cmd)
        $out = & docker compose -f $compose exec -T gates bash -lc $cmd 2>&1
        [pscustomobject]@{
            Output   = ($out | Out-String)
            ExitCode = $LASTEXITCODE
        }
    } -ArgumentList $ComposeFile, $Command

    $done = Wait-Job $job -Timeout $TimeoutSec
    if (-not $done) {
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        Say "$marker 超时（${TimeoutSec}s）" Red
        [void]$results.Add([pscustomobject]@{ Gate=$Name; ExitCode=124; Passed=$false; Summary="超时 ${TimeoutSec}s" })
        return
    }

    $r = Receive-Job $job
    Remove-Job $job -Force -ErrorAction SilentlyContinue

    $outText = if ($r) { $r.Output } else { '' }
    $code    = if ($r) { $r.ExitCode } else { 1 }

    # 日志落盘
    $safeName = $Name -replace '[^\w]', '_'
    Set-Content -Path (Join-Path $LogDir "gate-$safeName.log") -Value $outText -Encoding UTF8

    $tail = ($outText -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 8)
    foreach ($line in $tail) {
        if ($code -eq 0) { Say "    $line" DarkGray } else { Say "    $line" Red }
    }

    $passed = ($code -eq 0)
    $summary = if ($passed) { '通过' } else {
        $line = ($outText -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
        if ($line) { $line.Trim() } else { "exit=$code" }
    }

    if ($passed) { Say "$marker 通过 (exit=0)" Green }
    else { Say "$marker 失败 (exit=$code)" Red }

    [void]$results.Add([pscustomobject]@{
        Gate=$Name; ExitCode=$code; Passed=$passed; Summary=$summary
    })
}

# ---------- 确保 gates 容器在跑 ----------
Say "===== 容器内执行五道门禁 =====" White
Say "`n==> 检查 gates 容器" Cyan

& docker compose -f $ComposeFile --profile gates up -d gates 2>&1 | ForEach-Object { Say "    $_" DarkGray }
if ($LASTEXITCODE -ne 0) {
    Say "!! gates 容器启动失败" Red
    exit 1
}

# 等待容器可执行命令
$readyOk = $false
for ($i = 1; $i -le 20; $i++) {
    & docker compose -f $ComposeFile exec -T gates bash -lc 'true' 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $readyOk = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $readyOk) {
    Say "!! gates 容器不可用" Red
    exit 1
}
Say "    gates 容器就绪 ✔" Green

# ---------- 五道门禁（全部在容器内）----------
Invoke-InGates -Name '编码-静态检查' -Command 'bash scripts/lint.sh'
Invoke-InGates -Name '编码-构建'     -Command 'bash scripts/build.sh'
Invoke-InGates -Name '编码-单元测试' -Command 'bash scripts/test.sh'

if ($SkipE2E) {
    Say "`n[e2e] 按参数跳过" Yellow
} else {
    Invoke-InGates -Name '验收-e2e' -Command 'bash scripts/e2e.sh'
}

# 健康检查走容器网络内部（backend 服务名）
Invoke-InGates -Name '部署-健康检查' -Command 'HEALTH_HOST=backend PORT=8000 bash scripts/health.sh'

# ---------- 汇总 ----------
Say "`n===== 门禁汇总 =====" White
$results | Format-Table -AutoSize @(
    @{n='门禁'; e={$_.Gate}},
    @{n='退出码'; e={$_.ExitCode}},
    @{n='结论'; e={ if ($_.Passed) { '通过' } else { '失败' } }},
    @{n='摘要'; e={$_.Summary}}
) | Out-String | ForEach-Object { Write-Host $_ }

if ($Json) {
    $jsonPath = Join-Path $LogDir 'gate-results.json'
    ($results | ConvertTo-Json -Depth 5) | Set-Content -Path $jsonPath -Encoding UTF8
    Say "详细结果已写入: $jsonPath" Gray
}

$failed = @($results | Where-Object { -not $_.Passed })
if ($failed.Count -eq 0) {
    Say "`n[verify] 全部通过 ✔" Green
    exit 0
} else {
    Say "`n[verify] 有 $($failed.Count) 项失败：$(($failed | ForEach-Object { $_.Gate }) -join ', ')" Red
    exit 1
}
