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
$ManifestPath = Join-Path $BootstrapRoot "config\p0_manifest.json"
$TaskId = "TASK-{0}-{1:D4}" -f (Get-Date -Format "yyyyMMdd"), (Get-Random -Minimum 0 -Maximum 10000)
$ArtifactsRoot = Join-Path $BootstrapRoot "artifacts\$TaskId"
$LogPath = Join-Path $ArtifactsRoot "cascade.log"

New-Item -ItemType Directory -Force -Path $ArtifactsRoot | Out-Null
Start-Transcript -Path $LogPath -Force | Out-Null

function Write-Section {
    param([string]$Name)
    Write-Host ""
    Write-Host "============================================================"
    Write-Host $Name
    Write-Host "============================================================"
}

function Resolve-CompatiblePython {
    $Candidates = New-Object System.Collections.Generic.List[string]

    function Add-Candidate {
        param([string]$Path)
        if ($Path -and (Test-Path -LiteralPath $Path -PathType Leaf) -and -not $Candidates.Contains($Path)) {
            $Candidates.Add($Path)
        }
    }

    try {
        $PyList = @(& py -0p 2>$null)
        foreach ($Line in $PyList) {
            if ($Line -match '([A-Za-z]:\\.+python\.exe)') {
                Add-Candidate $Matches[1].Trim()
            }
        }
    }
    catch {}

    try {
        $PythonCommands = @(Get-Command python.exe -All -ErrorAction SilentlyContinue)
        foreach ($Command in $PythonCommands) {
            if ($Command.Source) { Add-Candidate $Command.Source }
        }
    }
    catch {}

    $Known = @(
        "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe"
    )
    foreach ($Path in $Known) { Add-Candidate $Path }

    $Resolved = @()
    foreach ($Path in $Candidates) {
        try {
            $VersionText = (& $Path -c "import sys; print('.'.join(map(str, sys.version_info[:3])))" 2>$null).Trim()
            if ($LASTEXITCODE -eq 0 -and $VersionText) {
                $Version = [version]$VersionText
                if ($Version.Major -eq 3 -and $Version.Minor -ge 11) {
                    $Resolved += [PSCustomObject]@{ Path = $Path; Version = $Version }
                }
            }
        }
        catch {}
    }

    $Best = $Resolved | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $Best) {
        throw "NO_COMPATIBLE_PYTHON_FOUND_REQUIRED=3.11_PLUS"
    }
    return $Best
}

function Get-GitState {
    param([string]$RepoPath)

    if (-not (Test-Path -LiteralPath (Join-Path $RepoPath ".git"))) {
        return $null
    }

    Push-Location $RepoPath
    try {
        $Branch = (& git branch --show-current).Trim()
        $Head = (& git rev-parse HEAD).Trim()
        $Dirty = @(& git status --porcelain).Count -gt 0
        return [PSCustomObject]@{
            Branch = $Branch
            Head = $Head
            Dirty = $Dirty
        }
    }
    finally {
        Pop-Location
    }
}

