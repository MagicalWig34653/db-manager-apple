#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Verify exact package provenance and unmodified bundled license notices."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NOTICES = ROOT/'Sources/DBManagerCore/Resources/ThirdParty'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkouts',type=Path)
    parser.add_argument('--products',type=Path)
    args = parser.parse_args()
    lock = json.loads((ROOT/'Package.resolved').read_text())
    project = json.loads((ROOT/'DBManager.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_text())
    pins = {p['identity']:p for p in lock['pins']}
    assert {p['identity']:p['state'] for p in project['pins']} == {name:p['state'] for name,p in pins.items()}, 'SwiftPM/Xcode dependency graph differs'
    inventory = json.loads((NOTICES/'inventory.json').read_text())['packages']
    assert {p['identity'] for p in inventory} == set(pins)
    for package in inventory:
        pin = pins[package['identity']]
        assert package['revision'] == pin['state']['revision']
        assert package['version'] == pin['state'].get('version')
        assert package['repository'] == pin['location']
        for path,digest in package['original_notices_sha256'].items():
            raw = (NOTICES/package['identity']/path).read_bytes()
            raw.decode('utf-8')
            assert hashlib.sha256(raw).hexdigest() == digest
            if args.checkouts:
                assert (args.checkouts/package['identity']/path).read_bytes() == raw
        if 'bundled_boringssl' in package:
            info = package['bundled_boringssl']; base = NOTICES/package['identity']/'boringssl'
            assert hashlib.sha256((base/'LICENSE').read_bytes()).hexdigest() == info['license_sha256']
            assert hashlib.sha256((base/'hash.txt').read_bytes()).hexdigest() == info['vendor_hash_sha256']
            assert info['revision'] in (base/'hash.txt').read_text()
            if args.checkouts:
                vendor = 'CNIOBoringSSL' if package['identity']=='swift-nio-ssl' else 'CCryptoBoringSSL'
                source = args.checkouts/package['identity']/'Sources'/vendor
                assert (source/'hash.txt').read_bytes() == (base/'hash.txt').read_bytes()
                header_path = 'ssl/ssl_lib.cc' if package['identity']=='swift-nio-ssl' else 'crypto/asn1/a_bitstr.cc'
                header = (source/header_path).read_text()
                assert 'Licensed under the Apache License, Version 2.0' in header[:2000]
    assert (NOTICES/'AGPL-3.0-only-LICENSE').read_bytes() == (ROOT/'LICENSE').read_bytes()
    if args.products:
        apps = list(args.products.rglob('DBManager.app'))
        assert len(apps) == 1, 'Expected one built app'
        inventories = list(apps[0].rglob('ThirdParty/inventory.json'))
        assert len(inventories) == 1, 'App original notices missing or ambiguous'
        bundled = inventories[0].parent
        for path in NOTICES.rglob('*'):
            if path.is_file():
                assert (bundled/path.relative_to(NOTICES)).read_bytes() == path.read_bytes()
    print(f'{len(pins)} exact dependency pins, matching Xcode graph and original notice hashes passed.')

if __name__ == '__main__': main()
