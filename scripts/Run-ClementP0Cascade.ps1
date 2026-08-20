param(
    [string]$Root = "C:\Users\Shadow\Documents\CLEMENT_STUDIO\04_TOOLS",
    [switch]$Install,
    [switch]$Test,
    [switch]$Certify,
    [switch]$MaterializeSkills,
    [string]$SkillsSourceRoot = "C:\Users\Shadow\Documents\CLEMENT_STUDIO\09_Drive\Mega\skill",
    [string]$SkillsAuditDirectory = "",
    [string]$SkillsAuditBundle = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$BootstrapRoot = Split-Path -Parent $PSScriptRoot
$Installer = Join-Path $PSScriptRoot "Install-ClementP0Cascade.ps1"
$Artifacts = Join-Path $BootstrapRoot "artifacts"
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$WrapperLog = Join-Path $Artifacts ("cascade-wrapper-{0}.log" -f $Stamp)
$StdOutLog = Join-Path $Artifacts ("cascade-wrapper-{0}.stdout.log" -f $Stamp)
$StdErrLog = Join-Path $Artifacts ("cascade-wrapper-{0}.stderr.log" -f $Stamp)
$PatchedInstaller = Join-Path $Artifacts ("Install-ClementP0Cascade.patched-{0}.ps1" -f $Stamp)

if (-not (Test-Path -LiteralPath $Installer)) {
    throw "CASCADE_INSTALLER_NOT_FOUND=$Installer"
}
New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null

# PowerShell functions emit every success-stream object. The installer has two
# functions that intentionally return one contract value, but native git/pip
# stdout can precede that value and turn the caller variable into Object[].
# Build a temporary, auditable execution copy that isolates the final contract
# object/path while preserving preceding command output on the host.
$InstallerSource = Get-Content -LiteralPath $Installer -Raw

$OriginalSync = '        $Sync = Sync-Component -Component $Component -Destination $Destination'
$ReplacementSync = @'
        $SyncItems = @(Sync-Component -Component $Component -Destination $Destination)
        if ($SyncItems.Count -lt 1) { throw "SYNC_COMPONENT_RETURN_EMPTY=$($Component.id)" }
        if ($SyncItems.Count -gt 1) {
            $SyncItems[0..($SyncItems.Count - 2)] | ForEach-Object { Write-Host $_ }
        }
        $Sync = $SyncItems[-1]
        if (-not ($Sync.PSObject.Properties.Name -contains "Protected")) {
            throw "SYNC_COMPONENT_CONTRACT_INVALID=$($Component.id)"
        }
'@

$OriginalVenv = '                $VenvPython = Ensure-VenvAndInstall -RepoPath $Destination -BasePython $BasePython'
$ReplacementVenv = @'
                $VenvItems = @(Ensure-VenvAndInstall -RepoPath $Destination -BasePython $BasePython)
                if ($VenvItems.Count -lt 1) { throw "VENV_INSTALL_RETURN_EMPTY=$($Component.id)" }
                if ($VenvItems.Count -gt 1) {
                    $VenvItems[0..($VenvItems.Count - 2)] | ForEach-Object { Write-Host $_ }
                }
                $VenvPython = [string]$VenvItems[-1]
                if (-not (Test-Path -LiteralPath $VenvPython -PathType Leaf)) {
                    throw "VENV_INSTALL_CONTRACT_INVALID=$($Component.id)_VALUE=$VenvPython"
                }
'@

if (-not $InstallerSource.Contains($OriginalSync)) {
    throw "CASCADE_PATCH_POINT_NOT_FOUND=SYNC_COMPONENT"
}
if (-not $InstallerSource.Contains($OriginalVenv)) {
    throw "CASCADE_PATCH_POINT_NOT_FOUND=VENV_INSTALL"
}

$ExecutionSource = $InstallerSource.Replace($OriginalSync, $ReplacementSync)
$ExecutionSource = $ExecutionSource.Replace($OriginalVenv, $ReplacementVenv)

if ($ExecutionSource.Contains($OriginalSync)) {
    throw "CASCADE_PATCH_FAILED=SYNC_COMPONENT"
}
if ($ExecutionSource.Contains($OriginalVenv)) {
    throw "CASCADE_PATCH_FAILED=VENV_INSTALL"
}

Set-Content -LiteralPath $PatchedInstaller -Value $ExecutionSource -Encoding ASCII
Write-Host "EXECUTION_INSTALLER=$PatchedInstaller"
Write-Host "SYNC_RETURN_CONTRACT_PATCH=PASS"
Write-Host "VENV_RETURN_CONTRACT_PATCH=PASS"

$ChildArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $PatchedInstaller,
    "-Root", $Root
)
if ($Install.IsPresent) { $ChildArgs += "-Install" }
if ($Test.IsPresent) { $ChildArgs += "-Test" }
if ($Certify.IsPresent) { $ChildArgs += "-Certify" }
if ($MaterializeSkills.IsPresent) {
    $ChildArgs += "-MaterializeSkills"
    $ChildArgs += @("-SkillsSourceRoot", $SkillsSourceRoot)
    if ($SkillsAuditDirectory) { $ChildArgs += @("-SkillsAuditDirectory", $SkillsAuditDirectory) }
    if ($SkillsAuditBundle) { $ChildArgs += @("-SkillsAuditBundle", $SkillsAuditBundle) }
}