function Sync-Component {
    param(
        $Component,
        [string]$Destination
    )

    $RepoUrl = "https://github.com/{0}.git" -f $Component.repository
    $ExpectedBranch = [string]$Component.branch
    $ProtectedExisting = [bool]$Component.protected_existing

    if (-not (Test-Path -LiteralPath $Destination)) {
        Write-Host "ACTION=CLONE"
        Write-Host "DESTINATION=$Destination"
        & git clone --branch $ExpectedBranch --single-branch $RepoUrl $Destination
        if ($LASTEXITCODE -ne 0) { throw "CLONE_FAILED=$($Component.id)" }
        return [PSCustomObject]@{ Protected = $false; Synced = $true }
    }

    $State = Get-GitState $Destination
    if (-not $State) {
        throw "DESTINATION_EXISTS_NOT_GIT=$Destination"
    }

    Write-Host "CURRENT_BRANCH=$($State.Branch)"
    Write-Host "CURRENT_HEAD=$($State.Head)"
    Write-Host "CURRENT_DIRTY=$($State.Dirty)"

    if ($ProtectedExisting -and ($State.Dirty -or $State.Branch -ne $ExpectedBranch)) {
        Write-Host "SYNC=SKIPPED_PROTECTED_EXISTING"
        Write-Host "PROTECTED_REASON=BRANCH_OR_WORKTREE_MUST_NOT_BE_OVERWRITTEN"
        return [PSCustomObject]@{ Protected = $true; Synced = $false }
    }

    if ($State.Dirty) {
        throw "BLOCKED_PROTECTED_WORKTREE=$Destination"
    }
    if ($State.Branch -ne $ExpectedBranch) {
        throw "BLOCKED_BRANCH_MISMATCH=$($State.Branch)_EXPECTED=$ExpectedBranch"
    }

    Push-Location $Destination
    try {
        & git fetch origin --prune
        if ($LASTEXITCODE -ne 0) { throw "FETCH_FAILED=$($Component.id)" }

        & git pull --ff-only origin $ExpectedBranch
        if ($LASTEXITCODE -ne 0) { throw "FAST_FORWARD_PULL_FAILED=$($Component.id)" }

        $LocalHead = (& git rev-parse HEAD).Trim()
        $RemoteHead = (& git rev-parse "origin/$ExpectedBranch").Trim()
        if ($LocalHead -ne $RemoteHead) {
            throw "LOCAL_REMOTE_HEAD_MISMATCH=$($Component.id)"
        }
        Write-Host "SYNCED_HEAD=$LocalHead"
    }
    finally {
        Pop-Location
    }

    return [PSCustomObject]@{ Protected = $false; Synced = $true }
}

function Ensure-VenvAndInstall {
    param(
        [string]$RepoPath,
        [string]$BasePython
    )

    $VenvPython = Join-Path $RepoPath ".venv\Scripts\python.exe"
    if (-not (Test-Path -LiteralPath $VenvPython)) {
        Write-Host "VENV_CREATE=YES"
        & $BasePython -m venv (Join-Path $RepoPath ".venv")
        if ($LASTEXITCODE -ne 0) { throw "VENV_CREATION_FAILED=$RepoPath" }
    }
    else {
        Write-Host "VENV_CREATE=NO"
    }

    & $VenvPython -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) { throw "PIP_UPGRADE_FAILED=$RepoPath" }

    Push-Location $RepoPath
    try {
        & $VenvPython -m pip install -e ".[dev]"
        if ($LASTEXITCODE -ne 0) { throw "PACKAGE_INSTALL_FAILED=$RepoPath" }
    }
    finally {
        Pop-Location
    }

    return $VenvPython
}

function Invoke-ProjectTests {
    param(
        [string]$RepoPath,
        [string]$Python
    )

    Push-Location $RepoPath
    try {
        & $Python -m compileall -q src tests scripts
        if ($LASTEXITCODE -ne 0) { throw "COMPILE_FAILED=$RepoPath" }
        Write-Host "COMPILE=PASS"

        & $Python -m pytest
        if ($LASTEXITCODE -ne 0) { throw "PYTEST_FAILED=$RepoPath" }
        Write-Host "PYTEST=PASS"
    }
    finally {
        Pop-Location
    }
}

function Invoke-Certifier {
    param(
        $Component,
        [string]$RepoPath,
        [string]$Python,
        [bool]$Protected
    )

    $Certifier = [string]$Component.certifier
    if (-not $Certifier) {
        Write-Host "CERTIFIER=NONE"
        return
    }

    $CertifierPath = Join-Path $RepoPath $Certifier
    if (-not (Test-Path -LiteralPath $CertifierPath)) {
        throw "CERTIFIER_NOT_FOUND=$CertifierPath"
    }

    if ($Component.id -eq "P0-01") {
        if ($Protected) {
            Write-Host "CERTIFICATION=SKIPPED_PROTECTED_EXISTING"
            return
        }
        & $Python $CertifierPath --root $RepoPath
        if ($LASTEXITCODE -ne 0) { throw "P0_01_CERTIFICATION_FAILED" }
        Write-Host "CERTIFICATION=PASS"
        return
    }

    powershell -NoProfile -ExecutionPolicy Bypass -File $CertifierPath
    if ($LASTEXITCODE -ne 0) { throw "CERTIFICATION_FAILED=$($Component.id)" }
    Write-Host "CERTIFICATION=PASS_OR_PARTIAL"
}

