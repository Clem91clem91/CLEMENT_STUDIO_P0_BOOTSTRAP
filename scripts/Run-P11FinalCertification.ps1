param(
    [string]$OrchestratorRoot = "",
    [string]$Owner = "Clem91clem91"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$ScriptFile = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($ScriptFile)) {
    $ScriptFile = $MyInvocation.MyCommand.Path
}
if ([string]::IsNullOrWhiteSpace($ScriptFile)) {
    throw "P1_1_FINAL_SCRIPT_PATH_UNRESOLVED"
}

$ScriptDirectory = Split-Path -Path $ScriptFile -Parent
$BootstrapRoot = Split-Path -Path $ScriptDirectory -Parent
$ToolsRoot = Split-Path -Path $BootstrapRoot -Parent
if ([string]::IsNullOrWhiteSpace($OrchestratorRoot)) {
    $OrchestratorRoot = Join-Path $ToolsRoot "CLEMENT_STUDIO_ORCHESTRATOR"
}

$OrchestratorRepo = "CLEMENT_STUDIO_ORCHESTRATOR"
$BootstrapRepo = "CLEMENT_STUDIO_P0_BOOTSTRAP"
$OrchestratorBranch = "feat/p1-1-evidence-contract"
$BootstrapBranch = "feat/p1-1-bootstrap"
$OrchestratorHead = "80ef5bd02c232b17cb04627a8c26430956e33d6c"
$BootstrapHead = "__SELF_HEAD__"
$OrchestratorPrNumber = 4
$BootstrapPrNumber = 5
$RequiredCheck = "governance-gate"

function Assert-Command {
    param([Parameter(Mandatory=$true)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "COMMAND_NOT_FOUND=$Name"
    }
    Write-Host "COMMAND=$Name STATUS=PASS"
}

function Invoke-GitText {
    param(
        [Parameter(Mandatory=$true)][string]$RepoPath,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [Parameter(Mandatory=$true)][string]$FailureMarker
    )
    $Text = (& git -C $RepoPath @Arguments 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMarker output=$Text"
    }
    return $Text
}

function Sync-PinnedRepo {
    param(
        [Parameter(Mandatory=$true)][string]$Repo,
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Branch,
        [Parameter(Mandatory=$true)][string]$ExpectedHead
    )

    Write-Host "------------------------------------------------------------"
    Write-Host "SYNC_REPOSITORY=$Owner/$Repo"
    Write-Host "BRANCH=$Branch"
    Write-Host "EXPECTED_HEAD=$ExpectedHead"

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        & git clone "https://github.com/$Owner/$Repo.git" $Path
        if ($LASTEXITCODE -ne 0) { throw "GIT_CLONE_FAILED=$Repo" }
    }

    $DirtyBefore = Invoke-GitText -RepoPath $Path -Arguments @("status","--porcelain") -FailureMarker "GIT_STATUS_FAILED=$Repo"
    if (-not [string]::IsNullOrWhiteSpace($DirtyBefore)) {
        Write-Host "DIRTY_FILES_BEGIN"
        Write-Host $DirtyBefore
        Write-Host "DIRTY_FILES_END"
        throw "WORKTREE_NOT_CLEAN=$Repo"
    }
    Write-Host "WORKTREE_BEFORE=CLEAN"

    & git -C $Path fetch origin --prune
    if ($LASTEXITCODE -ne 0) { throw "GIT_FETCH_FAILED=$Repo" }

    & git -C $Path rev-parse --verify "origin/$Branch" *> $null
    if ($LASTEXITCODE -ne 0) { throw "REMOTE_BRANCH_NOT_FOUND repo=$Repo branch=$Branch" }

    & git -C $Path show-ref --verify --quiet "refs/heads/$Branch"
    if ($LASTEXITCODE -eq 0) {
        & git -C $Path switch $Branch
    }
    else {
        & git -C $Path switch --track -c $Branch "origin/$Branch"
    }
    if ($LASTEXITCODE -ne 0) { throw "GIT_SWITCH_FAILED=$Repo" }

    & git -C $Path merge --ff-only "origin/$Branch"
    if ($LASTEXITCODE -ne 0) { throw "GIT_FF_ONLY_FAILED=$Repo" }

    $LocalHead = Invoke-GitText -RepoPath $Path -Arguments @("rev-parse","HEAD") -FailureMarker "LOCAL_HEAD_FAILED=$Repo"
    $RemoteHead = Invoke-GitText -RepoPath $Path -Arguments @("rev-parse","origin/$Branch") -FailureMarker "REMOTE_HEAD_FAILED=$Repo"
    Write-Host "LOCAL_HEAD=$LocalHead"
    Write-Host "REMOTE_HEAD=$RemoteHead"

    if ($LocalHead -ne $ExpectedHead) { throw "LOCAL_HEAD_MISMATCH repo=$Repo expected=$ExpectedHead actual=$LocalHead" }
    if ($RemoteHead -ne $ExpectedHead) { throw "REMOTE_HEAD_MISMATCH repo=$Repo expected=$ExpectedHead actual=$RemoteHead" }

    $DirtyAfter = Invoke-GitText -RepoPath $Path -Arguments @("status","--porcelain") -FailureMarker "GIT_STATUS_AFTER_FAILED=$Repo"
    if (-not [string]::IsNullOrWhiteSpace($DirtyAfter)) { throw "WORKTREE_DIRTY_AFTER_SYNC=$Repo" }
    Write-Host "PINNED_HEAD=PASS"
    Write-Host "WORKTREE_AFTER_SYNC=CLEAN"
}

