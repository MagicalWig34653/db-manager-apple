#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
set -eu
cd "$(dirname "$0")/.."
icon_check_dir=$(mktemp -d /tmp/dbmanager-icon-check.XXXXXX)
trap 'rm -rf "$icon_check_dir"' EXIT HUP INT TERM
# platform:device pairs; the iOS SDK is compiled once for iPad and once for iPhone.
for variant in macosx:mac iphonesimulator:ipad iphonesimulator:iphone; do
  platform=${variant%%:*}
  target_device=${variant##*:}
  minimum_version=26.0
  mkdir "$icon_check_dir/$target_device"
  xcrun actool Assets/AppIcon.icon \
    --compile "$icon_check_dir/$target_device" \
    --output-format human-readable-text --notices --warnings \
    --platform "$platform" --minimum-deployment-target "$minimum_version" \
    --target-device "$target_device" --app-icon AppIcon \
    --bundle-identifier de.linolaske.dbmanager \
    --output-partial-info-plist "$icon_check_dir/$target_device-info.plist"
  test -s "$icon_check_dir/$target_device/Assets.car"
  echo "Icon compilation passed: $platform ($target_device)"
done
