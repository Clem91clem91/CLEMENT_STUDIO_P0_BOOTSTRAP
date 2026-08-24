& {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $SourceScript = Join-Path $ScriptRoot "Start-ClementCognitiveCoreProduction.ps1"
    $PowerShellExe = (Get-Command powershell.exe -ErrorAction Stop).Source

    Write-Host "============================================================"
    Write-Host "CLEMENT STUDIO - COGNITIVE CORE PRODUCTION RUNNER V2"
    Write-Host "FIX=EXPECTED_MISSING_GITHUB_OBJECTS_ARE_NOT_FATAL"
    Write-Host "MERGE_ALLOWED=NO"
    Write-Host "TAG_ALLOWED=NO"
    Write-Host "RELEASE_ALLOWED=NO"
    Write-Host "============================================================"

    if (-not (Test-Path -LiteralPath $SourceScript -PathType Leaf)) {
        throw "SOURCE_PRODUCTION_SCRIPT_NOT_FOUND=$SourceScript"
    }

    $Source = Get-Content -LiteralPath $SourceScript -Raw -ErrorAction Stop

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

        # Missing repository is an expected control-flow state.
        # Keep gh stderr inside cmd.exe so Windows PowerShell 5.1 with
        # ErrorActionPreference=Stop does not convert it into a terminating
        # NativeCommandError before LASTEXITCODE can be inspected.
        & cmd.exe /d /s /c "gh repo view `"$FullName`" --json name 1>nul 2>nul"
        return ($LASTEXITCODE -eq 0)
    }

    function Remote-BranchExists {
        param([string]$FullName, [string]$Branch)

        # A missing branch is also expected while bootstrapping a new repo.
        & cmd.exe /d /s /c "gh api `"repos/$FullName/branches/$Branch`" 1>nul 2>nul"
        return ($LASTEXITCODE -eq 0)
    }

'@

    $Patched = $Source.Substring(0, $StartIndex) + $SafeFunctions + $Source.Substring($EndIndex)

    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $PatchedScript = Join-Path $env:TEMP "CLEMENT_CognitiveCoreProduction_patched_$Timestamp.ps1"
    $Utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PatchedScript, $Patched, $Utf8)

    Write-Host "SOURCE_SCRIPT=$SourceScript"
    Write-Host "PATCHED_SCRIPT=$PatchedScript"
    Write-Host "PATCH_STATUS=PASS"

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
        throw "COGNITIVE_CORE_PRODUCTION_V2=FAIL EXIT_CODE=$ExitCode"
    }

    Remove-Item -LiteralPath $PatchedScript -Force -ErrorAction SilentlyContinue

    Write-Host "============================================================"
    Write-Host "COGNITIVE_CORE_PRODUCTION_V2=PASS"
    Write-Host "EXPECTED_MISSING_REPOSITORY_HANDLING=PASS"
    Write-Host "EXPECTED_MISSING_BRANCH_HANDLING=PASS"
    Write-Host "SOURCE_GENERATOR_MODIFIED=NO"
    Write-Host "MERGE_EXECUTED=NO"
    Write-Host "TAG_CREATED=NO"
    Write-Host "RELEASE_CREATED=NO"
    Write-Host "============================================================"
}