#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Run native MySQL/MariaDB adapter tests against exclusively owned disposable TLS fixtures."""
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
ROOT_PASSWORD = 'public-a4-root'
APP_PASSWORD = 'public-a4-fixture'

SCHEMA = """
SET GLOBAL log_bin_trust_function_creators = 1;
CREATE DATABASE IF NOT EXISTS probe;
CREATE USER 'native_app'@'%' IDENTIFIED BY 'public-a4-fixture';
CREATE USER 'plain_probe'@'%' IDENTIFIED BY 'public-a4-fixture';
GRANT SELECT ON probe.* TO 'plain_probe'@'%';
GRANT SELECT,INSERT,UPDATE,DELETE,CREATE,DROP,EXECUTE ON probe.* TO 'native_app'@'%';
GRANT PROCESS ON *.* TO 'native_app'@'%';
SET time_zone = '+00:00';
CREATE TABLE probe.synthetic_values(amount DECIMAL(40,20), big BIGINT UNSIGNED, missing TEXT NULL, empty_text TEXT,
  emptyblob BLOB, raw_blob BLOB, flag BOOLEAN, zoned TIMESTAMP(6) NULL, local_value DATETIME(6), day DATE, tm TIME(3),
  dbl DOUBLE, label VARCHAR(40) CHARACTER SET utf8mb4);
INSERT INTO probe.synthetic_values VALUES(12345678901234567890.12345678901234567890, 18446744073709551615, NULL, '',
  x'', x'00ff80', TRUE, '2026-10-20 12:34:56.123456', '2026-10-20 12:34:56.654321', '2026-10-20', '-12:34:56.789',
  1.5, 'Grüße \U0001F600');
CREATE TABLE probe.writable(value INT);
CREATE TABLE probe.numbers(n BIGINT);
INSERT INTO probe.numbers VALUES(1);
INSERT INTO probe.numbers SELECT n FROM probe.numbers;\nINSERT INTO probe.numbers SELECT n FROM probe.numbers;\nINSERT INTO probe.numbers SELECT n FROM probe.numbers;\nINSERT INTO probe.numbers SELECT n FROM probe.numbers;\nINSERT INTO probe.numbers SELECT n FROM probe.numbers;\nINSERT INTO probe.numbers SELECT n FROM probe.numbers;\nINSERT INTO probe.numbers SELECT n FROM probe.numbers;\nINSERT INTO probe.numbers SELECT n FROM probe.numbers;\nINSERT INTO probe.numbers SELECT n FROM probe.numbers;\nINSERT INTO probe.numbers SELECT n FROM probe.numbers;\nINSERT INTO probe.numbers SELECT n FROM probe.numbers;\nINSERT INTO probe.numbers SELECT n FROM probe.numbers;\nINSERT INTO probe.numbers SELECT n FROM probe.numbers;\nINSERT INTO probe.numbers SELECT n FROM probe.numbers;\nINSERT INTO probe.numbers SELECT n FROM probe.numbers;\nINSERT INTO probe.numbers SELECT n FROM probe.numbers;\n
CREATE VIEW probe.synthetic_view AS SELECT big FROM probe.synthetic_values;
DELIMITER $$
CREATE FUNCTION probe.mutating_function() RETURNS INT MODIFIES SQL DATA BEGIN INSERT INTO probe.writable VALUES(5); RETURN 5; END$$
DELIMITER ;
CREATE DATABASE `odd``db`;
CREATE TABLE `odd``db`.`odd``table`(value TEXT);
INSERT INTO `odd``db`.`odd``table` VALUES('kept');
GRANT SELECT ON `odd``db`.* TO 'native_app'@'%';
"""

def run(*arguments, **kwargs):
    return subprocess.run(arguments, check=True, **kwargs)

