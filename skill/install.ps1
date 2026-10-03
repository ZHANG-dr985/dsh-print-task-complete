<#
    install.ps1  -  install the print-task-complete skill for the current user.

    Does three things:
      1. copies this skill folder into a DSH skill root (unless already there)
      2. wires the "print a receipt when a task completes" convention into
         AGENTS.md so the agent actually does it
      3. detects the physical printer and reports the state

    This file is deliberately 100% ASCII: Windows PowerShell 5.1 on a
    GB2312/936 host decodes BOM-less .ps1 files as ANSI, which would corrupt any
    literal CJK text. The Chinese instruction text lives in
    assets/agents-snippet.md and is copied as UTF-8 bytes instead.

    Usage:
      powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
      powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -Scope Project
      powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -Test
#>
[CmdletBinding()]
param(
    [ValidateSet('User', 'Project')] [string] $Scope = 'User',
    [string] $SkillRoot = '',
    [string] $PrinterName = '',
    [switch] $NoInstructions,
    [switch] $Test
)

$ErrorActionPreference = 'Stop'

function Say([string] $m)  { Write-Host "[install] $m" }
function Fail([string] $m) { Write-Host "[install] ERROR: $m"; exit 1 }

$sourceDir = $PSScriptRoot
if (-not $sourceDir) { $sourceDir = (Get-Location).Path }
$scriptRel = 'scripts\print-done.ps1'
$skillName = 'print-task-complete'

# ------------------------------------------------------------------ 1. skill root
$dshHome = $env:DSH_HOME
if (-not $dshHome) { $dshHome = Join-Path $env:USERPROFILE '.dsh' }
$workDir = (Get-Location).Path

if ($SkillRoot -ne '') {
    $root = $SkillRoot
} elseif ($Scope -eq 'User') {
    $root = Join-Path $dshHome 'skills'
} else {
    $root = Join-Path $workDir '.dsh\skills'
}

$target     = Join-Path $root $skillName
$scriptPath = Join-Path $target $scriptRel

Say "scope       : $Scope"
Say "source      : $sourceDir"
Say "skill root  : $root"

# ------------------------------------------------------------------- 2. copy files
$srcFull = (Resolve-Path $sourceDir).Path
$dstFull = $null
if (Test-Path $target) { $dstFull = (Resolve-Path $target).Path }

if ($dstFull -and ($srcFull -eq $dstFull)) {
    Say 'already installed in place - skipping copy.'
} else {
    if (-not (Test-Path $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
    Copy-Item -Path $sourceDir -Destination $target -Recurse -Force
    Say "copied to   : $target"
}

if (-not (Test-Path $scriptPath)) { Fail "print-done.ps1 not found at $scriptPath" }

# ------------------------------------------------------- 3. wire the AGENTS.md rule
if (-not $NoInstructions) {
    $snippetPath = Join-Path $sourceDir 'assets\agents-snippet.md'
    if (-not (Test-Path $snippetPath)) {
        Say 'WARN: assets\agents-snippet.md is missing - skipping AGENTS.md wiring.'
    } else {
        if ($Scope -eq 'User') { $agentsPath = Join-Path $dshHome 'AGENTS.md' }
        else                   { $agentsPath = Join-Path $workDir 'AGENTS.md' }

        $snippet = [System.IO.File]::ReadAllText($snippetPath, [System.Text.Encoding]::UTF8)
        $snippet = $snippet.Replace('__PRINT_SCRIPT__', $scriptPath).Replace('__SKILL_DIR__', $target)

        $begin = '<!-- dsh-print-task-complete:begin -->'
        $end   = '<!-- dsh-print-task-complete:end -->'
        $block = "$begin`r`n" + $snippet.Trim() + "`r`n$end"

        $existing = ''
        if (Test-Path $agentsPath) {
            $existing = [System.IO.File]::ReadAllText($agentsPath, [System.Text.Encoding]::UTF8)
        }

        if ($existing.Contains($begin) -and $existing.Contains($end)) {
            # Idempotent: swap the marked block so re-installing refreshes the text.
            $pattern = [regex]::Escape($begin) + '.*?' + [regex]::Escape($end)
            $evaluator = [System.Text.RegularExpressions.MatchEvaluator] { param($m) $block }
            $updated = [regex]::Replace($existing, $pattern, $evaluator,
                                        [System.Text.RegularExpressions.RegexOptions]::Singleline)
            [System.IO.File]::WriteAllText($agentsPath, $updated, (New-Object System.Text.UTF8Encoding $false))
            Say "updated rule: $agentsPath"
        } elseif ($existing -like "*$skillName*") {
            Say "AGENTS.md mentions $skillName but has no begin marker - left unchanged."
            Say "  Remove the old block by hand, then re-run this installer to get the marked one."
        } else {
            $sep = ''
            if ($existing.Trim().Length -gt 0) { $sep = "`r`n`r`n" }
            [System.IO.File]::WriteAllText(
                $agentsPath,
                $existing.TrimEnd() + $sep + $block + "`r`n",
                (New-Object System.Text.UTF8Encoding $false))
            Say "wired rule  : $agentsPath"
        }

        # Double wiring would make the agent print twice per completion.
        $otherAgents = ''
        if ($Scope -eq 'User') { $otherAgents = Join-Path $workDir 'AGENTS.md' }
        else                   { $otherAgents = Join-Path $dshHome 'AGENTS.md' }
        if ((Test-Path $otherAgents) -and
            ([System.IO.File]::ReadAllText($otherAgents, [System.Text.Encoding]::UTF8) -like "*$skillName*")) {
            Say "WARN: $otherAgents ALSO wires this skill. Two copies of the rule make the agent print twice per completion - remove one."
        }
    }
}

# ------------------------------------------------------------ 4. printer detection
function Invoke-Slip([string[]] $SlipArgs) {
    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path $exe)) { $exe = 'powershell.exe' }
    $all = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath)
    if ($PrinterName -ne '') { $all += @('-PrinterName', $PrinterName) }
    if ($SlipArgs) { $all += $SlipArgs }
    # Out-Host keeps the child's stdout off this function's pipeline, so the
    # only thing the caller captures is the exit code.
    & $exe @all | Out-Host
    return $LASTEXITCODE
}

Say 'detecting printers ...'
$code = Invoke-Slip @('-Status')
if ($code -ne 0) { Fail 'printer detection failed - see the output above.' }

# ------------------------------------------------------------------------ 5. test
if ($Test) {
    Say 'printing a test cell ...'
    $code = Invoke-Slip @()
    if ($code -ne 0) { Fail 'test print failed - see the output above.' }
    Say 'test cell printed.'
}

Say ''
Say 'done. The agent will now print one receipt cell each time a task completes.'
Say "  state file : $(Join-Path $env:LOCALAPPDATA 'dsh-print-task-complete\state.json')"
Say "  uninstall  : delete $target and remove the block from AGENTS.md"
exit 0
