# Backs up the gold bot's data on the old Windows machine (VPS) before moving to another one.
#
# Open PowerShell on the old VPS and paste:
#   irm https://raw.githubusercontent.com/chiruabay231-beep/gold/claude/ios-backtest-custom-indicators-jptyoz/bot-server/backup.ps1 | iex
#
# It makes GoldBot-backup.zip on the Desktop: the server's settings (password, MT5 login, Telegram, members and
# their invite codes, bots' settings), its state, the drawings, the virtual accounts' trades and the computer's own
# account copy (web.*). Copy that zip to the new machine and give it to install.ps1 -Restore.

param([string]$Dir = "C:\GoldBot")

$ErrorActionPreference = "Stop"
if (-not (Test-Path $Dir)) { Write-Host "Không thấy thư mục bot $Dir" -ForegroundColor Red; return }

# The files that are the bot's data (the program itself is downloaded again on the new machine).
$names = @("config.json", "state.json", "stops.json", "drawings.json", "tickbot_paper.json", "gridbot_paper.json")
$files = @()
foreach ($n in $names) { $p = Join-Path $Dir $n; if (Test-Path $p) { $files += $p } }
$files += Get-ChildItem -Path $Dir -Filter "web.*" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "*.log*" } | ForEach-Object { $_.FullName }
if (-not $files.Count) { Write-Host "Không có dữ liệu nào để sao lưu trong $Dir" -ForegroundColor Red; return }

$desktop = [Environment]::GetFolderPath("Desktop")
$zip = Join-Path $desktop "GoldBot-backup.zip"
Remove-Item $zip -ErrorAction SilentlyContinue
Compress-Archive -Path $files -DestinationPath $zip -Force

Write-Host ""
Write-Host "==================== XONG ====================" -ForegroundColor Green
Write-Host "Đã sao lưu $($files.Count) file vào: $zip" -ForegroundColor Green
$files | ForEach-Object { Write-Host "  - $(Split-Path $_ -Leaf)" }
Write-Host ""
Write-Host "Chép file GoldBot-backup.zip này sang máy mới (Google Drive, email cho chính mình, USB...)."
Write-Host "File có mật khẩu máy chủ và đăng nhập MT5: KHÔNG gửi cho người khác."
