#!/bin/bash
# Собирает Андреич.app (без Xcode, только Swift из Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="Андреич.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/AndreichNotch "$APP/Contents/MacOS/AndreichNotch"
mkdir -p "$APP/Contents/Resources/web"
(cd andreich3d && npx esbuild app-entry.js --bundle --format=iife --minify --outfile=dist/andreich.bundle.js --log-level=warning && cp app.html dist/app.html)
cp andreich3d/dist/app.html andreich3d/dist/andreich.bundle.js "$APP/Contents/Resources/web/"
cp scripts/usage.py "$APP/Contents/Resources/usage.py"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Андреич</string>
  <key>CFBundleDisplayName</key><string>Андреич</string>
  <key>CFBundleIdentifier</key><string>ru.oaiweb.andreich</string>
  <key>CFBundleExecutable</key><string>AndreichNotch</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Андреич слушает, только когда вы включаете микрофон: речь идёт в протокол, звук — в файл на этом Маке. Никуда не отправляется.</string>
  <key>NSRemindersFullAccessUsageDescription</key><string>Чтобы по вашей команде добавлять услышанные напоминания в приложение «Напоминания».</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Распознавание русской речи прямо на Маке, чтобы вести протокол разговоров.</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Готово: $PWD/$APP"
