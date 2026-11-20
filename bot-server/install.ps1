# Gold bot installer for a Windows VPS (Windows Server 2019/2022/2025, Windows 10/11).
#
# Open PowerShell as Administrator on the VPS and paste:
#   irm https://raw.githubusercontent.com/chiruabay231-beep/gold/claude/ios-backtest-custom-indicators-jptyoz/bot-server/install.ps1 | iex
#
# Phase 2 (MT5 / Exness), after logging in to MT5 once:
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/chiruabay231-beep/gold/claude/ios-backtest-custom-indicators-jptyoz/bot-server/install.ps1))) -Mt5
#
# Running it again updates the bot and keeps config.json / state.json.
#
# Moving from another machine: put GoldBot-backup.zip (made there by backup.ps1) on the Desktop or in Downloads,
# or give its path with -Restore; it is put back before the first start (settings, members, drawings, virtual
# accounts). On a Windows virtual machine (Mac + Parallels / UTM) the -Mt5 phase also keeps Windows awake and
# can sign Windows in by itself, so MT5 and the bot start with the virtual machine.
#
# -Ngrok: the server's address through ngrok instead of Cloudflare's quick tunnel (a free ngrok account: its
# authtoken and its free fixed domain, name.ngrok-free.app) — the same address every start, no quick-tunnel limits.

param(
    [switch]$Mt5,
    [switch]$Ngrok,
    [string]$Restore = "",
    [string]$Dir = "C:\GoldBot"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # much faster Invoke-WebRequest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Release = "https://github.com/chiruabay231-beep/gold/releases/download/bot-latest/gold-bot-windows.zip"
$PythonUrl = "https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe"
$VcRedistUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
$CloudflaredUrl = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"
$NgrokUrl = "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip"
$TaskName = "GoldBot"

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host "Hãy mở PowerShell bằng 'Run as Administrator' rồi chạy lại." -ForegroundColor Red
    return
}

# Updating an MT5 install (task runs at logon) keeps it in MT5 mode without -Mt5.
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $Mt5 -and $existingTask -and "$($existingTask.Principal.LogonType)" -eq "Interactive") {
    $Mt5 = $true
    Write-Host "Giữ chế độ MT5 (giai đoạn 2) của bản đã cài." -ForegroundColor Yellow
}

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$Temp = Join-Path $env:TEMP "goldbot-install"
New-Item -ItemType Directory -Force -Path $Temp | Out-Null

# Stop a running copy so its files can be replaced.
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='cloudflared.exe' OR Name='ngrok.exe' OR Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*$Dir\bot_server.py*" -or $_.CommandLine -like "*$Dir\run.ps1*" -or $_.ExecutablePath -like "$Dir*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# A backup from the old machine: given, or found on the Desktop / in Downloads when this machine has no settings yet.
if (-not $Restore -and -not (Test-Path (Join-Path $Dir "config.json"))) {
    foreach ($place in @([Environment]::GetFolderPath("Desktop"), (Join-Path $env:USERPROFILE "Downloads"))) {
        $found = Join-Path $place "GoldBot-backup.zip"
        if (Test-Path $found) { $Restore = $found; break }
    }
}
if ($Restore) {
    if (-not (Test-Path $Restore)) { throw "Không thấy file sao lưu $Restore" }
    Step "Khôi phục dữ liệu từ máy cũ ($Restore)"
    $restoreDir = Join-Path $Temp "restore"
    Remove-Item -Recurse -Force $restoreDir -ErrorAction SilentlyContinue
    Expand-Archive -Path $Restore -DestinationPath $restoreDir -Force
    Get-ChildItem $restoreDir -File | ForEach-Object {
        Copy-Item $_.FullName -Destination $Dir -Force
        Write-Host "  + $($_.Name)"
    }
}

Step "Tải bot (botkit + máy chủ)"
$zip = Join-Path $Temp "gold-bot-windows.zip"
Invoke-WebRequest -Uri $Release -OutFile $zip -UseBasicParsing
$unpack = Join-Path $Temp "unpack"
Remove-Item -Recurse -Force $unpack -ErrorAction SilentlyContinue
Expand-Archive -Path $zip -DestinationPath $unpack -Force
Get-ChildItem $unpack | Where-Object { $_.Name -notin @("config.json", "state.json") } |
    Copy-Item -Destination $Dir -Recurse -Force

