<#
.SYNOPSIS
    从模板新建一个独立项目仓库

.DESCRIPTION
    把 templates/<Stack> 复制到目标路径，并初始化成独立 git 仓库。
    生成的是"项目实例"，不是框架的一部分——改了不影响框架。

    会做的事：
      1. 校验模板存在、目标目录为空
      2. 复制模板内容（不含框架自身的 docs/03、docs/04 等）
      3. 生成项目级 AGENTS.md（指向框架规范）
      4. git init + 首次提交
      5. 提示下一步

.EXAMPLE
    pwsh -File tools/new-project.ps1 -Name 我的项目 -Stack react-python -Path D:\ai\我的项目
    pwsh -File tools/new-project.ps1 -Name demo -Stack vue-go -Path D:\ai\demo -NoGit
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$Stack,
    [Parameter(Mandatory=$true)][string]$Path,
    [switch]$NoGit,
    [string]$FrameworkRoot
)

$ErrorActionPreference = 'Stop'

if (-not $FrameworkRoot) {
    $FrameworkRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

Say "===== 从模板新建项目 =====" White
Say "  项目名: $Name"
Say "  技术栈: $Stack"
Say "  目标路径: $Path"

# ---------- 1. 校验 ----------
Say "`n==> [1/4] 校验" Cyan

$tplDir = Join-Path $FrameworkRoot "templates\$Stack"
if (-not (Test-Path $tplDir)) {
    $available = (Get-ChildItem (Join-Path $FrameworkRoot 'templates') -Directory |
                  ForEach-Object { $_.Name }) -join ', '
    Say "!! 模板不存在: $Stack" Red
    Say "   可用模板: $available" Yellow
    exit 1
}
Say "    模板: $tplDir ✔" Green

if (Test-Path $Path) {
    $existing = Get-ChildItem $Path -Force -ErrorAction SilentlyContinue
    if ($existing) {
        Say "!! 目标目录非空: $Path" Red
        Say "   请换一个路径，或先手动清空。" Yellow
        exit 1
    }
}
Say "    目标目录可用 ✔" Green

# ---------- 2. 复制 ----------
Say "`n==> [2/6] 复制模板" Cyan

New-Item -ItemType Directory -Force -Path $Path | Out-Null
Copy-Item (Join-Path $tplDir '*') $Path -Recurse -Force
# 复制隐藏文件（.gitignore / .dockerignore / .gitattributes）
Get-ChildItem $tplDir -File -Force | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $Path $_.Name) -Force
}
Say "    已复制 ✔" Green

# ---------- 2b. 注入框架通用资产（CI / 隔离环境 / 脚手架）----------
Say "`n==> [3/6] 注入框架资产（CI / 隔离环境 / 脚手架）" Cyan

# GitHub 工程化：CI 门禁 + Issue/PR 模板
$ghSrc = Join-Path $FrameworkRoot '.github'
if (Test-Path $ghSrc) {
    Copy-Item $ghSrc $Path -Recurse -Force
    Say "    .github/（CI + Issue/PR 模板）" Green
}

# 隔离环境：一键安装入口 + 部署方法手册 + docker（推荐）+ local（无 Docker 降级）
foreach ($f in @('install.ps1', 'README.md')) {
    $src = Join-Path $FrameworkRoot "deploy\$f"
    if (Test-Path $src) {
        Copy-Item $src (Join-Path $Path "deploy\$f") -Force
        Say "    deploy/$f" Green
    }
}
foreach ($sub in @('docker', 'local')) {
    $src = Join-Path $FrameworkRoot "deploy\$sub"
    if (Test-Path $src) {
        $dst = Join-Path $Path "deploy\$sub"
        New-Item -ItemType Directory -Force -Path $dst | Out-Null
        Copy-Item (Join-Path $src '*') $dst -Recurse -Force
        Say "    deploy/$sub/" Green
    }
}

