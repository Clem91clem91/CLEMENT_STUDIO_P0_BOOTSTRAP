# P0.5.1 - PowerShell root resolution hotfix

## Incident

`Apply-P05BranchProtection.ps1` resolved its default `ConfigPath` inside the `param(...)` block using `$PSScriptRoot`.

When launched on Shadow through Windows PowerShell 5.1 with `powershell -File`, parameter binding could observe an empty `$PSScriptRoot`, causing `Split-Path` to fail before the script body started.

## Fix

- `ConfigPath` is now optional without a default expression in `param(...)`.
- Resolution happens after parameter binding.
- `$PSCommandPath` is preferred, with `$MyInvocation.MyCommand.Path` as fallback.
- `-ResolveConfigOnly` validates path resolution without requiring GitHub authentication or mutating repository settings.
- CI Windows invokes the script through `powershell -File ... -ResolveConfigOnly`, matching the Shadow failure mode.

## Safety

This hotfix does not create tags or releases and does not apply branch protection during CI.
