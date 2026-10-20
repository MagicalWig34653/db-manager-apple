#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d /tmp/dbmanager-apple-check.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT HUP INT TERM
python3 scripts/check-dependencies.py
swift test --force-resolved-versions --scratch-path "$check_dir/swift" -j 4
python3 scripts/check-calendar-vectors.py
python3 scripts/check-dependencies.py --checkouts "$check_dir/swift/checkouts"
for platform in macOS 'iOS Simulator'; do
  if ! xcodebuild -project DBManager.xcodeproj -scheme DBManager \
      -destination "generic/platform=$platform" -derivedDataPath "$check_dir/xcode-$platform" \
      -clonedSourcePackagesDirPath "$check_dir/packages" -onlyUsePackageVersionsFromResolvedFile \
      CODE_SIGNING_ALLOWED=NO build > "$check_dir/xcode.log" 2>&1; then
    tail -n 60 "$check_dir/xcode.log"
    exit 1
  fi
  python3 scripts/check-dependencies.py --products "$check_dir/xcode-$platform/Build/Products"
  echo "Build bestanden: $platform"
done
python3 scripts/check-docs.py