# 脚手架：AGENTS.md / .gitattributes / CHANGELOG / 项目约定
$today = (Get-Date).ToString('yyyy-MM-dd')
$scaffoldMap = @(
    @{ Src = 'AGENTS.md.template';            Dst = 'AGENTS.md' },
    @{ Src = 'gitattributes.template';        Dst = '.gitattributes' },
    @{ Src = 'CHANGELOG.md.template';         Dst = 'CHANGELOG.md' },
    @{ Src = 'docs-00-项目约定.md.template';   Dst = 'docs\00-项目约定.md' }
)
$hasScaffold = $false
foreach ($m in $scaffoldMap) {
    $src = Join-Path (Join-Path $FrameworkRoot 'scaffold') $m.Src
    if (-not (Test-Path $src)) { continue }
    $hasScaffold = $true
    $dst = Join-Path $Path $m.Dst
    $dstDir = Split-Path $dst -Parent
    if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Force -Path $dstDir | Out-Null }

    $content = [System.IO.File]::ReadAllText($src, [System.Text.Encoding]::UTF8)
    $content = $content.Replace('{{PROJECT_NAME}}', $Name).
                        Replace('{{STACK}}', $Stack).
                        Replace('{{DATE}}', $today)
    [System.IO.File]::WriteAllText($dst, $content, (New-Object System.Text.UTF8Encoding($false)))
    Say "    $($m.Dst)" Green
}
if (-not $hasScaffold) {
    Say "    !! scaffold/ 缺失，跳过项目级模板" Yellow
}

# ---------- 2c. 补齐目录结构 ----------
foreach ($d in @('docs\test', 'docs\review', 'tests\e2e', 'tests\performance')) {
    $full = Join-Path $Path $d
    if (-not (Test-Path $full)) { New-Item -ItemType Directory -Force -Path $full | Out-Null }
    $keeper = Join-Path $full '.gitkeep'
    if (-not (Test-Path $keeper)) { Set-Content -Path $keeper -Value '' -Encoding ASCII }
}
Say "    docs/test, docs/review, tests/e2e, tests/performance" Green

# 沙箱忽略项
$gitignore = Join-Path $Path '.gitignore'
$needLines = @('', '# 本机/容器闭环沙箱（deploy/* 生成）', 'sandbox/', '.local-env/')
if (Test-Path $gitignore) {
    $gi = [System.IO.File]::ReadAllText($gitignore, [System.Text.Encoding]::UTF8)
    if ($gi -notmatch 'sandbox/') {
        Add-Content -Path $gitignore -Value ($needLines -join "`n") -Encoding UTF8
        Say "    .gitignore 已追加 sandbox/" Green
    }
} else {
    Set-Content -Path $gitignore -Value ($needLines -join "`n") -Encoding UTF8
}

