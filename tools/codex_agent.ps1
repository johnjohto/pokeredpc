#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Delegate a task to an OpenAI Codex "subagent" (codex exec) and return its final answer.

.DESCRIPTION
    Thin wrapper around `codex exec` so a coding agent (or a human) can hand a self-contained
    task to a Codex agent running on OpenAI models, then read back just the final message.

    Codex authenticates via the ChatGPT sign-in already stored in ~/.codex (no API key).
    `codex exec` is non-interactive: there is NO approval prompt, so it never hangs waiting
    for input. What the agent may touch is governed entirely by -Sandbox:
        read-only        can read the repo + reason; writes/commands that mutate fail back
                         to the model. Safe default for "consultant / second opinion / review".
        workspace-write  can edit files under the repo (use when you want Codex to DO the work).
        danger-full-access  unrestricted. Only with a clear reason.

    Available models on this account (see ~/.codex/models_cache.json):
        gpt-5.6-sol, gpt-5.6-terra, gpt-5.6-luna, gpt-5.5, gpt-5.4, gpt-5.4-mini
    Omit -Model to use the account default configured in Codex.

.EXAMPLE
    # Read-only second opinion, default model
    pwsh tools/codex_agent.ps1 -Task "Review scripts/Player.gd ledge-hop logic for off-by-one bugs."

.EXAMPLE
    # Let Codex actually implement a fix, using a specific model
    pwsh tools/codex_agent.ps1 -Sandbox workspace-write -Model gpt-5.6-sol `
        -Task "Fix issue #171: the Diglett's Cave Route 2 warp lands the player on a wall tile."

.EXAMPLE
    # Cheap model for a mechanical task, pipe the task in via stdin
    Get-Content task.md | pwsh tools/codex_agent.ps1 -Model gpt-5.4-mini
#>
[CmdletBinding()]
param(
    # The instruction for the Codex agent. If omitted, read from stdin.
    [Parameter(Position = 0, ValueFromPipeline = $true)]
    [string] $Task,

    # Codex model slug. Empty = account default.
    [string] $Model = '',

    # What the agent is allowed to touch.
    [ValidateSet('read-only', 'workspace-write', 'danger-full-access')]
    [string] $Sandbox = 'read-only',

    # Working root for the agent. Defaults to the repo this script lives in.
    [string] $Cd = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,

    # Enable Codex's live web search tool.
    [switch] $Search,

    # Stream raw JSONL events instead of just the final message.
    [switch] $Json,

    # Hard timeout in seconds; the agent is killed if it runs longer.
    [int] $TimeoutSec = 900,

    # Where to write the agent's final message. Default: a temp file (also printed to stdout).
    [string] $OutFile = ''
)

begin { $stdinLines = @() }
process { if ($PSItem) { $stdinLines += $PSItem } }
end {
    if ([string]::IsNullOrWhiteSpace($Task)) { $Task = ($stdinLines -join "`n") }
    if ([string]::IsNullOrWhiteSpace($Task)) {
        Write-Error "No task provided (pass as -Task or via stdin)."
        exit 2
    }

    if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
        Write-Error "codex CLI not found on PATH. Install with: npm i -g @openai/codex"
        exit 3
    }

    if ([string]::IsNullOrWhiteSpace($OutFile)) {
        $OutFile = Join-Path ([System.IO.Path]::GetTempPath()) ("codex_agent_{0}.txt" -f ([guid]::NewGuid().ToString('N')))
    }
    if (Test-Path $OutFile) { Remove-Item $OutFile -Force }

    $codexArgs = @('exec', '--cd', $Cd, '--sandbox', $Sandbox, '-o', $OutFile, '--color', 'never')
    if ($Model)  { $codexArgs += @('-m', $Model) }
    if ($Search) { $codexArgs += '--search' }
    if ($Json)   { $codexArgs += '--json' }
    $codexArgs += $Task

    Write-Host "→ codex exec (model=$(if ($Model) { $Model } else { 'default' }), sandbox=$Sandbox, cd=$Cd)" -ForegroundColor Cyan

    $job = Start-Job -ScriptBlock {
        param($a)
        & codex @a 2>&1
    } -ArgumentList (, $codexArgs)

    if (Wait-Job $job -Timeout $TimeoutSec) {
        Receive-Job $job
        Remove-Job $job -Force
    }
    else {
        Stop-Job $job; Remove-Job $job -Force
        Write-Error "codex exec exceeded $TimeoutSec s — killed."
        exit 124
    }

    Write-Host "`n===== FINAL MESSAGE =====" -ForegroundColor Green
    if (Test-Path $OutFile) { Get-Content $OutFile -Raw }
    else { Write-Warning "No final-message file was produced." }
}
