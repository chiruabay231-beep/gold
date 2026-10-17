#!/bin/sh
# Pulls the latest code and regenerates the Xcode project.
# Then press ▶︎ (⌘R) in Xcode.
set -e
cd "$(dirname "$0")"
git pull
xcodegen generate
echo "Xong. Quay lại Xcode và bấm ▶︎ (⌘R)."
