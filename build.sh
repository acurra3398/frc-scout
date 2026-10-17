#!/usr/bin/env bash
# Builds FRC Scout for SideStore, which re-signs the IPA with your Apple ID on install.
#   ./build.sh                 build/Scout.ipa to AirDrop (same version as the latest release)
#   ./build.sh --ipa 1.2 42    build/Scout.ipa as version 1.2, build 42 (the release workflow uses this)
#   ./build.sh --device        sign with your Xcode Apple ID and install on the plugged-in iPhones/iPads
#   ./build.sh --sim [tab]     build and launch on an iPad simulator, optionally on a tab (board, teams, ...)
#   ./build.sh --check         data-logic checks in Checks/main.swift
# To publish an update, run the Release workflow on GitHub (Actions › Release › Run workflow).
set -euo pipefail
cd "$(dirname "$0")"

ipa() {  # $1 version, $2 build number
  xcodebuild -project Scout.xcodeproj -target Scout -sdk iphoneos -configuration Release SYMROOT=build \
    CODE_SIGNING_ALLOWED=NO MARKETING_VERSION="$1" CURRENT_PROJECT_VERSION="$2" -quiet build
  rm -rf build/Payload build/Scout.ipa
  mkdir build/Payload
  cp -R build/Release-iphoneos/Scout.app build/Payload/
  (cd build && zip -qr Scout.ipa Payload && rm -rf Payload)
  echo "Built build/Scout.ipa ($1, build $2)"
}

case "${1:-}" in
  --check)
    mkdir -p build
    swiftc -o build/check Scout/Store.swift Scout/Fetch.swift Scout/SlackText.swift Checks/main.swift
    build/check
    ;;
  --ipa)
    ipa "${2:?version}" "${3:?build number}"
    ;;
  --device)
    # Signs with the Apple ID in Xcode › Settings › Accounts and installs on every plugged-in (or same
    # Wi-Fi) iPhone and iPad. Works while SideStore can't sign in; free signing lasts 7 days.
    TEAM=$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier | grep -m1 -oE 'teamID = [A-Z0-9]+' | cut -d' ' -f3)
    DEVICES=$(xcrun devicectl list devices | grep -E 'iPad|iPhone' | grep 'physical' | grep -vw 'unavailable' | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' || true)
    [[ -n "$TEAM" ]] || { echo "Sign in to Xcode › Settings › Accounts first." >&2; exit 1; }
    [[ -n "$DEVICES" ]] || { echo "No iPhone or iPad reachable: plug it in (or join the same Wi-Fi) and unlock it." >&2; exit 1; }
    for DEVICE in $DEVICES; do
      xcodebuild -project Scout.xcodeproj -scheme Scout -configuration Debug -destination "id=$DEVICE" -derivedDataPath build/device \
        -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic -quiet build
      xcrun devicectl device install app --device "$DEVICE" build/device/Build/Products/Debug-iphoneos/Scout.app
      xcrun devicectl device process launch --device "$DEVICE" com.alexcurrano.frcscout
    done
    ;;
  --sim)
    xcodebuild -project Scout.xcodeproj -target Scout -sdk iphonesimulator -configuration Debug SYMROOT=build -quiet build
    DEVICE=$(xcrun simctl list devices available | grep -m1 -oE 'iPad.*\(([0-9A-F-]{36})\)' | grep -oE '[0-9A-F-]{36}')
    xcrun simctl boot "$DEVICE" 2>/dev/null || true
    open -a Simulator
    xcrun simctl install "$DEVICE" build/Debug-iphonesimulator/Scout.app
    xcrun simctl terminate "$DEVICE" com.alexcurrano.frcscout 2>/dev/null || true
    xcrun simctl launch "$DEVICE" com.alexcurrano.frcscout ${2:+-tab "$2"}
    ;;
  *)
    # Same version as the latest release, so SideStore doesn't offer it again as an "update".
    read -r VERSION BUILD < <(python3 -c 'import json; v=json.load(open("updates/source.json"))["apps"][0]["versions"]; print(*(v[0]["version"], v[0]["buildVersion"]) if v else ("1.0", "1"))')
    ipa "$VERSION" "$BUILD"
    echo "AirDrop it to the iPad, then open it with SideStore."
    ;;
esac
