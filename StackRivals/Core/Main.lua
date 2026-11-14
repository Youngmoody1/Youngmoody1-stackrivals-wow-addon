--[[
  StackRivals - addon bootstrap: SavedVariables, events, slash commands, run lifecycle.
]]
local ADDON, ns = ...
local DB, Session, E = ns.DB, ns.Session, ns.Engine

local function meta(field)
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  if get then
    local ok, v = pcall(get, ADDON, field)
    if ok then return v end
  end
  return nil
end
ns.VERSION = meta("Version") or "dev"

local App = { session = nil, inMenu = true, lastMode = "classic" }
ns.App = App

local PREFIX = "|cfff6f4f0Stack|r|cffe0242fRivals|r: "
function App:Print(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) end

function App:Today() return date("!%Y-%m-%d") end

--- Remember which client/interface loaded the addon (visible in SavedVariables after a test).
function App:RecordDiag()
  local d = ns.db.diag
  local version, build, _, interface = GetBuildInfo()
  local key = tostring(interface or "?")
  local c = d.clients[key] or { loads = 0 }
  d.clients[key] = c
  c.version, c.build, c.interface = tostring(version), tostring(build), tonumber(interface) or 0
  c.project = tonumber(WOW_PROJECT_ID) or 0
  if ns.Client then local i = ns.Client.get(); c.client = i.key; c.hardcore = i.hardcore; c.sod = i.sod end
  c.addon = ns.VERSION
  c.last = date("!%Y-%m-%d %H:%M")
  c.loads = (c.loads or 0) + 1
  d.loads = d.loads + 1
  d.firstSeen = d.firstSeen or c.last
end

--- Seconds until the next Daily Challenge seed (00:00 UTC).
function App:SecondsToUtcMidnight()
  local t = date("!*t")
  return 86400 - (t.hour * 3600 + t.min * 60 + t.sec)
end

function App:BestFor(mode)
  local db = ns.db
  if not db then return 0 end
  if mode == "daily" then
    local d = db.records.dailyToday
    return (d.date == self:Today()) and d.best or 0
  end
  local r = db.records[mode]
  return r and r.best or 0
end

local function newSeed()
  return string.format("%06x%06x%04x", math.random(0, 0xffffff), math.random(0, 0xffffff), math.floor((GetTime() * 1000) % 0xffff))
end

--- Start a fresh run in `mode` (classic | blitz | daily).
function App:Start(mode)
  if ns.UI.inCombat() then self:Print("Can't start a run in combat."); return end
  local md = ns.Session.MODES[mode]
  if md and (md.duel or md.challenge or md.loot or md.ghost) then return end -- duels, web challenges, loot duels and Race My Best have their own start
  local d = ns.Duel and ns.Duel.current
  if d and (d.state == "playing" or d.state == "waiting") then self:Print("Finish or leave your duel first (/sr leave)."); return end
  if ns.LootDuel and ns.LootDuel.busy() then self:Print("You're in a Loot Duel: finish it (or pass) first."); return end
  if ns.Duel then ns.Duel.clear() end -- a finished/cancelled duel must not cover the new run
  if self.session and self.session.spell then ns.SpellBattle.settleAll(self.session) end -- count it first
  ns.UI:Create()
  local seed = (mode == "daily") and Session.dailySeed(self:Today()) or newSeed()
  local opts
  if mode == "spellbot" then
    -- your saved loadout and bot level; the match time picks the bot tuning (as on the web)
    opts = { loadout = ns.Spells.decodeLoadout(ns.db.spell.loadout) or ns.Spells.DEFAULT_LOADOUT,
      difficulty = ns.db.spell.difficulty, createdAtMs = (time and time() or 0) * 1000 }
  end
  self.session = Session.new(mode, seed, self:Today(), opts)
  self.lastMode = mode
  self.inMenu = false
  ns.db.suspended = nil
  if not ns.UI.frame:IsShown() then ns.UI.frame:Show() end
  ns.UI:RefreshPhase()
end

