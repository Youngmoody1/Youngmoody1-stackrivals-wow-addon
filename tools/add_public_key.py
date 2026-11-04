#!/usr/bin/env python3
"""Add (or replace) one PUBLIC signing key of stackrivals.io in StackRivals/Net/SnapshotKeys.lua.

  python3 tools/add_public_key.py --kid k1 --public <64 hex characters>
  python3 tools/add_public_key.py --remove k0        # retire a key (its codes then show UNVERIFIED)

Refuses: a kid that isn't 2 x [a-z0-9]; the test kid "t1"; anything but 64 hex characters; the RFC 8032 test
keys; bytes that aren't a valid Ed25519 public key (when the 'cryptography' package is available).
NEVER give this tool a private key or seed: it only ever needs the public half.
"""
import argparse, os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(ROOT, "StackRivals", "Net", "SnapshotKeys.lua")
RFC_TEST_KEYS = {
    "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
    "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
    "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
    "278117fc144c72340f67d0f2316e8386ceffbf2b2428c9c51fef7c597f1d426e",
}
LINE = re.compile(r'^K\["([a-z0-9]{2})"\] = "([0-9a-f]{64})"\s*$')

def read():
    keys = {}
    head = []
    for line in open(PATH, encoding="utf-8").read().split("\n"):
        m = LINE.match(line)
        if m: keys[m.group(1)] = m.group(2)
        elif line.strip() != "-- (no production key yet)": head.append(line)
    while head and head[-1] == "": head.pop()
    return head, keys

def write(head, keys):
    body = "\n".join(head) + "\n\n"
    body += "\n".join('K["%s"] = "%s"' % (k, keys[k]) for k in sorted(keys)) if keys else "-- (no production key yet)"
    open(PATH, "w", encoding="utf-8").write(body + "\n")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kid"); ap.add_argument("--public"); ap.add_argument("--remove")
    a = ap.parse_args()
    head, keys = read()
    if a.remove:
        if a.remove not in keys: sys.exit("no such kid: " + a.remove)
        del keys[a.remove]; write(head, keys); print("removed", a.remove); return
    if not (a.kid and a.public): sys.exit("give --kid and --public (or --remove)")
    kid, pub = a.kid.strip(), a.public.strip().lower()
    if not re.fullmatch(r"[a-z0-9]{2}", kid): sys.exit("kid must be 2 x [a-z0-9]")
    if kid == "t1": sys.exit("kid t1 is the RFC 8032 test kid: never a production key")
    if not re.fullmatch(r"[0-9a-f]{64}", pub): sys.exit("public key must be exactly 64 hex characters (32 bytes)")
    if pub in RFC_TEST_KEYS: sys.exit("that is an RFC 8032 test key (anyone can sign with it): refused")
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
        Ed25519PublicKey.from_public_bytes(bytes.fromhex(pub))
    except ImportError:
        pass
    except Exception as e:
        sys.exit("not a valid Ed25519 public key: %s" % e)
    keys[kid] = pub
    write(head, keys)
    print("added", kid)

if __name__ == "__main__":
    main()
