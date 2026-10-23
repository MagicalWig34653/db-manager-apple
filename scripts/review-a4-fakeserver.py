#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Reviewer attack harness for A4: a hostile fake MySQL server (local, synthetic, loopback only).

Usage: review-a4-fakeserver.py <workdir>
Writes <workdir>/ca.pem, <workdir>/ports.json and per-mode event logs <workdir>/log-<mode>.json.
"""
import datetime, ipaddress, json, socket, ssl, struct, sys, threading, time
from pathlib import Path
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

W = Path(sys.argv[1]); W.mkdir(parents=True, exist_ok=True)
now = datetime.datetime.now(datetime.timezone.utc)

def key(): return rsa.generate_private_key(public_exponent=65537, key_size=2048)
def name(cn): return x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, cn)])
def make_ca(cn):
    k = key()
    c = (x509.CertificateBuilder().subject_name(name(cn)).issuer_name(name(cn)).public_key(k.public_key())
         .serial_number(x509.random_serial_number()).not_valid_before(now - datetime.timedelta(days=2))
         .not_valid_after(now + datetime.timedelta(days=2))
         .add_extension(x509.BasicConstraints(ca=True, path_length=None), True).sign(k, hashes.SHA256()))
    return k, c
def make_leaf(ca, san, nb=-1, na=1):
    k = key()
    c = (x509.CertificateBuilder().subject_name(name("leaf")).issuer_name(ca[1].subject).public_key(k.public_key())
         .serial_number(x509.random_serial_number()).not_valid_before(now + datetime.timedelta(days=nb))
         .not_valid_after(now + datetime.timedelta(days=na))
         .add_extension(x509.SubjectAlternativeName(san), False)
         .add_extension(x509.ExtendedKeyUsage([x509.oid.ExtendedKeyUsageOID.SERVER_AUTH]), False)
         .sign(ca[0], hashes.SHA256()))
    return k, c
def ctx_for(k, c, tag):
    kp, cp = W / f"{tag}.key", W / f"{tag}.pem"
    kp.write_bytes(k.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL, serialization.NoEncryption()))
    cp.write_bytes(c.public_bytes(serialization.Encoding.PEM))
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain(cp, kp); return ctx

CA = make_ca("Review CA"); OTHER = make_ca("Review Other CA")
(W / "ca.pem").write_bytes(CA[1].public_bytes(serialization.Encoding.PEM))
(W / "other-ca.pem").write_bytes(OTHER[1].public_bytes(serialization.Encoding.PEM))
DNS = lambda n: x509.DNSName(n)
IP = lambda n: x509.IPAddress(ipaddress.ip_address(n))
CTX = {
    "good": ctx_for(*make_leaf(CA, [DNS("localhost")]), "good"),
    "expired": ctx_for(*make_leaf(CA, [DNS("localhost")], nb=-2, na=-1), "expired"),
    "otherca": ctx_for(*make_leaf(OTHER, [DNS("localhost")]), "otherca"),
    "wronghost": ctx_for(*make_leaf(CA, [DNS("wrong.invalid")]), "wronghost"),
    "ipcert": ctx_for(*make_leaf(CA, [IP("127.0.0.1")]), "ipcert"),
    "dnsonly_for_ip": ctx_for(*make_leaf(CA, [DNS("localhost")]), "dnsonly"),
    "cn_only_noname": ctx_for(*make_leaf(CA, [DNS("example.invalid")]), "noname"),
}

CAP = dict(LONG_PASSWORD=1, LONG_FLAG=4, CONNECT_DB=8, PROTO41=0x200, SSL=0x800, TX=0x2000, SECURE=0x8000, PLUGIN=0x80000)
def pkt(seq, payload): return struct.pack("<I", len(payload))[:3] + bytes([seq & 255]) + payload
def lenenc(n):
    if n < 251: return bytes([n])
    if n < 1 << 16: return b"\xfc" + struct.pack("<H", n)
    if n < 1 << 24: return b"\xfd" + struct.pack("<I", n)[:3]
    return b"\xfe" + struct.pack("<Q", n)
def lstr(b): return lenenc(len(b)) + b
def greeting(ssl_on=True, plugin=b"caching_sha2_password", thread=4242):
    caps = CAP["LONG_PASSWORD"] | CAP["LONG_FLAG"] | CAP["CONNECT_DB"] | CAP["PROTO41"] | CAP["TX"] | CAP["SECURE"] | CAP["PLUGIN"]
    if ssl_on: caps |= CAP["SSL"]
    s = bytes(range(1, 21))
    return (b"\x0a" + b"8.4.0-review-fake\0" + struct.pack("<I", thread) + s[:8] + b"\0" + struct.pack("<H", caps & 0xFFFF)
            + b"\x2d" + struct.pack("<H", 2) + struct.pack("<H", caps >> 16) + bytes([21]) + b"\0" * 10 + s[8:] + b"\0" + plugin + b"\0")
OK = lambda: b"\x00\x00\x00\x02\x00\x00\x00"
def coldef(nm, typ=253):
    return lstr(b"def") + lstr(b"") + lstr(b"") + lstr(b"") + lstr(nm) + lstr(nm) + b"\x0c" + struct.pack("<HIBHBH", 45, 255, typ, 0, 0, 0)
EOF = b"\xfe\x00\x00\x02\x00"

def recvn(sock, n, timeout=3):
    sock.settimeout(timeout); buf = b""
    while len(buf) < n:
        d = sock.recv(n - len(buf))
        if not d: raise EOFError
        buf += d
    return buf
def recvpkt(sock, timeout=3):
    h = recvn(sock, 4, timeout); n = h[0] | h[1] << 8 | h[2] << 16
    return h[3], recvn(sock, n, timeout) if n else b""

def log(mode, ev):
    p = W / f"log-{mode}.json"
    cur = json.loads(p.read_text()) if p.exists() else []
    cur.append(ev); p.write_text(json.dumps(cur))

def serve_query_loop(sock, mode, handler):
    """Answer COM_QUERY; catalog gets an empty 3-column result, SET/START/COMMIT get OK, others go to handler."""
    while True:
        try: seq, q = recvpkt(sock, 5)
        except Exception: return
        text = q[1:].decode("utf8", "replace")
        if text.startswith(("SET ", "START ", "COMMIT")): sock.sendall(pkt(1, OK())); continue
        if "information_schema" in text:
            sock.sendall(pkt(1, lenenc(3)) + pkt(2, coldef(b"s")) + pkt(3, coldef(b"n")) + pkt(4, coldef(b"k")) + pkt(5, EOF) + pkt(6, EOF)); continue
        handler(sock, text); return

def handler_for(mode):
    def hdr_huge(s, t): s.sendall(b"\xff\xff\xff\x01" + b"A" * 100000); time.sleep(2)
    def badseq(s, t): s.sendall(pkt(9, lenenc(1)))
    def stall(s, t): s.sendall(b"\x20\x00\x00\x01abc"); time.sleep(30)
    def rows(count, cell):
        def h(s, t):
            s.sendall(pkt(1, lenenc(1)) + pkt(2, coldef(b"v")) + pkt(3, EOF))
            seq = 4
            try:
                for _ in range(count):
                    s.sendall(pkt(seq, lstr(cell))); seq += 1
                s.sendall(pkt(seq, EOF))
            except Exception as e: log(mode, {"sendstop": type(e).__name__, "rows_sent": seq - 4})
            time.sleep(1)
        return h
    def bigcell(s, t):
        s.sendall(pkt(1, lenenc(1)) + pkt(2, coldef(b"v")) + pkt(3, EOF) + pkt(4, b"\xfe" + struct.pack("<Q", 2**64 - 1)) + pkt(5, EOF)); time.sleep(1)
    def bigcell2(s, t):
        s.sendall(pkt(1, lenenc(1)) + pkt(2, coldef(b"v")) + pkt(3, EOF) + pkt(4, b"\xfe" + struct.pack("<Q", 2**63)) + pkt(5, EOF)); time.sleep(1)
    def colcount(s, t): s.sendall(pkt(1, b"\xfe" + struct.pack("<Q", 2**64 - 1))); time.sleep(1)
    def zerocols(s, t): s.sendall(pkt(1, b"\xfc\x00\x00")); time.sleep(1)
    def drip(s, t):
        data = pkt(1, lenenc(1)) + pkt(2, coldef(b"v")) + pkt(3, EOF)
        for b in data: s.sendall(bytes([b])); time.sleep(0.0005)
        for i in range(4, 300): s.sendall(pkt(i, lstr(b"x")))
        s.sendall(pkt(300, EOF)); time.sleep(1)
    def invalid_utf8(s, t):
        s.sendall(pkt(1, lenenc(1)) + pkt(2, coldef(b"v")) + pkt(3, EOF) + pkt(4, lstr(b"\xff\xfe\xc3")) + pkt(5, EOF)); time.sleep(1)
    def nulbig(s, t):  # row shorter than columns
        s.sendall(pkt(1, lenenc(2)) + pkt(2, coldef(b"a")) + pkt(3, coldef(b"b")) + pkt(4, EOF) + pkt(5, lstr(b"x")) + pkt(6, EOF)); time.sleep(1)
    def errpacket(s, t):
        s.sendall(pkt(1, b"\xff" + struct.pack("<H", 1064) + b"#42000secret SQL text password=hunter2 /etc/passwd")); time.sleep(1)
    def multi_loop(s, t):  # LOCAL INFILE request
        s.sendall(pkt(1, b"\xfb/etc/passwd")); time.sleep(1)
    return dict(hdr_huge=hdr_huge, badseq=badseq, stall=stall,
                rows_endless=rows(10**7, b"x" * 100), bigcell=bigcell, bigcell2=bigcell2, colcount=colcount,
                zerocols=zerocols, drip=drip, invalid_utf8=invalid_utf8, shortrow=nulbig, errpacket=errpacket,
                infile=multi_loop, rows_fat=rows(10**6, b"y" * 60000))[mode]

def FORGED():
    f = pkt(3, OK()) + pkt(1, OK()) * 4
    f += (pkt(1, lenenc(3)) + pkt(2, coldef(b"s")) + pkt(3, coldef(b"n")) + pkt(4, coldef(b"k")) + pkt(5, EOF)
          + pkt(6, lstr(b"FORGED_SCHEMA") + lstr(b"forged_table") + lstr(b"table")) + pkt(7, EOF))
    return f + pkt(1, OK())

def handle_conn(sock, mode):
    try:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        if mode == "nossl":
            sock.sendall(pkt(0, greeting(ssl_on=False)))
            sock.settimeout(1.5); got = b""
            try:
                while True:
                    d = sock.recv(4096)
                    if not d: break
                    got += d
            except Exception: pass
            log(mode, {"client_bytes": len(got)}); return
        if mode.startswith("mal_"):  # plaintext, no SSL capability; client must use the loopback dev option
            sock.sendall(pkt(0, greeting(ssl_on=False, plugin=b"mysql_native_password")))
            try: recvpkt(sock)
            except Exception: log(mode, {"auth": "none"}); return
            sock.sendall(pkt(2, OK()))
            serve_query_loop(sock, mode, handler_for(mode[4:])); return
        if mode == "plain_fullauth":
            sock.sendall(pkt(0, greeting(ssl_on=False)))
            seq, r = recvpkt(sock); log(mode, {"auth_response_len": len(r)})
            sock.sendall(pkt(2, b"\x01\x04"))
            sock.settimeout(1.5); got = b""
            try:
                while True:
                    d = sock.recv(4096)
                    if not d: break
                    got += d
            except Exception: pass
            log(mode, {"bytes_after_fullauth_request": len(got), "hexprefix": got[:40].hex()}); return
        if mode == "plain_switch_clear":
            sock.sendall(pkt(0, greeting(ssl_on=False, plugin=b"mysql_native_password")))
            recvpkt(sock); sock.sendall(pkt(2, b"\xfemysql_clear_password\0abc\0"))
            sock.settimeout(1.5); got = b""
            try:
                while True:
                    d = sock.recv(4096)
                    if not d: break
                    got += d
            except Exception: pass
            log(mode, {"bytes_after_switch": len(got), "hex": got.hex()}); return
        # TLS modes
        tlsname = {"tls_good_fullauth": "good", "expired": "expired", "otherca": "otherca", "wronghost": "wronghost",
                   "ipcert": "ipcert", "inject": "good"}.get(mode, "good")
        if mode.startswith("inject"):
            sock.sendall(pkt(0, greeting()))
            delay = float(mode.split(":")[1]) if ":" in mode else 0
        else:
            sock.sendall(pkt(0, greeting(plugin=b"caching_sha2_password")))
        pre = mode.startswith("inject") and delay < 0
        if pre: sock.sendall(FORGED())
        seq, ssl_req = recvpkt(sock)
        log(mode, {"sslrequest_len": len(ssl_req)})
        if mode.startswith("inject") and not pre:
            # response injection: plaintext bytes immediately after the SSLRequest (before the TLS ClientHello arrives)
            time.sleep(delay)
            forged = pkt(3, OK())
            forged += pkt(1, OK()) * 4
            forged += (pkt(1, lenenc(3)) + pkt(2, coldef(b"s")) + pkt(3, coldef(b"n")) + pkt(4, coldef(b"k")) + pkt(5, EOF)
                       + pkt(6, lstr(b"FORGED_SCHEMA") + lstr(b"forged_table") + lstr(b"table")) + pkt(7, EOF))
            forged += pkt(1, OK())
            sock.sendall(forged)
        try:
            ts = CTX[tlsname].wrap_socket(sock, server_side=True)
        except Exception as e:
            log(mode, {"tls": "handshake-failed", "why": type(e).__name__ + ":" + str(e)[:80]}); return
        log(mode, {"tls": "established"})
        ts.settimeout(2.0)
        try:
            seq, resp = recvpkt(ts, 2)
            log(mode, {"auth_response_received": True, "len": len(resp)})
        except Exception as e:
            log(mode, {"auth_response_received": False, "why": type(e).__name__})
            if mode.startswith("inject"): time.sleep(1)
            return
        if mode == "tls_good_fullauth":
            ts.sendall(pkt(3, b"\x01\x04"))
            try:
                seq, pw = recvpkt(ts, 2); log(mode, {"fullauth_payload": pw.decode("latin1")})
            except Exception as e: log(mode, {"fullauth_payload": None})
        elif mode.startswith("switch_"):
            pass
    except Exception as e:
        log(mode, {"server_error": type(e).__name__ + str(e)[:60]})
    finally:
        try: sock.close()
        except Exception: pass

def handle_switch(sock, mode):
    plugin = mode[len("switch_"):].encode()
    try:
        sock.sendall(pkt(0, greeting(plugin=b"caching_sha2_password")))
        recvpkt(sock)
        ts = CTX["good"].wrap_socket(sock, server_side=True)
        seq, resp = recvpkt(ts, 2)
        log(mode, {"first_response_len": len(resp)})
        ts.sendall(pkt(3, b"\xfe" + plugin + b"\0" + bytes(range(1, 21)) + b"\0"))
        ts.settimeout(1.5)
        try:
            seq, nxt = recvpkt(ts, 1.5); log(mode, {"reply_after_switch_len": len(nxt), "hex": nxt.hex()})
        except Exception as e: log(mode, {"reply_after_switch": None, "why": type(e).__name__})
    except Exception as e:
        log(mode, {"server_error": type(e).__name__ + str(e)[:60]})

modes = (["nossl", "plain_fullauth", "plain_switch_clear", "tls_good_fullauth", "expired", "otherca", "wronghost", "ipcert", "good"]
         + ["switch_" + p for p in ("mysql_clear_password", "mysql_native_password", "sha256_password", "client_ed25519", "mysql_old_password")]
         + ["inject:-1", "inject:0", "inject:0.0005", "inject:0.002", "inject:0.005", "inject:0.02"]
         + ["mal_" + m for m in ("hdr_huge", "badseq", "stall", "rows_endless", "bigcell", "bigcell2", "colcount", "zerocols", "drip",
                                  "invalid_utf8", "shortrow", "errpacket", "infile", "rows_fat")])
ports = {}
for m in modes:
    for f in W.glob(f"log-{m}.json"): f.unlink()
    srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0)); srv.listen(64); ports[m] = srv.getsockname()[1]
    def loop(srv=srv, m=m):
        while True:
            c, _ = srv.accept()
            threading.Thread(target=(handle_switch if m.startswith("switch_") else handle_conn), args=(c, m), daemon=True).start()
    threading.Thread(target=loop, daemon=True).start()
(W / "ports.json").write_text(json.dumps(ports))
print("ready", flush=True)
while True: time.sleep(3600)
