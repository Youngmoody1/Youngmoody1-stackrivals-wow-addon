-- Prints the Daily Blitz seed and its first 7 pieces for a fixed instant, using the addon's own
-- code path (UTC date). run.lua executes this under several TZ settings and compares the output.
local ns = {}
for _, f in ipairs({ "Engine/Prng.lua", "Engine/Pieces.lua", "Engine/Engine.lua", "Engine/Input.lua", "Core/Session.lua" }) do
  assert(loadfile("StackRivals/" .. f))("StackRivals", ns)
end
local instant = 1793750400 + 23 * 3600 + 30 * 60 -- 2026-11-04 23:30 UTC (already Nov 5 east of UTC+0:30)
local day = os.date("!%Y-%m-%d", instant)
local s = ns.Session.new("daily", ns.Session.dailySeed(day), day)
io.write(day, " ", s.seed, " ", s.state.active.id, ",", table.concat(s.state.queue, ","), "\n")