--- Race My Best (Core/Ghost.lua): the pieces of your best `base` run (classic | blitz), that run beside you.
--- Returns false + why (Ghost.WHY) when there is no ghost that replays exactly.
function App:StartGhost(base)
  local G = ns.Ghost
  local gmode = G.MODES[base]
  if not gmode then return false, "mode" end
  if ns.UI.inCombat() then self:Print("Can't start a run in combat."); return false, "combat" end
  local d0 = ns.Duel and ns.Duel.current
  if d0 and (d0.state == "playing" or d0.state == "waiting") then self:Print("Finish or leave your duel first (/sr leave)."); return false, "busy" end
  if ns.LootDuel and ns.LootDuel.busy() then self:Print("You're in a Loot Duel: finish it (or pass) first."); return false, "busy" end
  local e, why = G.source(ns.db, base)
  local d
  if e then d, why = G.validate(e) end
  if not d then self:Print(G.WHY[why] or "There's no run to race yet."); ns.UI:RefreshMenu(); return false, why end
  if ns.Duel then ns.Duel.clear() end
  if self.session and self.session.spell then ns.SpellBattle.settleAll(self.session) end
  ns.UI:Create()
  self.session = Session.new(gmode, d.seed, self:Today())
  G.attach(self.session, e, d)
  self.lastMode = base -- (App:Start can't start a ghost mode: "play again" after a duel = the normal mode)
  self.inMenu = false
  ns.db.suspended = nil
  if not ns.UI.frame:IsShown() then ns.UI.frame:Show() end
  ns.UI:RefreshPhase()
  return true
end

--- After /reload: give a restored Race My Best run its ghost again (only the same ghost; otherwise the run
--- goes on without one and says so).
function App:ReattachGhost(sess, ghostId)
  local G = ns.Ghost
  local e = G.source(ns.db, sess.mode.base)
  local d = e and e.id == ghostId and G.validate(e)
  if d then G.attach(sess, e, d) else sess.ghost = { lost = true, base = sess.mode.base } end
end

--- A Loot Duel race starts (Core/LootDuel.lua): my run on the shared seed, like a duel start.
function App:StartLoot(d)
  if self.session and self.session.spell then ns.SpellBattle.settleAll(self.session) end
  ns.UI:Create()
  local cur = self.session
  if cur and not cur.duel and not cur.loot and not cur.challenge then
    local data = cur:suspendData() -- keep an unfinished solo run for "Continue last run"
    if data then data.date = cur.date or self:Today(); ns.db.suspended = data end
  end
  local du = ns.Duel and ns.Duel.current
  if du and du.state ~= "playing" and du.state ~= "waiting" then ns.Duel.clear() end -- its chat / result panels
  local s = Session.new("loot_" .. d.rs, d.seed, self:Today())
  s.loot = d
  if d.lateBy and d.lateBy > 0 and s.mode.limitTicks then
    -- my go came late: play the rest of the time, so my run ends with everyone else's
    local base = s.mode
    s.mode = setmetatable({ limitTicks = math.max(600, base.limitTicks - d.lateBy * 60) }, { __index = base })
  end
  self.session = s
  self.inMenu = false
  if ns.UI.HideSheets then ns.UI:HideSheets() end
  if not ns.UI.frame:IsShown() and not (ns.UI.inCombat() and ns.db.settings.hideInCombat) then ns.UI.frame:Show() end
  if ns.UI.inCombat() then s:pause("combat")
  elseif GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() then s:pause("chat") end
  ns.UI:RefreshPhase()
end

--- Play an SR1 challenge code (Account > Sync). Returns true or false, reason.
function App:StartChallenge(code)
  local ch, why = ns.Codes.parseChallenge(code)
  if not ch then return false, why end
  if ch.engine ~= E.ENGINE_VERSION then return false, "engine" end
  if ns.UI.inCombat() then return false, "combat" end
  local d = ns.Duel and ns.Duel.current
  if d and (d.state == "playing" or d.state == "waiting") then return false, "duel" end
  if ns.LootDuel and ns.LootDuel.busy() then return false, "loot" end
  if ns.Duel then ns.Duel.clear() end
  if self.session and self.session.spell then ns.SpellBattle.settleAll(self.session) end
  ns.UI:Create()
  self.session = Session.new("chal_" .. ch.ruleset, ch.seed, self:Today())
  self.session.challenge = ch
  self.lastChallenge = code
  self.inMenu = false
  ns.db.suspended = nil
  if ns.UI.HideSheets then ns.UI:HideSheets() end
  if not ns.UI.frame:IsShown() then ns.UI.frame:Show() end
  ns.UI:RefreshPhase()
  return true
end

function App:ContinueSuspended()
  local su = ns.db.suspended
  if not su then return end
  local sess
  if su.mode == "spellbot" then
    sess = Session.new("spellbot", su.seed, su.date, { loadout = ns.Spells.decodeLoadout(su.loadout), difficulty = su.difficulty, createdAtMs = su.createdAtMs })
    if ns.SpellBattle.restore(sess, su) then
      sess.events = {}
      sess.playSeconds = su.playSeconds or 0
      sess.phase, sess.resumePhase, sess.pauseReason = "paused", "playing", "restored"
    else
      sess = nil
    end
  else
    sess = Session.restore(su.mode, su.log, su.playSeconds, su.date)
    if sess and sess.mode.ghost then self:ReattachGhost(sess, su.ghostId) end
  end
  ns.db.suspended = nil
  if not sess then self:Print("That saved run could not be restored."); ns.UI:RefreshMenu(); return end
  self.session = sess
  if sess.mode.challenge then
    -- a web challenge restored after /reload: it is still that challenge (Play again = the same one)
    sess.challenge = { ruleset = sess.mode.challenge, seed = sess.seed, engine = E.ENGINE_VERSION }
    local okC, code = pcall(ns.Codes.challenge, sess.mode.challenge, sess.seed)
    self.lastChallenge = okC and code or nil
  else
    self.lastMode = sess.mode.base or su.mode
  end
  self.inMenu = false
  ns.UI:RefreshPhase()
end

function App:ShowMenu()
  if ns.Duel then ns.Duel.clear() end -- forget a finished/cancelled duel
  self.inMenu = true
  local cur = self.session
  if cur and not cur.duel and not cur.loot and cur.phase ~= "over" then
    -- an unfinished solo run goes to "Continue last run" (as a duel start does): the menu has no other way back
    if cur.spell then ns.SpellBattle.settleAll(cur) end
    local data = cur:suspendData()
    if data then data.date = cur.date or self:Today(); ns.db.suspended = data; self.session = nil end
  end
  if self.session and self.session:isActive() then self.session:pause("manual") end
  if ns.UI.frame then ns.UI:RefreshMenu(); ns.UI:RefreshPhase() end
end

--- The menu, unless a duel or Loot Duel run is on: that run stays (a sheet opened over it pauses it).
function App:MenuUnlessRacing()
  local s = self.session
  if s and (s.duel or s.loot) and s.phase ~= "over" then return end
  self:ShowMenu()
end

function App:Quit()
  -- quitting a running duel is a forfeit (the rival is told and wins), never a silent stop
  local s = self.session
  if s and s.duel and ns.Duel.busy() and s.duel == ns.Duel.current then ns.Duel.leave(); return end
  if s and s.spell then ns.SpellBattle.settleAll(s) end
  self.session = nil
  self:ShowMenu()
end

function App:Pause(reason)
  local s = self.session
  if s and s:pause(reason) and ns.UI.frame then ns.UI:RefreshPhase() end
end

function App:Resume()
  local s = self.session
  if not s then return end
  if ns.UI.inCombat() then self:Print("Finish the fight first."); return end
  if ns.UI.settings and ns.UI.settings:IsShown() then ns.UI:ShowSettings(false) end
  -- duel: if the rival is still paused, I'm "ready" and wait for them (both go on together)
  local m = s.duel
  if m and m.rivalPaused and m.state == "playing" and s.phase == "paused" then
    s.pauseReason = "rival"
    ns.UI:RefreshPhase()
    return
  end
  if s:resume() then ns.UI:RefreshPhase() end
end

--- Called once when a run ends (top-out or time up).
--- Start the local run of a duel (called by Core/Duel.lua when both players are ready).
function App:StartDuel(m)
  ns.UI:Create()
  local cur = self.session
  if cur and not cur.duel then
    local data = cur:suspendData() -- keep an unfinished solo run for "Continue last run"
    if data then data.date = cur.date or self:Today(); ns.db.suspended = data end
  end
  local opts
  if m.ruleset.spell then
    -- Spell Battle duel: my locked loadout; my casts on the rival go out as SP messages
    opts = { loadout = ns.Spells.decodeLoadout(m.myLoadout), remote = {
      loadout = ns.Spells.decodeLoadout(m.rivalLoadout), send = function(inc) ns.Duel.sendCast(m, inc) end } }
  end
  local s = Session.new("duel_" .. m.rulesetId, m.seed, self:Today(), opts)
  s.duel = m
  self.session = s
  self.lastMode = s.mode.key
  self.inMenu = false
  if ns.UI.HideSheets then ns.UI:HideSheets() end
  if not ns.UI.frame:IsShown() and not (ns.UI.inCombat() and ns.db.settings.hideInCombat) then ns.UI.frame:Show() end
  -- GO can arrive after we entered combat or while typing in chat (keys go to the edit box):
  -- never let pieces fall unattended
  if ns.UI.inCombat() then s:pause("combat")
  elseif GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() then s:pause("chat") end
  ns.UI:RefreshPhase()
end

function App:OnRunOver(reason)
  local s = self.session
  if not s or s.recorded then return end
  s.recorded = true
  if s.duel then
    ns.Sound.play("go") -- my run is in; victory / defeat sounds when the result is known (UI/DuelUI.lua)
    ns.Duel.onLocalEnd(s.state, s.spell and s.spell.me.log or nil, s.spell and s.spell.landings or nil)
    ns.UI:ShowOver({ state = s.state, reason = reason, mode = s.mode.key, modeName = s.mode.name, duel = s.duel })
    return
  end
  if s.spell then
    -- Spell Battle vs Bot: the result is final once the bot has played out (see OnSpellResult),
    -- which plays the one end sound (victory or defeat): never two at once
    ns.UI:ShowOver({ state = s.state, reason = reason, mode = s.mode.key, modeName = s.mode.name, spell = s.spell })
    if s.spell.result then self:OnSpellResult() end
    return
  end
  local mode = s.mode.key
  if s.loot then
    -- Loot Duel: my result + log go to everyone; the standings come when all are in (or the deadline)
    ns.LootDuel.onLocalEnd(s)
    ns.Sound.play("gameover")
    ns.UI:ShowOver({ state = s.state, reason = reason, mode = mode, modeName = s.mode.name, loot = s.loot })
    return
  end
  if s.mode.ghost then
    -- Race My Best: never a record; a win becomes the next ghost
    local gr = ns.Ghost.finish(ns.db, s) or { me = s.state.score, best = 0, lost = true }
    ns.Sound.play(gr.beat and "record" or "gameover")
    ns.UI:ShowOver({ state = s.state, reason = reason, mode = mode, modeName = s.mode.name, ghost = gr })
    ns.UI:RefreshMenu()
    return
  end
  if s.mode.challenge then
    -- a web challenge: never a local record; kept for export as an SR1 result code
    if ns.Sync then ns.Sync.saveChallengeRun(s) end
    ns.Sound.play("gameover")
    ns.UI:ShowOver({ state = s.state, reason = reason, mode = mode, modeName = s.mode.name, challenge = s.challenge or s.mode.challenge })
    return
  end
  local res = DB.recordRun(ns.db, mode, s.state, s.playSeconds, s.date or self:Today(), E.serializeLog(s.state), self:Today())
  if res.newBest and ns.Ghost then ns.Ghost.onNewRecord(ns.db, mode) end
  if res.newBest then ns.Sound.play("record") else ns.Sound.play("gameover") end
  if mode == "daily" and res.newTodayBest and ns.Sync then ns.Sync.saveDailyRun(s) end
  ns.UI:ShowOver({
    state = s.state, reason = reason, mode = mode, modeName = s.mode.name,
    newBest = res.newBest, prevBest = res.prevBest, newTodayBest = res.newTodayBest, rank = res.rank,
  })
  ns.UI:RefreshMenu()
end

--- Spell Battle vs Bot result is final: count it once (local stats, never ranked), show it.
function App:OnSpellResult()
  local s = self.session
  if not s or not s.spell or not s.spell.result or s.spellCounted then return end
  s.spellCounted = true
  local r = s.spell.result
  local st = ns.db.spell.stats[s.spell.difficulty]
  if st then
    if r.outcome == "win" then st.wins = st.wins + 1 elseif r.outcome == "loss" then st.losses = st.losses + 1 else st.draws = st.draws + 1 end
    if r.me > st.best then st.best = r.me end
  end
  ns.Sound.play(r.outcome == "win" and "record" or "gameover")
  if ns.UI.over and ns.UI.over:IsShown() then ns.UI:ShowSpellOver(s) end
  ns.UI:RefreshMenu()
end

--- Post the last result to guild or group chat (only when the player clicks the button).
function App:Share(where)
  local s = self.session
  if not s or s.phase ~= "over" then return end
  if ns.UI.inCombat() then return end
  -- Modern clients lock addon chat during encounters / M+ / rated PvP even out of combat.
  if ns.Client and ns.Client.messagingLocked() then
    self:Print("Chat is locked here right now. Share after the encounter.")
    return
  end
  local channel = where
  if where == "GROUP" then
    if IsInRaid and IsInRaid() then channel = "RAID" elseif IsInGroup and IsInGroup() then channel = "PARTY" else return end
  elseif not (IsInGuild and IsInGuild()) then return end
  local st = s.state
  local extra = (s.mode.key == "daily") and (" (Daily " .. (s.date or self:Today()) .. ")") or ""
  local msg = string.format("[StackRivals] %s points, %d lines in %s%s. Can you beat it?",
    ns.T.commas(st.score), st.lines, s.mode.name, extra)
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  local ok = pcall(send, msg, channel)
  if not ok then self:Print("Couldn't post to chat here.") end
end

------------------------------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------------------------------
local function slash(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, arg = msg:match("^(%S*)%s*(.*)$")
  if cmd == "" or cmd == "toggle" then
    ns.UI:Toggle()
  elseif cmd == "classic" or cmd == "blitz" or cmd == "daily" or cmd == "trial" then
    App:Start(cmd == "trial" and "blitz" or cmd) -- "blitz" = Time Trial (internal mode id kept)
  elseif cmd == "quickplay" or cmd == "qp" then
    if ns.BUILD and not ns.BUILD.duels then App:Print("Quickplay is switched off in this test build (Spell Battle vs Bot only).")
    else ns.UI:Create(); ns.UI.frame:Show(); App:MenuUnlessRacing(); ns.UI:ShowSheet("quickplay") end
  elseif cmd == "spell" or cmd == "spells" then
    ns.UI:Create(); ns.UI.frame:Show(); App:MenuUnlessRacing(); ns.UI:ShowSheet("spell")
  elseif cmd == "best" or cmd == "ghost" then
    -- /sr best [classic|trial]: Race My Best; /sr best panel: show / hide the live panel
    if arg == "panel" then
      ns.db.settings.raceBestPanel = not ns.db.settings.raceBestPanel
      App:Print("Race My Best panel " .. (ns.db.settings.raceBestPanel and "shown." or "hidden."))
      if ns.UI.frame then ns.UI:RefreshPhase() end
    else
      ns.UI:Create(); ns.UI.frame:Show()
      App:StartGhost((arg == "trial" or arg == "blitz") and "blitz" or "classic")
    end
  elseif cmd == "pause" then
    App:Pause("manual")
  elseif cmd == "settings" or cmd == "options" or cmd == "config" then
    ns.UI:Create(); ns.UI.frame:Show(); ns.UI:ShowSettings(true)
  elseif cmd == "loot" and ns.LootButton and ns.LootButton.button then
    ns.LootButton:Open() -- the Loot Duel lobby (sends nothing)
  elseif cmd == "lootbutton" and ns.LootButton and ns.LootButton.button then
    local on = ns.LootButton:Toggle(arg)
    App:Print("Loot Duel button " .. (arg == "reset" and "reset to its place" or (on and "on (shown in a party or raid)" or "hidden")) .. ".")
  elseif cmd == "minimap" then
    ns.db.settings.minimapHide = not ns.db.settings.minimapHide
    ns.Minimap:Update()
    App:Print("Minimap button " .. (ns.db.settings.minimapHide and "hidden" or "shown") .. ".")
  elseif cmd == "scale" and tonumber(arg) then
    ns.UI:Create(); ns.UI:SetScale(tonumber(arg))
    App:Print(string.format("Window size %d%%.", ns.db.settings.scale * 100))
  elseif cmd == "reset" then
    ns.UI:Create(); ns.UI:ResetPosition(); ns.UI:SetScale(1)
    App:Print("Window position and size reset.")
  elseif cmd == "sound" then
    ns.db.settings.sound = not ns.db.settings.sound
    ns.Sound.enabled = ns.db.settings.sound
    App:Print("Sound " .. (ns.db.settings.sound and "on" or "off") .. ".")
  elseif cmd == "stats" then
    for _, k in ipairs(Session.MODE_ORDER) do
      local r = ns.db.records[k]
      App:Print(string.format("%s: best %s, %d runs, %d lines, %d quads", Session.MODES[k].name,
        ns.T.commas(r.best), r.games, r.totalLines, r.quads))
    end
  elseif (cmd == "duel" or cmd == "leave") and ns.BUILD and not ns.BUILD.duels then
    App:Print("Duels are switched off in this test build (Spell Battle vs Bot only).")
  elseif cmd == "duel" and arg == "debug" then
    for _, l in ipairs(ns.DuelDiag.status()) do App:Print(l) end
  elseif cmd == "duel" then
    local name, three = arg:match("^(%S+)%s*(%S*)$")
    if not name then
      ns.UI:Create(); ns.UI.frame:Show(); ns.UI:ShowSheet("duel")
    else
      name = name:sub(1, 1):upper() .. name:sub(2)
      local okDuel, why = ns.Duel.challenge(name, (three == "3" or three == "web") and "r180" or "b120")
      if okDuel then App:Print("Duel challenge sent to " .. name .. ".")
      else App:Print("Can't challenge now: " .. (ns.Duel.WHY_NOT[why] or tostring(why)) .. ".") end
    end
  elseif cmd == "leave" then
    if ns.Duel.busy() then ns.Duel.leave(); App:Print("You left the duel.") end
  elseif cmd == "report" or cmd == "diag" then
    if ns.UI and ns.UI.ShowReport then ns.UI:ShowReport() end
  elseif cmd == "commtest" then
    local okT, why = ns.Report and ns.Report.commTest()
    if okT then App:Print("comm test sent: waiting " .. ns.Report.WAIT .. " s for the other StackRivals in your group...")
    else App:Print(({ not_in_group = "Join a party or raid first.", cooldown = "Wait a few seconds between comm tests.",
      unavailable = "Addon messages are not available here." })[why or ""] or "Comm test not available.") end
  elseif cmd == "version" then
    local flavour = (ns.BUILD and ns.BUILD.flavour ~= "full") and (", build " .. ns.BUILD.flavour .. (ns.BUILD.duels and "" or " (duels off)")) or ""
    App:Print("version " .. ns.VERSION .. ", engine v" .. E.ENGINE_VERSION .. ", interface " .. tostring(select(4, GetBuildInfo())) .. flavour
      .. (ns.Client and (", " .. ns.Client.label()) or ""))
  else
    App:Print("commands: /sr (open), /sr classic | trial | daily, /sr best [trial] (Race My Best), /sr best panel, /sr spell, /sr quickplay, /sr duel [Name] [3], /sr leave, /sr pause, /sr settings, /sr loot, /sr lootbutton [reset], /sr minimap, /sr scale 0.8, /sr reset, /sr sound, /sr stats, /sr version, /sr report, /sr commtest")
  end
end

SLASH_STACKRIVALS1 = "/sr"
SLASH_STACKRIVALS2 = "/stackrivals"
SlashCmdList.STACKRIVALS = slash

-- Addon compartment (the addon menu next to the minimap in modern clients). Named in the TOC.
function StackRivals_OnAddonCompartmentClick() ns.UI:Toggle() end

------------------------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local function reg(name) pcall(ev.RegisterEvent, ev, name) end -- unknown events must not error

reg("ADDON_LOADED")
reg("PLAYER_LOGIN")
reg("PLAYER_LOGOUT")
reg("PLAYER_REGEN_DISABLED")
reg("PLAYER_REGEN_ENABLED")
reg("LOADING_SCREEN_ENABLED")
reg("PLAYER_LEAVING_WORLD")
reg("PLAYER_DEAD")
reg("DISPLAY_SIZE_CHANGED")
reg("UI_SCALE_CHANGED")

ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    ns.db = DB.sanitize(StackRivalsDB)
    StackRivalsDB = ns.db
    ns.Sound.enabled = ns.db.settings.sound
    App:RecordDiag()
    local su = ns.db.suspended
    if su and su.mode == "daily" and su.date and su.date ~= App:Today() then ns.db.suspended = nil end
  elseif event == "PLAYER_LOGIN" then
    ns.Minimap:Create()
    if ns.Comm then
      -- a vs-Bot test build (Core/Build.lua) registers no addon messages: duels are off
      if not ns.BUILD or ns.BUILD.duels then ns.Comm.init(); ns.Duel.init() end
      -- build the (hidden) window now so a duel invite can be shown even if StackRivals was
      -- never opened this session
      ns.UI:Create()
      if ns.LootButton then ns.LootButton:Create() end
    end
    if ns.Account and ns.Account.reverify then ns.Account.reverify() end -- a saved VERIFIED profile is checked again
    if not ns.db.seenIntro then
      ns.db.seenIntro = true
      App:Print("loaded. Type |cffff4d5a/sr|r or click the minimap button to play.")
    end
  elseif event == "PLAYER_LOGOUT" then
    -- a running duel can't survive a reload: tell the rival (best effort)
    if ns.Duel and ns.Duel.busy() then ns.Duel.leave("logout") end
    -- keep an unfinished run so /reload or logout never loses it
    local s = App.session
    if s and s.spell then ns.SpellBattle.settleAll(s) end -- a finished Spell Battle is counted now
    if s then
      local data = s:suspendData()
      if data then data.date = s.date or App:Today(); ns.db.suspended = data end
    end
  elseif event == "PLAYER_REGEN_DISABLED" then
    ns.UI.combatNow = true -- the event is the fact: UnitAffectingCombat can be unreadable on modern clients
    -- Fires before combat lockdown starts: pause and hand every key back to WoW now.
    local s = App.session
    if s and s:isActive() then App:Pause("combat") end
    if ns.UI.binding then ns.UI:EndBind() end
    if ns.UI.keys then ns.UI:SetKeyboard(false) end
    local F = ns.UI.frame
    if F and F:IsShown() and ns.db.settings.hideInCombat then
      App.reopenAfterCombat = true
      F:Hide()
    end
    if ns.UI.frame then ns.UI:RefreshMenu() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    ns.UI.combatNow = false
    if App.reopenAfterCombat then
      App.reopenAfterCombat = false
      if ns.UI.frame then ns.UI.frame:Show() end
    end
    if ns.UI.frame then ns.UI:RefreshMenu(); ns.UI:RefreshPhase() end
  elseif event == "LOADING_SCREEN_ENABLED" or event == "PLAYER_LEAVING_WORLD" then
    App:Pause("loading")
  elseif event == "PLAYER_DEAD" then
    App:Pause("manual")
  elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
    -- apply on the next frame: UIParent may not have its new size yet when the event fires
    if ns.UI.frame then ns.UI.rescale = true end
  end
end)
