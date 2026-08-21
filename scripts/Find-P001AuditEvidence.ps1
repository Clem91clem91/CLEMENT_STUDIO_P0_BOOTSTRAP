param(
    [string[]]$SearchRoots = @(
        "$env:USERPROFILE\Downloads",
        "C:\Users\Shadow\Documents\CLEMENT_STUDIO"
    )
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ExpectedReport = "23726C8DD8FEA5D79636DF27E6AB8CF55BDE073138D9D5A60B5F7B455C958E49"
$ExpectedEvidence = "588EE8589278517FA66CFA8DF998E00E163C31DF21D6CC2425F6E95AD4775084"
$ExpectedBundle = "17ABD5B090E4077E28C887A3E2F1B0269FF0DE447718B1746E21780CD1A83F25"
$Excluded = @(".venv", "venv", "site-packages", ".git", "__pycache__")

function Test-ExcludedPath {
    param([string]$Path)
    $Parts = $Path -split '[\\/]'
    foreach ($Part in $Parts) {
        if ($Excluded -contains $Part) { return $true }
    }
    return $false
}

function Find-ByHash {
    param(
        [string]$Pattern,
        [string]$ExpectedHash
    )
    foreach ($Root in $SearchRoots) {
        if (-not (Test-Path -LiteralPath $Root)) { continue }
        $Files = Get-ChildItem -LiteralPath $Root -File -Recurse -Filter $Pattern -ErrorAction SilentlyContinue
        foreach ($File in $Files) {
            if (Test-ExcludedPath $File.FullName) { continue }
            try {
                $Hash = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
                if ($Hash -eq $ExpectedHash) { return $File.FullName }
            }
            catch {}
        }
    }
    return $null
}

Write-Host "============================================================"
Write-Host "CLEMENT - P0-01 AUDIT EVIDENCE LOCATOR"
Write-Host "MODE=READ_ONLY_SHA256_SEARCH"
Write-Host "============================================================"

$AuditReport = Find-ByHash -Pattern "SKILLS_LIBRARY_AUDIT_RECOVERED_*.md" -ExpectedHash $ExpectedReport
$EvidenceIndex = Find-ByHash -Pattern "EVIDENCE_SHA256_RECOVERED_*.txt" -ExpectedHash $ExpectedEvidence
$AuditBundle = Find-ByHash -Pattern "*.zip" -ExpectedHash $ExpectedBundle

$Inventory = $null
foreach ($Root in $SearchRoots) {
    if (-not (Test-Path -LiteralPath $Root)) { continue }
    $Candidates = Get-ChildItem -LiteralPath $Root -File -Recurse -Filter "skills_inventory.csv" -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-ExcludedPath $_.FullName) } |
        Sort-Object LastWriteTime -Descending
    if ($Candidates) {
        $Inventory = $Candidates[0].FullName
        break
    }
}

$AuditDirectory = $null
if ($AuditReport -and $EvidenceIndex -and $Inventory) {
    $ReportDir = Split-Path -Parent $AuditReport
    $EvidenceDir = Split-Path -Parent $EvidenceIndex
    $InventoryDir = Split-Path -Parent $Inventory
    if ($ReportDir -eq $EvidenceDir -and $ReportDir -eq $InventoryDir) {
        $AuditDirectory = $ReportDir
    }
}

Write-Host "AUDIT_REPORT=$AuditReport"
Write-Host "EVIDENCE_INDEX=$EvidenceIndex"
Write-Host "INVENTORY=$Inventory"
Write-Host "AUDIT_BUNDLE=$AuditBundle"
Write-Host "AUDIT_DIRECTORY=$AuditDirectory"

$Missing = @()
if (-not $AuditReport) { $Missing += "AUDIT_REPORT" }
if (-not $EvidenceIndex) { $Missing += "EVIDENCE_INDEX" }
if (-not $Inventory) { $Missing += "INVENTORY" }
if (-not $AuditBundle) { $Missing += "AUDIT_BUNDLE" }
if (-not $AuditDirectory) { $Missing += "COMMON_AUDIT_DIRECTORY" }

if ($Missing.Count -eq 0) {
    Write-Host "RESULT=PASS"
    Write-Host "NEXT=RUN_P0_01_MATERIALIZATION"
    exit 0
}

Write-Host "RESULT=PARTIAL"
Write-Host "MISSING=$($Missing -join ',')"
Write-Host "NEXT=RECOVER_MISSING_AUDIT_EVIDENCE"
exit 2