# ---------- 3. 兜底：确保 AGENTS.md 存在 ----------
# 唯一事实源是 scaffold/AGENTS.md.template；上面 §2b 已优先用它生成。
# 这里只处理"模板缺失但仍需一个可用 AGENTS.md"的极端情况：写最小指针，不重复维护铁律文案。
if (-not (Test-Path (Join-Path $Path 'AGENTS.md'))) {
    Say "`n==> 生成最小 AGENTS.md（scaffold/AGENTS.md.template 不可用时的兜底）" Cyan

    $projectAgents = @"
# AGENTS.md — 项目工作须知

> 本项目由 **AI-Dev-Framework** 生成（模板：``$Stack``）。
> 完整协作约定见 ``docs/00-项目约定.md``；门禁红线见项目根 ``scripts/`` 的五个入口。

## 必须遵守

1. 门禁必须由 ``scripts/*.sh`` 的**真实退出码**判定，禁止 ``|| true`` / ``; exit 0`` 式假通过。
2. 五入口 ``lint / build / test / health / e2e`` 不可增删。
3. 写代码的智能体不得验收自己的代码。
4. 只改自己职责的目录，绝不碰生产环境。

## 日常命令

``````powershell
powershell -File deploy/docker/up.ps1
powershell -File deploy/docker/verify.ps1
powershell -File deploy/docker/down.ps1
``````

``````bash
bash scripts/lint.sh && bash scripts/build.sh && bash scripts/test.sh
``````
"@
    Set-Content -Path (Join-Path $Path 'AGENTS.md') -Value $projectAgents -Encoding UTF8
    Say "    已生成最小 AGENTS.md ✔" Green
}

# ---------- 4. git init ----------
if (-not $NoGit) {
    Say "`n==> [4/6] 初始化 git 仓库" Cyan
    $git = 'C:\Program Files\Git\cmd\git.exe'
    if (-not (Test-Path $git)) { $git = 'git' }

    # git 会把 LF/CRLF 警告写到 stderr，PowerShell 会当成 NativeCommandError。
    # 所以这里临时放宽错误处理，靠 $LASTEXITCODE 判定真实结果，而不是靠异常。
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    Push-Location $Path
    try {
        & $git init -q > $null 2>&1
        $initOk = ($LASTEXITCODE -eq 0)
        # 主分支统一 main（git 2.28+）
        & $git symbolic-ref HEAD refs/heads/main > $null 2>&1
        # 让 .gitattributes 的 eol=lf 立即对整个工作区生效
        & $git add --renormalize . > $null 2>&1

        & $git add -A > $null 2>&1
        $addOk = ($LASTEXITCODE -eq 0)

        & $git -c user.name='AI-Dev-Framework' -c user.email='noreply@local' `
            commit -q -m "feat: 基于 $Stack 模板初始化项目 $Name" > $null 2>&1
        $commitOk = ($LASTEXITCODE -eq 0)

        if ($initOk -and $addOk -and $commitOk) {
            Say "    main 分支 + 首次提交 ✔" Green
        } elseif ($initOk -and $addOk) {
            Say "    git init 与 add 成功，但 commit 失败" Yellow
            Say "    （通常是没有配置 user.name / user.email，可手动 git commit）" Yellow
        } else {
            Say "    !! git 初始化失败，请检查 git 是否可用" Yellow
        }
    } finally {
        Pop-Location
        $ErrorActionPreference = $prevEAP
    }
} else {
    Say "`n==> [4/6] 跳过 git 初始化（-NoGit）" DarkGray
}

# ---------- 5. 自检 ----------
Say "`n==> [5/6] 结构自检" Cyan
$gateCount = @(Get-ChildItem (Join-Path $Path 'scripts') -Filter *.sh -ErrorAction SilentlyContinue).Count
$missing = @()
foreach ($g in @('lint.sh','build.sh','test.sh','health.sh','e2e.sh')) {
    if (-not (Test-Path (Join-Path $Path "scripts\$g"))) { $missing += $g }
}
if ($missing.Count -eq 0) {
    Say "    五入口门禁齐全（$gateCount 个脚本）✔" Green
} else {
    Say "    !! 缺少门禁脚本: $($missing -join ', ')" Yellow
}
foreach ($req in @('AGENTS.md','.gitattributes','docs\requirements.md','docs\pipeline-status.md')) {
    if (Test-Path (Join-Path $Path $req)) { Say "    $req ✔" Green }
    else { Say "    !! 缺少 $req" Yellow }
}

# ---------- 完成 ----------
Say "`n==> [6/6] 完成" Green
Say "`n===== 项目已创建 =====" Green
Say "  名称: $Name" Gray
Say "  位置: $Path" Gray
Say "  技术栈: $Stack（$gateCount 个门禁脚本）" Gray
Say ""
Say "下一步（按顺序）：" Cyan
Say "  1. 写需求：编辑 docs\requirements.md（验收标准必须可测）" Gray
Say "  2. 让 AI 开工：在项目目录里对它说" Gray
Say "     「按 AGENTS.md 和 docs\requirements.md 实现 FR-1」" White
Say "  3. 装依赖：cd frontend; npm install  /  cd backend; pip install -r requirements.txt" Gray
Say "  4. 跑门禁：bash scripts/lint.sh && bash scripts/build.sh && bash scripts/test.sh" Gray
Say "     有 Docker：powershell -File deploy\docker\up.ps1; powershell -File deploy\docker\verify.ps1" Gray
Say "     无 Docker：powershell -File deploy\local\setup.ps1; powershell -File deploy\local\up.ps1; powershell -File deploy\local\verify.ps1" Gray
Say ""
Say "  详细说明见项目内 docs\00-项目约定.md" Gray
