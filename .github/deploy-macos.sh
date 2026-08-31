#!/bin/bash
# Custom macOS deploy script: assembles the .app bundle, optionally signs (no notarization).
set -ex

TARGET_DIR=${TARGET_DIR:-target}
TAG_NAME=${TAG_NAME:-$(git -c "core.abbrev=8" show -s "--format=%cd-%h" "--date=format:%Y%m%d-%H%M%S")}

zipdir=WezTerm-macos-$TAG_NAME
zipname=$zipdir.zip

rm -rf "$zipdir" "$zipname"
mkdir "$zipdir"

# Copy app skeleton
cp -r assets/macos/WezTerm.app "$zipdir/"
rm -f "$zipdir"/WezTerm.app/*.dylib

# Resources
mkdir -p "$zipdir/WezTerm.app/Contents/MacOS"
mkdir -p "$zipdir/WezTerm.app/Contents/Resources"
cp -r assets/shell-integration/* "$zipdir/WezTerm.app/Contents/Resources"
cp -r assets/shell-completion "$zipdir/WezTerm.app/Contents/Resources"
tic -xe wezterm -o "$zipdir/WezTerm.app/Contents/Resources/terminfo" termwiz/data/wezterm.terminfo

# Binaries
for bin in wezterm wezterm-mux-server wezterm-gui strip-ansi-escapes; do
  if [[ -f "$TARGET_DIR/release/$bin" ]]; then
    cp "$TARGET_DIR/release/$bin" "$zipdir/WezTerm.app/Contents/MacOS/$bin"
  else
    lipo "$TARGET_DIR"/*/release/"$bin" -output "$zipdir/WezTerm.app/Contents/MacOS/$bin" -create
  fi
done

# Code signing (no notarization)
if [[ -n "$MACOS_TEAM_ID" ]]; then
  set +x
  MACOS_PW=$(echo "$MACOS_CERT_PW" | base64 --decode)

  def_keychain=$(eval echo "$(security default-keychain -d user)")
  security delete-keychain build.keychain || true
  security create-keychain -p "$MACOS_PW" build.keychain
  security default-keychain -d user -s build.keychain
  security unlock-keychain -p "$MACOS_PW" build.keychain

  echo "$MACOS_CERT" | base64 --decode > /tmp/certificate.p12
  security import /tmp/certificate.p12 -k build.keychain -P "$MACOS_PW" -T /usr/bin/codesign
  rm /tmp/certificate.p12
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$MACOS_PW" build.keychain

  /usr/bin/codesign --keychain build.keychain --force --options runtime \
    --entitlements ci/macos-entitlement.plist --deep --sign "$MACOS_TEAM_ID" "$zipdir/WezTerm.app/"

  security default-keychain -d user -s "$def_keychain"
  security delete-keychain build.keychain || true
  set -x
fi

zip -r "$zipname" "$zipdir"