function Get-RemoteCount {
    param(
        [Parameter(Mandatory=$true)][string]$FullRepo,
        [Parameter(Mandatory=$true)][ValidateSet("tags","releases")][string]$Kind
    )
    if ($Kind -eq "tags") {
        $Endpoint = "repos/$FullRepo/tags?per_page=100"
        $Jq = ".[].name"
    }
    else {
        $Endpoint = "repos/$FullRepo/releases?per_page=100"
        $Jq = ".[].id"
    }
    $Items = @(& gh api --paginate $Endpoint --jq $Jq 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "REMOTE_COUNT_FAILED repo=$FullRepo kind=$Kind" }
    return @($Items | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count
}

function Get-P11Snapshot {
    param(
        [Parameter(Mandatory=$true)][string]$Repo,
        [Parameter(Mandatory=$true)][int]$PrNumber,
        [Parameter(Mandatory=$true)][string]$ExpectedHead
    )

    $FullRepo = "$Owner/$Repo"
    $DevelopHead = (& gh api "repos/$FullRepo/branches/develop" --jq ".commit.sha").Trim()
    if ($LASTEXITCODE -ne 0) { throw "DEVELOP_HEAD_QUERY_FAILED=$FullRepo" }

    $PrRaw = @(& gh pr view $PrNumber --repo $FullRepo --json state,isDraft,headRefOid,headRefName,baseRefName,mergedAt,mergeable 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "PR_QUERY_FAILED=$FullRepo#$PrNumber" }

    # PowerShell variables are case-insensitive. Keep $PrNumber and $PrInfo distinct.
    $PrInfo = (($PrRaw | Out-String).Trim()) | ConvertFrom-Json

    if ([string]$PrInfo.state -ne "OPEN") { throw "PR_NOT_OPEN=$FullRepo#$PrNumber" }
    if (-not [bool]$PrInfo.isDraft) { throw "PR_NOT_DRAFT=$FullRepo#$PrNumber" }
    if ([string]$PrInfo.baseRefName -ne "develop") { throw "PR_BASE_NOT_DEVELOP=$FullRepo#$PrNumber" }
    if ([string]$PrInfo.headRefOid -ne $ExpectedHead) { throw "PR_HEAD_MISMATCH repo=$FullRepo expected=$ExpectedHead actual=$($PrInfo.headRefOid)" }
    if ($null -ne $PrInfo.mergedAt) { throw "PR_ALREADY_MERGED=$FullRepo#$PrNumber" }

    $Tags = Get-RemoteCount -FullRepo $FullRepo -Kind "tags"
    $Releases = Get-RemoteCount -FullRepo $FullRepo -Kind "releases"

    Write-Host "SNAPSHOT_REPOSITORY=$FullRepo"
    Write-Host "DEVELOP_HEAD=$DevelopHead"
    Write-Host "PR=$PrNumber"
    Write-Host "PR_HEAD=$($PrInfo.headRefOid)"
    Write-Host "PR_DRAFT=$($PrInfo.isDraft)"
    Write-Host "PR_MERGEABLE=$($PrInfo.mergeable)"
    Write-Host "TAGS=$Tags"
    Write-Host "RELEASES=$Releases"

    return [pscustomobject]@{
        DevelopHead = $DevelopHead
        PrHead = [string]$PrInfo.headRefOid
        Tags = $Tags
        Releases = $Releases
    }
}

function Assert-GovernanceGate {
    param(
        [Parameter(Mandatory=$true)][string]$FullRepo,
        [Parameter(Mandatory=$true)][string]$Sha
    )
    $Raw = @(& gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2026-03-10" "repos/$FullRepo/commits/$Sha/check-runs" 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "CHECK_RUN_QUERY_FAILED=$FullRepo" }
    $Checks = (($Raw | Out-String).Trim()) | ConvertFrom-Json
    $Gate = @($Checks.check_runs | Where-Object { [string]$_.name -eq $RequiredCheck } | Sort-Object id -Descending | Select-Object -First 1)
    if ($Gate.Count -eq 0) { throw "GOVERNANCE_GATE_NOT_FOUND=$FullRepo" }
    Write-Host "CI_CHECK_REPOSITORY=$FullRepo"
    Write-Host "CI_CHECK_HEAD=$Sha"
    Write-Host "GOVERNANCE_STATUS=$($Gate[0].status)"
    Write-Host "GOVERNANCE_CONCLUSION=$($Gate[0].conclusion)"
    if ([string]$Gate[0].status -ne "completed") { throw "GOVERNANCE_GATE_NOT_COMPLETED=$FullRepo" }
    if ([string]$Gate[0].conclusion -ne "success") { throw "GOVERNANCE_GATE_FAILED=$FullRepo" }
    Write-Host "GOVERNANCE_GATE=PASS"
}

function Assert-LocalFinal {
    param(
        [Parameter(Mandatory=$true)][string]$Repo,
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$ExpectedBranch,
        [Parameter(Mandatory=$true)][string]$ExpectedHead
    )
    $Branch = Invoke-GitText -RepoPath $Path -Arguments @("branch","--show-current") -FailureMarker "FINAL_BRANCH_READ_FAILED=$Repo"
    $Head = Invoke-GitText -RepoPath $Path -Arguments @("rev-parse","HEAD") -FailureMarker "FINAL_HEAD_READ_FAILED=$Repo"
    $Dirty = Invoke-GitText -RepoPath $Path -Arguments @("status","--porcelain") -FailureMarker "FINAL_STATUS_FAILED=$Repo"
    if ($Branch -ne $ExpectedBranch) { throw "FINAL_BRANCH_CHANGED repo=$Repo branch=$Branch" }
    if ($Head -ne $ExpectedHead) { throw "FINAL_HEAD_CHANGED repo=$Repo head=$Head" }
    if (-not [string]::IsNullOrWhiteSpace($Dirty)) { throw "FINAL_WORKTREE_DIRTY=$Repo" }
    Write-Host "FINAL_LOCAL repo=$Repo BRANCH=PASS HEAD=PASS WORKTREE=CLEAN"
}

Write-Host "============================================================"
Write-Host "CLEMENT STUDIO - P1.1 FINAL SHADOW CERTIFICATION V2"
Write-Host "MODE=VERSIONED_FAIL_CLOSED"
Write-Host "============================================================"

Assert-Command "git"
Assert-Command "gh"
Assert-Command "python"
Assert-Command "powershell.exe"

& gh auth status --hostname github.com
if ($LASTEXITCODE -ne 0) { throw "GITHUB_AUTH=FAIL" }
Write-Host "GITHUB_AUTH=PASS"

# Determine the exact HEAD of this Bootstrap script after checkout.
$BootstrapHead = Invoke-GitText -RepoPath $BootstrapRoot -Arguments @("rev-parse","HEAD") -FailureMarker "BOOTSTRAP_HEAD_READ_FAILED"
$BootstrapBranchActual = Invoke-GitText -RepoPath $BootstrapRoot -Arguments @("branch","--show-current") -FailureMarker "BOOTSTRAP_BRANCH_READ_FAILED"
if ($BootstrapBranchActual -ne $BootstrapBranch) { throw "BOOTSTRAP_BRANCH_MISMATCH expected=$BootstrapBranch actual=$BootstrapBranchActual" }
Write-Host "BOOTSTRAP_CERTIFIER_HEAD=$BootstrapHead"

Write-Host "============================================================"
Write-Host "PHASE=PRE_CERT_SNAPSHOT"
Write-Host "============================================================"
$OrchestratorBefore = Get-P11Snapshot -Repo $OrchestratorRepo -PrNumber $OrchestratorPrNumber -ExpectedHead $OrchestratorHead
$BootstrapBefore = Get-P11Snapshot -Repo $BootstrapRepo -PrNumber $BootstrapPrNumber -ExpectedHead $BootstrapHead

Write-Host "============================================================"
Write-Host "PHASE=PINNED_LOCAL_SYNC"
Write-Host "============================================================"
Sync-PinnedRepo -Repo $OrchestratorRepo -Path $OrchestratorRoot -Branch $OrchestratorBranch -ExpectedHead $OrchestratorHead
# Do not switch/update Bootstrap while executing this script; validate the already-pinned checkout instead.
Assert-LocalFinal -Repo $BootstrapRepo -Path $BootstrapRoot -ExpectedBranch $BootstrapBranch -ExpectedHead $BootstrapHead

Write-Host "============================================================"
Write-Host "PHASE=P1_1_MANIFEST"
Write-Host "============================================================"
$ManifestPath = Join-Path $BootstrapRoot "config\p1_1_manifest.json"
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "P1_1_MANIFEST_NOT_FOUND=$ManifestPath" }
$Manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$Manifest.orchestrator.repository -ne "$Owner/$OrchestratorRepo") { throw "P1_1_MANIFEST_REPO_MISMATCH" }
if ([string]$Manifest.orchestrator.branch -ne $OrchestratorBranch) { throw "P1_1_MANIFEST_BRANCH_MISMATCH" }
if ([string]$Manifest.orchestrator.head -ne $OrchestratorHead) { throw "P1_1_MANIFEST_HEAD_MISMATCH" }
Write-Host "P1_1_MANIFEST=PASS"

