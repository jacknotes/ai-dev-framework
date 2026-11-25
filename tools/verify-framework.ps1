<#
.SYNOPSIS
    框架自检：验证所有模板与框架资产的完整性和正确性

.DESCRIPTION
    检查项（全部为"机器可判定"，不靠人眼看）：
      1. 每个模板必须齐全 5 个门禁脚本（lint/build/test/health/e2e）
      2. 所有 *.sh 必须能通过 bash -n 语法检查
      3. 所有 *.sh 必须是 LF 换行（CRLF 会让 bash 直接失效）
      4. 所有文本文件必须是合法 UTF-8
      5. 门禁脚本禁止出现吞码写法（|| true / ; exit 0）
      6. 框架关键资产存在（docs / prompts / pipeline / deploy / .gitattributes / AGENTS.md）
      7. 每个门禁脚本首行必须是 shebang

    退出码：0 = 全部通过，非 0 = 有失败项。

.PARAMETER Stack
    只检查指定技术栈（默认检查全部）

.PARAMETER SkipSyntax
    跳过 bash -n 语法检查（无 Git Bash 时用）

.EXAMPLE
    pwsh -File tools\verify-framework.ps1

.EXAMPLE
    pwsh -File tools\verify-framework.ps1 -Stack react-python
#>
[CmdletBinding()]
param(
    [string]$Stack,
    [switch]$SkipSyntax,
    [switch]$Json
)

$ErrorActionPreference = 'Continue'

$FrameworkRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$GateNames = @('lint.sh', 'build.sh', 'test.sh', 'health.sh', 'e2e.sh')
$results = New-Object System.Collections.ArrayList

function Add-Result {
    param([string]$Category, [string]$Item, [bool]$Passed, [string]$Detail = '')
    [void]$results.Add([pscustomobject]@{
        Category = $Category
        Item     = $Item
        Passed   = $Passed
        Detail   = $Detail
    })
}

function Find-Bash {
    foreach ($c in @('C:\Program Files\Git\bin\bash.exe', 'C:\Program Files\Git\usr\bin\bash.exe')) {
        if (Test-Path $c) { return $c }
    }
    $cmd = Get-Command bash -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -notmatch 'WindowsApps') { return $cmd.Source }
    return $null
}

function ToPosix([string]$p) {
    if (-not $p) { return $p }
    return ('/' + $p.Substring(0, 1).ToLower() + ($p.Substring(2) -replace '\\', '/'))
}

Write-Host "==> 框架根: $FrameworkRoot" -ForegroundColor Cyan

# ---------- 1. 框架关键资产 ----------
Write-Host "`n==> [1/6] 框架关键资产" -ForegroundColor Cyan
$assets = @(
    'README.md',
    'AGENTS.md',
    '.gitattributes',
    'docs\01-开发规范文档.md',
    'docs\02-复用与GitHub推送指南.md',
    'docs\03-AI全闭环落地方案.md',
    'docs\04-门禁与命令契约.md',
    'docs\00-快速开始.md',
    'pipeline\pipeline.workflow.js',
    'deploy\docker-compose.yml',
    'deploy\local\setup.ps1',
    'deploy\local\up.ps1',
    'deploy\local\verify.ps1',
    'deploy\local\down.ps1',
    '.github\workflows\ai-dev-pipeline.yml',
    'tools\new-project.ps1',
    'tools\verify-framework.ps1'
)
foreach ($a in $assets) {
    $full = Join-Path $FrameworkRoot $a
    $ok = Test-Path $full
    Add-Result -Category '资产' -Item $a -Passed $ok -Detail $(if ($ok) { '' } else { '缺失' })
}
$promptCount = @(Get-ChildItem (Join-Path $FrameworkRoot 'prompts') -Filter *.md -ErrorAction SilentlyContinue).Count
Add-Result -Category '资产' -Item 'prompts/' -Passed ($promptCount -ge 9) -Detail "$promptCount 个角色提示词（应 ≥ 9）"
$scaffoldCount = @(Get-ChildItem (Join-Path $FrameworkRoot 'scaffold') -File -ErrorAction SilentlyContinue).Count
Add-Result -Category '资产' -Item 'scaffold/' -Passed ($scaffoldCount -ge 4) -Detail "$scaffoldCount 个脚手架模板（应 ≥ 4）"

# ---------- 2. 确定要检查的模板 ----------
$tplRoot = Join-Path $FrameworkRoot 'templates'
if (-not (Test-Path $tplRoot)) { throw "未找到 templates/ 目录" }

