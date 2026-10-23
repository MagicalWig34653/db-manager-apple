#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Verify identity, icon fallback, privacy and optional signing of an actual app."""
import argparse
from pathlib import Path
import plistlib
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--expected-build', default='2', help='Expected CFBundleVersion; defaults to the current build')
parser.add_argument('--signed', action='store_true')
parser.add_argument('--distribution-profile', action='store_true')
args = parser.parse_args()
app = args.app.resolve()
mac = (app / 'Contents').is_dir()
resources = app / 'Contents/Resources' if mac else app
info = plistlib.loads((app / 'Contents/Info.plist' if mac else app / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'de.linolaske.dbmanager'
assert info['CFBundleShortVersionString'] == '0.1.0'
assert info['CFBundleVersion'] == args.expected_build
assert 'ITSAppUsesNonExemptEncryption' not in info, 'Owner export assessment remains an explicit gate'
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
# Inspect every architecture separately: a valid arm64 runpath must not hide an
# unresolved dependency in the x86_64 slice of the universal macOS executable.
binary = app / ('Contents/MacOS' if mac else '') / info['CFBundleExecutable']
frameworks = app / ('Contents/Frameworks' if mac else 'Frameworks')
architectures = subprocess.check_output(['xcrun', 'lipo', '-archs', str(binary)], text=True).split()
for architecture in architectures:
    load_commands = subprocess.check_output(
        ['xcrun', 'otool', '-arch', architecture, '-l', str(binary)], text=True)
    runpaths = re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset', load_commands)
    for command in load_commands.split('Load command'):
        if not re.search(r'cmd LC_(?:LOAD|REEXPORT)_DYLIB\s', command):
            continue
        match = re.search(r'name (@rpath/.*?) \(offset', command)
        if not match:
            continue
        dependency = match.group(1).removeprefix('@rpath/')
        embedded = frameworks / dependency
        # Absolute system references may live in the dyld shared cache; do not
        # incorrectly require an ordinary filesystem entry for system dylibs.
        if not embedded.is_file():
            assert not dependency.startswith('libswiftCompatibility'), (
                f'Back-deployment library is not embedded: {dependency} ({architecture})')
            continue
        candidates = []
        for runpath in runpaths:
            resolved = runpath.replace('@executable_path', str(binary.parent)).replace(
                '@loader_path', str(binary.parent))
            candidates.append((Path(resolved) / dependency).resolve())
        assert embedded.resolve() in candidates, (
            f'Embedded dependency has no app-local LC_RPATH: {dependency} ({architecture})')
        embedded_architectures = subprocess.check_output(
            ['xcrun', 'lipo', '-archs', str(embedded)], text=True).split()
        assert architecture in embedded_architectures, (
            f'Embedded dependency lacks architecture: {dependency} ({architecture})')
print('Per-architecture embedded dependency runpaths passed')
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
