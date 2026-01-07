# BUILDME
## macOS
flutter build macos
hdiutil create -volname "Malinali" -srcfolder "build/macos/Build/Products/Release/malinali.app" -ov -format UDZO "malinali.dmg"