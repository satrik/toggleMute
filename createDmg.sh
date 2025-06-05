#!/usr/bin/env bash
cd toggleMute
xcodebuild clean build analyze -scheme "toggleMute" -project "toggleMute.xcodeproj"
xcodebuild archive -scheme "toggleMute" -archivePath App.xcarchive
cp ../toggleMuteDisableQuarantine.command App.xcarchive/Products/Applications/toggleMuteDisableQuarantine.command
cp ../README.md App.xcarchive/Products/Applications/README.md
chmod +x App.xcarchive/Products/Applications/toggleMuteDisableQuarantine.command
ln -s /Applications/ App.xcarchive/Products/Applications/Applications
hdiutil create -volname "toggleMute" -srcfolder "App.xcarchive/Products/Applications/" -ov -format UDZO "../toggleMute.dmg"
echo -e "$(cat ../changes)\n\nDMG_CHECKSUM: $(shasum -a 256 -b "../toggleMute.dmg" | awk '{print $1 }')"