function Invoke-SkillsMaterialization {
    param(
        [string]$RepoPath,
        [string]$Python,
        [bool]$Protected
    )

    if (-not $MaterializeSkills.IsPresent) {
        Write-Host "MATERIALIZE_SKILLS=NO"
        return
    }

    if ($Protected) {
        throw "P0_01_MATERIALIZATION_BLOCKED_PROTECTED_EXISTING"
    }
    if (-not (Test-Path -LiteralPath $SkillsSourceRoot)) {
        throw "SKILLS_SOURCE_ROOT_NOT_FOUND=$SkillsSourceRoot"
    }
    if (-not $SkillsAuditDirectory -or -not (Test-Path -LiteralPath $SkillsAuditDirectory)) {
        throw "SKILLS_AUDIT_DIRECTORY_REQUIRED"
    }
    if (-not $SkillsAuditBundle -or -not (Test-Path -LiteralPath $SkillsAuditBundle)) {
        throw "SKILLS_AUDIT_BUNDLE_REQUIRED"
    }

    $Inventory = Join-Path $SkillsAuditDirectory "skills_inventory.csv"
    $AuditReport = Get-ChildItem -LiteralPath $SkillsAuditDirectory -Filter "SKILLS_LIBRARY_AUDIT_RECOVERED_*.md" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $Evidence = Get-ChildItem -LiteralPath $SkillsAuditDirectory -Filter "EVIDENCE_SHA256_RECOVERED_*.txt" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $Contract = Join-Path $RepoPath "config\audit_contract.json"
    $Importer = Join-Path $RepoPath "scripts\import_skills.py"

    if (-not (Test-Path -LiteralPath $Inventory)) { throw "SKILLS_INVENTORY_NOT_FOUND=$Inventory" }
    if (-not $AuditReport) { throw "AUDIT_REPORT_NOT_FOUND" }
    if (-not $Evidence) { throw "EVIDENCE_INDEX_NOT_FOUND" }

    $CommonArgs = @(
        $Importer,
        "--source-root", $SkillsSourceRoot,
        "--inventory", $Inventory,
        "--contract", $Contract,
        "--audit-report", $AuditReport.FullName,
        "--evidence-index", $Evidence.FullName,
        "--audit-bundle", $SkillsAuditBundle,
        "--repository-root", $RepoPath
    )

    Write-Host "MATERIALIZATION_DRY_RUN=START"
    & $Python @CommonArgs
    if ($LASTEXITCODE -ne 0) { throw "P0_01_IMPORT_DRY_RUN_FAILED" }
    Write-Host "MATERIALIZATION_DRY_RUN=PASS"

    $BackupRoot = Join-Path $env:USERPROFILE "Downloads\CLEMENT_P0\P0-01_BACKUPS"
    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

    Write-Host "MATERIALIZATION_APPLY=START"
    & $Python @CommonArgs --apply --backup-root $BackupRoot
    if ($LASTEXITCODE -ne 0) { throw "P0_01_IMPORT_APPLY_FAILED" }
    Write-Host "MATERIALIZATION_APPLY=PASS"
    Write-Host "BACKUP_ROOT=$BackupRoot"
}

