#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Verify identity, icon fallback, privacy and optional signing of an actual app."""
import argparse
from pathlib import Path
import plistlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--signed', action='store_true')
parser.add_argument('--distribution-profile', action='store_true')
args = parser.parse_args()
app = args.app.resolve()
mac = (app / 'Contents').is_dir()
resources = app / 'Contents/Resources' if mac else app
info = plistlib.loads((app / 'Contents/Info.plist' if mac else app / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'de.linolaske.dbmanager'
assert info['CFBundleShortVersionString'] == '0.1.0'
assert info['CFBundleVersion'] == '2'
assert info.get('ITSAppUsesNonExemptEncryption') is True, 'Standard encryption usage must be declared'
assert (resources / 'Assets.car').is_file(), 'Compiled icon catalog absent'
if mac:
    assert info.get('CFBundleIconFile'), 'Older macOS fallback declaration absent'
else:
    assert info['UIDeviceFamily'] == [2]
    assert len(info.get('UISupportedInterfaceOrientations~ipad', [])) == 4
    assert info['CFBundleIcons~ipad']['CFBundlePrimaryIcon']['CFBundleIconName'] == 'AppIcon'
    assert (resources / 'AppIcon76x76@2x~ipad.png').is_file(), 'Older iPadOS fallback absent'
privacy = plistlib.loads((resources / 'PrivacyInfo.xcprivacy').read_bytes())
assert privacy['NSPrivacyTracking'] is False
assert privacy['NSPrivacyCollectedDataTypes'] == []
assert {'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategorySystemBootTime',
        'NSPrivacyAccessedAPITypeReasons': ['35F9.1']} in privacy['NSPrivacyAccessedAPITypes']
if args.signed:
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    result = subprocess.run(['codesign', '-dv', str(app)], capture_output=True, text=True, check=True)
    assert 'TeamIdentifier=J2DU2P47XW' in result.stderr
if args.distribution_profile:
    profile = app / ('Contents/embedded.provisionprofile' if mac else 'embedded.mobileprovision')
    result = subprocess.run(['security', 'cms', '-D', '-i', str(profile)], capture_output=True, check=True)
    data = plistlib.loads(result.stdout)
    entitlements = data['Entitlements']
    identifier = entitlements.get('application-identifier', entitlements.get('com.apple.application-identifier'))
    assert identifier == 'J2DU2P47XW.de.linolaske.dbmanager'
    assert entitlements.get('get-task-allow', entitlements.get('com.apple.security.get-task-allow', False)) is False
print('Actual app identity, versions, icon fallback and privacy passed' + ('; signing passed' if args.signed else ''))