Write-Host "============================================================"
Write-Host "PHASE=GITHUB_CI"
Write-Host "============================================================"
Assert-GovernanceGate -FullRepo "$Owner/$OrchestratorRepo" -Sha $OrchestratorHead
Assert-GovernanceGate -FullRepo "$Owner/$BootstrapRepo" -Sha $BootstrapHead
Write-Host "ALL_GOVERNANCE_GATES=PASS"

Write-Host "============================================================"
Write-Host "PHASE=P1_1_SHADOW_REAL"
Write-Host "============================================================"
$Wrapper = Join-Path $BootstrapRoot "scripts\Run-P11Certification.ps1"
if (-not (Test-Path -LiteralPath $Wrapper -PathType Leaf)) { throw "P1_1_BOOTSTRAP_WRAPPER_NOT_FOUND=$Wrapper" }
$Output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Wrapper -OrchestratorRoot $OrchestratorRoot 2>&1)
$ExitCode = $LASTEXITCODE
Write-Host "============== P1.1 OUTPUT BEGIN =============="
$Output | ForEach-Object { Write-Host $_ }
Write-Host "=============== P1.1 OUTPUT END ==============="
if ($ExitCode -ne 0) { throw "P1_1_CERTIFICATION_FAILED exit=$ExitCode" }

