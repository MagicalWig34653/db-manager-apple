#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Compile by default; --run explicitly permits only isolated synthetic keychain items."""
from pathlib import Path
import argparse
import json
import platform
import shutil
import subprocess
import tempfile
import sys

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--run', action='store_true')
parser.add_argument('--output', type=Path)
arguments = parser.parse_args()
with tempfile.TemporaryDirectory(prefix='dbmanager-gs2b-build-') as directory:
    build = Path(directory).resolve()
    command = ['swift','build','--package-path',str(ROOT),'--scratch-path',str(build)]
    subprocess.run(command+['-j','4'],check=True)
    if not arguments.run:
        print('Compile passed. No keychain API invoked.')
        sys.exit(0)
    binary = Path(subprocess.check_output(command+['--show-bin-path'],text=True).strip())/'keychain-gate'
    owned = Path(tempfile.mkdtemp(prefix='dbmanager-gs2b-receipt-')).resolve()
    receipt = owned/'receipt.json'
    try:
        child = subprocess.run([str(binary),str(receipt)],timeout=15,check=False)
    except subprocess.TimeoutExpired:
        print('Uncertain client timeout; exact synthetic identity receipt retained:',receipt)
        sys.exit(3)
    report = json.loads(receipt.read_text())
    report['system'] = platform.platform()
    signing = subprocess.run(['codesign','-dvv',str(binary)],capture_output=True,text=True,check=False)
    report['own_host_signing'] = {line.split('=',1)[0]:line.split('=',1)[1]
        for line in signing.stderr.splitlines() if line.startswith(('Signature=','TeamIdentifier='))}
    if arguments.output:
        arguments.output.parent.mkdir(parents=True,exist_ok=True)
        arguments.output.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print(json.dumps(report,sort_keys=True))
    if report.get('cleanup_needed'):
        print('Cleanup of an uncertain own item is NOT claimed; exact receipt retained:',receipt)
    else:
        shutil.rmtree(owned)
    sys.exit(child.returncode)
