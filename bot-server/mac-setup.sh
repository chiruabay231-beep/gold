#!/bin/bash
# Keeps a Mac awake for the gold bot's Windows virtual machine (Parallels / UTM) running MT5 24/7.
#
# Open Terminal on the Mac and paste:
#   curl -fsSL https://raw.githubusercontent.com/chiruabay231-beep/gold/claude/ios-backtest-custom-indicators-jptyoz/bot-server/mac-setup.sh | bash
#
# It asks for the Mac's password once (sudo) and:
#   - on the charger: never sleeps (the screen still turns off), disks never spin down;
#   - starts again by itself after a power cut, wakes for network access;
#   - keeps `caffeinate` running from login (a second guard against sleep), as a LaunchAgent.
#   - VMware Fusion: starts the Windows virtual machine by itself at login (Fusion has no such option of its own).
# Undo: bash mac-setup.sh --undo

set -e

AGENT="$HOME/Library/LaunchAgents/com.goldbot.caffeinate.plist"
VMAGENT="$HOME/Library/LaunchAgents/com.goldbot.vmware.plist"
VMRUN="/Applications/VMware Fusion.app/Contents/Library/vmrun"

if [ "$1" = "--undo" ]; then
  echo "==> Trả Mac về chế độ ngủ bình thường"
  sudo pmset -c sleep 1 disksleep 10 >/dev/null
  launchctl unload "$AGENT" 2>/dev/null || true
  launchctl unload "$VMAGENT" 2>/dev/null || true
  rm -f "$AGENT" "$VMAGENT"
  echo "Xong."
  exit 0
fi

echo "==> Mac không ngủ khi cắm sạc (màn hình vẫn tắt để tiết kiệm)"
sudo pmset -c sleep 0 disksleep 0 displaysleep 10 >/dev/null
echo "==> Tự bật lại sau khi mất điện, thức dậy khi có kết nối mạng"
sudo pmset -a autorestart 1 >/dev/null 2>&1 || true
sudo pmset -a womp 1 >/dev/null 2>&1 || true
# Power Nap off: it can freeze virtual machines in the background.
sudo pmset -a powernap 0 >/dev/null 2>&1 || true

echo "==> Giữ Mac thức từ lúc đăng nhập (caffeinate)"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$AGENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.goldbot.caffeinate</string>
  <key>ProgramArguments</key>
  <array><string>/usr/bin/caffeinate</string><string>-ims</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
PLIST
launchctl unload "$AGENT" 2>/dev/null || true
launchctl load "$AGENT"

if [ -x "$VMRUN" ]; then
  # The Windows virtual machine made in VMware Fusion (the first one found), started at login (with its window, so Fusion reads the encryption password from the Keychain).
  VMX=$(find "$HOME/Virtual Machines.localized" "$HOME/Virtual Machines" "$HOME/Documents/Virtual Machines.localized" \
        -maxdepth 3 -name "*.vmx" 2>/dev/null | grep -i -m1 "win" || true)
  [ -z "$VMX" ] && VMX=$(find "$HOME/Virtual Machines.localized" "$HOME/Virtual Machines" -maxdepth 3 -name "*.vmx" 2>/dev/null | head -1)
  if [ -n "$VMX" ]; then
    echo "==> VMware: tự bật máy ảo khi đăng nhập Mac ($VMX)"
    cat > "$VMAGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.goldbot.vmware</string>
  <key>ProgramArguments</key>
  <array><string>$VMRUN</string><string>-T</string><string>fusion</string><string>start</string><string>$VMX</string><string>gui</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST
    launchctl unload "$VMAGENT" 2>/dev/null || true
    launchctl load "$VMAGENT"
  else
    echo "==> VMware: chưa thấy máy ảo nào — tạo máy ảo Windows xong thì chạy lại lệnh này"
  fi
fi

echo ""
echo "==================== XONG ===================="
pmset -g | grep -E " sleep| disksleep| autorestart| womp| powernap" || true
echo ""
echo "Việc còn lại làm tay (xem hướng dẫn MAC.md):"
echo "  1. Cài đặt hệ thống → Người dùng & Nhóm → Tự động đăng nhập: chọn tài khoản của bạn"
echo "     (để sau khi mất điện Mac tự vào màn hình chính và mở máy ảo)."
echo "  2. Parallels / UTM: cho máy ảo Windows tự chạy khi mở Mac (VMware: lệnh này đã làm)."
echo "  3. MacBook: luôn cắm sạc; gập máy sẽ ngủ trừ khi cắm màn hình ngoài."
