# Keeps the bot server running: restarts it within seconds if it ever stops.
# Started by the "GoldBot" scheduled task (see install.ps1). The server writes
# its own server.log; crash output goes to crash.log.

$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Dir
$python = (Get-Content (Join-Path $Dir "python.txt") -ErrorAction SilentlyContinue | Select-Object -First 1)
if (-not $python) { $python = "python" }
$env:PYTHONIOENCODING = "utf-8"

while ($true) {
    Start-Process -FilePath $python -ArgumentList "`"$Dir\bot_server.py`"" -WorkingDirectory $Dir -NoNewWindow -Wait `
        -RedirectStandardOutput (Join-Path $Dir "stdout.log") -RedirectStandardError (Join-Path $Dir "crash.log")
    # A crashed server may leave its tunnel behind.
    Get-Process cloudflared -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$Dir*" } | Stop-Process -Force
    Start-Sleep -Seconds 5
}