Step "Cài Visual C++ runtime"
$vc = Join-Path $Temp "vc_redist.x64.exe"
Invoke-WebRequest -Uri $VcRedistUrl -OutFile $vc -UseBasicParsing
Start-Process -FilePath $vc -ArgumentList "/install", "/quiet", "/norestart" -Wait

Step "Cài Python"
$python = "C:\Program Files\Python312\python.exe"
if (-not (Test-Path $python)) {
    $installer = Join-Path $Temp "python-installer.exe"
    Invoke-WebRequest -Uri $PythonUrl -OutFile $installer -UseBasicParsing
    Start-Process -FilePath $installer -ArgumentList "/quiet", "InstallAllUsers=1", "PrependPath=1", "Include_test=0", "Include_launcher=0" -Wait
}
if (-not (Test-Path $python)) { throw "Cài Python thất bại" }
Set-Content -Path (Join-Path $Dir "python.txt") -Value $python -Encoding ASCII

Step "Cài thư viện MetaTrader5 (cho giai đoạn 2)"
& $python -m pip install --upgrade --quiet MetaTrader5
if ($LASTEXITCODE -ne 0) { Write-Host "Không cài được MetaTrader5 — giai đoạn 1 (Binance) vẫn chạy bình thường." -ForegroundColor Yellow }

Step "Tải Cloudflare Tunnel"
Invoke-WebRequest -Uri $CloudflaredUrl -OutFile (Join-Path $Dir "cloudflared.exe") -UseBasicParsing

Step "Kiểm tra botkit"
Push-Location $Dir
& $python bot_server.py --selftest
$selftest = $LASTEXITCODE
Pop-Location
if ($selftest -ne 0) { throw "botkit không chạy được trên máy này" }

$configPath = Join-Path $Dir "config.json"
if (-not (Test-Path $configPath)) {
    Step "Tạo cấu hình"
    $config = Get-Content (Join-Path $Dir "config.example.json") -Raw | ConvertFrom-Json
    $chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789".ToCharArray()
    $config.password = -join (1..16 | ForEach-Object { $chars | Get-Random })
    Write-Host "Token Telegram bot (từ @BotFather), Enter để bỏ qua:" -ForegroundColor Yellow
    $token = Read-Host
    if ($token) { $config.telegram.token = $token.Trim() }
    $config | ConvertTo-Json -Depth 8 | Set-Content -Path $configPath -Encoding UTF8
}
$config = Get-Content $configPath -Raw | ConvertFrom-Json

if ($Ngrok -or $config.ngrok_token) {
    Step "Đường hầm ngrok (địa chỉ cố định)"
    if ($Ngrok) {
        Write-Host "Mở https://dashboard.ngrok.com → 'Your Authtoken': copy token rồi dán vào đây:" -ForegroundColor Yellow
        $token = (Read-Host).Trim()
        Write-Host "Domain miễn phí của bạn (dashboard.ngrok.com → Domains, dạng ten-cua-ban.ngrok-free.app), Enter nếu chưa có:" -ForegroundColor Yellow
        $domain = (Read-Host).Trim() -replace "^https?://", "" -replace "/+$", ""
        if (-not $token) { throw "Chưa nhập authtoken ngrok" }
        $config | Add-Member -NotePropertyName ngrok_token -NotePropertyValue $token -Force
        $config | Add-Member -NotePropertyName ngrok_domain -NotePropertyValue $domain -Force
        $config | ConvertTo-Json -Depth 8 | Set-Content -Path $configPath -Encoding UTF8
    }
    $ngzip = Join-Path $Temp "ngrok.zip"
    Invoke-WebRequest -Uri $NgrokUrl -OutFile $ngzip -UseBasicParsing
    Expand-Archive -Path $ngzip -DestinationPath $Dir -Force
    Write-Host "Đã cài ngrok$(if ($config.ngrok_domain) { ': https://' + $config.ngrok_domain })."
}

