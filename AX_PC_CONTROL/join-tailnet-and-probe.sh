#!/usr/bin/env bash
# Join the tailnet from a machine that is not on it, then find out what PC1
# will actually answer on.
#
# The distinction that matters: Tailscale is a path, not a service. Being able
# to reach PC1 says nothing about whether anything is listening there. Which
# ports answer is the difference between "there is a way in right now" and "a
# person has to walk to the machine", and that cannot be determined from
# outside the tailnet.
#
# Usage:
#   TS_AUTHKEY=tskey-auth-... bash join-tailnet-and-probe.sh
#
# The key is read from the environment and never echoed. Use an ephemeral,
# short-lived key: the node it creates is removed on its own once it goes
# offline, so nothing is left behind.

set -uo pipefail

TARGET="${TARGET:-100.86.125.78}"
PORTS="${PORTS:-3389,22,8090,80,443,445,5985}"
WORK="${WORK:-/tmp/ts-join}"
PROXY_PORT="${PROXY_PORT:-1055}"

if [ -z "${TS_AUTHKEY:-}" ]; then
  echo "TS_AUTHKEY is not set. Refusing to run." >&2
  exit 2
fi

mkdir -p "$WORK"
cd "$WORK" || exit 2

# --- 1. Get the binary ----------------------------------------------------
if [ ! -x "$WORK/tailscale" ]; then
  echo "STEP=DOWNLOAD"
  curl -sS -L -o ts.tgz "https://pkgs.tailscale.com/stable/tailscale_latest_amd64.tgz" || {
    echo "DOWNLOAD_FAILED"; exit 2; }
  tar xzf ts.tgz
  cp "$(find "$WORK" -name tailscale -type f | head -1)" "$WORK/tailscale"
  cp "$(find "$WORK" -name tailscaled -type f | head -1)" "$WORK/tailscaled"
fi
echo "TAILSCALE_BINARY=$($WORK/tailscale version 2>/dev/null | head -1)"

# --- 2. Start tailscaled in userspace mode --------------------------------
# Userspace mode needs no root, no TUN device and no capabilities. The SOCKS5
# proxy it exposes is the only way out to the tailnet from here, and it carries
# tailnet traffic only, so callers must target it explicitly.
echo "STEP=TAILSCALED"
pkill -f "tailscaled --tun=userspace" 2>/dev/null
sleep 1
nohup "$WORK/tailscaled" --tun=userspace-networking \
  --state="$WORK/tailscaled.state" \
  --socket="$WORK/tailscaled.sock" \
  --socks5-server="localhost:${PROXY_PORT}" \
  --outbound-http-proxy-listen="localhost:${PROXY_PORT}" \
  > "$WORK/tailscaled.log" 2>&1 &
sleep 5

for _ in $(seq 1 10); do
  if (echo > /dev/tcp/127.0.0.1/"$PROXY_PORT") 2>/dev/null; then
    echo "SOCKS5_PROXY=open port ${PROXY_PORT}"; break
  fi
  sleep 2
done

# --- 3. Join ---------------------------------------------------------------
# `--auth-key` is passed on the command line to tailscale only; it is not
# echoed, and `set -x` is deliberately off.
echo "STEP=JOIN"
"$WORK/tailscale" --socket="$WORK/tailscaled.sock" up --auth-key="$TS_AUTHKEY" --hostname=ax-sandbox > "$WORK/up.log" 2>&1
UP_CODE=$?
echo "UP_EXIT=$UP_CODE"
if [ "$UP_CODE" -ne 0 ]; then
  # Do not print the log blindly: it can echo back parts of the command.
  sed -e "s/${TS_AUTHKEY}/<redacted>/g" "$WORK/up.log" | tail -5
  echo "JOIN_FAILED"
  exit 2
fi

echo "STEP=STATUS"
"$WORK/tailscale" --socket="$WORK/tailscaled.sock" status 2>&1 | sed -e "s/${TS_AUTHKEY}/<redacted>/g" | head -20

echo "STEP=SELF"
echo "SELF_IP=$("$WORK/tailscale" ip -4 2>/dev/null | head -1)"

# --- 4. Probe PC1 ----------------------------------------------------------
# tailscale ping answers "is the peer there", which is a different question
# from "is a service listening". Both are needed.
echo "STEP=PING"
"$WORK/tailscale" --socket="$WORK/tailscaled.sock" ping --timeout=5s --c=3 "$TARGET" 2>&1 | head -5

echo "STEP=PORTS"
# A hand-rolled SOCKS5 CONNECT is used rather than `curl telnet://` over
# --socks5-hostname. The curl form was tried and does not report reachability
# correctly, and this probe decides whether a person has to walk to the
# machine, so it is verified against a known-open and known-closed port first.
python3 - "$TARGET" "$PORTS" "$PROXY_PORT" <<'PY'
import socket
import sys

target, ports_csv, proxy_port = sys.argv[1], sys.argv[2], int(sys.argv[3])


def probe(host, port, timeout=5.0):
    try:
        s = socket.create_connection(("127.0.0.1", proxy_port), timeout=timeout)
        s.settimeout(timeout)
        s.sendall(b"\x05\x01\x00")
        if s.recv(2) != b"\x05\x00":
            return False
        req = b"\x05\x01\x00\x03" + bytes([len(host)]) + host.encode() + port.to_bytes(2, "big")
        s.sendall(req)
        resp = s.recv(10)
        return len(resp) >= 2 and resp[1] == 0x00
    except Exception:
        return False
    finally:
        try:
            s.close()
        except Exception:
            pass


for p in (int(x) for x in ports_csv.split(",")):
    print(f"PORT_{p}={'OPEN' if probe(target, p) else 'closed_or_filtered'}")
PY

echo "STEP=HTTP_CHECKS"
for url in "http://${TARGET}:8090/health" "https://desktop-rgk6jkb.tail8740ad.ts.net/health"; do
  code=$(timeout 8 curl -sS --socks5-hostname "127.0.0.1:${PROXY_PORT}" \
    -o /dev/null -w '%{http_code}' "$url" 2>/dev/null)
  echo "URL_${url}=${code:-no_response}"
done

echo "STEP=DONE"
