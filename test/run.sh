#!/bin/sh
# Functional tests for hc. Needs: openssl, python3.
#   ./build.sh && HC=./hc-x86_64-linux ./test/run.sh
# Creates a private CA + server cert (ECDSA P-256) in a temp dir, starts a plain
# HTTP server (:8080), a TLS 1.3 server (:8443) and a server that never answers (:8097).
set -u
HC=$(cd "$(dirname "${HC:-./hc-x86_64-linux}")" && pwd)/$(basename "${HC:-./hc-x86_64-linux}")
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
pids=""
cleanup() { for p in $pids; do kill "$p" 2>/dev/null; done; rm -rf "$work"; }
trap cleanup EXIT
cd "$work" || exit 1

q() { "$@" >/dev/null 2>&1; }
q openssl ecparam -name prime256v1 -genkey -noout -out ca.key
q openssl req -x509 -new -key ca.key -sha256 -days 3 -subj "/CN=hc-test-ca" -out ca.pem
q openssl ecparam -name prime256v1 -genkey -noout -out ca2.key
q openssl req -x509 -new -key ca2.key -sha256 -days 3 -subj "/CN=other-ca" -out ca2.pem
q openssl ecparam -name prime256v1 -genkey -noout -out srv.key
q openssl req -new -key srv.key -subj "/CN=localhost" -out srv.csr
printf 'subjectAltName=DNS:localhost,DNS:app.test,IP:127.0.0.1\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth\n' > ext.cnf
q openssl x509 -req -in srv.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 3 -sha256 -extfile ext.cnf -out srv.pem
mkdir www && echo ok > www/ping.txt && echo ok > www/health

python3 "$here/srv.py" & pids="$pids $!"
python3 -c "
import socket
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 8097)); s.listen(5); c = []
while True: c.append(s.accept())
" & pids="$pids $!"
i=0; while [ $i -lt 50 ]; do "$HC" tcp://127.0.0.1:8443 2>/dev/null && break; i=$((i + 1)); sleep 0.1; done

pass=0; fail=0
t() { want=$1; shift; "$@" >/dev/null 2>&1; rc=$?
  if [ "$rc" = "$want" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL want=$want got=$rc: $*"; fi; }

t 0 "$HC" tcp://127.0.0.1:8080;                        t 1 "$HC" tcp://127.0.0.1:9
t 0 "$HC" http://127.0.0.1:8080/health;                t 0 "$HC" http://localhost:8080/health
t 1 "$HC" http://127.0.0.1:8080/nope;                  t 1 "$HC" http://127.0.0.1:8080/teapot
t 0 "$HC" -s 418-418 http://127.0.0.1:8080/teapot;     t 1 "$HC" http://127.0.0.1:8080/redir
t 0 "$HC" -s 200-399 http://127.0.0.1:8080/redir;      t 0 "$HC" -m ok http://127.0.0.1:8080/ping.txt
t 1 "$HC" -m pong http://127.0.0.1:8080/ping.txt;      t 0 "$HC" -H app.test -m app.test http://127.0.0.1:8080/echo-host
t 0 "$HC" --ca ca.pem tls://localhost:8443;            t 0 "$HC" --ca ca.pem https://localhost:8443/ping.txt
t 0 "$HC" --ca ca.pem -m ok https://localhost:8443/ping.txt
t 1 "$HC" --ca ca.pem -m nope https://localhost:8443/ping.txt
t 1 "$HC" --ca ca.pem https://localhost:8443/nope
t 0 "$HC" --ca ca.pem -H app.test https://127.0.0.1:8443/ping.txt
t 1 "$HC" --ca ca.pem -H wrong.test https://127.0.0.1:8443/ping.txt   # hostname mismatch must fail
t 1 "$HC" tls://localhost:8443                                        # no CA configured must fail
t 1 "$HC" --ca ca2.pem tls://localhost:8443                           # wrong CA must fail
t 0 "$HC" -k https://127.0.0.1:8443/ping.txt
t 0 "$HC" -k -m ok -H app.test https://127.0.0.1:8443/ping.txt
t 2 "$HC";  t 2 "$HC" tcp://127.0.0.1;  t 2 "$HC" ftp://x:1

# watchdog: a server that accepts but never answers must fail at ~-t seconds, over plain and TLS
for u in http://127.0.0.1:8097/ "-k https://127.0.0.1:8097/"; do
  s=$(date +%s); "$HC" -t 2 $u >/dev/null 2>&1; rc=$?; d=$(( $(date +%s) - s ))
  if [ "$rc" = 1 ] && [ "$d" -ge 2 ] && [ "$d" -le 3 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL watchdog $u rc=$rc elapsed=${d}s"; fi
done

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
