#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Build and verify the isolated S2a package, with only synthetic crash fixtures."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = ROOT / 'Packages/DBManagerVault'

def run(arguments, **options):
    subprocess.run(arguments, check=True, **options)

def check_pins():
    lock = json.loads((PACKAGE/'format-lock.json').read_text())
    assert lock['schema_sha256'] == 'b688656056fe2e23848ce17149bc817609c7369f230a3f49dd91f05db4d3f4dd'
    for name, expected in lock['sha256'].items():
        assert hashlib.sha256((PACKAGE/name).read_bytes()).hexdigest() == expected, name
    assert hashlib.sha256((PACKAGE/'Format/contracts/vault-v1.schema.json').read_bytes()).hexdigest() == lock['schema_sha256']
    vendor = PACKAGE/'Vendor/argon2'
    upstream = json.loads((vendor/'upstream-lock.json').read_text())
    assert upstream['commit'] == 'f57e61e19229e23c4445b85494dbf7c07de721cb'
    assert len(upstream['sha256']) == 14
    for name, expected in upstream['sha256'].items():
        assert hashlib.sha256((vendor/name).read_bytes()).hexdigest() == expected, name
    assert (vendor/'LICENSE').read_bytes() == (PACKAGE/'Sources/DBManagerVault/Notices/Argon2-LICENSE.txt').read_bytes()
    assert (ROOT/'LICENSE').read_bytes() == (PACKAGE/'Sources/DBManagerVault/Notices/AGPL-3.0-only.txt').read_bytes()
    for language in ['go','swift']:
        for name in ['vault.json','synthetic-secrets.json']:
            assert (PACKAGE/f'Format/contracts/fixtures/vault-v1/{language}/{name}').read_bytes() == (PACKAGE/f'Tests/DBManagerVaultTests/Fixtures/{language}/{name}').read_bytes()
    print('Pinned v1 format, both public synthetic fixtures and 14 original Argon2 files passed.', flush=True)

def check_crashes(temporary):
    copied = temporary/'crash-package'
    shutil.copytree(PACKAGE, copied, ignore=shutil.ignore_patterns('.build','.swiftpm'))
    manifest = (copied/'Package.swift').read_text()
    manifest = manifest.replace('targets: [\n', 'targets: [\n        .executableTarget(name: "VaultCrashProbe", dependencies: ["DBManagerVault"], path: "Tools"),\n', 1)
    (copied/'Package.swift').write_text(manifest)
    scratch = temporary/'crash-build'
    run(['swift','build','--package-path',str(copied),'--scratch-path',str(scratch),'--product','VaultCrashProbe','-j','4'])
    binary = subprocess.check_output(['swift','build','--package-path',str(copied),'--scratch-path',str(scratch),'--show-bin-path'],text=True).strip()
    points = ['afterReservation','afterStaging','afterPrepared','afterRename','afterDirectorySync','afterFinalization']
    for index, point in enumerate(points):
        base = temporary/f'crash-case-{index}'
        (base/'managed').mkdir(parents=True,mode=0o700)
        executable = [str(Path(binary)/'VaultCrashProbe'),str(base)]
        run(executable+['setup'])
        child = subprocess.run(executable+[point],check=False)
        assert child.returncode == 86, (point,child.returncode)
        run(executable+['verify-new' if index >= 3 else 'verify-old'])
    print('Six real abrupt child exits: lock release, old/new recovery and burned reservations passed.', flush=True)

if __name__ == '__main__':
    check_pins()
    with tempfile.TemporaryDirectory(prefix='dbmanager-s2a-check-') as name:
        temporary = Path(name).resolve()
        run(['swift','test','--package-path',str(PACKAGE),'--scratch-path',str(temporary/'mac'),'-j','4'])
        sdk = subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip()
        run(['swift','build','--package-path',str(PACKAGE),'--scratch-path',str(temporary/'ipad'),
             '--triple','arm64-apple-ios17.0-simulator','--sdk',sdk,'--target','DBManagerVault','-j','4'])
        check_crashes(temporary)
    print('Isolated S2a verification passed; no app, OS anchor or device approval implied.', flush=True)
