#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Run native PostgreSQL adapter tests against exclusively owned disposable TLS fixtures."""
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent

def run(*arguments, **kwargs):
    return subprocess.run(arguments, check=True, **kwargs)

def main():
    prefix = 'dbmanager-a2-' + secrets.token_hex(5)
    owned = []
    with tempfile.TemporaryDirectory(prefix=prefix, dir='/tmp') as temporary:
        directory = Path(temporary)
        fixture = directory/'certificates'; fixture.mkdir()
        quiet = {'stdout': subprocess.DEVNULL, 'stderr': subprocess.DEVNULL}
        run('openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN=DBManager Public Test CA','-keyout',str(fixture/'ca.key'),'-out',str(fixture/'ca.pem'),**quiet)
        run('openssl','req','-newkey','rsa:2048','-nodes','-subj','/CN=localhost','-keyout',str(fixture/'server.key'),'-out',str(fixture/'server.csr'),**quiet)
        (fixture/'extensions.cnf').write_text('subjectAltName=DNS:localhost\nextendedKeyUsage=serverAuth\n')
        run('openssl','x509','-req','-days','1','-in',str(fixture/'server.csr'),'-CA',str(fixture/'ca.pem'),'-CAkey',str(fixture/'ca.key'),'-CAcreateserial','-extfile',str(fixture/'extensions.cnf'),'-out',str(fixture/'server.pem'),**quiet)
        run('openssl','req','-newkey','rsa:2048','-nodes','-subj','/CN=wrong.invalid','-keyout',str(fixture/'wrong.key'),'-out',str(fixture/'wrong.csr'),**quiet)
        (fixture/'wrong.cnf').write_text('subjectAltName=DNS:wrong.invalid\nextendedKeyUsage=serverAuth\n')
        run('openssl','x509','-req','-days','1','-in',str(fixture/'wrong.csr'),'-CA',str(fixture/'ca.pem'),'-CAkey',str(fixture/'ca.key'),'-CAcreateserial','-extfile',str(fixture/'wrong.cnf'),'-out',str(fixture/'wrong.pem'),**quiet)
        environment = os.environ.copy()
        environment['DBM_A2_CA_FILE'] = str(fixture/'ca.pem')
        try:
            for mode in ('tls','plain','wronghost'):
                name = prefix+'-'+mode
                entry = 'chown -R postgres /fixture && chmod 600 /fixture/server.key && exec /usr/local/bin/docker-entrypoint.sh "$@"'
                args = ['docker','create','--name',name,'--label','dbmanager.task=A2','-p','127.0.0.1::5432','-e','POSTGRES_PASSWORD=public-a2-fixture','-e','POSTGRES_DB=probe','--entrypoint','/bin/sh','postgres:18.6-alpine','-c',entry,'fixture','postgres']
                if mode in ('tls','wronghost'):
                    basename = 'server' if mode == 'tls' else 'wrong'
                    args += ['-c','ssl=on','-c','ssl_cert_file=/fixture/'+basename+'.pem','-c','ssl_key_file=/fixture/'+basename+'.key']
                run(*args,stdout=subprocess.DEVNULL); owned.append(name)
                run('docker','cp',str(fixture),name+':/fixture',stdout=subprocess.DEVNULL)
                run('docker','start',name,stdout=subprocess.DEVNULL)
                for _ in range(120):
                    if subprocess.run(['docker','exec',name,'pg_isready','-h','127.0.0.1','-U','postgres','-d','probe'],**quiet).returncode == 0: break
                    time.sleep(.5)
                else: raise RuntimeError('Owned PostgreSQL fixture startup failed')
                bindings=json.loads(subprocess.check_output(['docker','inspect',name],text=True))[0]['NetworkSettings']['Ports']
                environment['DBM_A2_'+mode.upper()+'_PORT'] = bindings['5432/tcp'][0]['HostPort']
                if mode == 'tls':
                    sql = """
CREATE ROLE native_app LOGIN PASSWORD 'public-a2-fixture';
CREATE TABLE synthetic_values(amount numeric(40,20),big bigint,missing text,empty text,emptyblob bytea,raw bytea,flag boolean,zoned timestamptz,local_value timestamp,day date);
INSERT INTO synthetic_values VALUES(12345678901234567890.12345678901234567890,9223372036854775807,NULL,'',decode('','hex'),decode('00ff80','hex'),true,'2026-10-20 12:34:56.123456+00','2026-10-20 12:34:56.654321','2026-10-20');
CREATE TABLE writable(value integer);
CREATE FUNCTION mutating_function() RETURNS integer LANGUAGE plpgsql AS $$ BEGIN INSERT INTO writable VALUES(5); RETURN 5; END $$;
CREATE SCHEMA "odd""schema";
CREATE TABLE "odd""schema"."odd""table"(value text);
INSERT INTO "odd""schema"."odd""table" VALUES('kept');
GRANT USAGE ON SCHEMA public,"odd""schema" TO native_app;
GRANT SELECT,INSERT,DELETE ON ALL TABLES IN SCHEMA public TO native_app;
GRANT SELECT ON ALL TABLES IN SCHEMA "odd""schema" TO native_app;
"""
                    run('docker','exec','-i','-e','PGPASSWORD=public-a2-fixture',name,'psql','-h','127.0.0.1','-v','ON_ERROR_STOP=1','-U','postgres','-d','probe',input=sql,text=True,stdout=subprocess.DEVNULL)
            run('swift','test','--scratch-path',environment.get('DBM_A2_SCRATCH',str(directory/'swift')),'-j','4',env=environment,cwd=ROOT)
        finally:
            for name in reversed(owned):
                run('docker','rm','-f','-v',name,stdout=subprocess.DEVNULL)

if __name__ == '__main__': main()
