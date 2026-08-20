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
$WrapperLog = Join-Path $Artifacts ("cascade-wrapper-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

if (-not (Test-Path -LiteralPath $Installer)) {
    throw "CASCADE_INSTALLER_NOT_FOUND=$Installer"
}
New-Item -ItemType Directory -Force -Path $Artifacts | Out-Null

$ChildArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $Installer,
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

$Output = @(& powershell @ChildArgs 2>&1)
$ExitCode = $LASTEXITCODE
$Output | Tee-Object -FilePath $WrapperLog | ForEach-Object { Write-Host $_ }

if ($ExitCode -ne 0) {
    Write-Host "============================================================"
    Write-Host "CASCADE_VERDICT=FAIL"
    Write-Host "CHILD_EXIT_CODE=$ExitCode"
    Write-Host "WRAPPER_LOG=$WrapperLog"
    Write-Host "============================================================"
    exit $ExitCode
}

$Protected = @($Output | Where-Object { [string]$_ -match "SYNC=SKIPPED_PROTECTED_EXISTING" })
$ChildFail = @($Output | Where-Object { [string]$_ -match "RESULT=FAIL" })

if ($ChildFail.Count -gt 0) {
    $Verdict = "FAIL"
}
elif ($Protected.Count -gt 0) {
    $Verdict = "PARTIAL"
}
else {
    $Verdict = "PASS"
}

Write-Host "============================================================"
Write-Host "CASCADE_VERDICT=$Verdict"
Write-Host "PROTECTED_COMPONENT_EVENTS=$($Protected.Count)"
Write-Host "WRAPPER_LOG=$WrapperLog"
Write-Host "MERGE_EXECUTED=NO"
Write-Host "TAG_CREATED=NO"
Write-Host "RELEASE_CREATED=NO"
Write-Host "============================================================"

if ($Verdict -eq "FAIL") { exit 1 }
exit 0
