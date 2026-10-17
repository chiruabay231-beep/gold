#!/bin/sh
# Saves the Team and Bundle ID chosen in Xcode (Signing & Capabilities) to
# Signing.local.xcconfig, so `xcodegen generate` keeps them from now on.
set -e
cd "$(dirname "$0")"
pbx=GoldBacktest.xcodeproj/project.pbxproj
if [ ! -f "$pbx" ]; then
    echo "Chưa có GoldBacktest.xcodeproj. Chạy: xcodegen generate"
    exit 1
fi
team=$(grep -Eo 'DEVELOPMENT_TEAM = "?[A-Z0-9]{10}"?;' "$pbx" | head -1 | sed -E 's/.*= "?([A-Z0-9]{10})"?;/\1/' || true)
bundle=$(grep -Eo 'PRODUCT_BUNDLE_IDENTIFIER = "?[A-Za-z0-9.-]+"?;' "$pbx" | head -1 | sed -E 's/.*= "?([^";]+)"?;/\1/' || true)
if [ -z "$team" ]; then
    echo "Chưa thấy Team. Trong Xcode: target GoldBacktest > Signing & Capabilities > chọn Team, rồi chạy lại script này."
    exit 1
fi
[ -n "$bundle" ] || bundle=com.gold.backtest
cat > Signing.local.xcconfig <<CONFIG
// Written by save-signing.sh. Not committed to git.
DEVELOPMENT_TEAM = $team
PRODUCT_BUNDLE_IDENTIFIER = $bundle
CONFIG
echo "Đã lưu: Team = $team, Bundle ID = $bundle"
