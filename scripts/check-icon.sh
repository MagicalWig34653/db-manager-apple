#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
set -eu
cd "$(dirname "$0")/.."
icon_check_dir=$(mktemp -d /tmp/dbmanager-icon-check.XXXXXX)
trap 'rm -rf "$icon_check_dir"' EXIT HUP INT TERM
for platform in macosx iphonesimulator; do
  mkdir "$icon_check_dir/$platform"
  if [ "$platform" = macosx ]; then
    minimum_version=14.0
    target_device=mac
  else
    minimum_version=17.0
    target_device=ipad
  fi
  xcrun actool Assets/AppIcon.icon \
    --compile "$icon_check_dir/$platform" \
    --output-format human-readable-text --notices --warnings \
    --platform "$platform" --minimum-deployment-target "$minimum_version" \
    --target-device "$target_device" --app-icon AppIcon \
    --bundle-identifier de.linolaske.dbmanager \
    --output-partial-info-plist "$icon_check_dir/$platform-info.plist"
  test -s "$icon_check_dir/$platform/Assets.car"
  echo "Icon compilation passed: $platform"
done
