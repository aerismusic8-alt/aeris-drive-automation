#!/usr/bin/env python3
"""AR's Nostr identity — the one social network AR can join with no signup at all.

Nostr has no accounts to create: an identity *is* a secp256k1 keypair the user
generates locally, and posts are signed events published to public relays. There
is no captcha, no email, no phone and no approval — which is exactly why it is
the only social surface AR can open unattended (verified 2026-11-15: Bluesky now
requires phone verification on every PDS; Mastodon and Lemmy block the mail.tm
domain or require human approval; Misskey instances all enforce a captcha).

The crypto is pure Python on purpose — no `coincurve`/`secp256k1` wheel needed,
so the module runs on the bare pod and on a CI runner alike. The secret key never
leaves `/workspace/ax-tools/ar-identity/` (the repo is public), matching the
mailbox and the browser profile.

Usage
-----
    python3 ops/ar_nostr.py create                 # generate the keypair
    python3 ops/ar_nostr.py whoami                 # npub + relays
    python3 ops/ar_nostr.py post "text"            # publish a kind-1 note

Environment
-----------
    AR_IDENTITY_DIR   where nostr.json lives (default: /workspace/ax-tools/ar-identity)
    NOSTR_RELAYS      comma-separated wss:// relays
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import secrets
import sys
import time
from pathlib import Path

IDENTITY_DIR = Path(os.environ.get("AR_IDENTITY_DIR", "/workspace/ax-tools/ar-identity"))
CREDS = IDENTITY_DIR / "nostr.json"
DEFAULT_RELAYS = [
    "wss://relay.damus.io", "wss://nos.lol", "wss://relay.primal.net",
    "wss://nostr.mom", "wss://relay.nostr.band",
]
AI_NOTE = "— เพลงส้นทีนไรเนี่ย (AI agent)"

# --- secp256k1, pure Python ------------------------------------------------
P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
G = (0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798,
     0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8)


def _add(p, q):
    if p is None:
        return q
    if q is None:
        return p
    if p[0] == q[0] and (p[1] + q[1]) % P == 0:
        return None
    if p == q:
        lam = 3 * p[0] * p[0] * pow(2 * p[1], -1, P) % P
    else:
        lam = (q[1] - p[1]) * pow(q[0] - p[0], -1, P) % P
    x = (lam * lam - p[0] - q[0]) % P
    return x, (lam * (p[0] - x) - p[1]) % P


def _mul(k, pt):
    r = None
    while k:
        if k & 1:
            r = _add(r, pt)
        pt = _add(pt, pt)
        k >>= 1
    return r


def _tagged(tag: str, msg: bytes) -> bytes:
    t = hashlib.sha256(tag.encode()).digest()
    return hashlib.sha256(t + t + msg).digest()


def xonly_pub(seckey: int) -> bytes:
    pt = _mul(seckey, G)
    return pt[0].to_bytes(32, "big")


def schnorr_sign(msg32: bytes, seckey: int, aux: bytes) -> bytes:
    d0 = seckey
    if _mul(d0, G)[1] % 2 != 0:
        d0 = N - d0
    px = xonly_pub(d0)
    t = bytes(a ^ b for a, b in zip(d0.to_bytes(32, "big"), _tagged("BIP0340/aux", aux)))
    k0 = int.from_bytes(_tagged("BIP0340/nonce", t + px + msg32), "big") % N
    if k0 == 0:
        raise SystemExit("nonce is zero; retry")
    rx = _mul(k0, G)[0]
    if _mul(k0, G)[1] % 2 != 0:
        k0 = N - k0
    e = int.from_bytes(_tagged("BIP0340/challenge",
                               rx.to_bytes(32, "big") + px + msg32), "big") % N
    return rx.to_bytes(32, "big") + ((k0 + e * d0) % N).to_bytes(32, "big")


# --- bech32 (npub / nsec) --------------------------------------------------
_CHARS = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"


def _bech32_hrp_expand(hrp: str) -> list[int]:
    return [ord(c) >> 5 for c in hrp] + [0] + [ord(c) & 31 for c in hrp]


def _bech32_polymod(values: list[int]) -> int:
    gen = [0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3]
    chk = 1
    for v in values:
        b = chk >> 25
        chk = (chk & 0x1FFFFFF) << 5 ^ v
        for i in range(5):
            chk ^= gen[i] if ((b >> i) & 1) else 0
    return chk


def _convertbits(data: bytes, frm: int, to: int, pad: bool) -> list[int]:
    acc = bits = 0
    ret = []
    maxv = (1 << to) - 1
    for value in data:
        acc = (acc << frm) | value
        bits += frm
        while bits >= to:
            bits -= to
            ret.append((acc >> bits) & maxv)
    if pad and bits:
        ret.append((acc << (to - bits)) & maxv)
    return ret


def bech32_encode(hrp: str, data: bytes) -> str:
    d = _convertbits(data, 8, 5, True)
    pm = _bech32_polymod(_bech32_hrp_expand(hrp) + d + [0, 0, 0, 0, 0, 0]) ^ 1
    chk = [(pm >> 5 * (5 - i)) & 31 for i in range(6)]
    return hrp + "1" + "".join(_CHARS[x] for x in d + chk)


# --- account ---------------------------------------------------------------
def load() -> dict:
    """The identity, from the file or from `AR_NOSTR_NSEC` (for CI runners).

    A GitHub Actions runner has no `/workspace/ax-tools`, so the key travels as
    a secret there. Accepting the nsec (or raw hex) from the environment lets the
    same module post from the pod and from a rail without a second code path.
    """
    env = os.environ.get("AR_NOSTR_NSEC")
    if env:
        if env.startswith("nsec1"):
            sk = _bech32_decode_nsec(env)
        else:
            sk = int(env, 16)
        return {"sk_hex": format(sk, "064x"),
                "npub": bech32_encode("npub", xonly_pub(sk))}
    if not CREDS.exists():
        raise SystemExit(f"no Nostr identity yet ({CREDS}); run: create")
    return json.loads(CREDS.read_text())


def _bech32_decode_nsec(nsec: str) -> int:
    data = nsec[nsec.index("1") + 1:]
    vals = [_CHARS.index(c) for c in data[:-6]]
    acc = bits = 0
    out = []
    for v in vals:
        acc = (acc << 5) | v
        bits += 5
        while bits >= 8:
            bits -= 8
            out.append((acc >> bits) & 0xFF)
    return int.from_bytes(bytes(out), "big")


def _save(rec: dict) -> None:
    IDENTITY_DIR.mkdir(parents=True, exist_ok=True)
    CREDS.write_text(json.dumps(rec, indent=2))
    os.chmod(CREDS, 0o600)


def create() -> dict:
    if CREDS.exists():
        rec = load()
        print(f"already have {rec['npub']}")
        return rec
    sk = secrets.randbelow(N - 1) + 1
    pub = xonly_pub(sk)
    rec = {"sk_hex": format(sk, "064x"),
           "npub": bech32_encode("npub", pub),
           "nsec": bech32_encode("nsec", sk.to_bytes(32, "big")),
           "relays": DEFAULT_RELAYS, "created": int(time.time())}
    _save(rec)
    print(f"created {rec['npub']}")
    return rec


def _event(content: str, kind: int = 1, tags=None) -> dict:
    rec = load()
    pub = bytes.fromhex(_pub_hex(rec))
    ev = {"pubkey": pub.hex(), "created_at": int(time.time()), "kind": kind,
          "tags": tags or [], "content": content}
    ser = json.dumps([0, ev["pubkey"], ev["created_at"], ev["kind"], ev["tags"],
                      ev["content"]], separators=(",", ":"), ensure_ascii=False)
    eid = hashlib.sha256(ser.encode()).digest()
    ev["id"] = eid.hex()
    ev["sig"] = schnorr_sign(eid, int(rec["sk_hex"], 16), secrets.token_bytes(32)).hex()
    return ev


def _pub_hex(rec: dict) -> str:
    return xonly_pub(int(rec["sk_hex"], 16)).hex()


def publish(ev: dict, relays: list[str]) -> list[str]:
    import websocket  # websocket-client

    ok = []
    for url in relays:
        try:
            ws = websocket.create_connection(url, timeout=15)
            ws.send(json.dumps(["EVENT", ev]))
            deadline = time.time() + 15
            while time.time() < deadline:
                msg = json.loads(ws.recv())
                if msg[0] == "OK" and msg[1] == ev["id"]:
                    if msg[2]:
                        ok.append(url)
                    print(f"  {url}: {'accepted' if msg[2] else msg[3] if len(msg) > 3 else 'rejected'}")
                    break
                if msg[0] == "NOTICE":
                    print(f"  {url}: NOTICE {msg[1][:60]}")
                    break
            ws.close()
        except Exception as e:  # noqa: BLE001 - a dead relay must not stop the rest
            print(f"  {url}: {str(e)[:70]}", file=sys.stderr)
    return ok


def post(text: str) -> list[str]:
    body = text if AI_NOTE in text else f"{text}\n\n{AI_NOTE}"
    ev = _event(body)
    relays = os.environ.get("NOSTR_RELAYS")
    relays = relays.split(",") if relays else load().get("relays", DEFAULT_RELAYS)
    print(f"publishing {ev['id'][:12]} to {len(relays)} relay(s)")
    return publish(ev, relays)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("create")
    sub.add_parser("whoami")
    p = sub.add_parser("post")
    p.add_argument("text")
    args = ap.parse_args()
    if args.cmd == "create":
        create()
    elif args.cmd == "whoami":
        rec = load()
        print(json.dumps({"npub": rec["npub"], "relays": rec.get("relays"),
                          "created": rec.get("created")}, indent=2))
    elif args.cmd == "post":
        ok = post(args.text)
        print(f"accepted by {len(ok)} relay(s)")
        return 0 if ok else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