if ($Stack) {
    $stacks = @(Get-ChildItem $tplRoot -Directory | Where-Object { $_.Name -eq $Stack })
    if ($stacks.Count -eq 0) { throw "未找到技术栈模板: $Stack" }
} else {
    $stacks = @(Get-ChildItem $tplRoot -Directory)
}

# ---------- 3. 五入口完整性 ----------
Write-Host "`n==> [2/6] 五入口门禁完整性" -ForegroundColor Cyan
foreach ($s in $stacks) {
    $scriptsDir = Join-Path $s.FullName 'scripts'
    if (-not (Test-Path $scriptsDir)) {
        Add-Result '契约' "$($s.Name)/scripts" $false '缺少 scripts/ 目录'
        continue
    }
    foreach ($g in $GateNames) {
        $p = Join-Path $scriptsDir $g
        $ok = Test-Path $p
        Add-Result '契约' "$($s.Name)/scripts/$g" $ok $(if ($ok) { '' } else { '门禁脚本缺失' })
    }
    # 不应有约定外的 .sh
    $extra = @(Get-ChildItem $scriptsDir -Filter *.sh | Where-Object { $GateNames -notcontains $_.Name })
    if ($extra.Count -gt 0) {
        Add-Result '契约' "$($s.Name)/scripts 额外脚本" $false ("约定外: " + (($extra | ForEach-Object Name) -join ', '))
    }
}

# ---------- 4. 换行符 ----------
Write-Host "`n==> [3/6] 换行符（.sh 必须 LF）" -ForegroundColor Cyan
$allSh = @()
foreach ($s in $stacks) {
    $allSh += @(Get-ChildItem (Join-Path $s.FullName 'scripts') -Filter *.sh -ErrorAction SilentlyContinue)
}
foreach ($f in $allSh) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $hasCR = $false
    for ($i = 0; $i -lt $bytes.Length - 1; $i++) {
        if ($bytes[$i] -eq 0x0D -and $bytes[$i + 1] -eq 0x0A) { $hasCR = $true; break }
    }
    $rel = $f.FullName.Substring($FrameworkRoot.Length + 1)
    Add-Result '换行符' $rel (-not $hasCR) $(if ($hasCR) { 'CRLF！bash 会报 $''\r'': command not found' } else { '' })
}

# 框架自带 .gitattributes 必须锁定 .sh
$gaPath = Join-Path $FrameworkRoot '.gitattributes'
if (Test-Path $gaPath) {
    $ga = Get-Content $gaPath -Raw
    $ok = ($ga -match '\*\.sh\s+text\s+eol=lf')
    Add-Result '换行符' '.gitattributes 锁定 *.sh eol=lf' $ok $(if ($ok) { '' } else { '缺少 *.sh 的 LF 锁定规则' })
}

# ---------- 5. UTF-8 合法性 ----------
Write-Host "`n==> [4/6] UTF-8 编码合法性" -ForegroundColor Cyan
$textExts = @('.sh', '.md', '.ps1', '.js', '.yml', '.yaml', '.json', '.py', '.go', '.java', '.cs', '.ts', '.tsx', '.vue', '.xml', '.jsp')
$scanDirs = @('templates', 'docs', 'prompts', 'pipeline', 'deploy', 'scaffold', 'tools', '.github')
$checked = 0
foreach ($d in $scanDirs) {
    $dirFull = Join-Path $FrameworkRoot $d
    if (-not (Test-Path $dirFull)) { continue }
    Get-ChildItem $dirFull -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $textExts -contains $_.Extension -and $_.FullName -notmatch 'node_modules' } |
        ForEach-Object {
            $checked++
            $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
            $enc = New-Object System.Text.UTF8Encoding($false, $true)
            $okText = $true
            try { $null = $enc.GetString($bytes) } catch { $okText = $false }
            if (-not $okText) {
                $rel = $_.FullName.Substring($FrameworkRoot.Length + 1)
                Add-Result '编码' $rel $false '非法 UTF-8 字节'
            }
        }
}
Add-Result '编码' "已扫描 $checked 个文本文件" $true