try {
    Write-Section "CLEMENT - P0 CASCADE INSTALLER"
    Write-Host "TASK_ID=$TaskId"
    Write-Host "ROOT=$Root"
    Write-Host "INSTALL=$($Install.IsPresent)"
    Write-Host "TEST=$($Test.IsPresent)"
    Write-Host "CERTIFY=$($Certify.IsPresent)"
    Write-Host "MATERIALIZE_SKILLS=$($MaterializeSkills.IsPresent)"
    Write-Host "MERGE_ALLOWED=NO"
    Write-Host "TAG_ALLOWED=NO"
    Write-Host "RELEASE_ALLOWED=NO"

    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "MANIFEST_NOT_FOUND=$ManifestPath"
    }
    New-Item -ItemType Directory -Force -Path $Root | Out-Null

    & git --version
    if ($LASTEXITCODE -ne 0) { throw "GIT_NOT_AVAILABLE" }

    $PythonInfo = Resolve-CompatiblePython
    $BasePython = [string]$PythonInfo.Path
    Write-Host "BASE_PYTHON=$BasePython"
    Write-Host "BASE_PYTHON_VERSION=$($PythonInfo.Version)"

    $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    $Results = @()

    foreach ($Component in $Manifest.components) {
        Write-Section ("{0} - {1}" -f $Component.id, $Component.name)
        $Destination = Join-Path $Root ([string]$Component.local_dir)
        Write-Host "DESTINATION=$Destination"
        Write-Host "EXPECTED_BRANCH=$($Component.branch)"

        $Sync = Sync-Component -Component $Component -Destination $Destination
        $VenvPython = $null

        if ($Install.IsPresent) {
            if ($Sync.Protected) {
                Write-Host "INSTALL=SKIPPED_PROTECTED_EXISTING"
            }
            else {
                $VenvPython = Ensure-VenvAndInstall -RepoPath $Destination -BasePython $BasePython
                Write-Host "INSTALL=PASS"
            }
        }
        else {
            $ExistingVenv = Join-Path $Destination ".venv\Scripts\python.exe"
            if (Test-Path -LiteralPath $ExistingVenv) { $VenvPython = $ExistingVenv }
        }

        if ($Component.id -eq "P0-01" -and $MaterializeSkills.IsPresent) {
            if (-not $VenvPython) {
                throw "P0_01_VENV_REQUIRED_FOR_MATERIALIZATION"
            }
            Invoke-SkillsMaterialization -RepoPath $Destination -Python $VenvPython -Protected ([bool]$Sync.Protected)
        }

        if ($Test.IsPresent) {
            if ($Sync.Protected) {
                Write-Host "TEST=SKIPPED_PROTECTED_EXISTING"
            }
            else {
                if (-not $VenvPython) { throw "VENV_REQUIRED_FOR_TEST=$($Component.id)" }
                Invoke-ProjectTests -RepoPath $Destination -Python $VenvPython
                Write-Host "TEST=PASS"
            }
        }

        if ($Certify.IsPresent) {
            if ($Sync.Protected) {
                Write-Host "CERTIFY=SKIPPED_PROTECTED_EXISTING"
            }
            else {
                if (-not $VenvPython) { throw "VENV_REQUIRED_FOR_CERTIFY=$($Component.id)" }
                Invoke-Certifier -Component $Component -RepoPath $Destination -Python $VenvPython -Protected ([bool]$Sync.Protected)
            }
        }

        $FinalState = Get-GitState $Destination
        if ($FinalState) {
            Write-Host "FINAL_BRANCH=$($FinalState.Branch)"
            Write-Host "FINAL_HEAD=$($FinalState.Head)"
            Write-Host "FINAL_DIRTY=$($FinalState.Dirty)"
        }

        $Results += [PSCustomObject]@{
            id = [string]$Component.id
            protected = [bool]$Sync.Protected
            branch = if ($FinalState) { [string]$FinalState.Branch } else { "" }
            head = if ($FinalState) { [string]$FinalState.Head } else { "" }
        }
    }

    Write-Section "BOOTSTRAP SELF TEST"
    $BootstrapVenv = Ensure-VenvAndInstall -RepoPath $BootstrapRoot -BasePython $BasePython
    Invoke-ProjectTests -RepoPath $BootstrapRoot -Python $BootstrapVenv
    Write-Host "BOOTSTRAP_SELF_TEST=PASS"

    Write-Section "CASCADE RESULT"
    foreach ($Result in $Results) {
        Write-Host ("COMPONENT={0} PROTECTED={1} BRANCH={2} HEAD={3}" -f $Result.id, $Result.protected, $Result.branch, $Result.head)
    }
    Write-Host "RESULT=PASS"
    Write-Host "TASK_ID=$TaskId"
    Write-Host "LOG=$LogPath"
    Write-Host "MERGE_EXECUTED=NO"
    Write-Host "TAG_CREATED=NO"
    Write-Host "RELEASE_CREATED=NO"
}
catch {
    Write-Section "CASCADE RESULT"
    Write-Host "RESULT=FAIL"
    Write-Host "TASK_ID=$TaskId"
    Write-Host "ERROR=$($_.Exception.Message)"
    Write-Host "LOG=$LogPath"
    Write-Host "MERGE_EXECUTED=NO"
    Write-Host "TAG_CREATED=NO"
    Write-Host "RELEASE_CREATED=NO"
    throw
}
finally {
    Stop-Transcript | Out-Null
}