$Text = $Output -join "`n"
$Markers = @(
    "P1_REAL_E2E=PASS",
    "P1_1_01_RAW_EVIDENCE=PASS",
    "P1_1_02_PROVENANCE=PASS",
    "P1_1_03_CONSISTENCY=PASS",
    "P1_1_04_FAIL_CLOSED_VERIFIER=PASS",
    "FABRICATED_EVIDENCE_BLOCKED=PASS",
    "NO_EVIDENCE_NO_PASS=PASS",
    "P1_1_SHADOW_REAL=PASS",
    "P1_1_GLOBAL=PASS",
    "MERGE_EXECUTED=NO",
    "TAG_CREATED=NO",
    "RELEASE_CREATED=NO"
)
foreach ($Marker in $Markers) {
    if ($Text -notmatch [regex]::Escape($Marker)) { throw "P1_1_MARKER_MISSING=$Marker" }
    Write-Host "FINAL_MARKER=$Marker"
}

Write-Host "============================================================"
Write-Host "PHASE=LOCAL_IMMUTABILITY"
Write-Host "============================================================"
Assert-LocalFinal -Repo $OrchestratorRepo -Path $OrchestratorRoot -ExpectedBranch $OrchestratorBranch -ExpectedHead $OrchestratorHead
Assert-LocalFinal -Repo $BootstrapRepo -Path $BootstrapRoot -ExpectedBranch $BootstrapBranch -ExpectedHead $BootstrapHead

