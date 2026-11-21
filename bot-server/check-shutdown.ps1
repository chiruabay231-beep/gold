# Why the gold bot's Windows machine turned itself off or restarted, and the settings so it stays on.
#
# Check only (any PowerShell window):
#   irm https://raw.githubusercontent.com/chiruabay231-beep/gold/claude/ios-backtest-custom-indicators-jptyoz/bot-server/check-shutdown.ps1 | iex
# Check and fix (PowerShell "Run as Administrator"):
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/chiruabay231-beep/gold/claude/ios-backtest-custom-indicators-jptyoz/bot-server/check-shutdown.ps1))) -Fix

param([switch]$Fix, [int]$Days = 7)

$ErrorActionPreference = "SilentlyContinue"
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host ""
Write-Host "==================== KIỂM TRA VÌ SAO WINDOWS TỰ TẮT ====================" -ForegroundColor Cyan

# 1. Windows itself: an expired evaluation copy shuts down every hour.
$os = Get-CimInstance Win32_OperatingSystem
Write-Host ""
Write-Host "Windows: $($os.Caption)  ·  bật lần cuối: $($os.LastBootUpTime)"
$lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f'" | Select-Object -First 1
$evaluation = $os.Caption -match "Evaluation"
if ($lic) {
    $days = [math]::Round($lic.GracePeriodRemaining / 1440, 1)
    $state = @{0 = "chưa kích hoạt"; 1 = "đã kích hoạt"; 2 = "dùng thử (OOB)"; 3 = "dùng thử (OOT)"; 4 = "không chính hãng"; 5 = "thông báo"; 6 = "gia hạn" }[[int]$lic.LicenseStatus]
    Write-Host "Bản quyền: $state$(if ($lic.LicenseStatus -ne 1 -or $evaluation) { " · còn $days ngày" })"
}
if ($evaluation -and $lic -and $lic.GracePeriodRemaining -le 0) {
    Write-Host "⛔ Đây là bản Windows DÙNG THỬ (Evaluation) ĐÃ HẾT HẠN: Windows tự tắt khoảng MỖI GIỜ. Đây là nguyên nhân." -ForegroundColor Red
    Write-Host "   Cách sửa: kích hoạt bằng key bản quyền, hoặc cài lại Windows bản thường (không phải Evaluation)." -ForegroundColor Red
} elseif ($evaluation) {
    Write-Host "⚠️ Bản Windows dùng thử (Evaluation): khi hết hạn sẽ tự tắt mỗi giờ." -ForegroundColor Yellow
}

# 2. The system log: who turned it off, and how.
$since = (Get-Date).AddDays(-$Days)
$events = Get-WinEvent -FilterHashtable @{ LogName = "System"; Id = 41, 42, 1074, 6006, 6008, 107; StartTime = $since } |
    Sort-Object TimeCreated -Descending | Select-Object -First 25
Write-Host ""
Write-Host "Các lần tắt / khởi động lại / ngủ trong $Days ngày qua (mới nhất trước):" -ForegroundColor Cyan
$update = $false; $sudden = $false; $sleep = $false
if (-not $events) { Write-Host "  (không có)" }
foreach ($e in $events) {
    $t = $e.TimeCreated.ToString("dd/MM HH:mm")
    switch ($e.Id) {
        1074 {
            $proc = [string]$e.Properties[0].Value; $why = [string]$e.Properties[2].Value; $kind = [string]$e.Properties[4].Value
            $who = Split-Path $proc -Leaf
            if ($proc -match "TrustedInstaller|MoUsoCoreWorker|wuauclt|usoclient|UpdateOrchestrator|svchost") {
                $update = $true
                Write-Host "  $t  🔄 Windows Update tự $kind ($who)" -ForegroundColor Yellow
            } else {
                Write-Host "  $t  ⏻ $kind do $who · $why"
            }
        }
        41 { $sudden = $true; Write-Host "  $t  ⚡ TẮT ĐỘT NGỘT (không tắt đúng cách): máy ảo bị dừng cứng / Mac ngủ hoặc tắt / hết RAM" -ForegroundColor Red }
        6008 { $sudden = $true; Write-Host "  $t  ⚡ lần tắt trước đó không bình thường" -ForegroundColor Red }
        6006 { Write-Host "  $t  ⏹ Windows tắt bình thường" }
        42 { $sleep = $true; Write-Host "  $t  💤 Windows đi NGỦ" -ForegroundColor Yellow }
        107 { Write-Host "  $t  ☀ Windows thức dậy sau khi ngủ" }
    }
}

