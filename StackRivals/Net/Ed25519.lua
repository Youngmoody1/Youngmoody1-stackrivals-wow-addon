--[[
  StackRivals - Ed25519 signature verification (RFC 8032) with SHA-512, in pure Lua 5.1.

  Used to check stackrivals.io's signed profile codes (SRP1-SIG v1, SRP2-SIG v1; Net/SnapshotSig.lua).
  VERIFY ONLY: there is no signing and no secret here. The website signs with a private key that never
  leaves its server; the addon holds public keys.

  * No C library. WoW's `bit` library is used for AND / XOR when it exists, normalised to unsigned
    32-bit (so signed or unsigned results both work); without it (plain Lua 5.1, the CI) the same
    operations come from byte tables. Shifts and rotations are plain arithmetic.
  * Field arithmetic mod 2^255-19 follows TweetNaCl's 16 limbs of 16 bits: every product and sum stays
    far below 2^53, so Lua's doubles are exact.
  * RFC 8032 rules: a public key that isn't a curve point and S >= L are refused.
  Tested with the RFC 8032 test vectors and the website's shared vectors (tests/test_ed25519.lua).
]]
local _, ns = ...
ns = ns or {}

local Ed = {}
ns.Ed25519 = Ed

local floor = math.floor
local P32 = 4294967296

------------------------------------------------------------------ 32-bit AND / XOR
local band, bxor
local bitlib = type(_G) == "table" and rawget(_G, "bit") or nil
if type(bitlib) == "table" and bitlib.band and bitlib.bxor then
  local b_and, b_xor = bitlib.band, bitlib.bxor
  band = function(a, b) return b_and(a, b) % P32 end
  bxor = function(a, b) return b_xor(a, b) % P32 end
else
  band, bxor = nil, nil
end
local XOR8, AND8
local function tables()
  if XOR8 then return end
  XOR8, AND8 = {}, {}
  for a = 0, 255 do
    for b = 0, 255 do
      local x, y, r, s, bitv = a, b, 0, 0, 1
      for _ = 1, 8 do
        local p, q = x % 2, y % 2
        if p ~= q then r = r + bitv end
        if p == 1 and q == 1 then s = s + bitv end
        x, y, bitv = (x - p) / 2, (y - q) / 2, bitv * 2
      end
      XOR8[a * 256 + b], AND8[a * 256 + b] = r, s
    end
  end
end
local function pureOp(T, a, b)
  local r, m = 0, 1
  for _ = 1, 4 do
    local x, y = a % 256, b % 256
    r = r + T[x * 256 + y] * m
    a, b, m = (a - x) / 256, (b - y) / 256, m * 256
  end
  return r
end
--- Select the implementation (tests use this to check both paths give the same answers).
function Ed.useBitLib(lib)
  if lib and lib.band and lib.bxor then
    local b_and, b_xor = lib.band, lib.bxor
    band = function(a, b) return b_and(a, b) % P32 end
    bxor = function(a, b) return b_xor(a, b) % P32 end
    Ed.bitPath = "bit"
  else
    tables()
    band = function(a, b) return pureOp(AND8, a, b) end
    bxor = function(a, b) return pureOp(XOR8, a, b) end
    Ed.bitPath = "pure"
  end
end
if band then Ed.bitPath = "bit" else Ed.useBitLib(nil) end