Write-Host "============================================================"
Write-Host "PHASE=REMOTE_IMMUTABILITY"
Write-Host "============================================================"
$OrchestratorAfter = Get-P11Snapshot -Repo $OrchestratorRepo -PrNumber $OrchestratorPrNumber -ExpectedHead $OrchestratorHead
$BootstrapAfter = Get-P11Snapshot -Repo $BootstrapRepo -PrNumber $BootstrapPrNumber -ExpectedHead $BootstrapHead
foreach ($Pair in @(
    @{ Name="ORCHESTRATOR"; Before=$OrchestratorBefore; After=$OrchestratorAfter },
    @{ Name="BOOTSTRAP"; Before=$BootstrapBefore; After=$BootstrapAfter }
)) {
    if ($Pair.Before.DevelopHead -ne $Pair.After.DevelopHead) { throw "DEVELOP_CHANGED_DURING_CERT=$($Pair.Name)" }
    if ($Pair.Before.PrHead -ne $Pair.After.PrHead) { throw "PR_HEAD_CHANGED_DURING_CERT=$($Pair.Name)" }
    if ($Pair.Before.Tags -ne $Pair.After.Tags) { throw "TAG_COUNT_CHANGED_DURING_CERT=$($Pair.Name)" }
    if ($Pair.Before.Releases -ne $Pair.After.Releases) { throw "RELEASE_COUNT_CHANGED_DURING_CERT=$($Pair.Name)" }
    Write-Host "REMOTE_IMMUTABILITY=$($Pair.Name)=PASS"
}

Write-Host "============================================================"
Write-Host "CLEMENT STUDIO - P1.1 FINAL RESULT"
Write-Host "============================================================"
Write-Host "ORCHESTRATOR_HEAD=$OrchestratorHead"
Write-Host "BOOTSTRAP_HEAD=$BootstrapHead"
Write-Host "P1_1_01_RAW_EVIDENCE=PASS"
Write-Host "P1_1_02_PROVENANCE=PASS"
Write-Host "P1_1_03_CONSISTENCY=PASS"
Write-Host "P1_1_04_FAIL_CLOSED_VERIFIER=PASS"
Write-Host "FABRICATED_EVIDENCE_BLOCKED=PASS"
Write-Host "NO_EVIDENCE_NO_PASS=PASS"
Write-Host "P1_1_SHADOW_REAL=PASS"
Write-Host "P1_1_GLOBAL=PASS"
Write-Host "WORKTREES=CLEAN"
Write-Host "DEVELOP_CHANGED=NO"
Write-Host "MERGE_EXECUTED=NO"
Write-Host "TAG_CREATED=NO"
Write-Host "RELEASE_CREATED=NO"
Write-Host "P1_1_CERTIFICATION_PROGRESS=100%"
Write-Host "NEXT=ODYSSEUS_P1_1_EVIDENCE_TEST"
Write-Host "============================================================"