if ($Mt5) {
    Step "Giữ Windows luôn thức (máy ảo / máy bàn chạy 24/24)"
    # Never sleep or hibernate on power; the screen may turn off.
    powercfg /change standby-timeout-ac 0 | Out-Null
    powercfg /change hibernate-timeout-ac 0 | Out-Null
    powercfg /change standby-timeout-dc 0 | Out-Null
    powercfg /change hibernate-timeout-dc 0 | Out-Null
    # Windows Update: no restart on its own while someone is signed in (the bot's session).
    $wu = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    New-Item -Path $wu -Force | Out-Null
    Set-ItemProperty -Path $wu -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord
    Write-Host "Đã tắt ngủ / ngủ đông và tự khởi động lại khi cập nhật."

    Write-Host "Tự đăng nhập Windows khi bật máy (để MT5 và bot tự chạy, không cần ai bấm)? (y/N)" -ForegroundColor Yellow
    if ((Read-Host) -match "^[yYcC]") {
        $secure = Read-Host "Mật khẩu Windows của $env:USERNAME (để trống nếu không có)" -AsSecureString
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
        $autologon = Join-Path $Temp "Autologon64.exe"
        try {
            Invoke-WebRequest -Uri "https://live.sysinternals.com/Autologon64.exe" -OutFile $autologon -UseBasicParsing
            # Sysinternals Autologon keeps the password encrypted (LSA secret), not in plain text in the registry.
            & $autologon $env:USERNAME $env:USERDOMAIN $plain /accepteula | Out-Null
            Write-Host "Đã bật tự đăng nhập cho $env:USERNAME." -ForegroundColor Green
        } catch {
            Write-Host "Không bật được tự đăng nhập ($($_.Exception.Message)). Có thể bật tay: Win+R → netplwiz." -ForegroundColor Yellow
        }
        $plain = $null
    }
}

Step "Đăng ký tự chạy"
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Dir\run.ps1`"" -WorkingDirectory $Dir
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
if ($Mt5) {
    # MT5 needs the desktop session: run when this user logs on.
    $user = "$env:USERDOMAIN\$env:USERNAME"
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $mode = "khi $user đăng nhập (giai đoạn 2, MT5)"
} else {
    # Binance needs no desktop: run as SYSTEM from boot, even with nobody logged in.
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $mode = "khi bật máy (giai đoạn 1, Binance)"
}
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
Start-ScheduledTask -TaskName $TaskName

Step "Chờ địa chỉ máy chủ"
$url = $null
$tunnelFile = Join-Path $Dir "tunnel.txt"
Remove-Item $tunnelFile -ErrorAction SilentlyContinue
for ($i = 0; $i -lt 45 -and -not $url; $i++) {
    Start-Sleep -Seconds 2
    if (Test-Path $tunnelFile) { $url = (Get-Content $tunnelFile | Select-Object -First 1).Trim() }
}

Write-Host ""
Write-Host "==================== XONG ====================" -ForegroundColor Green
Write-Host "Bot tự chạy $mode."
if ($url) { Write-Host "Địa chỉ máy chủ : $url" -ForegroundColor Green }
else { Write-Host "Địa chỉ máy chủ : chưa có, xem lại sau trong $Dir\tunnel.txt hoặc gõ /url cho bot Telegram" -ForegroundColor Yellow }
Write-Host "Mật khẩu máy chủ: $($config.password)" -ForegroundColor Green
Write-Host ""
Write-Host "Mở app → Backtest → Bot → Máy chủ VPS, nhập địa chỉ và mật khẩu ở trên."
Write-Host "KHÔNG gửi mật khẩu này cho ai (kể cả trong chat)."
if ($config.telegram.token -and -not $config.telegram.chat_id) {
    Write-Host "Mở Telegram, nhắn bất kỳ chữ nào cho bot của bạn để liên kết thông báo." -ForegroundColor Yellow
}
Write-Host "Địa chỉ đổi mỗi khi VPS khởi động lại: bot Telegram sẽ gửi địa chỉ mới (hoặc gõ /url)."
