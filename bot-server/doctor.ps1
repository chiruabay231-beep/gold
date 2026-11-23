# Why the website / app cannot reach the gold bot's server, and a restart of everything with -Fix.
#
# Check (any PowerShell window on the Windows machine):
#   irm https://raw.githubusercontent.com/chiruabay231-beep/gold/claude/ios-backtest-custom-indicators-jptyoz/bot-server/doctor.ps1 | iex
# Check and restart the server + its tunnel (PowerShell "Run as Administrator"):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/chiruabay231-beep/gold/claude/ios-backtest-custom-indicators-jptyoz/bot-server/doctor.ps1))) -Fix
# Leave ngrok for Cloudflare's free tunnel (no data limit; the address changes on each start, the website and the
# app find it by the server's password), then restart:
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/chiruabay231-beep/gold/claude/ios-backtest-custom-indicators-jptyoz/bot-server/doctor.ps1))) -Cloudflare

param([switch]$Fix, [switch]$Cloudflare, [string]$Dir = "C:\GoldBot")
if ($Cloudflare) { $Fix = $true }

$ErrorActionPreference = "SilentlyContinue"
function Ok($t) { Write-Host "✅ $t" -ForegroundColor Green }
function Bad($t) { Write-Host "❌ $t" -ForegroundColor Red }
function Info($t) { Write-Host "   $t" -ForegroundColor Gray }

Write-Host ""
Write-Host "==================== KIỂM TRA MÁY CHỦ BOT ====================" -ForegroundColor Cyan
if (-not (Test-Path $Dir)) { Bad "Không thấy thư mục $Dir"; return }
$cfg = Get-Content (Join-Path $Dir "config.json") -Raw | ConvertFrom-Json
$port = if ($cfg.port) { [int]$cfg.port } else { 8787 }
$token = [string]$cfg.ngrok_token
$domain = ([string]$cfg.ngrok_domain) -replace "^https?://", "" -replace "/$", ""
$problems = @()

# 1. The scheduled task and the server's process.
$task = Get-ScheduledTask -TaskName "GoldBot"
if ($task) { if ($task.State -eq "Running") { Ok "Tác vụ GoldBot đang chạy" } else { Bad "Tác vụ GoldBot: $($task.State)"; $problems += "task" } }
else { Bad "Không có tác vụ GoldBot (chạy lại bộ cài)"; $problems += "task" }
$py = Get-CimInstance Win32_Process -Filter "Name like 'python%'" | Where-Object { $_.CommandLine -like "*bot_server.py*" }
$main = $py | Where-Object { $_.CommandLine -notlike "*--instance*" }
if ($main) { Ok "Máy chủ bot (python) đang chạy" } else { Bad "Máy chủ bot (python) KHÔNG chạy"; $problems += "server" }

# 2. The server answers on this machine.
try {
    $ping = Invoke-RestMethod -Uri "http://127.0.0.1:$port/ping" -TimeoutSec 5
    Ok "Máy chủ trả lời trên máy này (bản $($ping.version), cổng $port)"
} catch { Bad "Máy chủ KHÔNG trả lời trên cổng $port"; $problems += "local" }

# 3. Internet, the tunnel's process and its address from outside.
if (Test-NetConnection "ngrok.com" -Port 443 -InformationLevel Quiet) { Ok "Có Internet" } else { Bad "Không ra được Internet (mạng của máy ảo / Mac)"; $problems += "net" }
$tunnel = Get-Process ngrok, cloudflared
if ($tunnel) { Ok "Đường hầm đang chạy ($($tunnel.ProcessName -join ', '))" } else { Bad "Đường hầm (ngrok) KHÔNG chạy"; $problems += "tunnel" }
if ($domain) {
    try {
        $r = Invoke-WebRequest -Uri "https://$domain/ping" -Headers @{ "ngrok-skip-browser-warning" = "1" } -TimeoutSec 10 -UseBasicParsing
        if ($r.Content -match "gold-bot") { Ok "Từ Internet vào được: https://$domain" } else { Bad "https://$domain trả lời lạ"; $problems += "public" }
    } catch { Bad "Từ Internet KHÔNG vào được https://$domain ($($_.Exception.Message))"; $problems += "public" }
}

# 4. MT5.
$mt5 = Get-Process terminal64
if ($mt5) { Ok "MT5 đang mở ($($mt5.Count) cửa sổ)" } else { Bad "MT5 không mở"; $problems += "mt5" }

# 5. The last lines of the logs (the ngrok token hidden).
foreach ($name in @("server.log", "crash.log", "tunnel.log")) {
    $p = Join-Path $Dir $name
    if (Test-Path $p) {
        Write-Host ""
        Write-Host "--- $name (cuối) ---" -ForegroundColor Cyan
        Get-Content $p -Tail 8 | ForEach-Object { if ($token) { $_.Replace($token, "***") } else { $_ } } | ForEach-Object { Info $_ }
    }
}

