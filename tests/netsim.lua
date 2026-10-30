--[[
  Network simulator for multiplayer tests: several COMPLETE addon instances (each with its own
  WoW API mock, SavedVariables and globals) in one Lua process, connected by a fake addon-message
  bus with configurable latency, loss, duplication, reordering, throttling, lockdown and offline
  players. Deterministic (seeded) so failures reproduce.

  This simulates WoW; it is not a real two-client test.
]]
local root, testdir = ...
local NS = {}

local function tocFiles()
  local files = {}
  for line in io.lines(root .. "/StackRivals.toc") do
    if line ~= "" and not line:match("^##") then files[#files + 1] = (line:gsub("\\", "/")) end
  end
  return files
end

NS.stdlib = {}
for _, k in ipairs({ "assert", "error", "ipairs", "next", "pairs", "pcall", "print", "rawequal", "rawget", "rawset",
  "select", "setmetatable", "getmetatable", "tonumber", "tostring", "type", "unpack", "xpcall", "loadstring",
  "string", "table", "math", "os", "io", "coroutine", "debug", "_VERSION" }) do NS.stdlib[k] = _G[k] end

function NS.new(opts)
  opts = opts or {}
  local net = {
    clients = {}, byName = {}, queue = {}, time = 0, seq = 0,
    latency = opts.latency or { 0.05, 0.25 }, drop = opts.drop or 0, dup = opts.dup or 0,
    rng = opts.seed or 1, log = {}, sent = 0, delivered = 0, throttled = 0,
    instance = opts.instance or false, -- whispers are throttled inside instances
  }

  function net.random()
    net.rng = (net.rng * 1103515245 + 12345) % 2147483648
    return math.floor(net.rng / 65536) / 32768
  end

  local function full(name) return name:find("-", 1, true) and name or (name .. "-Realm") end

  --- Add a client. o: name, realm, guild, group, engine (override ENGINE_VERSION), flavor
  function net.add(o)
    -- only the Lua standard library leaks in: no WoW globals or saved data from other tests
    local env = setmetatable({}, { __index = NS.stdlib })
    local M = dofile(testdir .. "/wowmock.lua")
    M.install(env)
    M.playerName, M.realm = o.name, o.realm or "Realm"
    M.inInstance = net.instance
    env.IsInGuild = function() return o.guild ~= nil end
    env.IsInGroup = function() return o.group ~= nil end
    env.IsInRaid = function() return false end
    env.StackRivalsDB = o.saved
    env.math = setmetatable({ random = function(a, b) return a + math.floor(net.random() * (b - a + 1)) end }, { __index = math })
    local c = { name = full(o.name), env = env, M = M, o = o, bucket = { tokens = 10, at = 0 }, online = true, lockdownUntil = -1 }
    env.C_ChatInfo.SendAddonMessage = function(prefix, text, channel, target) return net.send(c, prefix, text, channel, target) end
    local ns = {}
    for _, f in ipairs(tocFiles()) do
      local chunk = assert(loadfile(root .. "/" .. f))
      setfenv(chunk, env)
      chunk("StackRivals", ns)
    end
    if o.engine then ns.Engine.ENGINE_VERSION = o.engine end
    c.ns = ns
    M.time = net.time
    if o.beforeLogin then o.beforeLogin(env, M, ns) end
    M.fire("ADDON_LOADED", "StackRivals")
    M.fire("PLAYER_LOGIN")
    net.clients[#net.clients + 1] = c
    net.byName[c.name:lower()] = c
    return c
  end

  --- /reload: logout (the addon may send a last message), then a fresh Lua state with the same
  --- SavedVariables and the same character. Messages in flight are delivered to the new instance.
  function net.reload(c)
    c.M.time = net.time
    c.M.fire("PLAYER_LOGOUT")
    for i, x in ipairs(net.clients) do if x == c then table.remove(net.clients, i); break end end
    local o = {}
    for k, v in pairs(c.o) do o[k] = v end
    o.saved = c.env.StackRivalsDB
    o.beforeLogin = nil
    local n = net.add(o)
    n.reloads = (c.reloads or 0) + 1
    return n
  end

  -- Blizzard's documented limit: per prefix 10 messages, +1/s; whispers exempt outside instances.
  local function throttled(c, channel)
    if channel == "WHISPER" and not net.instance then return false end
    local b = c.bucket
    b.tokens = math.min(10, b.tokens + (net.time - b.at))
    b.at = net.time
    if b.tokens < 1 then return true end
    b.tokens = b.tokens - 1
    return false
  end

  local function enqueue(to, from, prefix, text, channel)
    if net.random() < net.drop then net.log[#net.log + 1] = "drop " .. text; return end
    local copies = (net.random() < net.dup) and 2 or 1
    for _ = 1, copies do
      net.seq = net.seq + 1
      local lat = net.latency[1] + net.random() * (net.latency[2] - net.latency[1])
      net.queue[#net.queue + 1] = { at = net.time + lat, seq = net.seq, to = to, from = from, prefix = prefix, text = text, channel = channel }
    end
  end

  function net.send(c, prefix, text, channel, target)
    assert(#prefix <= 16 and #text <= 255, "addon message limits")
    if not c.online then return 9 end
    if net.time < c.lockdownUntil then return 11 end
    if throttled(c, channel) then net.throttled = net.throttled + 1; return 3 end
    net.sent = net.sent + 1
    if net.tap then net.tap(c, text, channel, target) end
    if channel == "WHISPER" then
      local to = net.byName[full(target):lower()]
      if not to or not to.online then return 12 end
      enqueue(to, c, prefix, text, channel)
    elseif channel == "GUILD" then
      if not c.o.guild then return 10 end
      for _, o in ipairs(net.clients) do if o.o.guild == c.o.guild and o.online then enqueue(o, c, prefix, text, channel) end end -- incl. own echo
    elseif channel == "PARTY" or channel == "RAID" then
      if not c.o.group then return 5 end
      for _, o in ipairs(net.clients) do if o.o.group == c.o.group and o.online then enqueue(o, c, prefix, text, channel) end end
    else
      return 4
    end
    return 0
  end

  --- Inject a raw packet as if `fromName` had sent it.
  function net.inject(to, fromName, text, channel)
    to.M.fire("CHAT_MSG_ADDON", "StackRivals", text, channel or "WHISPER", fromName)
  end

  --- Advance simulated time by n frames of dt for every client, delivering due messages.
  function net.step(n, dt)
    dt = dt or (1 / 60)
    for _ = 1, n do
      net.time = net.time + dt
      table.sort(net.queue, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.seq < b.seq end)
      while net.queue[1] and net.queue[1].at <= net.time do
        local q = table.remove(net.queue, 1)
        local to = net.byName[q.to.name:lower()] or q.to -- the current instance (after a /reload)
        if to.hangUntil and net.time < to.hangUntil then
          -- a frozen client runs no Lua: the message waits until it is back
          q.at = to.hangUntil; net.queue[#net.queue + 1] = q
        elseif to.online then
          net.delivered = net.delivered + 1
          to.M.fire("CHAT_MSG_ADDON", q.prefix, q.text, q.channel, q.from.name)
        end
      end
      for _, c in ipairs(net.clients) do
        -- a client can run at its own frame rate (c.frameDt, e.g. 1/15) and freeze (c.hangUntil):
        -- its frames then come less often, each with the time since its last frame
        if not c.frameDt and not c.hangUntil then
          c.M.time = net.time
          c.M.frames_step(1, dt)
        else
          c.acc = (c.acc or 0) + dt
          local hung = c.hangUntil and net.time < c.hangUntil
          if not hung and c.acc >= (c.frameDt or dt) - 1e-9 then
            local fdt = c.acc
            c.acc = 0
            c.M.time = net.time - fdt -- frames_step adds fdt: GetTime() = net.time in this frame
            c.M.frames_step(1, fdt)
          end
        end
        c.M.time = net.time -- frames_step advanced it; keep every client on the shared clock
      end
    end
  end

  return net
end

--- A scripted "player" that plays decently (so runs last the full time): for each new piece it
--- simulates every rotation/column on a copy of the board, picks the flattest result and then
--- presses the keys for it like a human, one key every few frames. `skill` 1..3 = pace.
function NS.autoplay(c, style)
  local E = c.ns.Engine
  local plan, planFor, wait = nil, nil, 0
  local gap = (style == "fast") and 4 or 7
  local function copy(s)
    local t = {}
    for k, v in pairs(s) do t[k] = v end
    t.board = {}
    for i = 1, #s.board do t.board[i] = s.board[i] end
    t.active = s.active and { id = s.active.id, rotation = s.active.rotation, x = s.active.x, y = s.active.y }
    t.queue = {}
    for i = 1, #s.queue do t.queue[i] = s.queue[i] end
    t.clears = { none = 0, single = 0, double = 0, triple = 0, quad = 0 }
    t.inputLog = {}
    return t
  end
  local function evaluate(s)
    local w, h = s.config.width, s.config.height + s.config.hiddenRows
    local holes, agg, bump, prevH = 0, 0, 0, nil
    for x = 0, w - 1 do
      local top = h
      for y = 0, h - 1 do if s.board[y * w + x + 1] ~= 0 then top = y; break end end
      local ht = h - top
      agg = agg + ht
      if prevH then bump = bump + math.abs(ht - prevH) end
      prevH = ht
      for y = top + 1, h - 1 do if s.board[y * w + x + 1] == 0 then holes = holes + 1 end end
    end
    return -0.5 * agg - 3.5 * holes - 0.3 * bump + 0.8 * s.lines * 10
  end
  local function choose(s)
    local best
    for rot = 0, 3 do
      for dx = -5, 5 do
        local t = copy(s)
        local keys = {}
        local okMove = true
        for _ = 1, rot do keys[#keys + 1] = "UP"; local r0 = t.active.rotation; E.applyInput(t, "rotateCW"); if t.active.rotation == r0 and t.active.id ~= "cube" then okMove = false end end
        for _ = 1, math.abs(dx) do
          keys[#keys + 1] = dx < 0 and "LEFT" or "RIGHT"
          local x0 = t.active.x
          E.applyInput(t, dx < 0 and "left" or "right")
          if t.active.x == x0 then okMove = false end
        end
        if okMove then
          E.applyInput(t, "hardDrop")
          local v = t.gameOver and -1e9 or evaluate(t)
          if not best or v > best.v then keys[#keys + 1] = "SPACE"; best = { v = v, keys = keys } end
        end
      end
    end
    return best and best.keys or { "SPACE" }
  end
  return function()
    local ui = c.ns.UI
    local sess = c.ns.App.session
    if not (sess and sess.phase == "playing" and ui.keys and ui.keys._kb) then return end
    local s = sess.state
    if not s.active then return end
    if planFor ~= s.piecesPlaced then plan, planFor, wait = choose(s), s.piecesPlaced, gap end
    wait = wait - 1
    if wait > 0 or not plan or #plan == 0 then return end
    wait = gap
    local key = table.remove(plan, 1)
    local down, up = ui.keys:GetScript("OnKeyDown"), ui.keys:GetScript("OnKeyUp")
    down(ui.keys, key); up(ui.keys, key)
  end
end

return NS
