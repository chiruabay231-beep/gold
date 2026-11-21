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
# Check what is set: ... | bash -s -- --check      Undo: bash mac-setup.sh --undo

set -e

AGENT="$HOME/Library/LaunchAgents/com.goldbot.caffeinate.plist"
VMAGENT="$HOME/Library/LaunchAgents/com.goldbot.vmware.plist"
VMRUN="/Applications/VMware Fusion.app/Contents/Library/vmrun"

if [ "$1" = "--check" ]; then
  # What is set now: does the Mac stay awake for the virtual machine?
  ok=0
  echo "==================== KIỂM TRA MAC ===================="
  ac=$(pmset -g custom | awk '/AC Power/{f=1;next} /Battery Power|UPS Power/{f=0} f && $1=="sleep"{print $2; exit}')
  [ -z "$ac" ] && ac=$(pmset -g | awk '$1=="sleep"{print $2; exit}')
  if [ "$ac" = "0" ]; then echo "✅ Cắm sạc: Mac KHÔNG tự ngủ"; else echo "❌ Cắm sạc: Mac tự ngủ sau ${ac:-?} phút"; ok=1; fi
  if launchctl list | grep -q com.goldbot.caffeinate && pgrep -x caffeinate >/dev/null; then
    echo "✅ Lớp chống ngủ (caffeinate) đang chạy"
  else
    echo "❌ Lớp chống ngủ (caffeinate) chưa chạy"; ok=1
  fi
  if [ -x "$VMRUN" ]; then
    if launchctl list | grep -q com.goldbot.vmware; then echo "✅ Tự mở máy ảo VMware khi đăng nhập Mac"; else echo "❌ Chưa tự mở máy ảo VMware khi đăng nhập Mac"; ok=1; fi
    running=$("$VMRUN" list 2>/dev/null | head -1)
    echo "   VMware: ${running:-không đọc được}"
  fi
  [ "$(pmset -g | awk '$1=="autorestart"{print $2}')" = "1" ] && echo "✅ Tự bật lại sau khi mất điện" || { echo "❌ Chưa tự bật lại sau khi mất điện"; ok=1; }
  pn=$(pmset -g | awk '$1=="powernap"{print $2}')
  [ "$pn" = "1" ] && { echo "❌ Power Nap đang bật (có thể làm máy ảo bị đóng băng)"; ok=1; } || echo "✅ Power Nap tắt"
  user=$(defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true)
  [ -n "$user" ] && echo "✅ Tự đăng nhập Mac: $user" || echo "⚠️ Mac chưa tự đăng nhập (Cài đặt hệ thống → Người dùng & Nhóm → Tự động đăng nhập)"
  if pmset -g batt 2>/dev/null | grep -q "InternalBattery"; then
    pmset -g batt | grep -q "AC Power" && echo "✅ MacBook đang cắm sạc" || { echo "❌ MacBook đang chạy PIN: cắm sạc (chạy pin vẫn có thể ngủ)"; ok=1; }
    echo "⚠️ MacBook: GẬP NẮP là ngủ (trừ khi cắm màn hình ngoài) — để mở nắp"
  fi
  echo ""
  [ $ok = 0 ] && echo "==> Mac đã cài KHÔNG NGỦ đầy đủ." || echo "==> Còn mục ❌: chạy lại lệnh cài (không có --check) để sửa."
  exit 0
fi

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
  # Elsewhere (another folder or disk): the virtual machine running now, as VMware lists it.
  [ -z "$VMX" ] && VMX=$("$VMRUN" list 2>/dev/null | grep -i "\.vmx$" | head -1 || true)
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
    echo "==> VMware: chưa thấy máy ảo nào — mở máy ảo Windows trong VMware rồi chạy lại lệnh này"
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
