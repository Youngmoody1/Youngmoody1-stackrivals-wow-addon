--[[
  StackRivals - input-log verification (Lua port of verifyLog in the web project's
  src/lib/match/rules.ts). Replays a log with the real engine and flags impossible play.

  In WoW this runs on the *opponent's* machine (peer check). That catches tampered results and
  impossible input, but it is not the same as the web server verifying a match: both players run
  code they control. Results are labelled accordingly ("peer-checked", never "verified").
  Pure Lua, no WoW API.
]]
local _, ns = ...
ns = ns or {}
local E = ns.Engine

local V = {}
ns.Verify = V

-- Same limits as the web (fingerprinted against src/lib/match/rules.ts in tests).
V.MAX_INPUTS_PER_TICK = 4
V.MAX_INPUTS_PER_SECOND = 80
V.TIME_CAP_MS = 180000 -- web 1v1 default cap; a ruleset may use a shorter cap
V.COUNTDOWN_MS = 4000
V.RECONNECT_GRACE_MS = 15000
V.CLOCK_SLACK_MS = 3000 -- web CLOCK_SLACK_MS: a log may run up to 3 s longer than the observed clock

--- Verify a flat log {tick, action, tick, action, ...}.
--- opts: seed, capTicks, claimed = {score, lines, level?, hash} (optional),
---       engine (optional: the log's engine version, like the web's log.v),
---       elapsedMs (optional: wall-clock ms observed by the verifier, enables faster_than_clock)
--- Reasons appear in the web's order; claim_mismatch / hash_mismatch are added after (import spec).
--- Returns { ok, reasons = {...}, score, lines, level, ticks, hash, toppedOut }
function V.verify(log, logSeed, logTicks, opts)
  local reasons = {}
  local function fail(r)
    reasons[#reasons + 1] = r
    return { ok = false, reasons = reasons, score = 0, lines = 0, level = 1, ticks = 0, hash = nil, toppedOut = false }
  end
  if opts.engine ~= nil and opts.engine ~= E.ENGINE_VERSION then return fail("engine_mismatch") end
  if logSeed ~= opts.seed then return fail("seed_mismatch") end
  if type(logTicks) ~= "number" or logTicks < 0 or logTicks % 1 ~= 0 then return fail("malformed_log") end
  local cap = opts.capTicks
  if logTicks > cap then reasons[#reasons + 1] = "over_time_cap" end
  if opts.elapsedMs and (logTicks / E.TICKS_PER_SECOND) * 1000 > opts.elapsedMs + V.CLOCK_SLACK_MS then
    reasons[#reasons + 1] = "faster_than_clock"
  end

  local n = #log
  if n % 2 ~= 0 then return fail("malformed_log") end
  local prev, perTick, tickCount = -1, 0, 0
  local burst = false
  for i = 1, n, 2 do
    local t, a = log[i], log[i + 1]
    if type(t) ~= "number" or t % 1 ~= 0 or t < prev or t > logTicks or type(a) ~= "number" or a < 0 or a > #E.INPUT_ACTIONS - 1 then
      return fail("malformed_log")
    end
    if t == prev then perTick = perTick + 1 else perTick = 1 end
    if perTick > V.MAX_INPUTS_PER_TICK then burst = true end
    prev = t
    tickCount = tickCount + 1
  end
  if burst then
    reasons[#reasons + 1] = "inhuman_input_rate"
  else
    -- sliding one-second window, same as the web
    local lo = 1
    for hi = 1, n, 2 do
      while log[hi] - log[lo] >= E.TICKS_PER_SECOND do lo = lo + 2 end
      if (hi - lo) / 2 + 1 > V.MAX_INPUTS_PER_SECOND then reasons[#reasons + 1] = "inhuman_input_rate"; break end
    end
  end

  local untilTick = math.min(logTicks, cap)
  local final = E.replay(opts.seed, { startLevel = 1 }, log, untilTick)
  local within = 0
  for i = 1, n, 2 do if log[i] <= cap then within = within + 1 end end
  if #final.inputLog / 2 < within then reasons[#reasons + 1] = "inputs_after_topout" end

  local res = {
    reasons = reasons, score = final.score, lines = final.lines, level = final.level,
    ticks = final.tick, hash = E.hashState(final), toppedOut = final.gameOver,
  }
  local c = opts.claimed
  if c then
    if c.score ~= res.score or c.lines ~= res.lines or (c.level and c.level ~= res.level) then
      reasons[#reasons + 1] = "claim_mismatch"
    end
    if c.hash and c.hash ~= res.hash then reasons[#reasons + 1] = "hash_mismatch" end
  end
  res.ok = #reasons == 0
  return res
end

return V
