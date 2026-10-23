#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d /tmp/dbmanager-apple-check.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT HUP INT TERM
sh scripts/check-icon.sh
python3 scripts/check-dependencies.py
swift test --force-resolved-versions --scratch-path "$check_dir/swift" -j 4
python3 scripts/check-calendar-vectors.py
python3 scripts/check-dependencies.py --checkouts "$check_dir/swift/checkouts"
for platform in macOS 'iOS Simulator'; do
  if ! xcodebuild -project DBManager.xcodeproj -scheme DBManager \
      -destination "generic/platform=$platform" -derivedDataPath "$check_dir/xcode-$platform" \
      -clonedSourcePackagesDirPath "$check_dir/packages" -onlyUsePackageVersionsFromResolvedFile \
      CODE_SIGNING_ALLOWED=NO build > "$check_dir/xcode.log" 2>&1; then
    python3 - "$check_dir/xcode.log" <<'PYERROR'
from pathlib import Path
import sys
lines = Path(sys.argv[1]).read_text(errors="replace").splitlines()
for position, line in enumerate(lines):
    if "error:" in line.lower() or "com.apple.actool.errors" in line:
        print("\n".join(lines[max(0, position - 3):position + 8]))
PYERROR
    tail -n 60 "$check_dir/xcode.log"
    exit 1
  fi
  python3 scripts/check-dependencies.py --products "$check_dir/xcode-$platform/Build/Products"
  if [ "$platform" = macOS ]; then
    product_dir=Debug
  else
    product_dir=Debug-iphonesimulator
  fi
  python3 scripts/check-distribution.py --app "$check_dir/xcode-$platform/Build/Products/$product_dir/DBManager.app"
  echo "Build bestanden: $platform"
done
python3 scripts/check-docs.py
