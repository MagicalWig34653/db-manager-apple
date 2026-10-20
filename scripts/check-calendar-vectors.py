#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Compare the actual integer calendar helper with independent Python AD vectors."""
import datetime
from pathlib import Path
import random
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
source = (ROOT/'Sources/DBManagerCore/PostgresValues.swift').read_text()
helper = source[source.index('    static func date('):source.rfind('}')]
probe = 'enum CalendarProbe {\n' + helper + '\n}\n'
epoch = datetime.date(2000, 1, 1)
values = [datetime.date(1,1,1), datetime.date(1500,1,1), datetime.date(1582,10,4),
          datetime.date(1582,10,5), datetime.date(1600,2,29), datetime.date(1900,3,1),
          datetime.date(2000,2,29), datetime.date(9999,12,31)]
randomizer = random.Random(20261020)
start = datetime.date(1,1,1)
span = (datetime.date(9999,12,31) - start).days
values += [start + datetime.timedelta(days=randomizer.randrange(span)) for _ in range(1000)]
for value in values:
    days = (value-epoch).days
    probe += f'assert(CalendarProbe.date({days}) == "{value.isoformat()}")\n'
    for micros in [0, 1, 123456, 999999]:
        # Python datetime supplies an independent proleptic-Gregorian calendar.
        total = days * 86_400_000_000 + 12_345_000_000 + micros
        expected = value.isoformat() + f'T03:25:45.{micros:06d}Z'
        probe += f'assert(CalendarProbe.timestamp({total}, zoned: true) == "{expected}")\n'
with tempfile.TemporaryDirectory(prefix='dbmanager-calendar-', dir='/tmp') as temporary:
    path = Path(temporary)/'probe.swift'
    path.write_text(probe)
    subprocess.run(['swift',str(path)],check=True,timeout=120)
print('1008 independent Gregorian AD date vectors and 4032 exact timestamp vectors passed.')