# 3. Sleep settings now.
$standby = (powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE | Select-String "Current AC Power Setting Index") -replace ".*0x", ""
if ($standby -and [Convert]::ToInt32($standby, 16) -gt 0) {
    $sleep = $true
    Write-Host ""
    Write-Host "⚠️ Windows đang cài TỰ NGỦ sau $([Convert]::ToInt32($standby, 16) / 60) phút khi cắm điện." -ForegroundColor Yellow
}

# 4. Signing in by itself: after a restart MT5 and the bot start only once the user is signed in.
$wl = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
$autoOn = $wl.AutoAdminLogon -eq "1"
$pwless = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device").DevicePasswordLessBuildVersion
Write-Host ""
if ($autoOn -and $pwless -ne 2) {
    Write-Host "Tự đăng nhập: BẬT ($($wl.DefaultUserName))"
} else {
    Write-Host "⛔ Tự đăng nhập: CHƯA HOẠT ĐỘNG$(if ($pwless -eq 2) { ' (Windows đang bắt đăng nhập bằng Windows Hello/PIN nên tự đăng nhập bị chặn)' })." -ForegroundColor Red
    Write-Host "   Sau mỗi lần Windows khởi động lại, máy đứng ở màn hình khoá → MT5 và bot KHÔNG chạy cho tới khi có người đăng nhập." -ForegroundColor Red
}

Write-Host ""
Write-Host "==================== KẾT LUẬN ====================" -ForegroundColor Cyan
if (-not $autoOn -or $pwless -eq 2) { Write-Host "• Chưa tự đăng nhập: chạy lệnh có -Fix để bật (nhập mật khẩu Windows 1 lần)." -ForegroundColor Red }
if ($update) { Write-Host "• Windows Update tự khởi động lại máy → chạy lệnh có -Fix (bên dưới) để Windows không tự khởi động lại." -ForegroundColor Yellow }
if ($sleep) { Write-Host "• Windows tự ngủ → chạy lệnh có -Fix để tắt chế độ ngủ." -ForegroundColor Yellow }
if ($sudden) {
    Write-Host "• Máy ảo bị dừng đột ngột (không phải Windows tự tắt). Thường do phía Mac:" -ForegroundColor Red
    Write-Host "    - Mac đi ngủ / gập nắp MacBook → chạy mac-setup.sh trên Mac, luôn cắm sạc, mở nắp." -ForegroundColor Red
    Write-Host "    - Mac thiếu RAM (VMware bị macOS dừng) → bớt RAM cho máy ảo hoặc đóng bớt app trên Mac." -ForegroundColor Red
    Write-Host "    - Thoát VMware Fusion / tắt Mac → mở lại VMware, máy ảo tự chạy lại bot." -ForegroundColor Red
}
if (-not ($update -or $sleep -or $sudden -or $evaluation)) { Write-Host "• Không thấy lần tắt nào trong $Days ngày qua." }

if (-not $Fix) {
    Write-Host ""
    Write-Host "Để tự sửa (tắt ngủ, chặn Windows Update tự khởi động lại): mở PowerShell bằng 'Run as Administrator' rồi dán:"
    Write-Host '  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/chiruabay231-beep/gold/claude/ios-backtest-custom-indicators-jptyoz/bot-server/check-shutdown.ps1))) -Fix' -ForegroundColor Green
    return
}
if (-not $admin) {
    Write-Host ""
    Write-Host "Cần mở PowerShell bằng 'Run as Administrator' để sửa (chuột phải PowerShell → Run as administrator)." -ForegroundColor Red
    return
}

Write-Host ""
Write-Host "==================== ĐANG SỬA ====================" -ForegroundColor Cyan
# Never sleep or hibernate (the screen may still turn off).
powercfg /change standby-timeout-ac 0 | Out-Null
powercfg /change standby-timeout-dc 0 | Out-Null
powercfg /change hibernate-timeout-ac 0 | Out-Null
powercfg /change hibernate-timeout-dc 0 | Out-Null
powercfg /hibernate off | Out-Null
Write-Host "✓ Tắt chế độ ngủ và ngủ đông"

