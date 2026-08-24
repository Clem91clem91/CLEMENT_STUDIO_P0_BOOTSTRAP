& {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    # ============================================================
    # CLEMENT STUDIO - COGNITIVE CORE PRODUCTION RUNNER V7
    #
    # Design rule:
    #   NEVER invoke git.exe / gh.exe / python.exe with PowerShell '&'.
    #   Windows PowerShell 5.1 can convert native stderr into a
    #   NativeCommandError even when the native exit code is 0.
    #
    # Native processes are therefore executed exclusively through
    # System.Diagnostics.Process with stdout/stderr redirected.
    # ExitCode is the only native PASS/FAIL authority.
    #
    # This runner is resume-safe and does not merge/tag/release.
    # ============================================================

    $Owner = "Clem91clem91"
    $ToolsRoot = "C:\Users\Shadow\Documents\CLEMENT_STUDIO\04_TOOLS"
    $OdysseusPython = "C:\Users\Shadow\ODYSSEUS\venv\Scripts\python.exe"

    $ScriptRoot = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($ScriptRoot)) {
        if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
            throw "SCRIPT_ROOT_RESOLUTION_FAILED"
        }
        $ScriptRoot = Split-Path -Parent $PSCommandPath
    }

    $SourceScript = Join-Path $ScriptRoot "Start-ClementCognitiveCoreProduction.ps1"

    Write-Host "============================================================"
    Write-Host "CLEMENT STUDIO - COGNITIVE CORE PRODUCTION RUNNER V7"
    Write-Host "NATIVE_EXECUTION=SYSTEM_DIAGNOSTICS_PROCESS"
    Write-Host "NATIVE_STDERR=DATA_NOT_POWERSHELL_ERROR"
    Write-Host "NATIVE_EXIT_CODE_AUTHORITATIVE=YES"
    Write-Host "RESUME_SAFE=YES"
    Write-Host "MERGE_ALLOWED=NO"
    Write-Host "TAG_ALLOWED=NO"
    Write-Host "RELEASE_ALLOWED=NO"
    Write-Host "============================================================"

    # ------------------------------------------------------------
    # Native process layer
    # ------------------------------------------------------------

    function ConvertTo-NativeArgument {
        param([AllowNull()][string]$Value)

        if ($null -eq $Value -or $Value.Length -eq 0) {
            return '""'
        }

        if ($Value -notmatch '[\s"]') {
            return $Value
        }

        # Arguments used by this production runner do not contain embedded
        # command-shell metacharacters. Escape embedded quotes defensively.
        return '"' + $Value.Replace('"', '\"') + '"'
    }

    function Invoke-NativeProcess {
        param(
            [Parameter(Mandatory=$true)][string]$FilePath,
            [string[]]$Arguments = @(),
            [switch]$AllowFailure,
            [switch]$ShowOutput,
            [string]$WorkingDirectory
        )

        if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
            throw "NATIVE_EXECUTABLE_NOT_FOUND=$FilePath"
        }

        $Psi = New-Object System.Diagnostics.ProcessStartInfo
        $Psi.FileName = $FilePath
        $Psi.Arguments = (($Arguments | ForEach-Object { ConvertTo-NativeArgument ([string]$_) }) -join ' ')
        $Psi.UseShellExecute = $false
        $Psi.RedirectStandardOutput = $true
        $Psi.RedirectStandardError = $true
        $Psi.CreateNoWindow = $true

        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            $Psi.WorkingDirectory = $WorkingDirectory
        }

        $Process = New-Object System.Diagnostics.Process
        $Process.StartInfo = $Psi

        try {
            if (-not $Process.Start()) {
                throw "NATIVE_PROCESS_START_FAILED=$FilePath"
            }

            $StdOut = $Process.StandardOutput.ReadToEnd()
            $StdErr = $Process.StandardError.ReadToEnd()
            $Process.WaitForExit()
            $ExitCode = $Process.ExitCode
        }
        finally {
            $Process.Dispose()
        }

        $OutLines = @()
        if (-not [string]::IsNullOrWhiteSpace($StdOut)) {
            $OutLines = @($StdOut -split "`r?`n" | Where-Object { $_ -ne '' })
        }

        $ErrLines = @()
        if (-not [string]::IsNullOrWhiteSpace($StdErr)) {
            $ErrLines = @($StdErr -split "`r?`n" | Where-Object { $_ -ne '' })
        }

        if ($ShowOutput) {
            foreach ($Line in $OutLines) { Write-Host $Line }
            foreach ($Line in $ErrLines) { Write-Host $Line }
        }

        if (($ExitCode -ne 0) -and (-not $AllowFailure)) {
            Write-Host "NATIVE_FAILURE_BEGIN"
            Write-Host "FILE=$FilePath"
            Write-Host "ARGS=$($Arguments -join ' ')"
            Write-Host "EXIT_CODE=$ExitCode"
            foreach ($Line in $OutLines) { Write-Host "STDOUT=$Line" }
            foreach ($Line in $ErrLines) { Write-Host "STDERR=$Line" }
            Write-Host "NATIVE_FAILURE_END"
            throw "NATIVE_COMMAND_FAILED file=$FilePath exit=$ExitCode"
        }

        return [PSCustomObject]@{
            ExitCode = $ExitCode
            StdOut = $StdOut
            StdErr = $StdErr
            Output = $OutLines
            ErrorOutput = $ErrLines
        }
    }

    $GitExe = (Get-Command git.exe -ErrorAction Stop).Source
    $GhExe = (Get-Command gh.exe -ErrorAction Stop).Source

    if (-not (Test-Path -LiteralPath $OdysseusPython -PathType Leaf)) {
        throw "ODYSSEUS_PYTHON_NOT_FOUND=$OdysseusPython"
    }

    Write-Host "GIT_EXE=$GitExe"
    Write-Host "GH_EXE=$GhExe"
    Write-Host "PYTHON_EXE=$OdysseusPython"

    # ------------------------------------------------------------
    # Basic helpers
    # ------------------------------------------------------------

    $Utf8 = New-Object System.Text.UTF8Encoding($false)

    function Write-TextFile {
        param([string]$Path, [string]$Content)
        $Parent = Split-Path -Parent $Path
        if ($Parent) {
            New-Item -ItemType Directory -Path $Parent -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($Path, $Content, $Utf8)
    }

    function Invoke-Git {
        param(
            [string]$RepoPath,
            [Parameter(ValueFromRemainingArguments=$true)][string[]]$Args,
            [switch]$AllowFailure,
            [switch]$ShowOutput
        )

        $AllArgs = @('-C', $RepoPath) + @($Args)
        return Invoke-NativeProcess -FilePath $GitExe -Arguments $AllArgs -AllowFailure:$AllowFailure -ShowOutput:$ShowOutput
    }

    function Invoke-Gh {
        param(
            [Parameter(ValueFromRemainingArguments=$true)][string[]]$Args,
            [switch]$AllowFailure,
            [switch]$ShowOutput
        )

        return Invoke-NativeProcess -FilePath $GhExe -Arguments $Args -AllowFailure:$AllowFailure -ShowOutput:$ShowOutput
    }

    function Remote-RepoExists {
        param([string]$FullName)
        $Result = Invoke-Gh -Args @('repo','view',$FullName,'--json','name') -AllowFailure
        return ($Result.ExitCode -eq 0)
    }

    function Remote-BranchExists {
        param([string]$FullName, [string]$Branch)
        $Encoded = [System.Uri]::EscapeDataString($Branch)
        $Result = Invoke-Gh -Args @('api',"repos/$FullName/branches/$Encoded") -AllowFailure
        return ($Result.ExitCode -eq 0)
    }

    function Local-BranchExists {
        param([string]$RepoPath, [string]$Branch)
        $Result = Invoke-Git -RepoPath $RepoPath -Args @('branch','--list',$Branch)
        return (-not [string]::IsNullOrWhiteSpace($Result.StdOut))
    }

    function Get-CurrentBranch {
        param([string]$RepoPath)
        $Result = Invoke-Git -RepoPath $RepoPath -Args @('branch','--show-current')
        return $Result.StdOut.Trim()
    }

    function Get-GitHead {
        param([string]$RepoPath)
        $Result = Invoke-Git -RepoPath $RepoPath -Args @('rev-parse','HEAD')
        return $Result.StdOut.Trim()
    }

    function Get-GitDirtyLines {
        param([string]$RepoPath)
        $Result = Invoke-Git -RepoPath $RepoPath -Args @('status','--porcelain')
        if ([string]::IsNullOrWhiteSpace($Result.StdOut)) { return @() }
        return @($Result.StdOut -split "`r?`n" | Where-Object { $_ -ne '' })
    }

    # ------------------------------------------------------------
    # Load only deterministic code-generation functions from the
    # source generator. Native orchestration from that legacy script
    # is deliberately NOT executed.
    # ------------------------------------------------------------

    if (-not (Test-Path -LiteralPath $SourceScript -PathType Leaf)) {
        throw "SOURCE_GENERATOR_NOT_FOUND=$SourceScript"
    }

    $Tokens = $null
    $ParseErrors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $SourceScript,
        [ref]$Tokens,
        [ref]$ParseErrors
    )

    if ($ParseErrors.Count -gt 0) {
        foreach ($ParseError in $ParseErrors) {
            Write-Host "SOURCE_PARSE_ERROR=$($ParseError.Message)"
        }
        throw "SOURCE_GENERATOR_PARSE=FAIL"
    }

    $NeededFunctions = @(
        'Write-CommonFiles',
        'Build-CoreRepo',
        'Build-IntentRepo',
        'Build-KnowledgeRepo'
    )

    foreach ($FunctionName in $NeededFunctions) {
        $Node = $Ast.Find({
            param($AstNode)
            ($AstNode -is [System.Management.Automation.Language.FunctionDefinitionAst]) -and
            ($AstNode.Name -eq $FunctionName)
        }, $true)

        if ($null -eq $Node) {
            throw "GENERATOR_FUNCTION_NOT_FOUND=$FunctionName"
        }

        Invoke-Expression $Node.Extent.Text
        Write-Host "GENERATOR_FUNCTION_LOADED=$FunctionName"
    }

    # ------------------------------------------------------------
    # GitHub auth
    # ------------------------------------------------------------

    Write-Host ""
    Write-Host "=== GITHUB_AUTH ==="
    $Auth = Invoke-Gh -Args @('auth','status') -ShowOutput
    Write-Host "GITHUB_AUTH=PASS"

    New-Item -ItemType Directory -Path $ToolsRoot -Force | Out-Null

    # ------------------------------------------------------------
    # Repository preparation - fully idempotent/resume-safe
    # ------------------------------------------------------------

    function Initialize-RepositoryV7 {
        param(
            [string]$Name,
            [string]$Description,
            [string]$FeatureBranch
        )

        $FullName = "$Owner/$Name"
        $RepoPath = Join-Path $ToolsRoot $Name

        Write-Host ""
        Write-Host "=== REPOSITORY_PREPARE=$Name ==="

        $RemoteExists = Remote-RepoExists $FullName
        Write-Host "REMOTE_EXISTS=$RemoteExists"

        if (-not $RemoteExists) {
            Invoke-Gh -Args @('repo','create',$FullName,'--private','--description',$Description) -ShowOutput | Out-Null
            Write-Host "REPOSITORY_CREATED=$FullName"
            $RemoteExists = $true
        }

        if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
            Invoke-Gh -Args @('repo','clone',$FullName,$RepoPath) -ShowOutput | Out-Null
            Write-Host "LOCAL_CLONE_CREATED=$RepoPath"
        }

        if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git') -PathType Container)) {
            throw "LOCAL_NOT_GIT_REPOSITORY=$RepoPath"
        }

        # If the remote was empty when cloned, create the main baseline now.
        $HeadCheck = Invoke-Git -RepoPath $RepoPath -Args @('rev-parse','--verify','HEAD') -AllowFailure
        if ($HeadCheck.ExitCode -ne 0) {
            Write-TextFile (Join-Path $RepoPath 'README.md') "# $Name`r`n`r`nCLEMENT STUDIO cognitive foundation repository.`r`n"
            Invoke-Git -RepoPath $RepoPath -Args @('add','README.md') | Out-Null
            Invoke-Git -RepoPath $RepoPath -Args @('commit','-m','chore: initialize repository') -ShowOutput | Out-Null
            Invoke-Git -RepoPath $RepoPath -Args @('branch','-M','main') | Out-Null
            Invoke-Git -RepoPath $RepoPath -Args @('push','-u','origin','main') -ShowOutput | Out-Null
            Write-Host "MAIN_BASELINE_CREATED=$Name"
        }

        Invoke-Git -RepoPath $RepoPath -Args @('fetch','origin','--prune') -ShowOutput | Out-Null

        $Dirty = @(Get-GitDirtyLines $RepoPath)
        $CurrentBranch = Get-CurrentBranch $RepoPath
        Write-Host "CURRENT_BRANCH_BEFORE_PREPARE=$CurrentBranch"
        Write-Host "DIRTY_COUNT_BEFORE_PREPARE=$($Dirty.Count)"

        if ($Dirty.Count -gt 0 -and $CurrentBranch -ne $FeatureBranch) {
            foreach ($Line in $Dirty) { Write-Host "DIRTY=$Line" }
            throw "LOCAL_WORKTREE_DIRTY_OUTSIDE_FEATURE=$Name"
        }

        # DEVELOP
        if (Remote-BranchExists $FullName 'develop') {
            if (Local-BranchExists $RepoPath 'develop') {
                Invoke-Git -RepoPath $RepoPath -Args @('switch','develop') -ShowOutput | Out-Null
            }
            else {
                Invoke-Git -RepoPath $RepoPath -Args @('switch','-c','develop','--track','origin/develop') -ShowOutput | Out-Null
            }
            Invoke-Git -RepoPath $RepoPath -Args @('pull','--ff-only','origin','develop') -ShowOutput | Out-Null
        }
        else {
            if (Local-BranchExists $RepoPath 'main') {
                Invoke-Git -RepoPath $RepoPath -Args @('switch','main') -ShowOutput | Out-Null
            }
            else {
                Invoke-Git -RepoPath $RepoPath -Args @('switch','-c','main','--track','origin/main') -ShowOutput | Out-Null
            }
            Invoke-Git -RepoPath $RepoPath -Args @('pull','--ff-only','origin','main') -ShowOutput | Out-Null

            if (Local-BranchExists $RepoPath 'develop') {
                Invoke-Git -RepoPath $RepoPath -Args @('switch','develop') -ShowOutput | Out-Null
            }
            else {
                Invoke-Git -RepoPath $RepoPath -Args @('switch','-c','develop') -ShowOutput | Out-Null
            }
            Invoke-Git -RepoPath $RepoPath -Args @('push','-u','origin','develop') -ShowOutput | Out-Null
        }

        # FEATURE
        if (Remote-BranchExists $FullName $FeatureBranch) {
            if (Local-BranchExists $RepoPath $FeatureBranch) {
                Invoke-Git -RepoPath $RepoPath -Args @('switch',$FeatureBranch) -ShowOutput | Out-Null
            }
            else {
                Invoke-Git -RepoPath $RepoPath -Args @('switch','-c',$FeatureBranch,'--track',"origin/$FeatureBranch") -ShowOutput | Out-Null
            }
            Invoke-Git -RepoPath $RepoPath -Args @('pull','--ff-only','origin',$FeatureBranch) -ShowOutput | Out-Null
        }
        else {
            if (Local-BranchExists $RepoPath $FeatureBranch) {
                Invoke-Git -RepoPath $RepoPath -Args @('switch',$FeatureBranch) -ShowOutput | Out-Null
            }
            else {
                Invoke-Git -RepoPath $RepoPath -Args @('switch','-c',$FeatureBranch) -ShowOutput | Out-Null
            }
        }

        $Resolved = [System.IO.Path]::GetFullPath($RepoPath)
        Write-Host "RESOLVED_LOCAL_REPO_PATH=$Resolved"
        return $Resolved
    }

    $Specs = @(
        @{ Name='CLEMENT_STUDIO_CORE'; Description='CLEMENT cognitive contracts, Event Bus, provenance and Odysseus runtime adapters'; Branch='feat/cognitive-foundation'; Builder='core' },
        @{ Name='CLEMENT_STUDIO_INTENT'; Description='CLEMENT Intent Core and deterministic Intent Compiler'; Branch='feat/intent-core-mvp'; Builder='intent' },
        @{ Name='CLEMENT_STUDIO_KNOWLEDGE'; Description='CLEMENT Knowledge Core, ontology, entity resolution and Digital Twin primitives'; Branch='feat/knowledge-core-mvp'; Builder='knowledge' }
    )

    $Results = @()

    foreach ($Spec in $Specs) {
        $RepoPath = Initialize-RepositoryV7 -Name $Spec.Name -Description $Spec.Description -FeatureBranch $Spec.Branch

        Write-Host ""
        Write-Host "=== GENERATE_CODE=$($Spec.Name) ==="

        switch ($Spec.Builder) {
            'core' { Build-CoreRepo $RepoPath }
            'intent' { Build-IntentRepo $RepoPath }
            'knowledge' { Build-KnowledgeRepo $RepoPath }
            default { throw "UNKNOWN_BUILDER=$($Spec.Builder)" }
        }

        Write-Host "CODE_GENERATION=PASS REPO=$($Spec.Name)"

        Write-Host "=== TEST=$($Spec.Name) ==="

        $Compile = Invoke-NativeProcess -FilePath $OdysseusPython -Arguments @('-m','compileall','-q',(Join-Path $RepoPath 'src')) -ShowOutput
        $Tests = Invoke-NativeProcess -FilePath $OdysseusPython -Arguments @('-m','pytest','-q',(Join-Path $RepoPath 'tests')) -ShowOutput

        Write-Host "UNIT_TESTS=PASS REPO=$($Spec.Name)"

        Invoke-Git -RepoPath $RepoPath -Args @('add','.') | Out-Null
        $Changes = @(Get-GitDirtyLines $RepoPath)

        if ($Changes.Count -gt 0) {
            Invoke-Git -RepoPath $RepoPath -Args @('commit','-m','feat: bootstrap cognitive core MVP') -ShowOutput | Out-Null
            Write-Host "COMMIT_CREATED=YES REPO=$($Spec.Name)"
        }
        else {
            Write-Host "COMMIT_CREATED=NO REASON=NO_CHANGES REPO=$($Spec.Name)"
        }

        Invoke-Git -RepoPath $RepoPath -Args @('push','-u','origin',$Spec.Branch) -ShowOutput | Out-Null
        $Head = Get-GitHead $RepoPath

        $FullName = "$Owner/$($Spec.Name)"
        $PrList = Invoke-Gh -Args @('pr','list','--repo',$FullName,'--head',$Spec.Branch,'--base','develop','--state','open','--json','number,isDraft,url')

        $ExistingPrs = @()
        if (-not [string]::IsNullOrWhiteSpace($PrList.StdOut)) {
            $ExistingPrs = @($PrList.StdOut | ConvertFrom-Json)
        }

        if ($ExistingPrs.Count -eq 0) {
            $BodyPath = Join-Path $env:TEMP ("CLEMENT_PR_BODY_" + $Spec.Name + ".md")
            $Body = @"
## CLEMENT Cognitive OS production

Initial production scaffold for `$($Spec.Name)`.

- GitHub-first feature branch
- deterministic MVP contracts
- Python 3.11/3.13 CI
- unit tests
- no merge/tag/release requested

Architecture source: `CLEMENT_STUDIO_P0_BOOTSTRAP` / `feat/cognitive-core-production`.
"@
            [System.IO.File]::WriteAllText($BodyPath, $Body, $Utf8)
            try {
                Invoke-Gh -Args @('pr','create','--repo',$FullName,'--base','develop','--head',$Spec.Branch,'--title','feat: bootstrap cognitive core MVP','--body-file',$BodyPath,'--draft') -ShowOutput | Out-Null
            }
            finally {
                Remove-Item -LiteralPath $BodyPath -Force -ErrorAction SilentlyContinue
            }
            Write-Host "DRAFT_PR_CREATED=YES REPO=$($Spec.Name)"
        }
        else {
            $Pr = $ExistingPrs[0]
            if (-not $Pr.isDraft) {
                throw "EXISTING_PR_NOT_DRAFT=$FullName PR=$($Pr.number)"
            }
            Write-Host "DRAFT_PR_ALREADY_EXISTS=$($Pr.number) REPO=$($Spec.Name)"
        }

        $FinalDirty = @(Get-GitDirtyLines $RepoPath)
        if ($FinalDirty.Count -ne 0) {
            foreach ($Line in $FinalDirty) { Write-Host "FINAL_DIRTY=$Line" }
            throw "FINAL_WORKTREE_DIRTY=$($Spec.Name)"
        }

        $Results += [PSCustomObject]@{
            Repository = $Spec.Name
            Branch = $Spec.Branch
            Head = $Head
            Tests = 'PASS'
        }
    }

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "COGNITIVE_CORE_PRODUCTION_V7=PASS"
    Write-Host "NATIVE_EXECUTION=SYSTEM_DIAGNOSTICS_PROCESS"
    Write-Host "NATIVE_STDERR_POWERSHELL_CONVERSION=ELIMINATED"
    Write-Host "NATIVE_EXIT_CODE_AUTHORITATIVE=YES"
    foreach ($Result in $Results) {
        Write-Host "REPO=$($Result.Repository) BRANCH=$($Result.Branch) HEAD=$($Result.Head) TESTS=$($Result.Tests)"
    }
    Write-Host "REPOSITORIES_CREATED_OR_REUSED=3"
    Write-Host "DRAFT_PRS=CREATED_OR_REUSED"
    Write-Host "MERGE_EXECUTED=NO"
    Write-Host "TAG_CREATED=NO"
    Write-Host "RELEASE_CREATED=NO"
    Write-Host "NEXT=EXTEND_MEMORY_KNOWLEDGE_PIPELINE_ORCHESTRATOR"
    Write-Host "============================================================"
}