Write-Host "============================================================"
Write-Host "CLEMENT - P0 CASCADE MASTER WRAPPER"
Write-Host "============================================================"

# Do not invoke the child with 2>&1 under ErrorActionPreference=Stop.
# Windows PowerShell 5.1 can wrap native stderr records (for example normal Git
# progress such as From https://github.com/...) as NativeCommandError. A
# successful child can therefore look like a wrapper failure. Start-Process
# keeps stdout/stderr as raw files and makes the process exit code authoritative.
Remove-Item -LiteralPath $StdOutLog, $StdErrLog -Force -ErrorAction SilentlyContinue

$ChildProcess = Start-Process `
    -FilePath "powershell.exe" `
    -ArgumentList $ChildArgs `
    -RedirectStandardOutput $StdOutLog `
    -RedirectStandardError $StdErrLog `
    -NoNewWindow `
    -Wait `
    -PassThru

$ExitCode = $ChildProcess.ExitCode
$StdOut = @()
$StdErr = @()
if (Test-Path -LiteralPath $StdOutLog) { $StdOut = @(Get-Content -LiteralPath $StdOutLog) }
if (Test-Path -LiteralPath $StdErrLog) { $StdErr = @(Get-Content -LiteralPath $StdErrLog) }

$Output = @($StdOut)
$Output | Set-Content -LiteralPath $WrapperLog -Encoding UTF8

foreach ($Line in $StdOut) {
    Write-Host $Line
}

if ($StdErr.Count -gt 0) {
    Add-Content -LiteralPath $WrapperLog -Value "STDERR_BEGIN" -Encoding UTF8
    $StdErr | Add-Content -LiteralPath $WrapperLog -Encoding UTF8
    Add-Content -LiteralPath $WrapperLog -Value "STDERR_END" -Encoding UTF8

    Write-Host "STDERR_BEGIN"
    foreach ($Line in $StdErr) {
        # stderr is informational unless the child process exits non-zero.
        Write-Host $Line
    }
    Write-Host "STDERR_END"
}

Write-Host "CHILD_EXIT_CODE=$ExitCode"

if ($ExitCode -ne 0) {
    Write-Host "============================================================"
    Write-Host "CASCADE_VERDICT=FAIL"
    Write-Host "CHILD_EXIT_CODE=$ExitCode"
    Write-Host "WRAPPER_LOG=$WrapperLog"
    Write-Host "STDOUT_LOG=$StdOutLog"
    Write-Host "STDERR_LOG=$StdErrLog"
    Write-Host "PATCHED_INSTALLER=$PatchedInstaller"
    Write-Host "============================================================"
    exit $ExitCode
}

$Protected = @($StdOut | Where-Object { [string]$_ -match "SYNC=SKIPPED_PROTECTED_EXISTING" })
$ChildFail = @($StdOut | Where-Object { [string]$_ -match "RESULT=FAIL" })

if ($ChildFail.Count -gt 0) {
    $Verdict = "FAIL"
}
elseif ($Protected.Count -gt 0) {
    $Verdict = "PARTIAL"
}
else {
    $Verdict = "PASS"
}

Write-Host "============================================================"
Write-Host "CASCADE_VERDICT=$Verdict"
Write-Host "PROTECTED_COMPONENT_EVENTS=$($Protected.Count)"
Write-Host "WRAPPER_LOG=$WrapperLog"
Write-Host "STDOUT_LOG=$StdOutLog"
Write-Host "STDERR_LOG=$StdErrLog"
Write-Host "PATCHED_INSTALLER=$PatchedInstaller"
Write-Host "MERGE_EXECUTED=NO"
Write-Host "TAG_CREATED=NO"
Write-Host "RELEASE_CREATED=NO"
Write-Host "============================================================"

if ($Verdict -eq "FAIL") { exit 1 }
exit 0
