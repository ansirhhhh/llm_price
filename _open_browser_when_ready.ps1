<#
.SYNOPSIS
Waits for http://localhost:$Port/api/health to return HTTP 200 (up to 30 seconds),
then opens $OpenUrl in the user's default browser.
#>
param(
    [int]$Port = 8000,
    [string]$OpenUrl = 'http://localhost:8000'
)

$health = "http://localhost:$Port/api/health"
for ($i = 0; $i -lt 60; $i++) {
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Uri $health -TimeoutSec 3
        if ($r.StatusCode -eq 200) {
            Start-Process $OpenUrl
            exit 0
        }
    } catch {
        Start-Sleep -Milliseconds 400
        continue
    }
    Start-Sleep -Milliseconds 400
}
Write-Warning "Timed out waiting for $health"
exit 1
