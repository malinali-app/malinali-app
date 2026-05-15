# BUILDME

## Turso credentials

Create `secrets.txt` at the project root with two lines: database URL, then auth token. The file is gitignored. The app reads it at startup from the project directory and from bundled assets when present.

Build-time `TURSO_DATABASE_URL` and `TURSO_AUTH_TOKEN` values override `secrets.txt`.

## macOS

flutter build macos
hdiutil create -volname "Malinali" -srcfolder "build/macos/Build/Products/Release/malinali.app" -ov -format UDZO "malinali.dmg"

## Run

flutter run

flutter run --dart-define=MALINALI_SKIP_AUTO_TURSO_SYNC=true