def main():
    prefix = 'dbmanager-a4-' + secrets.token_hex(5)
    owned = []
    with tempfile.TemporaryDirectory(prefix=prefix, dir='/tmp') as temporary:
        directory = Path(temporary)
        fixture = directory/'certificates'; fixture.mkdir()
        quiet = {'stdout': subprocess.DEVNULL, 'stderr': subprocess.DEVNULL}
        run('openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN=DBManager Public Test CA','-keyout',str(fixture/'ca.key'),'-out',str(fixture/'ca.pem'),**quiet)
        for basename, name in (('server','localhost'), ('wrong','wrong.invalid')):
            run('openssl','req','-newkey','rsa:2048','-nodes','-subj','/CN='+name,'-keyout',str(fixture/(basename+'.key')),'-out',str(fixture/(basename+'.csr')),**quiet)
            (fixture/(basename+'.cnf')).write_text('subjectAltName=DNS:'+name+'\nextendedKeyUsage=serverAuth\n')
            run('openssl','x509','-req','-days','1','-in',str(fixture/(basename+'.csr')),'-CA',str(fixture/'ca.pem'),'-CAkey',str(fixture/'ca.key'),'-CAcreateserial','-extfile',str(fixture/(basename+'.cnf')),'-out',str(fixture/(basename+'.pem')),**quiet)
        # A second, unrelated self-signed CA proves that a certificate not issued by the trusted CA is refused.
        run('openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN=Unrelated Public Test CA','-keyout',str(fixture/'other.key'),'-out',str(fixture/'other-ca.pem'),**quiet)
        environment = os.environ.copy()
        environment['DBM_A4_CA_FILE'] = str(fixture/'ca.pem')
        environment['DBM_A4_OTHER_CA_FILE'] = str(fixture/'other-ca.pem')
        # (name, image, daemon, client binary, TLS certificate basename or None)
        servers = [
            ('maria_tls', 'mariadb:11.4.4', 'mariadbd', 'mariadb', 'server'),
            ('maria_wronghost', 'mariadb:11.4.4', 'mariadbd', 'mariadb', 'wrong'),
            ('maria_plain', 'mariadb:11.4.4', 'mariadbd', 'mariadb', None),
            ('mysql_tls', 'mysql:8.4', 'mysqld', 'mysql', 'server'),
        ]
        try:
            for mode, image, daemon, client, certificate in servers:
                name = prefix+'-'+mode.replace('_','-')
                entry = 'chown -R mysql:mysql /fixture && chmod 600 /fixture/*.key && exec docker-entrypoint.sh "$@"'
                root_variable = 'MYSQL_ROOT_PASSWORD' if client == 'mysql' else 'MARIADB_ROOT_PASSWORD'
                args = ['docker','create','--name',name,'--label','dbmanager.task=A4','-p','127.0.0.1::3306',
                        '-e',root_variable+'='+ROOT_PASSWORD,'--entrypoint','/bin/sh',image,'-c',entry,'fixture',daemon]
                if not certificate:
                    # Recent images auto-generate a certificate; this fixture must truly lack TLS.
                    args += ['--skip-ssl']
                if certificate:
                    args += ['--ssl-ca=/fixture/ca.pem','--ssl-cert=/fixture/'+certificate+'.pem','--ssl-key=/fixture/'+certificate+'.key']
                run(*args,stdout=subprocess.DEVNULL); owned.append(name)
                run('docker','cp',str(fixture),name+':/fixture',stdout=subprocess.DEVNULL)
                run('docker','start',name,stdout=subprocess.DEVNULL)
                # Loopback inside the container; the client must not insist on TLS for the TLS-less fixture.
                client_tls = [] if certificate else ['--skip-ssl']
                admin = 'mysqladmin' if client == 'mysql' else 'mariadb-admin'
                for _ in range(240):
                    if subprocess.run(['docker','exec',name,admin,'ping','-h127.0.0.1','-uroot','-p'+ROOT_PASSWORD,'--silent',*client_tls],**quiet).returncode == 0: break
                    time.sleep(.5)
                else: raise RuntimeError('Owned MySQL/MariaDB fixture startup failed')
                bindings=json.loads(subprocess.check_output(['docker','inspect',name],text=True))[0]['NetworkSettings']['Ports']
                environment['DBM_A4_'+mode.upper()+'_PORT'] = bindings['3306/tcp'][0]['HostPort']
                if mode != 'maria_wronghost':
                    run('docker','exec','-i',name,client,'-h127.0.0.1','-uroot','-p'+ROOT_PASSWORD,'--default-character-set=utf8mb4',*client_tls,input=SCHEMA,text=True,stdout=subprocess.DEVNULL)
            run('swift','test','--scratch-path',environment.get('DBM_A4_SCRATCH',str(directory/'swift')),'-j','4',env=environment,cwd=ROOT)
        finally:
            for name in reversed(owned):
                run('docker','rm','-f','-v',name,stdout=subprocess.DEVNULL)

if __name__ == '__main__': main()
