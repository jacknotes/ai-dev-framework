<#
.SYNOPSIS
    本机纯闭环测试环境 —— 执行五道门禁并汇总

.DESCRIPTION
    真实执行 scripts/*.sh（通过 Git Bash），收集真实退出码。
    退出码即整体结论：0 = 全部通过，非 0 = 有失败项。

.EXAMPLE
    pwsh -File deploy/local/verify.ps1
    pwsh -File deploy/local/verify.ps1 -SkipE2E
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [int]$BackendPort = 18080,
    [switch]$SkipE2E,
    [switch]$Json
)

$ErrorActionPreference = 'Continue'

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$SandboxDir = Join-Path $ProjectRoot 'sandbox'
$AppDir     = Join-Path $SandboxDir 'app'
$VenvDir    = Join-Path $SandboxDir '.venv'
$LogDir     = Join-Path $SandboxDir 'logs'

function Find-Bash {
    foreach ($c in @('C:\Program Files\Git\bin\bash.exe','C:\Program Files\Git\usr\bin\bash.exe')) {
        if (Test-Path $c) { return $c }
    }
    $cmd = Get-Command bash -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$Bash = Find-Bash
if (-not $Bash) { throw "未找到 bash（需要 Git Bash）。" }

if (-not (Test-Path $AppDir)) {
    throw "沙箱工程不存在，请先执行：pwsh -File deploy/local/up.ps1"
}

# ---------- 让 scripts/*.sh 能找到沙箱内的解释器 ----------
$nodeExe = Join-Path $env:USERPROFILE '.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe'
$nodeDir = Split-Path $nodeExe -Parent
$pnpmMjs = Join-Path $env:USERPROFILE '.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\pnpm\bin\pnpm.mjs'

# Git Bash 需要 POSIX 风格路径
function ToPosix([string]$p) {
    if (-not $p) { return $p }
    return ('/' + $p.Substring(0,1).ToLower() + ($p.Substring(2) -replace '\\','/'))
}

$envVars = @{
    PYTHON              = (ToPosix (Join-Path $VenvDir 'Scripts\python.exe'))
    PATH                = "$nodeDir;" + $env:PATH
    PORT                = "$BackendPort"
    HEALTH_PORT         = "$BackendPort"
    npm_config_verify_deps_before_run = 'false'
}

# npm 兼容层：本机没有 npm，但有 pnpm。scripts/*.sh 里调用的是 `npm`，
# 而 bash 只认无扩展名的可执行文件（不认 .cmd），所以同时提供两个：
#   npm     —— 供 Git Bash 使用（POSIX shell 脚本）
#   npm.cmd —— 供 PowerShell/cmd 使用（批处理）
$npmShimDir = Join-Path $SandboxDir '.shims'
if (-not (Test-Path $npmShimDir)) { New-Item -ItemType Directory -Force -Path $npmShimDir | Out-Null }

if (Test-Path $pnpmMjs) {
    $shimCmd = Join-Path $npmShimDir 'npm.cmd'
    $shimContent = "@echo off`r`n`"$nodeExe`" `"$pnpmMjs`" %*`r`n"
    Set-Content -Path $shimCmd -Value $shimContent -Encoding ASCII

    $shimPosix = Join-Path $npmShimDir 'npm'
    $nodePosix = ToPosix $nodeExe
    $pnpmPosix = ToPosix $pnpmMjs
    $posixContent = @"
#!/usr/bin/env bash
# npm 兼容包装：把 npm 调用转给 pnpm（本机无 npm）
exec "$nodePosix" "$pnpmPosix" "`$@"
"@
    Set-Content -Path $shimPosix -Value $posixContent -Encoding UTF8 -NoNewline
}

$envVars['PATH'] = "$npmShimDir;" + $envVars['PATH']

# ---------- 执行器 ----------
$results = New-Object System.Collections.ArrayList

function Invoke-Gate {
    param(
        [string]$Name,
        [string]$Script,
        [int]$TimeoutSec = 600
    )
    $scriptPath = Join-Path $AppDir $Script
    $marker = "[$Name]"

    if (-not (Test-Path $scriptPath)) {
        Write-Host "$marker 跳过：脚本不存在 ($Script)" -ForegroundColor Yellow
        [void]$results.Add([pscustomobject]@{ Gate=$Name; Script=$Script; ExitCode=127; Passed=$false; Summary='脚本不存在' })
        return
    }

    Write-Host "`n$marker 执行 $Script ..." -ForegroundColor Cyan

    $outFile = Join-Path $LogDir ("gate-" + ($Name -replace '[^\w]','_') + ".log")
    $errFile = Join-Path $LogDir ("gate-" + ($Name -replace '[^\w]','_') + ".err.log")

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Bash
    # 传给 bash 的脚本路径用 POSIX 形式；工作目录必须用 Windows 形式（.NET 不认 /d/...）
    $psi.Arguments = "`"$(ToPosix $scriptPath)`""
    $psi.WorkingDirectory = $AppDir
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    foreach ($k in $envVars.Keys) {
        if ($k -eq 'PATH') { $psi.EnvironmentVariables['PATH'] = $envVars[$k] }
        else { $psi.EnvironmentVariables[$k] = $envVars[$k] }
    }

    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
    } catch {
        Write-Host "$marker 启动失败：$($_.Exception.Message)" -ForegroundColor Red
        [void]$results.Add([pscustomobject]@{ Gate=$Name; Script=$Script; ExitCode=126; Passed=$false; Summary="启动失败: $($_.Exception.Message)" })
        return
    }

    # 异步读取，避免 ReadToEnd 与 WaitForExit 互相阻塞导致的假超时
    $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
    $stderrTask = $proc.StandardError.ReadToEndAsync()
    $finished = $proc.WaitForExit($TimeoutSec * 1000)

    if (-not $finished) {
        try { $proc.Kill($true) } catch { try { $proc.Kill() } catch {} }
        Write-Host "$marker 超时（${TimeoutSec}s）" -ForegroundColor Red
        [void]$results.Add([pscustomobject]@{ Gate=$Name; Script=$Script; ExitCode=124; Passed=$false; Summary="超时 ${TimeoutSec}s" })
        return
    }

    $stdout = if ($stdoutTask.Wait(5000)) { $stdoutTask.Result } else { '' }
    $stderr = if ($stderrTask.Wait(5000)) { $stderrTask.Result } else { '' }
    $code = $proc.ExitCode
    $proc.Dispose()

    Set-Content -Path $outFile -Value $stdout -Encoding UTF8
    Set-Content -Path $errFile -Value $stderr -Encoding UTF8

    $passed = ($code -eq 0)
    $summary = if ($passed) { '通过' } else {
        $line = ($stderr -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
        if ($line) { $line.Trim() } else { "exit=$code" }
    }

    # 打印末尾几行，便于当场看结论
    $tail = ($stdout -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 6)
    if ($tail) { $tail | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray } }
    if (-not $passed -and $stderr.Trim()) {
        ($stderr -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 8) |
            ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
    }

    if ($passed) { Write-Host "$marker 通过 (exit=0)" -ForegroundColor Green }
    else { Write-Host "$marker 失败 (exit=$code)" -ForegroundColor Red }

    [void]$results.Add([pscustomobject]@{
        Gate=$Name; Script=$Script; ExitCode=$code; Passed=$passed; Summary=$summary
    })
}

# ---------- 顺序执行五道门禁 ----------
Write-Host "===== 门禁执行开始 =====" -ForegroundColor White
Invoke-Gate -Name '编码-静态检查' -Script 'scripts/lint.sh'
Invoke-Gate -Name '编码-构建'     -Script 'scripts/build.sh'
Invoke-Gate -Name '编码-单元测试' -Script 'scripts/test.sh'

if ($SkipE2E) {
    Write-Host "`n[e2e] 按参数跳过" -ForegroundColor Yellow
} else {
    Invoke-Gate -Name '验收-e2e' -Script 'scripts/e2e.sh'
}

Invoke-Gate -Name '部署-健康检查' -Script 'scripts/health.sh'

# ---------- 汇总 ----------
Write-Host "`n===== 门禁汇总 =====" -ForegroundColor White
$results | Format-Table -AutoSize @(
    @{n='门禁'; e={$_.Gate}},
    @{n='脚本'; e={$_.Script}},
    @{n='退出码'; e={$_.ExitCode}},
    @{n='结论'; e={ if ($_.Passed) { '通过' } else { '失败' } }},
    @{n='摘要'; e={$_.Summary}}
) | Out-String | Write-Host

if ($Json) {
    $jsonOut = $results | ConvertTo-Json -Depth 5
    $jsonPath = Join-Path $LogDir 'gate-results.json'
    Set-Content -Path $jsonPath -Value $jsonOut -Encoding UTF8
    Write-Host "详细结果已写入: $jsonPath" -ForegroundColor Gray
}

$failed = @($results | Where-Object { -not $_.Passed })
if ($failed.Count -eq 0) {
    Write-Host "[verify] 全部通过 ✔" -ForegroundColor Green
    exit 0
} else {
    Write-Host "[verify] 有 $($failed.Count) 项失败：$(($failed | ForEach-Object { $_.Gate }) -join ', ')" -ForegroundColor Red
    exit 1
}
