param(
    [string]$OdysseusRoot = "C:\Users\Shadow\ODYSSEUS",
    [string]$ToolsRoot = "C:\Users\Shadow\Documents\CLEMENT_STUDIO\04_TOOLS"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Name = "CLEMENT Skills MCP"
$P002 = Join-Path $ToolsRoot "CLEMENT_STUDIO_SKILLS_MCP"
$Hub = Join-Path $ToolsRoot "CLEMENT_STUDIO_SKILLS_HUB"
$P002Python = Join-Path $P002 ".venv\Scripts\python.exe"
$Cli = Join-Path $OdysseusRoot "scripts\odysseus-mcp"

Write-Host "============================================================"
Write-Host "CLEMENT - TRUSTED ODYSSEUS P0-02 REGISTRATION"
Write-Host "============================================================"

if (-not (Test-Path -LiteralPath $P002Python)) {
    throw "P0_02_PYTHON_NOT_FOUND=$P002Python"
}
if (-not (Test-Path -LiteralPath $Hub)) {
    throw "SKILLS_HUB_NOT_FOUND=$Hub"
}
if (-not (Test-Path -LiteralPath $Cli)) {
    throw "ODYSSEUS_MCP_CLI_NOT_FOUND=$Cli"
}

$PythonCandidates = @(
    (Join-Path $OdysseusRoot ".venv\Scripts\python.exe"),
    (Join-Path $OdysseusRoot "venv\Scripts\python.exe")
)

try {
    $Listener = Get-NetTCPConnection -LocalPort 7000 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Listener) {
        $Process = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $Listener.OwningProcess) -ErrorAction SilentlyContinue
        if ($Process -and $Process.ExecutablePath) {
            $PythonCandidates += [string]$Process.ExecutablePath
        }
    }
}
catch {}

$OdysseusPython = $PythonCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
if (-not $OdysseusPython) {
    throw "ODYSSEUS_PYTHON_NOT_FOUND"
}

Write-Host "ODYSSEUS_PYTHON=$OdysseusPython"
Write-Host "ODYSSEUS_CLI=$Cli"
Write-Host "P0_02_PYTHON=$P002Python"
Write-Host "SKILLS_HUB=$Hub"

Push-Location $OdysseusRoot
try {
    $RawList = @(& $OdysseusPython $Cli list)
    if ($LASTEXITCODE -ne 0) {
        throw "ODYSSEUS_MCP_LIST_FAILED"
    }
    $ListText = ($RawList -join "`n").Trim()
    $Servers = @()
    if ($ListText) {
        $Parsed = $ListText | ConvertFrom-Json
        $Servers = @($Parsed)
    }

    $Matches = @($Servers | Where-Object { $_.name -eq $Name })
    Write-Host "MATCHING_SERVERS=$($Matches.Count)"

    if ($Matches.Count -gt 1) {
        foreach ($Item in $Matches) {
            Write-Host "DUPLICATE_ID=$($Item.id)"
        }
        throw "DUPLICATE_CLEMENT_SKILLS_MCP"
    }

    $ArgsJson = ConvertTo-Json -InputObject @("-m", "clement_skills_mcp.server") -Compress
    $EnvJson = ConvertTo-Json -InputObject @{ CLEMENT_SKILLS_HUB_ROOT = $Hub } -Compress

    if ($Matches.Count -eq 1) {
        $Id = [string]$Matches[0].id
        $RawShow = @(& $OdysseusPython $Cli show $Id --reveal)
        if ($LASTEXITCODE -ne 0) { throw "ODYSSEUS_MCP_SHOW_FAILED=$Id" }
        $Show = (($RawShow -join "`n").Trim()) | ConvertFrom-Json

        Write-Host "EXISTING_SERVER_ID=$Id"
        Write-Host "EXISTING_COMMAND=$($Show.command)"

        if ([string]$Show.command -ne $P002Python) {
            Write-Host "RESULT=PARTIAL"
            Write-Host "CAUSE=EXISTING_COMMAND_MISMATCH"
            Write-Host "EXPECTED_COMMAND=$P002Python"
            Write-Host "ACTUAL_COMMAND=$($Show.command)"
            Write-Host "AUTOMATIC_DELETE=NO"
            Write-Host "AUTOMATIC_REPLACE=NO"
            exit 2
        }

        if (-not [bool]$Show.is_enabled) {
            & $OdysseusPython $Cli enable $Id | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "ODYSSEUS_MCP_ENABLE_FAILED=$Id" }
        }

        Write-Host "CONFIG_ACTION=EXISTING_VALID"
        Write-Host "SERVER_ID=$Id"
    }
    else {
        $RawAdd = @(
            & $OdysseusPython $Cli add `
                --name $Name `
                --transport stdio `
                --command $P002Python `
                --args $ArgsJson `
                --env $EnvJson
        )
        if ($LASTEXITCODE -ne 0) { throw "ODYSSEUS_MCP_ADD_FAILED" }
        $Added = (($RawAdd -join "`n").Trim()) | ConvertFrom-Json
        $Id = [string]$Added.id
        if (-not $Id) { throw "ODYSSEUS_MCP_ID_NOT_RETURNED" }
        Write-Host "CONFIG_ACTION=CREATED"
        Write-Host "SERVER_ID=$Id"
    }

    Write-Host "RESULT=PASS"
    Write-Host "ODYSSEUS_MCP_CONFIG=PASS"
    Write-Host "SECURITY_SETTINGS_CHANGED=NO"
    Write-Host "PROCESS_KILLED=NO"
    Write-Host "RESTART_EXECUTED=NO"
    Write-Host "RESTART_REQUIRED=YES"
    Write-Host "NEXT=RESTART_ODYSSEUS_THEN_VERIFY_9_TOOLS"
}
finally {
    Pop-Location
}