------------------------------------------------------------------ SHA-512 (words as hi, lo 32-bit halves)
local K = {
  0x428a2f98, 0xd728ae22, 0x71374491, 0x23ef65cd, 0xb5c0fbcf, 0xec4d3b2f, 0xe9b5dba5, 0x8189dbbc, 0x3956c25b,
  0xf348b538, 0x59f111f1, 0xb605d019, 0x923f82a4, 0xaf194f9b, 0xab1c5ed5, 0xda6d8118, 0xd807aa98, 0xa3030242,
  0x12835b01, 0x45706fbe, 0x243185be, 0x4ee4b28c, 0x550c7dc3, 0xd5ffb4e2, 0x72be5d74, 0xf27b896f, 0x80deb1fe,
  0x3b1696b1, 0x9bdc06a7, 0x25c71235, 0xc19bf174, 0xcf692694, 0xe49b69c1, 0x9ef14ad2, 0xefbe4786, 0x384f25e3,
  0x0fc19dc6, 0x8b8cd5b5, 0x240ca1cc, 0x77ac9c65, 0x2de92c6f, 0x592b0275, 0x4a7484aa, 0x6ea6e483, 0x5cb0a9dc,
  0xbd41fbd4, 0x76f988da, 0x831153b5, 0x983e5152, 0xee66dfab, 0xa831c66d, 0x2db43210, 0xb00327c8, 0x98fb213f,
  0xbf597fc7, 0xbeef0ee4, 0xc6e00bf3, 0x3da88fc2, 0xd5a79147, 0x930aa725, 0x06ca6351, 0xe003826f, 0x14292967,
  0x0a0e6e70, 0x27b70a85, 0x46d22ffc, 0x2e1b2138, 0x5c26c926, 0x4d2c6dfc, 0x5ac42aed, 0x53380d13, 0x9d95b3df,
  0x650a7354, 0x8baf63de, 0x766a0abb, 0x3c77b2a8, 0x81c2c92e, 0x47edaee6, 0x92722c85, 0x1482353b, 0xa2bfe8a1,
  0x4cf10364, 0xa81a664b, 0xbc423001, 0xc24b8b70, 0xd0f89791, 0xc76c51a3, 0x0654be30, 0xd192e819, 0xd6ef5218,
  0xd6990624, 0x5565a910, 0xf40e3585, 0x5771202a, 0x106aa070, 0x32bbd1b8, 0x19a4c116, 0xb8d2d0c8, 0x1e376c08,
  0x5141ab53, 0x2748774c, 0xdf8eeb99, 0x34b0bcb5, 0xe19b48a8, 0x391c0cb3, 0xc5c95a63, 0x4ed8aa4a, 0xe3418acb,
  0x5b9cca4f, 0x7763e373, 0x682e6ff3, 0xd6b2b8a3, 0x748f82ee, 0x5defb2fc, 0x78a5636f, 0x43172f60, 0x84c87814,
  0xa1f0ab72, 0x8cc70208, 0x1a6439ec, 0x90befffa, 0x23631e28, 0xa4506ceb, 0xde82bde9, 0xbef9a3f7, 0xb2c67915,
  0xc67178f2, 0xe372532b, 0xca273ece, 0xea26619c, 0xd186b8c7, 0x21c0c207, 0xeada7dd6, 0xcde0eb1e, 0xf57d4f7f,
  0xee6ed178, 0x06f067aa, 0x72176fba, 0x0a637dc5, 0xa2c898a6, 0x113f9804, 0xbef90dae, 0x1b710b35, 0x131c471b,
  0x28db77f5, 0x23047d84, 0x32caab7b, 0x40c72493, 0x3c9ebe0a, 0x15c9bebc, 0x431d67c4, 0x9c100d4c, 0x4cc5d4be,
  0xcb3e42b6, 0x597f299c, 0xfc657e2a, 0x5fcb6fab, 0x3ad6faec, 0x6c44198c, 0x4a475817,
}
local H0 = {
  0x6a09e667, 0xf3bcc908, 0xbb67ae85, 0x84caa73b, 0x3c6ef372, 0xfe94f82b, 0xa54ff53a, 0x5f1d36f1, 0x510e527f,
  0xade682d1, 0x9b05688c, 0x2b3e6c1f, 0x1f83d9ab, 0xfb41bd6b, 0x5be0cd19, 0x137e2179,
}

-- rotate right a 64-bit (hi, lo) by n (0 < n < 64): plain arithmetic, the parts never overlap
local function rotr(hi, lo, n)
  if n >= 32 then hi, lo, n = lo, hi, n - 32 end
  if n == 0 then return hi, lo end
  local d, u = 2 ^ n, 2 ^ (32 - n)
  return floor(hi / d) + (lo % d) * u, floor(lo / d) + (hi % d) * u
end
local function shr(hi, lo, n) -- n < 32
  local d, u = 2 ^ n, 2 ^ (32 - n)
  return floor(hi / d), floor(lo / d) + (hi % d) * u
end

