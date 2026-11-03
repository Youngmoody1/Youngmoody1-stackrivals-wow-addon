--[[
  StackRivals - Account > Sync tab: paste an SR1 challenge code to play it; copy SR1 result codes
  for stackrivals.io. Manual copy / paste: says so, never claims live sync.
]]
local _, ns = ...
local T = ns.T
local C = T.C
local UI = ns.UI
local SZ = T.SIZE

local ROWS = 3
local RULESET_NAME = { b120 = "Web Challenge 2:00", r180 = "Web Challenge 3:00", daily120 = "Daily Challenge" }

function UI:CreateSync(sheet)
  local Sync = ns.Sync
  local L = 24
  local cw = self.frame:GetWidth() - 2 * L - 2
  local y = CreateFrame("Frame", nil, sheet)
  y:SetPoint("TOPLEFT", 0, 0); y:SetPoint("BOTTOMRIGHT", 0, 0)
  sheet.sync = y
  y.status = T.text(y, SZ.label, C.label); y.status:SetPoint("TOPLEFT", L, -92); y.status:SetWidth(cw); y.status:SetJustifyH("LEFT")

  local h1 = T.label(y, "PLAY A CHALLENGE CODE"); h1:SetPoint("TOPLEFT", L, -116)
  y.code = UI.accountEditBox(y, cw - 106, "Paste an SR1C... code from stackrivals.io", ns.Codes.MAX_CODE)
  y.code:SetPoint("TOPLEFT", L, -132)
  local function play()
    local okP, why = Sync.play(y.code:GetText())
    if okP then y.code:SetText(""); y.code:ClearFocus(); UI.syncNote = nil
    else UI.syncNote = Sync.ERRORS[why] or ("Can't play it: " .. tostring(why)) end
    UI:RefreshSync()
  end
  y.code:SetScript("OnEnterPressed", play)
  y.play = T.button(y, "Play", 100, 24, "primary", play)
  y.play:SetPoint("LEFT", y.code, "RIGHT", 6, 0)

  local h2 = T.label(y, "YOUR RESULTS  -  MANUAL COPY / PASTE TO STACKRIVALS.IO"); h2:SetPoint("TOPLEFT", L, -170)
  y.rows = {}
  for i = 1, ROWS do
    local row = T.panel(y)
    row:SetSize(cw, 28); row:SetPoint("TOPLEFT", L, -186 - (i - 1) * 31)
    row.name = T.text(row, SZ.small, C.paper); row.name:SetPoint("LEFT", 10, 0); row.name:SetJustifyH("LEFT")
    row.info = T.text(row, SZ.label, C.label); row.info:SetPoint("LEFT", 160, 0); row.info:SetJustifyH("LEFT"); row.info:SetWidth(cw - 160 - 100)
    row.btn = T.button(row, "Copy code", 92, 22, "steel", function(b)
      local code, why = Sync.resultCode(b.r)
      if code then
        y.out:SetValue(code); y.out:Show(); y.out:SetFocus(); y.out:HighlightText()
        UI.syncNote = "Ctrl+C, then paste it on stackrivals.io (" .. T.commas(#code) .. " characters). The website replays it before it counts."
        UI.syncNoteGood = true
      else
        UI.syncNote = Sync.ERRORS[why] or ("Can't make a code: " .. tostring(why)); UI.syncNoteGood = false
      end
      UI:RefreshSync()
    end)
    row.btn:SetPoint("RIGHT", -3, 0)
    row:Hide()
    y.rows[i] = row
  end
  y.empty = T.text(y, SZ.small, C.body); y.empty:SetPoint("TOPLEFT", L, -190); y.empty:SetWidth(cw); y.empty:SetJustifyH("LEFT")
  y.empty:SetSpacing(3)
  y.out = UI.accountCopyBox(y, cw, ns.Codes.MAX_CODE)
  y.out:SetPoint("TOPLEFT", L, -282)
  y.out:Hide()
  y.note = T.text(y, SZ.label, C.gold); y.note:SetPoint("TOPLEFT", L, -312); y.note:SetWidth(cw - 150); y.note:SetJustifyH("LEFT")
end

function UI:RefreshSync()
  local s = self.accountSheet
  local y = s and s.sync
  if not y or not y:IsShown() then return end
  local st, r = ns.Account.state()
  y.status:SetText((st == "linked" or st == "not_synced") and ("Linked to " .. (r.profile.name:gsub("|", "||")) .. ": result codes carry your link.")
    or "Not linked: result codes carry only your character name.")
  local list = ns.Sync.exportable(ns.App:Today())
  for i, row in ipairs(y.rows) do
    local e = list[i]
    if e then
      local rr = e.r
      row.name:SetText((e.kind == "daily" and "Daily Challenge (today)") or RULESET_NAME[rr.ruleset] or rr.ruleset)
      row.info:SetText(T.commas(rr.score) .. "  -  " .. date("%d %b", rr.at) .. (rr.exported and "  -  copied" or ""))
      row.btn.r = rr
      row:Show()
    else
      row:Hide()
    end
  end
  y.empty:SetShown(#list == 0)
  y.empty:SetText("Nothing to export yet. Play a challenge code from stackrivals.io, or today's Daily Challenge:\n"
    .. "its best run can be sent to the website's Daily board.")
  y.note:SetText(self.syncNote or "")
  local nc = (self.syncNoteGood and self.syncNote) and C.green or C.gold
  y.note:SetTextColor(nc[1], nc[2], nc[3])
end
