#!/usr/bin/env bash
# Builds FRC Scout for SideStore, which re-signs the IPA with your Apple ID on install.
#   ./build.sh                 build/Scout.ipa to AirDrop (same version as the latest release)
#   ./build.sh --ipa 1.2 42    build/Scout.ipa as version 1.2, build 42 (the release workflow uses this)
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
    swiftc -o build/check Scout/Store.swift Scout/Fetch.swift Checks/main.swift
    build/check
    ;;
  --ipa)
    ipa "${2:?version}" "${3:?build number}"
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
