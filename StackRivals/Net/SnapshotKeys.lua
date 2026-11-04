--[[
  StackRivals - the website's PUBLIC signing keys (kid -> Ed25519 public key, 64 hex characters).
  Written by tools/add_public_key.py; read by Net/SnapshotSig.lua. See docs/SIGNING_KEYS.md.

  * Public keys only. The private half lives only in stackrivals.io's server secrets and is never sent here,
    shown in a chat or put on GitHub.
  * Never a test key: kid "t1" and the RFC 8032 test keys are refused by the tool and by the tests.
  * Rotation: add the new kid here in an addon update; remove a retired kid in a later update (its codes then
    show UNVERIFIED, never an error).
]]
local _, ns = ...
local K = ns.SnapshotSig and ns.SnapshotSig.KEYS
if not K then return end

-- (no production key yet)
