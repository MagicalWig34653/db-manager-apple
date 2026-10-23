#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Build a local archive; never upload or submit an app."""
import argparse
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--platform', choices=['ipad', 'mac'], required=True)
parser.add_argument('--output-dir', type=Path, required=True)
parser.add_argument('--provision', action='store_true', help='Allow existing Xcode account provisioning and signing')
parser.add_argument('--export', action='store_true', help='Locally export App Store artifact; requires --provision')
args = parser.parse_args()
if args.export and not args.provision:
    parser.error('--export requires --provision')
output = args.output_dir.resolve()
output.mkdir(parents=True, exist_ok=True)
archive = output / (args.platform + '.xcarchive')
if archive.exists():
    parser.error('Archive already exists; choose a fresh output directory')
options = ROOT / 'Distribution/ExportOptions-AppStore.plist'
config = plistlib.loads(options.read_bytes())
if config.get('destination') != 'export' or config.get('method') != 'app-store-connect':
    parser.error('Export configuration must remain local App Store export')
command = ['xcodebuild', '-project', str(ROOT / 'DBManager.xcodeproj'), '-scheme', 'DBManager',
           '-configuration', 'Release', '-destination', 'generic/platform=' + ('iOS' if args.platform == 'ipad' else 'macOS'),
           '-derivedDataPath', str(output / 'DerivedData'), '-clonedSourcePackagesDirPath', str(output / 'Packages'),
           '-onlyUsePackageVersionsFromResolvedFile', '-archivePath', str(archive)]
command += ['-allowProvisioningUpdates'] if args.provision else ['CODE_SIGNING_ALLOWED=NO']
subprocess.run(command + ['archive'], cwd=ROOT, check=True)
if args.export:
    subprocess.run(['xcodebuild', '-exportArchive', '-archivePath', str(archive), '-exportOptionsPlist', str(options),
                    '-exportPath', str(output / 'Export'), '-allowProvisioningUpdates'], cwd=ROOT, check=True)
print('Local preparation finished. Nothing uploaded or submitted.')
