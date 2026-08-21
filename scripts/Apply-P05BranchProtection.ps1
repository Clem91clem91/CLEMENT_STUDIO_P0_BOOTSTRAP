[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$IncludeMain,
    [switch]$ResolveConfigOnly,
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ScriptFile = [string]$PSCommandPath
    if ([string]::IsNullOrWhiteSpace($ScriptFile)) {
        $ScriptFile = [string]$MyInvocation.MyCommand.Path
    }
    if ([string]::IsNullOrWhiteSpace($ScriptFile)) {
        throw "SCRIPT_PATH_UNAVAILABLE"
    }

    $ScriptDirectory = Split-Path -LiteralPath $ScriptFile -Parent
    if ([string]::IsNullOrWhiteSpace($ScriptDirectory)) {
        throw "SCRIPT_DIRECTORY_UNAVAILABLE path=$ScriptFile"
    }

    $RepositoryRoot = Split-Path -LiteralPath $ScriptDirectory -Parent
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        throw "REPOSITORY_ROOT_UNAVAILABLE script_directory=$ScriptDirectory"
    }

    $ConfigPath = Join-Path -Path $RepositoryRoot -ChildPath "config\p0_5_governance.json"
}

$ConfigPath = [System.IO.Path]::GetFullPath($ConfigPath)

function Invoke-GhJson {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$InputJson
    )

    if ($null -ne $InputJson) {
        $Output = $InputJson | & gh @Arguments 2>&1
    }
    else {
        $Output = & gh @Arguments 2>&1
    }

    if ($LASTEXITCODE -ne 0) {
        $Text = ($Output | Out-String).Trim()
        throw "GH_API_FAILED exit=$LASTEXITCODE args=$($Arguments -join ' ') output=$Text"
    }

    return (($Output | Out-String).Trim())
}

Write-Host "============================================================"
Write-Host "CLEMENT - P0.5 BRANCH PROTECTION"
Write-Host "============================================================"
Write-Host "MODE=$(if ($ResolveConfigOnly) { 'RESOLVE_CONFIG_ONLY' } elseif ($Apply) { 'APPLY' } else { 'DRY_RUN' })"
Write-Host "CONFIG=$ConfigPath"

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "CONFIG_NOT_FOUND=$ConfigPath"
}

if ($ResolveConfigOnly) {
    Write-Host "CONFIG_RESOLUTION=PASS"
    Write-Host "TAG_CREATED=NO"
    Write-Host "RELEASE_CREATED=NO"
    return
}

$Gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $Gh) {
    throw "GH_CLI_NOT_FOUND"
}

& gh auth status --hostname github.com 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "GH_AUTH_NOT_READY"
}

$Config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$Owner = [string]$Config.owner
$Check = [string]$Config.required_status_check
$Protection = $Config.branch_protection

$Branches = @([string]$Config.target_branch)
if ($IncludeMain -and ($Branches -notcontains "main")) {
    $Branches += "main"
}

$Applied = 0
$Verified = 0

