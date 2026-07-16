<#
.SYNOPSIS
Stops any AI-Model-Price-Compare server processes that listen on port 8000
and cleans up orphaned uvicorn --reload spawn workers (a common Windows
multiprocessing spawn leak: the reload parent dies but workers keep the socket).
#>
[CmdletBinding()]
param(
    [int]$Port = 8000,
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'

function Write-Q {
    param([string]$msg)
    if (-not $Quiet) { Write-Host $msg }
}

Write-Q "=== stop_server.ps1 (port $Port) ==="
$killed = New-Object System.Collections.Generic.HashSet[int]

# --- 1) Kill processes LISTENING on $Port ---
$owningPids = New-Object System.Collections.Generic.List[int]
try {
    $c = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($c) {
        foreach ($o in ($c | Select-Object -ExpandProperty OwningProcess -Unique)) {
            [void]$owningPids.Add([int]$o)
        }
    }
} catch {}
if (-not $owningPids -or $owningPids.Count -eq 0) {
    try {
        $lines = netstat -ano | Select-String 'LISTENING' | Select-String ":$Port\s"
        foreach ($line in $lines) {
            if ($line -match 'LISTENING\s+(\d+)\s*$') {
                [void]$owningPids.Add([int]$Matches[1])
            }
        }
    } catch {}
}
foreach ($pidItem in $owningPids) {
    if ($killed.Add($pidItem)) {
        try {
            $p = Get-Process -Id $pidItem -ErrorAction Stop
            Write-Q ("  Killing port owner PID=" + $pidItem + "  Name=" + $p.ProcessName + "  Start=" + $p.StartTime.ToString("yyyy-MM-dd HH:mm:ss"))
            Stop-Process -Id $pidItem -Force -ErrorAction Stop
        } catch {
            Write-Q ("  Killing port owner PID=" + $pidItem + " (via taskkill)")
            try { taskkill /F /PID $pidItem /T >$null 2>&1 } catch {}
        }
    }
}

# --- 2) Kill all python processes that look like "part of this project" ---
#    Two patterns:
#    (a) CommandLine contains "--multiprocessing-fork" (uvicorn spawn workers)
#    (b) CommandLine or ExecutablePath points into the project directory (to catch: uvicorn reloader,
#        foreground sleep-keepalive, any stray venv python that was spawned)
$projectRoot = Split-Path -Parent $PSScriptRoot
$altProject = "d:\llm_price"
$matchPaths = @($PSScriptRoot, $projectRoot, $altProject) | Where-Object { $_ } | Sort-Object -Unique
Write-Q ""
Write-Q "Scanning python.exe processes that match project roots: $($matchPaths -join ', ')"
$pyProcs = Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue
foreach ($p in $pyProcs) {
    $pidItem = [int]$p.ProcessId
    if ($killed.Contains($pidItem)) { continue }
    $cmd = [string]$p.CommandLine
    $exe = [string]$p.ExecutablePath
    $text = ($exe + " " + $cmd).ToLowerInvariant()

    $match = $false
    if ($cmd -match '--multiprocessing-fork') { $match = $true; $reason = 'spawn-worker' }
    else {
        foreach ($root in $matchPaths) {
            $rootLow = $root.ToLowerInvariant()
            if ($text.Contains($rootLow)) {
                # Avoid killing THIS current powershell's python children launched by test harnesses...
                # As long as python process itself points into project dir, it's fair game.
                $match = $true
                $reason = "path-match:$root"
                break
            }
        }
    }
    if (-not $match) { continue }
    try {
        $pp = Get-Process -Id $pidItem -ErrorAction Stop
        Write-Q ("  Killing PID=" + $pidItem + " [" + $reason + "]  Start=" + $pp.StartTime.ToString("yyyy-MM-dd HH:mm:ss") + "  CMD=" + $cmd)
        Stop-Process -Id $pidItem -Force -ErrorAction Stop
        [void]$killed.Add($pidItem)
    } catch {
        Write-Q ("  Killing PID=" + $pidItem + " [" + $reason + "] (via taskkill fallback)")
        try { taskkill /F /PID $pidItem /T >$null 2>&1; [void]$killed.Add($pidItem) } catch {}
    }
}

# --- 3) Final wait & confirm ---
Write-Q ""
Start-Sleep -Milliseconds 900
$rem = netstat -ano | Select-String 'LISTENING' | Select-String ":$Port\s"
if ($rem) {
    Write-Q "WARNING: port $Port still has listeners after cleanup:"
    $rem | ForEach-Object { Write-Q ("  " + $_) }
    exit 1
}
Write-Q ("Clean. Total PIDs killed: " + $killed.Count)
exit 0
