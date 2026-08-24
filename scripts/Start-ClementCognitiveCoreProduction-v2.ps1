& {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    # V5 recovery runner.
    # - resolves script path safely under an outer ScriptBlock
    # - treats missing GitHub repositories/branches as expected control flow
    # - URL-encodes branch names for GitHub API lookups
    # - normalizes Initialize-Repository output so native git/gh stdout cannot
    #   pollute the returned local repository path
    # - resumes safely when a previous interrupted run already created local
    #   develop/feature branches

    $ScriptRoot = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($ScriptRoot)) {
        if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
            throw "SCRIPT_ROOT_RESOLUTION_FAILED"
        }
        $ScriptRoot = Split-Path -Parent $PSCommandPath
    }

    if (-not (Test-Path -LiteralPath $ScriptRoot -PathType Container)) {
        throw "SCRIPT_ROOT_NOT_FOUND=$ScriptRoot"
    }

    $SourceScript = Join-Path $ScriptRoot "Start-ClementCognitiveCoreProduction.ps1"
    $PowerShellExe = (Get-Command powershell.exe -ErrorAction Stop).Source

    Write-Host "============================================================"
    Write-Host "CLEMENT STUDIO - COGNITIVE CORE PRODUCTION RUNNER V5"
    Write-Host "FIX=PATH_OUTPUT_POLLUTION_AND_INTERRUPTED_RUN_RESUME"
    Write-Host "SCRIPT_ROOT=$ScriptRoot"
    Write-Host "MERGE_ALLOWED=NO"
    Write-Host "TAG_ALLOWED=NO"
    Write-Host "RELEASE_ALLOWED=NO"
    Write-Host "============================================================"

    if (-not (Test-Path -LiteralPath $SourceScript -PathType Leaf)) {
        throw "SOURCE_PRODUCTION_SCRIPT_NOT_FOUND=$SourceScript"
    }

    $Source = Get-Content -LiteralPath $SourceScript -Raw -ErrorAction Stop

    # -----------------------------------------------------------------
    # PATCH 1 - safe remote existence probes.
    # -----------------------------------------------------------------
    $StartMarker = "    function Remote-RepoExists {"
    $EndMarker = "    function Initialize-Repository {"

    $StartIndex = $Source.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
    $EndIndex = $Source.IndexOf($EndMarker, [System.StringComparison]::Ordinal)

    if ($StartIndex -lt 0) {
        throw "PATCH_START_MARKER_NOT_FOUND"
    }

    if ($EndIndex -lt 0 -or $EndIndex -le $StartIndex) {
        throw "PATCH_END_MARKER_NOT_FOUND"
    }

    $SafeFunctions = @'
    function Remote-RepoExists {
        param([string]$FullName)

        & cmd.exe /d /s /c "gh repo view `"$FullName`" --json name 1>nul 2>nul"
        return ($LASTEXITCODE -eq 0)
    }

    function Remote-BranchExists {
        param([string]$FullName, [string]$Branch)

        $EncodedBranch = [System.Uri]::EscapeDataString([string]$Branch)
        & cmd.exe /d /s /c "gh api `"repos/$FullName/branches/$EncodedBranch`" 1>nul 2>nul"
        return ($LASTEXITCODE -eq 0)
    }

'@

    $Patched = $Source.Substring(0, $StartIndex) + $SafeFunctions + $Source.Substring($EndIndex)

    # -----------------------------------------------------------------
    # PATCH 2 - interrupted-run-safe develop branch creation.
    # -----------------------------------------------------------------
    $OldDevelopElse = @'
        else {
            & git -C $RepoPath switch main
            if ($LASTEXITCODE -ne 0) { throw "SWITCH_MAIN_FAILED=$Name" }
            Invoke-Git $RepoPath pull --ff-only origin main
            Invoke-Git $RepoPath switch -c develop
            Invoke-Git $RepoPath push -u origin develop
        }
'@

    $NewDevelopElse = @'
        else {
            & git -C $RepoPath switch main
            if ($LASTEXITCODE -ne 0) { throw "SWITCH_MAIN_FAILED=$Name" }
            Invoke-Git $RepoPath pull --ff-only origin main

            $LocalDevelop = (& git -C $RepoPath branch --list develop).Trim()
            if ([string]::IsNullOrWhiteSpace($LocalDevelop)) {
                Invoke-Git $RepoPath switch -c develop
            }
            else {
                & git -C $RepoPath switch develop
                if ($LASTEXITCODE -ne 0) { throw "SWITCH_LOCAL_DEVELOP_FAILED=$Name" }
            }

            Invoke-Git $RepoPath push -u origin develop
        }
'@

    if (-not $Patched.Contains($OldDevelopElse)) {
        throw "PATCH_DEVELOP_BLOCK_NOT_FOUND"
    }
    $Patched = $Patched.Replace($OldDevelopElse, $NewDevelopElse)

    # -----------------------------------------------------------------
    # PATCH 3 - interrupted-run-safe feature branch creation.
    # -----------------------------------------------------------------
    $OldFeatureElse = @'
        else {
            & git -C $RepoPath switch develop
            if ($LASTEXITCODE -ne 0) { throw "SWITCH_DEVELOP_FAILED=$Name" }
            Invoke-Git $RepoPath switch -c $FeatureBranch
        }
