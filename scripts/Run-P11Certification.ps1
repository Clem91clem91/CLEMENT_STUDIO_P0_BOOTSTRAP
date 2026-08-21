param(
    [string]$OrchestratorRoot = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$ScriptFile = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($ScriptFile)) {
    $ScriptFile = $MyInvocation.MyCommand.Path
}
if ([string]::IsNullOrWhiteSpace($ScriptFile)) {
    throw "P1_1_BOOTSTRAP_SCRIPT_PATH_UNRESOLVED"
}

$ScriptDirectory = Split-Path -Path $ScriptFile -Parent
$BootstrapRoot = Split-Path -Path $ScriptDirectory -Parent
$ConfigPath = Join-Path $BootstrapRoot "config\p1_1_manifest.json"
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "P1_1_MANIFEST_NOT_FOUND=$ConfigPath"
}

$Manifest = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$ExpectedBranch = [string]$Manifest.orchestrator.branch
$ExpectedHead = [string]$Manifest.orchestrator.head

if ([string]::IsNullOrWhiteSpace($OrchestratorRoot)) {
    $ToolsRoot = Split-Path -Path $BootstrapRoot -Parent
    $OrchestratorRoot = Join-Path $ToolsRoot "CLEMENT_STUDIO_ORCHESTRATOR"
}

Write-Host "============================================================"
Write-Host "CLEMENT STUDIO - P1.1 BOOTSTRAP CERTIFICATION"
Write-Host "MODE=PINNED_SHADOW_FAIL_CLOSED"
Write-Host "============================================================"
Write-Host "MANIFEST=$ConfigPath"
Write-Host "ORCHESTRATOR_ROOT=$OrchestratorRoot"
Write-Host "EXPECTED_BRANCH=$ExpectedBranch"
Write-Host "EXPECTED_HEAD=$ExpectedHead"

if (-not (Test-Path -LiteralPath $OrchestratorRoot -PathType Container)) {
    throw "P1_1_ORCHESTRATOR_ROOT_NOT_FOUND=$OrchestratorRoot"
}

Push-Location $OrchestratorRoot
try {
    $Branch = (& git branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0) { throw "P1_1_GIT_BRANCH_FAILED" }
    $Head = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw "P1_1_GIT_HEAD_FAILED" }
    $Dirty = @(& git status --porcelain)
    if ($LASTEXITCODE -ne 0) { throw "P1_1_GIT_STATUS_FAILED" }

    Write-Host "ORCHESTRATOR_BRANCH=$Branch"
    Write-Host "ORCHESTRATOR_HEAD=$Head"
    Write-Host "ORCHESTRATOR_DIRTY_COUNT=$($Dirty.Count)"

    if ($Branch -ne $ExpectedBranch) {
        throw "P1_1_PIN_BRANCH_MISMATCH expected=$ExpectedBranch actual=$Branch"
    }
    if ($Head -ne $ExpectedHead) {
        throw "P1_1_PIN_HEAD_MISMATCH expected=$ExpectedHead actual=$Head"
    }
    if ($Dirty.Count -gt 0) {
        $Dirty | ForEach-Object { Write-Host $_ }
        throw "P1_1_ORCHESTRATOR_WORKTREE_NOT_CLEAN"
    }

    $Certifier = Join-Path $OrchestratorRoot "scripts\certify_p1_1_shadow.ps1"
    if (-not (Test-Path -LiteralPath $Certifier -PathType Leaf)) {
        throw "P1_1_SHADOW_CERTIFIER_NOT_FOUND=$Certifier"
    }

    $Output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Certifier 2>&1)
    $ExitCode = $LASTEXITCODE
    $Output | ForEach-Object { Write-Host $_ }

    if ($ExitCode -ne 0) {
        throw "P1_1_SHADOW_CERTIFIER_FAILED exit=$ExitCode"
    }

    $Text = $Output -join "`n"
    foreach ($Marker in @($Manifest.required_markers)) {
        if ($Text -notmatch [regex]::Escape([string]$Marker)) {
            throw "P1_1_REQUIRED_MARKER_MISSING=$Marker"
        }
    }

    foreach ($Marker in @(
        "MERGE_EXECUTED=NO",
        "TAG_CREATED=NO",
        "RELEASE_CREATED=NO"
    )) {
        if ($Text -notmatch [regex]::Escape($Marker)) {
            throw "P1_1_SAFETY_MARKER_MISSING=$Marker"
        }
    }
}
finally {
    Pop-Location
}

Write-Host "============================================================"
Write-Host "P1_1_01_RAW_EVIDENCE=PASS"
Write-Host "P1_1_02_PROVENANCE=PASS"
Write-Host "P1_1_03_CONSISTENCY=PASS"
Write-Host "P1_1_04_FAIL_CLOSED_VERIFIER=PASS"
Write-Host "P1_1_SHADOW_REAL=PASS"
Write-Host "P1_1_GLOBAL=PASS"
Write-Host "MERGE_EXECUTED=NO"
Write-Host "TAG_CREATED=NO"
Write-Host "RELEASE_CREATED=NO"
Write-Host "NEXT=P1_1_MERGE_VALIDATION"
Write-Host "============================================================"
