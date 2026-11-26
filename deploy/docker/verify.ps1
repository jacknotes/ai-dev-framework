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

        # 关键：docker 把日志写到 stderr，PowerShell 会把它包成 ErrorRecord。
        # 直接 Out-String 会把 PowerShell 的格式化噪音（"+ CategoryInfo"、
        # "FullyQualifiedErrorId" 等）混进日志和摘要，导致失败原因完全不可读
        # （实测：摘要变成了 "+ FullyQualifiedErrorId : NativeCommandError"）。
        # 所以逐条转成纯文本消息。
        $lines = foreach ($item in $out) {
            if ($item -is [System.Management.Automation.ErrorRecord]) {
                $item.Exception.Message
            } else {
                [string]$item
            }
        }

        [pscustomobject]@{
            Output   = (($lines -join "`n"))
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
    # e2e 必须在**独立的 test-runner 容器**里跑：
    #   gates 容器没有浏览器，且它也不在需要 Playwright 的语境里。
    #   先确保 test-runner 已起（profile: e2e），再在其中执行。
    Say "`n==> 准备 e2e 执行器" Cyan
    & docker compose -f $ComposeFile --profile e2e up -d test-runner 2>&1 |
        ForEach-Object { Say "    $_" DarkGray }

    $runnerUp = $false
    for ($i = 1; $i -le 30; $i++) {
        & docker compose -f $ComposeFile exec -T test-runner bash -lc 'true' 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $runnerUp = $true; break }
        Start-Sleep -Seconds 2
    }

    if (-not $runnerUp) {
        Say "[验收-e2e] 失败：test-runner 容器不可用" Red
        [void]$results.Add([pscustomobject]@{ Gate='验收-e2e'; ExitCode=1; Passed=$false; Summary='test-runner 容器不可用' })
    } else {
        Say "    test-runner 就绪 ✔" Green
        $marker = "[验收-e2e]"
        Say "`n$marker 在 test-runner 容器内执行 Playwright" Cyan

        # 为什么在 test-runner 而不是 gates：
        #   gates 容器没有浏览器，跑不了 Playwright；test-runner 才有。
        #
        # 为什么要把退出码用 `echo EXIT=$?` 单独打出来：
        #   PowerShell 经过管道（| ForEach-Object）后 $LASTEXITCODE 会被后续命令覆盖，
        #   直接读它会得到错误结论（实测：e2e 明明失败，却读到 0）。
        #   用 bash 显式回显退出码，再从输出里解析，才能拿到真实值。
        $e2eCmd = 'cd /tests && npx --no-install playwright test > /tmp/e2e.log 2>&1; echo "EXIT_CODE=$?"; tail -40 /tmp/e2e.log'
        $raw = & docker compose -f $ComposeFile exec -T test-runner bash -lc $e2eCmd 2>&1

        $e2eCode = 1
        foreach ($line in $raw) {
            if ($line -match '^EXIT_CODE=(\d+)\s*$') { $e2eCode = [int]$Matches[1] }
        }

        # 打印日志（去掉那行标记）
        foreach ($line in $raw) {
            if ($line -match '^EXIT_CODE=\d+\s*$') { continue }
            if ($line -match '✘|failed|Error:') { Say "    $line" Red }
            elseif ($line -match '✓|passed') { Say "    $line" DarkGray }
            else { Say "    $line" DarkGray }
        }

        $passed = ($e2eCode -eq 0)
        if ($passed) { Say "$marker 通过 (exit=0)" Green }
        else { Say "$marker 失败 (exit=$e2eCode)" Red }

        # 失败摘要要能直接看懂：从 Playwright 输出里抽出失败用例名与通过/失败计数
        $summary = '通过'
        if (-not $passed) {
            $failedTitles = @($raw | Where-Object { $_ -match '✘|✗' } | ForEach-Object { $_.Trim() })
            $counts = @($raw | Where-Object { $_ -match '\d+\s+(passed|failed)' } | ForEach-Object { $_.Trim() })
            $piece = @()
            if ($counts.Count -gt 0) { $piece += ($counts -join ' ') }
            if ($failedTitles.Count -gt 0) { $piece += ($failedTitles[0]) }
            $summary = if ($piece.Count -gt 0) { $piece -join ' | ' } else { "exit=$e2eCode" }
        }

        [void]$results.Add([pscustomobject]@{
            Gate='验收-e2e'
            ExitCode=$e2eCode
            Passed=$passed
            Summary=$summary
        })
    }
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
