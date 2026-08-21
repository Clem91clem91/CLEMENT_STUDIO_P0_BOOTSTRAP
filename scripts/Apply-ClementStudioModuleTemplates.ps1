param(
    [string]$Owner = "Clem91clem91",
    [string]$Workspace = "C:\Users\Shadow\Documents\CLEMENT_STUDIO\04_TOOLS",
    [string]$FeatureBranch = "feat/bootstrap-module-mvp",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$ScriptFile = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($ScriptFile)) { $ScriptFile = $MyInvocation.MyCommand.Path }
if ([string]::IsNullOrWhiteSpace($ScriptFile)) { throw "SCRIPT_PATH_UNRESOLVED" }
$BootstrapRoot = Split-Path -Path (Split-Path -Path $ScriptFile -Parent) -Parent
$ManifestPath = Join-Path $BootstrapRoot "config\module_repositories.json"
$TemplatesRoot = Join-Path $BootstrapRoot "templates\modules"

function Invoke-Git {
    param([string]$Path, [string[]]$Arguments, [string]$Failure)
    & git -C $Path @Arguments
    if ($LASTEXITCODE -ne 0) { throw $Failure }
}

function Assert-Clean {
    param([string]$Path, [string]$Repo)
    $Dirty = @(& git -C $Path status --porcelain)
    if ($LASTEXITCODE -ne 0) { throw "GIT_STATUS_FAILED=$Repo" }
    if ($Dirty.Count -gt 0) {
        Write-Host "DIRTY_FILES_BEGIN"
        $Dirty | ForEach-Object { Write-Host $_ }
        Write-Host "DIRTY_FILES_END"
        throw "WORKTREE_NOT_CLEAN=$Repo"
    }
}

function Copy-TemplateTree {
    param([string]$TemplatePath, [string]$LocalPath)
    Get-ChildItem -LiteralPath $TemplatePath -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $LocalPath -Recurse -Force
    }
}

function Stage-ChangedPaths {
    param([string]$LocalPath, [string]$Repo)
    $StatusLines = @(& git -C $LocalPath status --porcelain)
    if ($LASTEXITCODE -ne 0) { throw "GIT_STATUS_TEMPLATE_FAILED=$Repo" }
    if ($StatusLines.Count -eq 0) { throw "TEMPLATE_PRODUCED_NO_CHANGES=$Repo" }

    foreach ($Line in $StatusLines) {
        if ([string]::IsNullOrWhiteSpace($Line) -or $Line.Length -lt 4) { continue }
        $PathText = $Line.Substring(3).Trim()
        if ($PathText -match " -> ") { $PathText = ($PathText -split " -> ")[-1].Trim() }
        if ($PathText.StartsWith('"') -and $PathText.EndsWith('"')) {
            $PathText = $PathText.Substring(1, $PathText.Length - 2)
        }
        & git -C $LocalPath add -- $PathText
        if ($LASTEXITCODE -ne 0) { throw "STAGE_PATH_FAILED repo=$Repo path=$PathText" }
    }
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "COMMAND_NOT_FOUND=gh" }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "COMMAND_NOT_FOUND=git" }
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "MODULE_MANIFEST_NOT_FOUND=$ManifestPath" }

& gh auth status --hostname github.com
if ($LASTEXITCODE -ne 0) { throw "GITHUB_AUTH=FAIL" }

$Manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$Applied = 0
$NoTemplate = 0
$ExistingBranch = 0

Write-Host "============================================================"
Write-Host "CLEMENT STUDIO - APPLY MODULE MVP TEMPLATES"
Write-Host "============================================================"
Write-Host "FEATURE_BRANCH=$FeatureBranch"
Write-Host "DRY_RUN=$($DryRun.IsPresent)"