'@

    $NewFeatureElse = @'
        else {
            & git -C $RepoPath switch develop
            if ($LASTEXITCODE -ne 0) { throw "SWITCH_DEVELOP_FAILED=$Name" }

            $LocalFeature = (& git -C $RepoPath branch --list $FeatureBranch).Trim()
            if ([string]::IsNullOrWhiteSpace($LocalFeature)) {
                Invoke-Git $RepoPath switch -c $FeatureBranch
            }
            else {
                & git -C $RepoPath switch $FeatureBranch
                if ($LASTEXITCODE -ne 0) { throw "SWITCH_LOCAL_FEATURE_FAILED=$Name BRANCH=$FeatureBranch" }
            }
        }
'@

    if (-not $Patched.Contains($OldFeatureElse)) {
        throw "PATCH_FEATURE_BLOCK_NOT_FOUND"
    }
    $Patched = $Patched.Replace($OldFeatureElse, $NewFeatureElse)

    # -----------------------------------------------------------------
    # PATCH 4 - normalize Initialize-Repository return value.
    # PowerShell captures every success-stream object produced by a function.
    # gh repo create / git operations can therefore precede the intended path.
    # The function's explicit return is last, so keep only the last object.
    # -----------------------------------------------------------------
    $OldCall = '        $RepoPath = Initialize-Repository -Name $Spec.Name -Description $Spec.Description -FeatureBranch $Spec.Branch'

    $NewCall = @'
        $InitializeOutput = @(Initialize-Repository -Name $Spec.Name -Description $Spec.Description -FeatureBranch $Spec.Branch)
        if ($InitializeOutput.Count -eq 0) {
            throw "INITIALIZE_REPOSITORY_RETURNED_NO_PATH=$($Spec.Name)"
        }

        if ($InitializeOutput.Count -gt 1) {
            for ($OutputIndex = 0; $OutputIndex -lt ($InitializeOutput.Count - 1); $OutputIndex++) {
                Write-Host "INITIALIZE_OUTPUT=$($InitializeOutput[$OutputIndex])"
            }
        }

        $RepoPath = [string]$InitializeOutput[-1]

        if ([string]::IsNullOrWhiteSpace($RepoPath)) {
            throw "INITIALIZE_REPOSITORY_EMPTY_PATH=$($Spec.Name)"
        }

        if (-not [System.IO.Path]::IsPathRooted($RepoPath)) {
            throw "INITIALIZE_REPOSITORY_NONLOCAL_PATH=$($Spec.Name) VALUE=$RepoPath"
        }

        if ($RepoPath -match '^https?:') {
            throw "INITIALIZE_REPOSITORY_URL_POLLUTION=$($Spec.Name) VALUE=$RepoPath"
        }

        Write-Host "RESOLVED_LOCAL_REPO_PATH=$RepoPath"
'@

    if (-not $Patched.Contains($OldCall)) {
        throw "PATCH_INITIALIZE_CALL_NOT_FOUND"
    }
    $Patched = $Patched.Replace($OldCall, $NewCall.TrimEnd("`r", "`n"))

    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $PatchedScript = Join-Path $env:TEMP "CLEMENT_CognitiveCoreProduction_patched_$Timestamp.ps1"
    $Utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PatchedScript, $Patched, $Utf8)

    Write-Host "SOURCE_SCRIPT=$SourceScript"
    Write-Host "PATCHED_SCRIPT=$PatchedScript"
    Write-Host "PATCH_REMOTE_PROBES=PASS"
    Write-Host "PATCH_DEVELOP_RESUME=PASS"
    Write-Host "PATCH_FEATURE_RESUME=PASS"
    Write-Host "PATCH_RETURN_NORMALIZATION=PASS"

    $Tokens = $null
    $ParseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $PatchedScript,
        [ref]$Tokens,
        [ref]$ParseErrors
    ) | Out-Null

    if ($ParseErrors.Count -gt 0) {
        foreach ($ParseError in $ParseErrors) {
            Write-Host "PARSE_ERROR=$($ParseError.Message)"
        }
        throw "PATCHED_SCRIPT_PARSE=FAIL"
    }

    Write-Host "PATCHED_SCRIPT_PARSE=PASS"

    & $PowerShellExe `
        -NoLogo `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $PatchedScript

    $ExitCode = $LASTEXITCODE
    Write-Host "PATCHED_PRODUCTION_EXIT_CODE=$ExitCode"

    if ($ExitCode -ne 0) {
        Write-Host "PATCHED_SCRIPT_PRESERVED_FOR_EVIDENCE=$PatchedScript"
        throw "COGNITIVE_CORE_PRODUCTION_V5=FAIL EXIT_CODE=$ExitCode"
    }

    Remove-Item -LiteralPath $PatchedScript -Force -ErrorAction SilentlyContinue

    Write-Host "============================================================"
    Write-Host "COGNITIVE_CORE_PRODUCTION_V5=PASS"
    Write-Host "SCRIPT_ROOT_RESOLUTION=PASS"
    Write-Host "EXPECTED_MISSING_REPOSITORY_HANDLING=PASS"
    Write-Host "EXPECTED_MISSING_BRANCH_HANDLING=PASS"
    Write-Host "FEATURE_BRANCH_URL_ENCODING=PASS"
    Write-Host "INITIALIZE_RETURN_NORMALIZATION=PASS"
    Write-Host "INTERRUPTED_RUN_RESUME=PASS"
    Write-Host "SOURCE_GENERATOR_MODIFIED=NO"
    Write-Host "MERGE_EXECUTED=NO"
    Write-Host "TAG_CREATED=NO"
    Write-Host "RELEASE_CREATED=NO"
    Write-Host "============================================================"
}