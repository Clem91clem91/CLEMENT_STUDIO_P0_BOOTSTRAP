param(
    [string]$Owner = "Clem91clem91",
    [string]$Workspace = "C:\Users\Shadow\Documents\CLEMENT_STUDIO\04_TOOLS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ManifestPath = Join-Path $Root "config\wave_a_manifest.json"
$PythonCertifier = Join-Path $PSScriptRoot "certify_wave_a_shadow.py"
$Venv = Join-Path $Root ".venv-wave-a"

function Test-IgnorableGeneratedUntracked {
    param([Parameter(Mandatory=$true)][string]$StatusLine)

    # Only untracked generated Python artifacts are tolerated. Any tracked
    # modification remains blocking, even when its path resembles a cache.
    if (-not $StatusLine.StartsWith("?? ")) { return $false }

    $Path = $StatusLine.Substring(3).Replace("\", "/")
    if ($Path -match '(^|/)__pycache__/') { return $true }
    if ($Path -match '(^|/)\.pytest_cache/') { return $true }
    if ($Path -match '(^|/)[^/]+\.egg-info/') { return $true }
    if ($Path -match '\.py[co]$') { return $true }
    return $false
}

Write-Host "============================================================"
Write-Host "CLEMENT STUDIO - WAVE A SHADOW CERTIFICATION"
Write-Host "MODE=PINNED_FAIL_CLOSED"
Write-Host "============================================================"

foreach ($Command in @("git", "python")) {
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        throw "COMMAND_NOT_FOUND=$Command"
    }
    Write-Host "COMMAND=$Command STATUS=PASS"
}

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "WAVE_A_MANIFEST_NOT_FOUND=$ManifestPath"
}

$Manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Write-Host "PROGRAM=$($Manifest.program)"
Write-Host "MODULE_COUNT=$($Manifest.modules.Count)"

foreach ($Module in $Manifest.modules) {
    $RepoRoot = Join-Path $Workspace $Module.repository
    if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
        throw "MODULE_LOCAL_REPO_NOT_FOUND=$($Module.repository)"
    }

    $Dirty = @(& git -C $RepoRoot status --porcelain --untracked-files=all)
    if ($LASTEXITCODE -ne 0) { throw "GIT_STATUS_FAILED=$($Module.repository)" }

    $GeneratedUntracked = @(
        $Dirty | Where-Object {
            Test-IgnorableGeneratedUntracked -StatusLine ([string]$_)
        }
    )
    $BlockingDirty = @(
        $Dirty | Where-Object {
            -not (Test-IgnorableGeneratedUntracked -StatusLine ([string]$_))
        }
    )

    if ($GeneratedUntracked.Count -gt 0) {
        Write-Host "GENERATED_UNTRACKED_IGNORED=$($Module.repository) COUNT=$($GeneratedUntracked.Count)"
        $GeneratedUntracked | ForEach-Object { Write-Host "IGNORED_GENERATED=$_" }
    }

    if ($BlockingDirty.Count -gt 0) {
        Write-Host "DIRTY_REPO=$($Module.repository)"
        $BlockingDirty | ForEach-Object { Write-Host $_ }
        throw "MODULE_WORKTREE_NOT_CLEAN=$($Module.repository)"
    }

    Write-Host "MODULE_WORKTREE_PRECHECK=$($Module.repository) STATUS=PASS"

    & git -C $RepoRoot fetch origin --prune
    if ($LASTEXITCODE -ne 0) { throw "GIT_FETCH_FAILED=$($Module.repository)" }

    & git -C $RepoRoot switch $Module.branch
    if ($LASTEXITCODE -ne 0) { throw "GIT_SWITCH_FAILED=$($Module.repository)" }

    & git -C $RepoRoot merge --ff-only "origin/$($Module.branch)"
    if ($LASTEXITCODE -ne 0) { throw "GIT_FAST_FORWARD_FAILED=$($Module.repository)" }

    $Head = (& git -C $RepoRoot rev-parse HEAD).Trim()
    if ($Head -ne $Module.head) {
        throw "MODULE_HEAD_MISMATCH repo=$($Module.repository) expected=$($Module.head) actual=$Head"
    }
    Write-Host "MODULE_PIN=$($Module.name) HEAD=$Head STATUS=PASS"

    # After synchronization, the repository-specific .gitignore should absorb
    # generated Python artifacts. Unknown/tracked mutations still fail closed.
    $PostSyncDirty = @(& git -C $RepoRoot status --porcelain --untracked-files=all)
    if ($LASTEXITCODE -ne 0) { throw "GIT_POST_SYNC_STATUS_FAILED=$($Module.repository)" }
    $PostSyncBlocking = @(
        $PostSyncDirty | Where-Object {
            -not (Test-IgnorableGeneratedUntracked -StatusLine ([string]$_))
        }
    )
    if ($PostSyncBlocking.Count -gt 0) {
        Write-Host "POST_SYNC_DIRTY_REPO=$($Module.repository)"
        $PostSyncBlocking | ForEach-Object { Write-Host $_ }
        throw "MODULE_POST_SYNC_WORKTREE_NOT_CLEAN=$($Module.repository)"
    }
}

if (-not (Test-Path -LiteralPath $Venv -PathType Container)) {
    & python -m venv $Venv
    if ($LASTEXITCODE -ne 0) { throw "VENV_CREATE_FAILED" }
}

$Python = Join-Path $Venv "Scripts\python.exe"
if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) { throw "VENV_PYTHON_NOT_FOUND=$Python" }

& $Python -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw "PIP_UPGRADE_FAILED" }

foreach ($Module in $Manifest.modules) {
    $RepoRoot = Join-Path $Workspace $Module.repository
    & $Python -m pip install -e "$RepoRoot[dev]"
    if ($LASTEXITCODE -ne 0) { throw "MODULE_INSTALL_FAILED=$($Module.repository)" }
    & $Python -m pytest -q (Join-Path $RepoRoot "tests")
    if ($LASTEXITCODE -ne 0) { throw "MODULE_TEST_FAILED=$($Module.repository)" }
    Write-Host "MODULE_TEST=$($Module.name) STATUS=PASS"
}

$Output = & $Python $PythonCertifier 2>&1
$Exit = $LASTEXITCODE
$Output | ForEach-Object { Write-Host $_ }

if ($Exit -ne 0) {
    throw "WAVE_A_CERTIFIER_FAILED exit=$Exit"
}

$Text = ($Output | Out-String)
foreach ($Required in $Manifest.required_markers) {
    if ($Text -notmatch [regex]::Escape([string]$Required)) {
        throw "WAVE_A_REQUIRED_MARKER_MISSING=$Required"
    }
    Write-Host "FINAL_MARKER=$Required"
}

Write-Host "MERGE_EXECUTED=NO"
Write-Host "TAG_CREATED=NO"
Write-Host "RELEASE_CREATED=NO"
Write-Host "WAVE_A_CERTIFICATION_PROGRESS=100%"
Write-Host "NEXT=WAVE_A_ODYSSEUS_INTEGRATION"