foreach ($Module in @($Manifest.modules | Sort-Object order)) {
    $Repo = [string]$Module.repository
    $FullRepo = "$Owner/$Repo"
    $TemplatePath = Join-Path $TemplatesRoot ([string]$Module.key)
    $LocalPath = Join-Path $Workspace $Repo

    Write-Host "------------------------------------------------------------"
    Write-Host "REPOSITORY=$FullRepo"

    if (-not (Test-Path -LiteralPath $TemplatePath -PathType Container)) {
        $NoTemplate++
        Write-Host "MVP_TEMPLATE=NOT_YET_IMPLEMENTED"
        continue
    }

    & gh repo view $FullRepo --json name,visibility *> $null
    if ($LASTEXITCODE -ne 0) { throw "REMOTE_REPOSITORY_NOT_FOUND=$FullRepo" }

    if (-not (Test-Path -LiteralPath $LocalPath -PathType Container)) {
        if ($DryRun) {
            Write-Host "LOCAL_REPO=WOULD_CLONE"
            continue
        }
        & gh repo clone $FullRepo $LocalPath
        if ($LASTEXITCODE -ne 0) { throw "CLONE_FAILED=$FullRepo" }
    }

    Assert-Clean -Path $LocalPath -Repo $Repo
    Invoke-Git -Path $LocalPath -Arguments @("fetch", "origin", "--prune") -Failure "FETCH_FAILED=$Repo"
    Invoke-Git -Path $LocalPath -Arguments @("switch", "develop") -Failure "SWITCH_DEVELOP_FAILED=$Repo"
    Invoke-Git -Path $LocalPath -Arguments @("merge", "--ff-only", "origin/develop") -Failure "DEVELOP_FAST_FORWARD_FAILED=$Repo"
    Assert-Clean -Path $LocalPath -Repo $Repo

    & git -C $LocalPath rev-parse --verify "origin/$FeatureBranch" *> $null
    if ($LASTEXITCODE -eq 0) {
        $ExistingBranch++
        Write-Host "FEATURE_BRANCH_STATUS=EXISTS_SKIP"
        continue
    }

    if ($DryRun) {
        Write-Host "MVP_TEMPLATE=WOULD_APPLY"
        continue
    }

    Invoke-Git -Path $LocalPath -Arguments @("switch", "-c", $FeatureBranch, "origin/develop") -Failure "FEATURE_BRANCH_CREATE_FAILED=$Repo"
    Copy-TemplateTree -TemplatePath $TemplatePath -LocalPath $LocalPath
    Stage-ChangedPaths -LocalPath $LocalPath -Repo $Repo

    $Changed = @(& git -C $LocalPath diff --cached --name-only)
    if ($Changed.Count -eq 0) { throw "TEMPLATE_PRODUCED_NO_STAGED_CHANGES=$Repo" }

    Invoke-Git -Path $LocalPath -Arguments @("commit", "-m", "feat: implement initial module MVP") -Failure "COMMIT_FAILED=$Repo"
    Invoke-Git -Path $LocalPath -Arguments @("push", "-u", "origin", $FeatureBranch) -Failure "PUSH_FAILED=$Repo"

    $PrBody = @"
## Initial module MVP

Repository: `$Repo`
Phase: `$($Module.phase)`

Implements the first deterministic/testable module contract from the CLEMENT STUDIO modular roadmap.

### Governance
- Draft PR only.
- No merge/tag/release authorized.
- CI and Shadow integration must pass before merge consideration.
"@

    & gh pr create --repo $FullRepo --draft --base develop --head $FeatureBranch --title "feat: initial $($Module.key) MVP" --body $PrBody
    if ($LASTEXITCODE -ne 0) { throw "DRAFT_PR_CREATE_FAILED=$Repo" }
    $Applied++
    Write-Host "MVP_TEMPLATE=PASS"
    Write-Host "DRAFT_PR=PASS"
}

Write-Host "============================================================"
Write-Host "MVP_TEMPLATES_APPLIED=$Applied"
Write-Host "NO_TEMPLATE_YET=$NoTemplate"
Write-Host "EXISTING_FEATURE_BRANCH_SKIPPED=$ExistingBranch"
Write-Host "MERGE_EXECUTED=NO"
Write-Host "TAG_CREATED=NO"
Write-Host "RELEASE_CREATED=NO"
Write-Host "============================================================"
