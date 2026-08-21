param(
    [string]$Root = "C:\Users\Shadow\Documents\CLEMENT_STUDIO\04_TOOLS"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$BootstrapRoot = Split-Path -Parent $PSScriptRoot
$ManifestPath = Join-Path $BootstrapRoot "config\p0_manifest.json"
$Cascade = Join-Path $PSScriptRoot "Run-ClementP0Cascade.ps1"
$Artifacts = Join-Path $BootstrapRoot "artifacts"
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$StdOutLog = Join-Path $Artifacts ("final-p0-certification-{0}.stdout.log" -f $Stamp)
$StdErrLog = Join-Path $Artifacts ("final-p0-certification-{0}.stderr.log" -f $Stamp)

function Assert-PinnedComponents {
    param(
        $Manifest,
        [string]$Phase
    )

    foreach ($Component in $Manifest.components) {
        $Destination = Join-Path $Root ([string]$Component.local_dir)
        $ExpectedBranch = [string]$Component.branch
        $ExpectedHead = [string]$Component.expected_head

        if (-not $ExpectedHead) {
            throw "EXPECTED_HEAD_MISSING=$($Component.id)"
        }
        if (-not (Test-Path -LiteralPath (Join-Path $Destination ".git"))) {
            throw "COMPONENT_GIT_NOT_FOUND=$($Component.id)_PATH=$Destination"
        }

        Push-Location $Destination
        try {
            $Branch = (& git branch --show-current).Trim()
            if ($LASTEXITCODE -ne 0) { throw "GIT_BRANCH_FAILED=$($Component.id)" }

            $Head = (& git rev-parse HEAD).Trim()
            if ($LASTEXITCODE -ne 0) { throw "GIT_HEAD_FAILED=$($Component.id)" }

            $Dirty = @(& git status --porcelain)
            if ($LASTEXITCODE -ne 0) { throw "GIT_STATUS_FAILED=$($Component.id)" }

            Write-Host "PIN_PHASE=$Phase COMPONENT=$($Component.id) BRANCH=$Branch HEAD=$Head DIRTY_COUNT=$($Dirty.Count)"

            if ($Branch -ne $ExpectedBranch) {
                throw "PIN_BRANCH_MISMATCH=$($Component.id)_ACTUAL=$Branch_EXPECTED=$ExpectedBranch"
            }
            if ($Head -ne $ExpectedHead) {
                throw "PIN_HEAD_MISMATCH=$($Component.id)_ACTUAL=$Head_EXPECTED=$ExpectedHead"
            }
            if ($Dirty.Count -ne 0) {
                Write-Host "DIRTY_BEGIN COMPONENT=$($Component.id)"
                foreach ($Line in $Dirty) { Write-Host $Line }
                Write-Host "DIRTY_END COMPONENT=$($Component.id)"
                throw "PIN_WORKTREE_DIRTY=$($Component.id)"
            }
        }
        finally {
            Pop-Location
        }
    }
}

Write-Host "============================================================"
Write-Host "CLEMENT - FINAL P0 BOOTSTRAP CERTIFICATION"
Write-Host "MODE=PINNED_HEADS_REAL_E2E_FAIL_CLOSED"
Write-Host "============================================================"

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "MANIFEST_NOT_FOUND=$ManifestPath"
}
if (-not (Test-Path -LiteralPath $Cascade)) {
    throw "CASCADE_NOT_FOUND=$Cascade"
}

New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null
$Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json

Assert-PinnedComponents -Manifest $Manifest -Phase "BEFORE"
Write-Host "PINNED_HEADS_BEFORE=PASS"

Remove-Item -LiteralPath $StdOutLog, $StdErrLog -Force -ErrorAction SilentlyContinue

$Arguments = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $Cascade,
    "-Root", $Root,
    "-Install",
    "-Test",
    "-Certify"
)

$Process = Start-Process `
    -FilePath "powershell.exe" `
    -ArgumentList $Arguments `
    -RedirectStandardOutput $StdOutLog `
    -RedirectStandardError $StdErrLog `
    -NoNewWindow `
    -Wait `
    -PassThru

$ExitCode = $Process.ExitCode
$StdOut = @()
$StdErr = @()
if (Test-Path -LiteralPath $StdOutLog) { $StdOut = @(Get-Content -LiteralPath $StdOutLog) }
if (Test-Path -LiteralPath $StdErrLog) { $StdErr = @(Get-Content -LiteralPath $StdErrLog) }

foreach ($Line in $StdOut) { Write-Host $Line }
if ($StdErr.Count -gt 0) {
    Write-Host "FINAL_CASCADE_STDERR_BEGIN"
    foreach ($Line in $StdErr) { Write-Host $Line }
    Write-Host "FINAL_CASCADE_STDERR_END"
}

Write-Host "FINAL_CASCADE_EXIT_CODE=$ExitCode"
if ($ExitCode -ne 0) {
    throw "FINAL_CASCADE_FAILED_EXIT=$ExitCode"
}

$CascadePass = @($StdOut | Where-Object { [string]$_ -eq "CASCADE_VERDICT=PASS" }).Count -gt 0
$GlobalPass = @($StdOut | Where-Object { [string]$_ -eq "GLOBAL_RESULT=PASS" }).Count -gt 0
$ProtectedEvents = @($StdOut | Where-Object { [string]$_ -match "SYNC=SKIPPED_PROTECTED_EXISTING" }).Count

Write-Host "CASCADE_PASS_OBSERVED=$CascadePass"
Write-Host "GLOBAL_PASS_OBSERVED=$GlobalPass"
Write-Host "PROTECTED_COMPONENT_EVENTS=$ProtectedEvents"

if (-not $CascadePass) {
    throw "FINAL_CASCADE_VERDICT_NOT_PASS"
}
if (-not $GlobalPass) {
    throw "FINAL_GLOBAL_RESULT_NOT_PASS"
}
if ($ProtectedEvents -ne 0) {
    throw "FINAL_PROTECTED_COMPONENT_EVENT_COUNT=$ProtectedEvents"
}

Assert-PinnedComponents -Manifest $Manifest -Phase "AFTER"
Write-Host "PINNED_HEADS_AFTER=PASS"

Write-Host "============================================================"
Write-Host "P0_01=PASS"
Write-Host "P0_02=PASS"
Write-Host "P0_03=PASS"
Write-Host "P0_04=PASS"
Write-Host "GLOBAL_P0=PASS"
Write-Host "BOOTSTRAP_CASCADE=PASS"
Write-Host "FINAL_P0_BOOTSTRAP=PASS"
Write-Host "MERGE_EXECUTED=NO"
Write-Host "TAG_CREATED=NO"
Write-Host "RELEASE_CREATED=NO"
Write-Host "STDOUT_LOG=$StdOutLog"
Write-Host "STDERR_LOG=$StdErrLog"
Write-Host "============================================================"