--- SHA-512 of a byte array (0-based, length n) -> byte array (0-based, 64).
function Ed.sha512(msg, n)
  local bytes = {}
  for i = 0, n - 1 do bytes[i] = msg[i] end
  bytes[n] = 0x80
  local total = n + 1
  while total % 128 ~= 112 do bytes[total] = 0; total = total + 1 end
  -- 128-bit length in bits, big endian (messages here are far below 2^53 bits)
  local bits = n * 8
  for i = 15, 0, -1 do bytes[total + i] = bits % 256; bits = floor(bits / 256) end
  total = total + 16
  local h = {}
  for i = 1, 16 do h[i] = H0[i] end
  local w = {}
  for blk = 0, total - 1, 128 do
    for t = 0, 15 do
      local o = blk + t * 8
      w[2 * t + 1] = ((bytes[o] * 256 + bytes[o + 1]) * 256 + bytes[o + 2]) * 256 + bytes[o + 3]
      w[2 * t + 2] = ((bytes[o + 4] * 256 + bytes[o + 5]) * 256 + bytes[o + 6]) * 256 + bytes[o + 7]
    end
    for t = 16, 79 do
      local ah, al = w[2 * (t - 15) + 1], w[2 * (t - 15) + 2]
      local r1h, r1l = rotr(ah, al, 1)
      local r8h, r8l = rotr(ah, al, 8)
      local s7h, s7l = shr(ah, al, 7)
      local s0h, s0l = bxor(bxor(r1h, r8h), s7h), bxor(bxor(r1l, r8l), s7l)
      local bh, bl = w[2 * (t - 2) + 1], w[2 * (t - 2) + 2]
      local r19h, r19l = rotr(bh, bl, 19)
      local r61h, r61l = rotr(bh, bl, 61)
      local s6h, s6l = shr(bh, bl, 6)
      local s1h, s1l = bxor(bxor(r19h, r61h), s6h), bxor(bxor(r19l, r61l), s6l)
      local lo = s0l + s1l + w[2 * (t - 16) + 2] + w[2 * (t - 7) + 2]
      local hi = s0h + s1h + w[2 * (t - 16) + 1] + w[2 * (t - 7) + 1] + floor(lo / P32)
      w[2 * t + 1], w[2 * t + 2] = hi % P32, lo % P32
    end
    local ah, al, bh, bl, ch, cl, dh, dl = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
    local eh, el, fh, fl, gh, gl, hh, hl = h[9], h[10], h[11], h[12], h[13], h[14], h[15], h[16]
    for t = 0, 79 do
      local x1h, x1l = rotr(eh, el, 14)
      local x2h, x2l = rotr(eh, el, 18)
      local x3h, x3l = rotr(eh, el, 41)
      local S1h, S1l = bxor(bxor(x1h, x2h), x3h), bxor(bxor(x1l, x2l), x3l)
      local chh = bxor(band(eh, fh), band(P32 - 1 - eh, gh))
      local chl = bxor(band(el, fl), band(P32 - 1 - el, gl))
      local lo = hl + S1l + chl + K[2 * t + 2] + w[2 * t + 2]
      local t1h = hh + S1h + chh + K[2 * t + 1] + w[2 * t + 1] + floor(lo / P32)
      local t1l = lo % P32
      local y1h, y1l = rotr(ah, al, 28)
      local y2h, y2l = rotr(ah, al, 34)
      local y3h, y3l = rotr(ah, al, 39)
      local S0h, S0l = bxor(bxor(y1h, y2h), y3h), bxor(bxor(y1l, y2l), y3l)
      local mjh = bxor(bxor(band(ah, bh), band(ah, ch)), band(bh, ch))
      local mjl = bxor(bxor(band(al, bl), band(al, cl)), band(bl, cl))
      local lo2 = S0l + mjl
      local t2h, t2l = S0h + mjh + floor(lo2 / P32), lo2 % P32
      hh, hl, gh, gl, fh, fl = gh, gl, fh, fl, eh, el
      local elo = dl + t1l
      eh, el = (dh + t1h + floor(elo / P32)) % P32, elo % P32
      dh, dl, ch, cl, bh, bl = ch, cl, bh, bl, ah, al
      local alo = t1l + t2l
      ah, al = (t1h + t2h + floor(alo / P32)) % P32, alo % P32
    end
    local v = { ah, al, bh, bl, ch, cl, dh, dl, eh, el, fh, fl, gh, gl, hh, hl }
    for i = 1, 15, 2 do
      local lo = h[i + 1] + v[i + 1]
      h[i], h[i + 1] = (h[i] + v[i] + floor(lo / P32)) % P32, lo % P32
    end
  end
  local out = {}
  for i = 0, 15 do
    local x = h[i + 1]
    for j = 3, 0, -1 do out[i * 4 + j] = x % 256; x = floor(x / 256) end
  end
  return out
