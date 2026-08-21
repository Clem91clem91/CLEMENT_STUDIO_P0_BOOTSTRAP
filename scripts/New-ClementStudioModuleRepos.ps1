param(
    [string]$Owner = "Clem91clem91",
    [ValidateSet("private", "public")][string]$Visibility = "private",
    [string]$Workspace = "C:\Users\Shadow\Documents\CLEMENT_STUDIO\04_TOOLS",
    [switch]$ApplyProtection,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$ScriptFile = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($ScriptFile)) { $ScriptFile = $MyInvocation.MyCommand.Path }
if ([string]::IsNullOrWhiteSpace($ScriptFile)) { throw "SCRIPT_PATH_UNRESOLVED" }
$BootstrapRoot = Split-Path -Path (Split-Path -Path $ScriptFile -Parent) -Parent
$ManifestPath = Join-Path $BootstrapRoot "config\module_repositories.json"

function Assert-Command {
    param([Parameter(Mandatory=$true)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "COMMAND_NOT_FOUND=$Name"
    }
    Write-Host "COMMAND=$Name STATUS=PASS"
}

function Invoke-Git {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [Parameter(Mandatory=$true)][string]$Failure
    )
    & git -C $Path @Arguments
    if ($LASTEXITCODE -ne 0) { throw $Failure }
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $Directory = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function New-ModuleScaffold {
    param(
        [Parameter(Mandatory=$true)]$Module,
        [Parameter(Mandatory=$true)][string]$LocalPath
    )

    $Repo = [string]$Module.repository
    $Package = [string]$Module.package
    $Description = [string]$Module.description
    $ProjectName = $Repo.ToLowerInvariant().Replace("_", "-")
    $PackagePath = Join-Path $LocalPath ("src\" + $Package)

    $Readme = @"
# $Repo

$Description

## CLEMENT STUDIO contract

This repository is an independently versioned CLEMENT STUDIO module.

Core rules:
- GitHub-first development.
- `develop` is the integration branch.
- feature work uses `feat/*` branches.
- `governance-gate` is the required CI gate.
- no merge, tag or release without explicit user authorization.
- machine evidence outranks model narrative.
- `NO EVIDENCE -> NO PASS` for operational claims.

Initial phase: $($Module.phase)
"@

    $PyProject = @"
[build-system]
requires = ["setuptools>=75", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "$ProjectName"
version = "0.1.0"
description = "$Description"
requires-python = ">=3.11"

[project.optional-dependencies]
dev = ["pytest>=8,<9"]

[tool.pytest.ini_options]
testpaths = ["tests"]

[tool.setuptools.packages.find]
where = ["src"]
"@

    $Init = @"
from __future__ import annotations

__version__ = "0.1.0"
"@

    $Contracts = @"
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class ModuleVerdict(str, Enum):
    PASS = "PASS"
    PARTIAL = "PARTIAL"
    FAIL = "FAIL"
    INCONCLUSIVE = "INCONCLUSIVE"


@dataclass(frozen=True, slots=True)
class ModuleIdentity:
    repository: str = "$Repo"
    package: str = "$Package"
    phase: str = "$($Module.phase)"
    capabilities: tuple[str, ...] = ()
    metadata: dict[str, Any] = field(default_factory=dict)


def module_status() -> dict[str, Any]:
    identity = ModuleIdentity()
    return {
        "repository": identity.repository,
        "package": identity.package,
        "phase": identity.phase,
        "status": "SCAFFOLD_READY",
        "verdict": ModuleVerdict.PASS.value,
    }
"@

    $Test = @"
from $Package.contracts import module_status


def test_module_contract() -> None:
    status = module_status()
    assert status["repository"] == "$Repo"
    assert status["package"] == "$Package"
    assert status["status"] == "SCAFFOLD_READY"
    assert status["verdict"] == "PASS"
"@

    $ModuleJson = $Module | ConvertTo-Json -Depth 12

    $Roadmap = @"
# $Repo roadmap

## Purpose

$Description

## Dependencies

$([string]::Join("`n", @($Module.depends_on | ForEach-Object { "- $_" })))

## Delivery discipline

1. Contract-first implementation.
2. Unit tests before Shadow integration.
3. Windows and Ubuntu CI on Python 3.11 and 3.13.
4. Real Shadow E2E when the module touches local applications or hardware.
5. Evidence and provenance for external side effects.
6. Draft PR before certification.
7. No merge/tag/release without explicit user authorization.
"@

    $Workflow = @'
name: module-ci

on:
  workflow_dispatch:
  pull_request:
    branches: [main, develop]
  push:
    branches: [main, develop, "feat/**", "fix/**", "chore/**"]

permissions:
  contents: read

jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        os: [windows-latest, ubuntu-latest]
        python-version: ["3.11", "3.13"]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
      - name: Install
        run: python -m pip install -e ".[dev]"
      - name: Compile
        run: python -m compileall -q src tests
      - name: Test
        run: python -m pytest

  governance-gate:
    name: governance-gate
    if: ${{ always() }}
    needs: [test]
    runs-on: ubuntu-latest
    steps:
      - name: Enforce CI matrix success
        shell: bash
        run: test "${{ needs.test.result }}" = "success"
'@

    Write-Utf8NoBom -Path (Join-Path $LocalPath "README.md") -Content $Readme
    Write-Utf8NoBom -Path (Join-Path $LocalPath "pyproject.toml") -Content $PyProject
    Write-Utf8NoBom -Path (Join-Path $LocalPath "module.json") -Content $ModuleJson
    Write-Utf8NoBom -Path (Join-Path $PackagePath "__init__.py") -Content $Init
    Write-Utf8NoBom -Path (Join-Path $PackagePath "contracts.py") -Content $Contracts
    Write-Utf8NoBom -Path (Join-Path $LocalPath "tests\test_contract.py") -Content $Test
    Write-Utf8NoBom -Path (Join-Path $LocalPath "docs\ROADMAP.md") -Content $Roadmap
    Write-Utf8NoBom -Path (Join-Path $LocalPath ".github\workflows\ci.yml") -Content $Workflow
}

function Set-DevelopProtection {
    param([Parameter(Mandatory=$true)][string]$FullRepo)
    $Payload = @{
        required_status_checks = @{ strict = $true; contexts = @("governance-gate") }
        enforce_admins = $true
        required_pull_request_reviews = $null
        restrictions = $null
        allow_force_pushes = $false
        allow_deletions = $false
    } | ConvertTo-Json -Depth 8 -Compress

    $Temp = Join-Path $env:TEMP ("clement-protection-" + [guid]::NewGuid().ToString("N") + ".json")
    try {
        [System.IO.File]::WriteAllText($Temp, $Payload, (New-Object System.Text.UTF8Encoding($false)))
        & gh api --method PUT -H "Accept: application/vnd.github+json" "repos/$FullRepo/branches/develop/protection" --input $Temp
        if ($LASTEXITCODE -ne 0) {
            Write-Host "BRANCH_PROTECTION=$FullRepo PARTIAL reason=GitHub_plan_or_api_restriction"
            return
        }
        Write-Host "BRANCH_PROTECTION=$FullRepo PASS"
    }
    finally {
        Remove-Item -LiteralPath $Temp -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "============================================================"
Write-Host "CLEMENT STUDIO - MODULAR REPOSITORY BOOTSTRAP"
Write-Host "============================================================"
Write-Host "VISIBILITY=$Visibility"
Write-Host "WORKSPACE=$Workspace"
Write-Host "DRY_RUN=$($DryRun.IsPresent)"

Assert-Command "gh"
Assert-Command "git"

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "MODULE_MANIFEST_NOT_FOUND=$ManifestPath"
}

& gh auth status --hostname github.com
if ($LASTEXITCODE -ne 0) { throw "GITHUB_AUTH=FAIL" }
Write-Host "GITHUB_AUTH=PASS"

$Manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$Modules = @($Manifest.modules | Sort-Object order)
if ($Modules.Count -eq 0) { throw "MODULE_MANIFEST_EMPTY" }

New-Item -ItemType Directory -Path $Workspace -Force | Out-Null
$Created = 0
$Existing = 0

foreach ($Module in $Modules) {
    $Repo = [string]$Module.repository
    $FullRepo = "$Owner/$Repo"
    $LocalPath = Join-Path $Workspace $Repo

    Write-Host "------------------------------------------------------------"
    Write-Host "MODULE=$($Module.key)"
    Write-Host "REPOSITORY=$FullRepo"
    Write-Host "PHASE=$($Module.phase)"

    & gh repo view $FullRepo --json name,visibility,defaultBranchRef *> $null
    if ($LASTEXITCODE -eq 0) {
        $Existing++
        Write-Host "REPOSITORY_STATUS=EXISTS"
        Write-Host "MUTATION=SKIPPED_EXISTING_REPOSITORY"
        continue
    }

    if ($DryRun) {
        Write-Host "REPOSITORY_STATUS=WOULD_CREATE"
        continue
    }

    $CreateArgs = @("repo", "create", $FullRepo, "--description", [string]$Module.description, "--add-readme")
    if ($Visibility -eq "public") { $CreateArgs += "--public" } else { $CreateArgs += "--private" }
    & gh @CreateArgs
    if ($LASTEXITCODE -ne 0) { throw "REPOSITORY_CREATE_FAILED=$FullRepo" }
    $Created++
    Write-Host "REPOSITORY_CREATE=PASS"

    if (Test-Path -LiteralPath $LocalPath) {
        throw "LOCAL_PATH_ALREADY_EXISTS_FOR_NEW_REPO=$LocalPath"
    }

    & gh repo clone $FullRepo $LocalPath
    if ($LASTEXITCODE -ne 0) { throw "REPOSITORY_CLONE_FAILED=$FullRepo" }

    Invoke-Git -Path $LocalPath -Arguments @("switch", "-c", "develop") -Failure "DEVELOP_CREATE_FAILED=$FullRepo"
    New-ModuleScaffold -Module $Module -LocalPath $LocalPath

    Invoke-Git -Path $LocalPath -Arguments @("config", "user.name", $Owner) -Failure "GIT_USER_NAME_FAILED=$FullRepo"
    Invoke-Git -Path $LocalPath -Arguments @("config", "user.email", "$Owner@users.noreply.github.com") -Failure "GIT_USER_EMAIL_FAILED=$FullRepo"
    Invoke-Git -Path $LocalPath -Arguments @("add", "--", "README.md", "pyproject.toml", "module.json", ".github", "src", "tests", "docs") -Failure "GIT_STAGE_FAILED=$FullRepo"
    Invoke-Git -Path $LocalPath -Arguments @("commit", "-m", "chore: bootstrap CLEMENT STUDIO module") -Failure "GIT_COMMIT_FAILED=$FullRepo"
    Invoke-Git -Path $LocalPath -Arguments @("push", "-u", "origin", "develop") -Failure "DEVELOP_PUSH_FAILED=$FullRepo"

    $Head = (& git -C $LocalPath rev-parse HEAD).Trim()
    Write-Host "DEVELOP_HEAD=$Head"
    Write-Host "SCAFFOLD=PASS"

    if ($ApplyProtection) {
        Set-DevelopProtection -FullRepo $FullRepo
    }
}

Write-Host "============================================================"
Write-Host "CLEMENT STUDIO - MODULAR REPOSITORY RESULT"
Write-Host "============================================================"
Write-Host "MODULE_COUNT=$($Modules.Count)"
Write-Host "CREATED=$Created"
Write-Host "EXISTING_SKIPPED=$Existing"
Write-Host "MERGE_EXECUTED=NO"
Write-Host "TAG_CREATED=NO"
Write-Host "RELEASE_CREATED=NO"
Write-Host "NEXT=DEVELOP_FEATURE_BRANCHES_AND_DRAFT_PRS"
Write-Host "============================================================"
