--[[
  StackRivals - deterministic PRNG (port of src/game/engine/prng.ts).

  Pure Lua 5.1 arithmetic on unsigned 32-bit integers stored in doubles. No bit library,
  no math.random, no time: identical results in WoW, in tests and in the web engine.
]]
local _, ns = ...
ns = ns or {}

local floor = math.floor
local TWO32 = 4294967296
local TWO16 = 65536

-- 4-bit XOR / OR lookup tables (16x16), built once.
local XOR4, OR4 = {}, {}
for a = 0, 15 do
  for b = 0, 15 do
    local x, o, bit = 0, 0, 1
    local aa, bb = a, b
    for _ = 1, 4 do
      local ab, bbit = aa % 2, bb % 2
      if ab ~= bbit then x = x + bit end
      if ab == 1 or bbit == 1 then o = o + bit end
      aa, bb, bit = floor(aa / 2), floor(bb / 2), bit * 2
    end
    XOR4[a * 16 + b] = x
    OR4[a * 16 + b] = o
  end
end

local function nibbleOp(tbl, a, b)
  local r, mul = 0, 1
  for _ = 1, 8 do
    local na, nb = a % 16, b % 16
    r = r + tbl[na * 16 + nb] * mul
    a, b, mul = floor(a / 16), floor(b / 16), mul * 16
  end
  return r
end

--- a XOR b for uint32 values.
local function bxor(a, b) return nibbleOp(XOR4, a, b) end
--- a OR b for uint32 values.
local function bor(a, b) return nibbleOp(OR4, a, b) end
--- logical right shift of a uint32.
local function rshift(a, n) return floor(a / 2 ^ n) end
--- uint32 addition modulo 2^32.
local function add32(a, b) return (a + b) % TWO32 end

--- Math.imul(a, b) >>> 0 for uint32 inputs, without losing precision.
local function imul(a, b)
  local ah, al = floor(a / TWO16), a % TWO16
  local bh, bl = floor(b / TWO16), b % TWO16
  local mid = (ah * bl + al * bh) % TWO16
  return (al * bl + mid * TWO16) % TWO32
end

local Prng = {}

--- FNV-1a 32-bit hash of an ASCII string -> uint32.
function Prng.hashString(input)
  local h = 2166136261 -- 0x811c9dc5
  for i = 1, #input do
    h = bxor(h, input:byte(i))
    h = imul(h, 16777619) -- 0x01000193
  end
  return h
end

--- mulberry32 step: returns value in [0,1) and the next uint32 state.
function Prng.nextRandom(state)
  local nxt = add32(state, 1831565813) -- 0x6d2b79f5
  local t = nxt
  t = imul(bxor(t, rshift(t, 15)), bor(t, 1))
  t = bxor(t, add32(t, imul(bxor(t, rshift(t, 7)), bor(t, 61))))
  local value = bxor(t, rshift(t, 14)) / TWO32
  return value, nxt
end

--- Fisher-Yates shuffle driven by the seeded PRNG. Returns shuffled copy and next state.
function Prng.shuffle(items, state)
  local out = {}
  for i = 1, #items do out[i] = items[i] end
  local s = state
  for i = #out - 1, 1, -1 do -- JS: for (i = len-1; i > 0; i--), 0-based
    local r
    r, s = Prng.nextRandom(s)
    local j = floor(r * (i + 1))
    out[i + 1], out[j + 1] = out[j + 1], out[i + 1]
  end
  return out, s
end

Prng._bxor, Prng._bor, Prng._imul = bxor, bor, imul
ns.Prng = Prng
return Prng