Write-Host ""
Write-Host "==================== KẾT LUẬN ====================" -ForegroundColor Cyan
if (-not $problems.Count) { Ok "Mọi thứ đều chạy. Web / app vẫn không vào được: tắt hẳn rồi mở lại, hoặc đăng nhập lại bằng mật khẩu máy chủ." }
if ($problems -contains "net") { Bad "Máy ảo mất mạng: trong VMware → Virtual Machine → Network Adapter → chọn lại 'Share with my Mac', hoặc khởi động lại máy ảo." }
if ($problems -contains "server" -or $problems -contains "local" -or $problems -contains "task") { Bad "Máy chủ bot đã dừng → chạy lệnh có -Fix để khởi động lại." }
if (($problems -contains "tunnel" -or $problems -contains "public") -and -not ($problems -contains "local")) { Bad "Máy chủ chạy nhưng đường hầm ngrok đứt → chạy lệnh có -Fix để nối lại." }
if ($problems -contains "mt5") { Bad "MT5 chưa mở: mở MT5 (bot tự mở lại khi máy chủ khởi động)." }

if (-not $Fix) {
    if ($problems.Count) {
        Write-Host ""
        Write-Host "Sửa: mở PowerShell bằng 'Run as administrator' rồi dán:"
        Write-Host '  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/chiruabay231-beep/gold/claude/ios-backtest-custom-indicators-jptyoz/bot-server/doctor.ps1))) -Fix' -ForegroundColor Green
    }
    return
}

if ($Cloudflare) {
    # ngrok's token and domain out of the settings (kept aside in ngrok.backup.json to go back later).
    $path = Join-Path $Dir "config.json"
    $c = Get-Content $path -Raw | ConvertFrom-Json
    if ($c.ngrok_token) {
        [pscustomobject]@{ ngrok_token = $c.ngrok_token; ngrok_domain = $c.ngrok_domain } | ConvertTo-Json | Set-Content (Join-Path $Dir "ngrok.backup.json") -Encoding UTF8
        $c.PSObject.Properties.Remove("ngrok_token"); $c.PSObject.Properties.Remove("ngrok_domain")
        $c | ConvertTo-Json -Depth 8 | Set-Content $path -Encoding UTF8
    }
    $domain = ""
    Ok "Chuyển sang đường hầm Cloudflare (miễn phí, không giới hạn dung lượng)"
}

Write-Host ""
Write-Host "==================== KHỞI ĐỘNG LẠI ====================" -ForegroundColor Cyan
Stop-ScheduledTask -TaskName "GoldBot"
Get-CimInstance Win32_Process -Filter "Name like 'python%'" | Where-Object { $_.CommandLine -like "*bot_server.py*" -or $_.CommandLine -like "*run.ps1*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like "*GoldBot*run.ps1*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Get-Process ngrok, cloudflared | Stop-Process -Force
Remove-Item (Join-Path $Dir "update.flag") -Force
Start-Sleep -Seconds 3
Start-ScheduledTask -TaskName "GoldBot"
Write-Host "Đã khởi động lại máy chủ bot và đường hầm. Chờ khoảng 1 phút..." -ForegroundColor Yellow
$ok = $false
foreach ($i in 1..12) {
    Start-Sleep -Seconds 5
    try { $null = Invoke-RestMethod -Uri "http://127.0.0.1:$port/ping" -TimeoutSec 3; $ok = $true; break } catch {}
}
if ($ok) { Ok "Máy chủ đã chạy lại" } else { Bad "Máy chủ chưa lên sau 1 phút: xem crash.log ở trên" }
if ($Cloudflare) {
    # Cloudflare gives a new address each start: wait for it, then try it from outside.
    $url = ""
    foreach ($i in 1..18) {
        Start-Sleep -Seconds 5
        $url = (Get-Content (Join-Path $Dir "tunnel.txt") -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($url -and $url -like "*trycloudflare.com*") { break }
    }
    if ($url) {
        Start-Sleep -Seconds 10
        try {
            $r = Invoke-WebRequest -Uri "$url/ping" -TimeoutSec 15 -UseBasicParsing
            if ($r.Content -match "gold-bot") { Ok "Đường hầm Cloudflare chạy: $url — mở lại web / app, đăng nhập bằng mật khẩu máy chủ (tự tìm địa chỉ mới)" }
        } catch { Bad "Có địa chỉ $url nhưng chưa vào được: chờ 1–2 phút rồi mở web / app" }
    } else { Bad "Chưa có địa chỉ Cloudflare sau 90 giây: xem tunnel.log (chạy lệnh kiểm tra)" }
}
if ($domain) {
    Start-Sleep -Seconds 10
    try {
        $r = Invoke-WebRequest -Uri "https://$domain/ping" -Headers @{ "ngrok-skip-browser-warning" = "1" } -TimeoutSec 10 -UseBasicParsing
        if ($r.Content -match "gold-bot") { Ok "Từ Internet đã vào được: mở lại web / app" }
    } catch { Bad "Đường hầm chưa lên: chờ thêm 1–2 phút rồi chạy lại lệnh kiểm tra (không có -Fix)" }
}