end

------------------------------------------------------------------ field arithmetic (TweetNaCl, 0-based)
local function gf(init)
  local r = {}
  for i = 0, 15 do r[i] = init and init[i + 1] or 0 end
  return r
end
local gf0, gf1 = gf(), gf({ 1 })
local D = gf({ 0x78a3, 0x1359, 0x4dca, 0x75eb, 0xd8ab, 0x4141, 0x0a4d, 0x0070, 0xe898, 0x7779, 0x4079, 0x8cc7, 0xfe73, 0x2b6f, 0x6cee, 0x5203 })
local D2 = gf({ 0xf159, 0x26b2, 0x9b94, 0xebd6, 0xb156, 0x8283, 0x149a, 0x00e0, 0xd130, 0xeef3, 0x80f2, 0x198e, 0xfce7, 0x56df, 0xd9dc, 0x2406 })
local X = gf({ 0xd51a, 0x8f25, 0x2d60, 0xc956, 0xa7b2, 0x9525, 0xc760, 0x692c, 0xdc5c, 0xfdd6, 0xe231, 0xc0a4, 0x53fe, 0xcd6e, 0x36d3, 0x2169 })
local Y = gf({ 0x6658, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666 })
local I = gf({ 0xa0b0, 0x4a0e, 0x1b27, 0xc4ee, 0xe478, 0xad2f, 0x1806, 0x2f43, 0xd7a7, 0x3dfb, 0x0099, 0x2b4d, 0xdf0b, 0x4fc1, 0x2480, 0x2b83 })
local L = { [0] = 0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x10 }

local function set25519(r, a) for i = 0, 15 do r[i] = a[i] end end
local function car25519(o)
  local c = 1
  for i = 0, 15 do
    local v = o[i] + c + 65535
    c = floor(v / 65536)
    o[i] = v - c * 65536
  end
  o[0] = o[0] + c - 1 + 37 * (c - 1)
end
local function sel25519(p, q, b)
  if b == 1 then for i = 0, 15 do p[i], q[i] = q[i], p[i] end end
end
local function pack25519(o, n)
  local m, t = gf(), gf()
  for i = 0, 15 do t[i] = n[i] end
  car25519(t); car25519(t); car25519(t)
  for _ = 1, 2 do
    m[0] = t[0] - 0xffed
    for i = 1, 14 do
      m[i] = t[i] - 0xffff - ((m[i - 1] < 0) and 1 or 0)
      m[i - 1] = m[i - 1] % 65536
    end
    m[15] = t[15] - 0x7fff - ((m[14] < 0) and 1 or 0)
    local b = (m[15] < 0) and 1 or 0
    m[14] = m[14] % 65536
    sel25519(t, m, 1 - b)
  end
  for i = 0, 15 do
    o[2 * i] = t[i] % 256
    o[2 * i + 1] = floor(t[i] / 256)
  end
end
local function neq25519(a, b)
  local c, d = {}, {}
  pack25519(c, a); pack25519(d, b)
  for i = 0, 31 do if c[i] ~= d[i] then return true end end
  return false
end
local function par25519(a)
  local d = {}
  pack25519(d, a)
  return d[0] % 2
end
local function unpack25519(o, n)
  for i = 0, 15 do o[i] = n[2 * i] + n[2 * i + 1] * 256 end
  o[15] = o[15] % 32768
end
local function A(o, a, b) for i = 0, 15 do o[i] = a[i] + b[i] end end
local function Z(o, a, b) for i = 0, 15 do o[i] = a[i] - b[i] end end
local t31 = {}
local function M(o, a, b)
  local t = t31
  for i = 0, 30 do t[i] = 0 end
  for i = 0, 15 do
    local ai = a[i]
    if ai ~= 0 then
      for j = 0, 15 do t[i + j] = t[i + j] + ai * b[j] end
    end
  end
  for i = 0, 14 do t[i] = t[i] + 38 * t[i + 16] end
  for i = 0, 15 do o[i] = t[i] end
  car25519(o); car25519(o)