# Windows Update: downloads, but installs (and restarts) only when you choose; never restarts while signed in.
$au = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
New-Item -Path $au -Force | Out-Null
Set-ItemProperty -Path $au -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord
Set-ItemProperty -Path $au -Name "AUOptions" -Value 3 -Type DWord
Set-ItemProperty -Path $au -Name "NoAutoUpdate" -Value 0 -Type DWord
$wu = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
Set-ItemProperty -Path $wu -Name "SetActiveHours" -Value 1 -Type DWord
Set-ItemProperty -Path $wu -Name "ActiveHoursStart" -Value 6 -Type DWord
Set-ItemProperty -Path $wu -Name "ActiveHoursEnd" -Value 23 -Type DWord
$ux = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
New-Item -Path $ux -Force | Out-Null
Set-ItemProperty -Path $ux -Name "ActiveHoursStart" -Value 6 -Type DWord
Set-ItemProperty -Path $ux -Name "ActiveHoursEnd" -Value 23 -Type DWord
Write-Host "✓ Windows Update: chỉ tải về, KHÔNG tự cài và tự khởi động lại (giờ hoạt động 6h–23h)"

# Nightly maintenance must not wake / restart the machine.
$mt = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance"
New-Item -Path $mt -Force | Out-Null
Set-ItemProperty -Path $mt -Name "MaintenanceDisabled" -Value 1 -Type DWord
Write-Host "✓ Tắt bảo trì tự động ban đêm"

# No lock screen: never ask to sign in again after the screen turns off, wakes, or a screen saver.
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 0 | Out-Null
powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 0 | Out-Null
powercfg /SETACTIVE SCHEME_CURRENT | Out-Null
$sys = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Set-ItemProperty -Path $sys -Name "InactivityTimeoutSecs" -Value 0 -Type DWord
$desk = "HKCU:\Control Panel\Desktop"
Set-ItemProperty -Path $desk -Name "ScreenSaveActive" -Value "0"
Set-ItemProperty -Path $desk -Name "ScreenSaverIsSecure" -Value "0"
Remove-ItemProperty -Path $desk -Name "SCRNSAVE.EXE" -ErrorAction SilentlyContinue
Write-Host "✓ Không khoá màn hình khi để lâu / tắt màn hình / thức dậy"

# Signing in by itself after a restart (MT5 and the bot need the user's session).
$pl = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device"
New-Item -Path $pl -Force | Out-Null
Set-ItemProperty -Path $pl -Name "DevicePasswordLessBuildVersion" -Value 0 -Type DWord
if (-not $autoOn) {
    Write-Host ""
    Write-Host "Bật TỰ ĐĂNG NHẬP cho $env:USERNAME (bắt buộc để bot tự chạy sau khi Windows khởi động lại)." -ForegroundColor Yellow
    Write-Host "Nhập mật khẩu đăng nhập Windows (mật khẩu tài khoản, KHÔNG phải mã PIN; tài khoản Microsoft thì là mật khẩu Microsoft):" -ForegroundColor Yellow
    $secure = Read-Host "Mật khẩu Windows của $env:USERNAME" -AsSecureString
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    $user = $env:USERNAME; $domain = $env:USERDOMAIN
    $autologon = Join-Path $env:TEMP "Autologon64.exe"
    try {
        Invoke-WebRequest -Uri "https://live.sysinternals.com/Autologon64.exe" -OutFile $autologon -UseBasicParsing
        # Sysinternals Autologon keeps the password encrypted (LSA secret), not in plain text in the registry.
        & $autologon $user $domain $plain /accepteula | Out-Null
        Write-Host "✓ Đã bật tự đăng nhập cho $user" -ForegroundColor Green
    } catch {
        Write-Host "Không bật được tự đăng nhập ($($_.Exception.Message)). Bật tay: Win+R → netplwiz → bỏ tick 'Users must enter a user name and password'." -ForegroundColor Red
    }
    $plain = $null
} else {
    Write-Host "✓ Tự đăng nhập đã bật"
}

Write-Host ""
Write-Host "XONG. Thỉnh thoảng (khi thị trường nghỉ cuối tuần) tự vào Settings → Windows Update để cài bản cập nhật rồi khởi động lại." -ForegroundColor Green
Write-Host "Bot tự chạy lại sau khi Windows khởi động (đã cài tự đăng nhập + tác vụ GoldBot)." -ForegroundColor Green
