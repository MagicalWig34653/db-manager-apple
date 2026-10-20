#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d /tmp/dbmanager-apple-check.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT HUP INT TERM
swift test --scratch-path "$check_dir/swift" -j 4
for platform in macOS 'iOS Simulator'; do
  if ! xcodebuild -project DBManager.xcodeproj -scheme DBManager \
      -destination "generic/platform=$platform" -derivedDataPath "$check_dir/xcode-$platform" \
      CODE_SIGNING_ALLOWED=NO build > "$check_dir/xcode.log" 2>&1; then
    tail -n 60 "$check_dir/xcode.log"
    exit 1
  fi
  echo "Build bestanden: $platform"
done
python3 scripts/check-docs.py
