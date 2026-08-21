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
$Bridge = Join-Path $PSScriptRoot "odysseus_cli_bridge.py"

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
if (-not (Test-Path -LiteralPath $Bridge)) {
    throw "ODYSSEUS_CLI_BRIDGE_NOT_FOUND=$Bridge"
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
Write-Host "ODYSSEUS_CLI_BRIDGE=$Bridge"
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

    $ExpectedArgs = @("-m", "clement_skills_mcp.server")
    $ArgsJson = ConvertTo-Json -InputObject $ExpectedArgs -Compress
    $EnvJson = ConvertTo-Json -InputObject @{ CLEMENT_SKILLS_HUB_ROOT = $Hub } -Compress

    if ($Matches.Count -eq 1) {
        $Id = [string]$Matches[0].id
        Write-Host "CONFIG_ACTION=EXISTING_VERIFY"
        Write-Host "SERVER_ID=$Id"
    }
    else {
        $ArgvFile = Join-Path $env:TEMP ("CLEMENT_ODYSSEUS_MCP_ADD_{0}.json" -f ([guid]::NewGuid().ToString("N")))
        try {
            $StructuredArgv = @(
                "add",
                "--name", $Name,
                "--transport", "stdio",
                "--command", $P002Python,
                "--args", $ArgsJson,
                "--env", $EnvJson
            )
            $StructuredJson = ConvertTo-Json -InputObject $StructuredArgv -Compress
            Set-Content -LiteralPath $ArgvFile -Value $StructuredJson -Encoding UTF8

            Write-Host "ADD_TRANSPORT=STRUCTURED_ARGV_FILE"
            Write-Host "ARGV_BRIDGE=PASS"

            $RawAdd = @(& $OdysseusPython $Bridge --cli $Cli --argv-file $ArgvFile)
            if ($LASTEXITCODE -ne 0) { throw "ODYSSEUS_MCP_ADD_FAILED" }
            $Added = (($RawAdd -join "`n").Trim()) | ConvertFrom-Json
            $Id = [string]$Added.id
            if (-not $Id) { throw "ODYSSEUS_MCP_ID_NOT_RETURNED" }

            Write-Host "CONFIG_ACTION=CREATED"
            Write-Host "SERVER_ID=$Id"
        }
        finally {
            Remove-Item -LiteralPath $ArgvFile -Force -ErrorAction SilentlyContinue
        }
    }

    $RawShow = @(& $OdysseusPython $Cli show $Id --reveal)
    if ($LASTEXITCODE -ne 0) { throw "ODYSSEUS_MCP_SHOW_FAILED=$Id" }
    $Show = (($RawShow -join "`n").Trim()) | ConvertFrom-Json

    Write-Host "VERIFY_COMMAND=$($Show.command)"
    Write-Host "VERIFY_ARGS=$((ConvertTo-Json -InputObject @($Show.args) -Compress))"
    Write-Host "VERIFY_HUB=$($Show.env.CLEMENT_SKILLS_HUB_ROOT)"

    $Mismatch = @()
    if ([string]$Show.command -ne $P002Python) {
        $Mismatch += "COMMAND"
    }

    $ActualArgs = @($Show.args)
    if ($ActualArgs.Count -ne 2 -or [string]$ActualArgs[0] -ne "-m" -or [string]$ActualArgs[1] -ne "clement_skills_mcp.server") {
        $Mismatch += "ARGS"
    }

    $ActualHub = [string]$Show.env.CLEMENT_SKILLS_HUB_ROOT
    if ($ActualHub -ne $Hub) {
        $Mismatch += "ENV_CLEMENT_SKILLS_HUB_ROOT"
    }

    if ($Mismatch.Count -gt 0) {
        Write-Host "RESULT=PARTIAL"
        Write-Host "CAUSE=EXISTING_CONFIGURATION_MISMATCH"
        Write-Host "MISMATCH=$($Mismatch -join ',')"
        Write-Host "EXPECTED_COMMAND=$P002Python"
        Write-Host "EXPECTED_ARGS=$ArgsJson"
        Write-Host "EXPECTED_HUB=$Hub"
        Write-Host "AUTOMATIC_DELETE=NO"
        Write-Host "AUTOMATIC_REPLACE=NO"
        exit 2
    }

    if (-not [bool]$Show.is_enabled) {
        & $OdysseusPython $Cli enable $Id | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "ODYSSEUS_MCP_ENABLE_FAILED=$Id" }
        Write-Host "SERVER_ENABLED=YES"
    }

    Write-Host "CONFIG_VERIFICATION=PASS"
    Write-Host "RESULT=PASS"
    Write-Host "ODYSSEUS_MCP_CONFIG=PASS"
    Write-Host "SECURITY_SETTINGS_CHANGED=NO"
    Write-Host "PROCESS_KILLED=NO"
    Write-Host "RESTART_EXECUTED=NO"
    Write-Host "RESTART_REQUIRED=YES"
    Write-Host "SERVER_ID=$Id"
    Write-Host "NEXT=RESTART_ODYSSEUS_THEN_VERIFY_9_TOOLS"
}
finally {
    Pop-Location
}