foreach ($Repo in @($Config.repositories)) {
    $FullRepo = "$Owner/$Repo"

    foreach ($Branch in $Branches) {
        Write-Host "------------------------------------------------------------"
        Write-Host "REPOSITORY=$FullRepo"
        Write-Host "BRANCH=$Branch"

        $null = Invoke-GhJson -Arguments @(
            "api",
            "-H", "Accept: application/vnd.github+json",
            "-H", "X-GitHub-Api-Version: 2026-03-10",
            "repos/$FullRepo/branches/$Branch"
        )
        Write-Host "BRANCH_EXISTS=PASS"

        # These repositories are personal repositories. GitHub documents
        # dismissal_restrictions as organization-only, so it is omitted.
        $PayloadObject = [ordered]@{
            required_status_checks = [ordered]@{
                strict   = [bool]$Protection.strict_status_checks
                contexts = @($Check)
            }
            enforce_admins = [bool]$Protection.enforce_admins
            required_pull_request_reviews = [ordered]@{
                dismiss_stale_reviews = [bool]$Protection.dismiss_stale_reviews
                require_code_owner_reviews = [bool]$Protection.require_code_owner_reviews
                required_approving_review_count = [int]$Protection.required_approving_review_count
                require_last_push_approval = [bool]$Protection.require_last_push_approval
            }
            restrictions = $null
            required_linear_history = [bool]$Protection.required_linear_history
            allow_force_pushes = [bool]$Protection.allow_force_pushes
            allow_deletions = [bool]$Protection.allow_deletions
            block_creations = $false
            required_conversation_resolution = [bool]$Protection.required_conversation_resolution
            lock_branch = $false
            allow_fork_syncing = $true
        }

        $Payload = $PayloadObject | ConvertTo-Json -Depth 12 -Compress

        if (-not $Apply) {
            Write-Host "PROTECTION_APPLY=SKIPPED_DRY_RUN"
            Write-Host "REQUIRED_STATUS_CHECK=$Check"
            Write-Host "ENFORCE_ADMINS=$($Protection.enforce_admins)"
            Write-Host "REQUIRE_PULL_REQUEST=$($Protection.require_pull_request)"
            Write-Host "ALLOW_FORCE_PUSHES=$($Protection.allow_force_pushes)"
            Write-Host "ALLOW_DELETIONS=$($Protection.allow_deletions)"
            continue
        }

        try {
            $null = Invoke-GhJson -Arguments @(
                "api",
                "--method", "PUT",
                "-H", "Accept: application/vnd.github+json",
                "-H", "X-GitHub-Api-Version: 2026-03-10",
                "repos/$FullRepo/branches/$Branch/protection",
                "--input", "-"
            ) -InputJson $Payload
        }
        catch {
            $Message = $_.Exception.Message
            if ($Message -match "HTTP 403|status.*403|403") {
                throw "BRANCH_PROTECTION_BLOCKED repo=$FullRepo branch=$Branch reason=PLAN_OR_PERMISSION_REQUIRED details=$Message"
            }
            throw
        }

        $Applied++
        Write-Host "PROTECTION_APPLY=PASS"

        $VerifyText = Invoke-GhJson -Arguments @(
            "api",
            "-H", "Accept: application/vnd.github+json",
            "-H", "X-GitHub-Api-Version: 2026-03-10",
            "repos/$FullRepo/branches/$Branch/protection"
        )
        $Verify = $VerifyText | ConvertFrom-Json

        $Contexts = @($Verify.required_status_checks.contexts)
        if ($Contexts -notcontains $Check) {
            throw "REQUIRED_CHECK_NOT_APPLIED repo=$FullRepo branch=$Branch expected=$Check"
        }
        if (-not [bool]$Verify.enforce_admins.enabled) {
            throw "ENFORCE_ADMINS_NOT_APPLIED repo=$FullRepo branch=$Branch"
        }
        if ([bool]$Verify.allow_force_pushes.enabled) {
            throw "FORCE_PUSH_STILL_ALLOWED repo=$FullRepo branch=$Branch"
        }
        if ([bool]$Verify.allow_deletions.enabled) {
            throw "DELETION_STILL_ALLOWED repo=$FullRepo branch=$Branch"
        }

        $Verified++
        Write-Host "PROTECTION_VERIFY=PASS"
    }
}

Write-Host "============================================================"
Write-Host "P0_5_BRANCH_PROTECTION_DRY_RUN=$(if ($Apply) { 'NO' } else { 'PASS' })"
Write-Host "P0_5_BRANCH_PROTECTION_APPLIED=$Applied"
Write-Host "P0_5_BRANCH_PROTECTION_VERIFIED=$Verified"
Write-Host "TAG_CREATED=NO"
Write-Host "RELEASE_CREATED=NO"
Write-Host "============================================================"