# ---------- 6. 吞码写法检查 ----------
Write-Host "`n==> [5/6] 门禁脚本吞码写法" -ForegroundColor Cyan
# docs/04 §2 硬性约束 4：禁止 cmd || true、cmd; exit 0 这类写法。
#
# 两种合法用法必须放行，否则会把正确代码判成缺陷：
#   a) 命令替换 $(... || true) —— 只为在 set -e 下捕获输出，后续显式判断结果
#   b) if/循环分支里的 exit 0 —— 正常成功路径
# 只拦截"把整条命令的失败变成脚本成功"的写法。
$swallowPatterns = @(
    ';\s*exit\s+0\s*$',     # cmd; exit 0
    '&&\s*exit\s+0\s*$',    # cmd && exit 0
    '^\s*\|\|\s*true'       # 裸 || true
)
$swallowFound = @()
foreach ($f in $allSh) {
    $rel = $f.FullName.Substring($FrameworkRoot.Length + 1)
    $lines = Get-Content $f.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $raw = $lines[$i]
        $stripped = ($raw -replace '#.*$', '').Trim()
        if (-not $stripped) { continue }

        # (a) 跳过命令替换内部：整行里 || true 出现在 $( ... ) 内
        $inSubst = $stripped -match '\$\([^)]*\|\|\s*true'

        foreach ($pat in $swallowPatterns) {
            if ($stripped -match $pat) {
                if ($inSubst) { continue }
                $swallowFound += "$rel L$($i+1): $($raw.Trim())"
                break
            }
        }
    }
}
if ($swallowFound.Count -gt 0) {
    Add-Result '吞码' '门禁脚本吞码' $false ($swallowFound -join ' | ')
} else {
    Add-Result '吞码' '无真吞码写法（命令替换内的 || true 已放行）' $true
}

# ---------- 7. shebang + bash -n 语法 ----------
Write-Host "`n==> [6/6] shebang 与语法检查" -ForegroundColor Cyan
foreach ($f in $allSh) {
    $rel = $f.FullName.Substring($FrameworkRoot.Length + 1)
    $first = Get-Content $f.FullName -TotalCount 1
    $ok = ($first -match '^#!/usr/bin/env bash')
    Add-Result '语法' "$rel shebang" $ok $(if ($ok) { '' } else { "首行不是 #!/usr/bin/env bash：$first" })
}

if ($SkipSyntax) {
    Write-Host "    按 -SkipSyntax 跳过 bash -n" -ForegroundColor Yellow
} else {
    $bash = Find-Bash
    if (-not $bash) {
        Write-Host "    !! 未找到 bash，跳过语法检查（用 -SkipSyntax 可显式跳过）" -ForegroundColor Yellow
        Add-Result '语法' 'bash -n' $false '未找到 Git Bash'
    } else {
        foreach ($f in $allSh) {
            $rel = $f.FullName.Substring($FrameworkRoot.Length + 1)
            $posix = ToPosix $f.FullName
            $out = & $bash -n $posix 2>&1
            $code = $LASTEXITCODE
            Add-Result '语法' $rel ($code -eq 0) $(if ($code -ne 0) { ($out | Out-String).Trim() } else { '' })
        }
    }
}

# ---------- 汇总 ----------
Write-Host "`n===== 自检汇总 =====" -ForegroundColor White
$failed = @($results | Where-Object { -not $_.Passed })

$byCat = $results | Group-Object Category
foreach ($g in $byCat) {
    $bad = @($g.Group | Where-Object { -not $_.Passed }).Count
    $color = if ($bad -eq 0) { 'Green' } else { 'Red' }
    Write-Host ("  {0,-8} {1,3} 项，失败 {2}" -f $g.Name, $g.Count, $bad) -ForegroundColor $color
}

if ($failed.Count -gt 0) {
    Write-Host "`n失败明细：" -ForegroundColor Red
    $failed | ForEach-Object {
        Write-Host ("  ✗ [{0}] {1}" -f $_.Category, $_.Item) -ForegroundColor Red
        if ($_.Detail) { Write-Host ("      {0}" -f $_.Detail) -ForegroundColor DarkYellow }
    }
}

if ($Json) {
    $jsonPath = Join-Path $FrameworkRoot 'sandbox\framework-verify.json'
    $jsonDir = Split-Path $jsonPath -Parent
    if (-not (Test-Path $jsonDir)) { New-Item -ItemType Directory -Force -Path $jsonDir | Out-Null }
    $results | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonPath -Encoding UTF8
    Write-Host "详细结果: $jsonPath" -ForegroundColor Gray
}

Write-Host ""
if ($failed.Count -eq 0) {
    Write-Host "[verify-framework] 全部通过 ✔  （$($results.Count) 项检查）" -ForegroundColor Green
    exit 0
} else {
    Write-Host "[verify-framework] 有 $($failed.Count) 项失败 ✗" -ForegroundColor Red
    exit 1
}