end
local function S(o, a) M(o, a, a) end
local function inv25519(o, i)
  local c = gf()
  set25519(c, i)
  for a = 253, 0, -1 do
    S(c, c)
    if a ~= 2 and a ~= 4 then M(c, c, i) end
  end
  set25519(o, c)
end
local function pow2523(o, i)
  local c = gf()
  set25519(c, i)
  for a = 250, 0, -1 do
    S(c, c)
    if a ~= 1 then M(c, c, i) end
  end
  set25519(o, c)
end

------------------------------------------------------------------ points
local function add(p, q)
  local a, b, c, d, e, f, g, h, t = gf(), gf(), gf(), gf(), gf(), gf(), gf(), gf(), gf()
  Z(a, p[1], p[0]); Z(t, q[1], q[0]); M(a, a, t)
  A(b, p[0], p[1]); A(t, q[0], q[1]); M(b, b, t)
  M(c, p[3], q[3]); M(c, c, D2)
  M(d, p[2], q[2]); A(d, d, d)
  Z(e, b, a); Z(f, d, c); A(g, d, c); A(h, b, a)
  M(p[0], e, f); M(p[1], h, g); M(p[2], g, f); M(p[3], e, h)
end
local function cswap(p, q, b) for i = 0, 3 do sel25519(p[i], q[i], b) end end
local function pack(r, p)
  local tx, ty, zi = gf(), gf(), gf()
  inv25519(zi, p[2])
  M(tx, p[0], zi); M(ty, p[1], zi)
  pack25519(r, ty)
  r[31] = r[31] + par25519(tx) * 128
end
local function point() return { [0] = gf(), gf(), gf(), gf() } end
local function scalarmult(p, q, s)
  set25519(p[0], gf0); set25519(p[1], gf1); set25519(p[2], gf1); set25519(p[3], gf0)
  for i = 255, 0, -1 do
    local b = floor(s[floor(i / 8)] / 2 ^ (i % 8)) % 2
    cswap(p, q, b)
    add(q, p)
    add(p, p)
    cswap(p, q, b)
  end
end
local function scalarbase(p, s)
  local q = point()
  set25519(q[0], X); set25519(q[1], Y); set25519(q[2], gf1); M(q[3], X, Y)
  scalarmult(p, q, s)
end
local function copyPoint(p) local r = point(); for i = 0, 3 do set25519(r[i], p[i]) end; return r end
local function bitOf(s, i) return floor(s[floor(i / 8)] / 2 ^ (i % 8)) % 2 end
--- h * Q + s * B in one pass (Straus / Shamir: one doubling per bit, at most one addition).
--- Verification works on public data only, so the branches on the scalar bits leak nothing secret.
local function doubleScalarmult(r, h, q, s)
  local b = point()
  set25519(b[0], X); set25519(b[1], Y); set25519(b[2], gf1); M(b[3], X, Y)
  local qb = copyPoint(q); add(qb, b)
  set25519(r[0], gf0); set25519(r[1], gf1); set25519(r[2], gf1); set25519(r[3], gf0)
  local started = false
  for i = 255, 0, -1 do
    if started then add(r, r) end
    local x, y = bitOf(h, i), bitOf(s, i)
    if x == 1 and y == 1 then add(r, qb); started = true
    elseif x == 1 then add(r, q); started = true
    elseif y == 1 then add(r, b); started = true end
  end
end
Ed._scalarmult, Ed._scalarbase, Ed._doubleScalarmult, Ed._point, Ed._pack = scalarmult, scalarbase, doubleScalarmult, point, pack
local function unpackneg(r, p)
  local t, chk, num, den, den2, den4, den6 = gf(), gf(), gf(), gf(), gf(), gf(), gf()
  set25519(r[2], gf1)
  unpack25519(r[1], p)
  S(num, r[1]); M(den, num, D); Z(num, num, r[2]); A(den, r[2], den)
  S(den2, den); S(den4, den2); M(den6, den4, den2); M(t, den6, num); M(t, t, den)
  pow2523(t, t); M(t, t, num); M(t, t, den); M(t, t, den); M(r[0], t, den)
  S(chk, r[0]); M(chk, chk, den)
  if neq25519(chk, num) then M(r[0], r[0], I) end
  S(chk, r[0]); M(chk, chk, den)
  if neq25519(chk, num) then return false end
  if par25519(r[0]) == floor(p[31] / 128) then Z(r[0], gf0, r[0]) end
  M(r[3], r[0], r[1])
  return true
end

------------------------------------------------------------------ scalars mod L
local function modL(r, x)
  for i = 63, 32, -1 do
    local carry = 0
    local j = i - 32
    while j < i - 12 do
      x[j] = x[j] + carry - 16 * x[i] * L[j - (i - 32)]
      carry = floor((x[j] + 128) / 256)
      x[j] = x[j] - carry * 256
      j = j + 1
    end
    x[j] = x[j] + carry
    x[i] = 0
  end
  local carry = 0
  for j = 0, 31 do
    x[j] = x[j] + carry - floor(x[31] / 16) * L[j]
    carry = floor(x[j] / 256)
    x[j] = x[j] % 256
  end
  for j = 0, 31 do x[j] = x[j] - carry * L[j] end
  for i = 0, 31 do
    x[i + 1] = x[i + 1] + floor(x[i] / 256)
    r[i] = x[i] % 256
  end
end
local function reduce(r)
  local x = {}
  for i = 0, 63 do x[i] = r[i]; r[i] = 0 end
  modL(r, x)
end
-- S < L (RFC 8032 5.1.7): compare little-endian 32-byte numbers
local function lessThanL(s)
  for i = 31, 0, -1 do
    if s[i] < L[i] then return true end
    if s[i] > L[i] then return false end
  end
  return false
end

------------------------------------------------------------------ API
local function hexBytes(h)
  if type(h) ~= "string" or #h % 2 ~= 0 or h:find("[^0-9a-fA-F]") then return nil end
  local b, n = {}, #h / 2
  for i = 0, n - 1 do b[i] = tonumber(h:sub(2 * i + 1, 2 * i + 2), 16) end
  return b, n
end
Ed.hexBytes = hexBytes
local function strBytes(s)
  local b = {}
  for i = 1, #s do b[i - 1] = s:byte(i) end
  return b, #s
end
Ed.strBytes = strBytes
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local B64V = {}
for i = 1, 64 do B64V[B64:byte(i)] = i - 1 end
--- base64url without padding -> byte array (0-based), length; nil if a character is outside the alphabet
function Ed.unb64url(s)
  local out, n, acc, bits = {}, 0, 0, 0
  for i = 1, #s do
    local v = B64V[s:byte(i)]
    if not v then return nil end
    acc, bits = acc * 64 + v, bits + 6
    if bits >= 8 then
      bits = bits - 8
      local d = 2 ^ bits
      out[n] = floor(acc / d); n = n + 1
      acc = acc % d
    end
  end
  return out, n
end
function Ed.toHex(b, n)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = string.format("%02x", b[i]) end
  return table.concat(t)
end

--- Verify an Ed25519 signature. pub: 32 bytes, sig: 64 bytes (0-based byte arrays), msg: string.
--- Returns true only for a valid signature; false for anything else (never errors on bad input).
function Ed.verify(pub, sig, msg)
  if type(pub) ~= "table" or type(sig) ~= "table" or type(msg) ~= "string" then return false end
  for i = 0, 31 do local v = pub[i]; if type(v) ~= "number" or v < 0 or v > 255 or v % 1 ~= 0 then return false end end
  for i = 0, 63 do local v = sig[i]; if type(v) ~= "number" or v < 0 or v > 255 or v % 1 ~= 0 then return false end end
  local s = {}
  for i = 0, 31 do s[i] = sig[32 + i] end
  if not lessThanL(s) then return false end
  local q = point()
  if not unpackneg(q, pub) then return false end
  -- h = SHA-512(R || A || M) mod L
  local m, n = {}, 0
  for i = 0, 31 do m[n] = sig[i]; n = n + 1 end
  for i = 0, 31 do m[n] = pub[i]; n = n + 1 end
  for i = 1, #msg do m[n] = msg:byte(i); n = n + 1 end
  local h = Ed.sha512(m, n)
  reduce(h)
  local p = point()
  doubleScalarmult(p, h, q, s)
  local t = {}
  pack(t, p)
  for i = 0, 31 do if t[i] ~= sig[i] then return false end end
  return true
end

return Ed
