-- Layout checks on every screen: text and buttons inside the window, no colliding text, button
-- labels fit their buttons. Sizes of text are estimated (see tests/layout.lua), so the margins
-- are conservative and a pass here still needs the real-client look.
local root, testdir = ...
local H = dofile(testdir .. "/harness.lua")
local L = dofile(testdir .. "/layout.lua")
local S = assert(loadfile(testdir .. "/screens.lua"))(root, testdir)
local it, ok, describe = H.it, H.ok, H.describe

local function overlap(a, b, pad)
  pad = pad or 0
  return a.l < b.r - pad and b.l < a.r - pad and a.b < b.t - pad and b.b < a.t - pad
end

local function name(o)
  local t = o._text and L.stripCodes(o._text):gsub("\n", " ") or "?"
  return string.format("%q", #t > 30 and (t:sub(1, 30) .. "...") or t)
end

describe("layout of every screen", function()
  for _, sc in ipairs(S.list) do
    it(sc[1] .. " - " .. sc[2], function()
      local M, ns, root_ = sc[3]()
      local F = root_ or StackRivalsFrame
      local R, items = L.collect(M, F)
      local texts = {}
      for _, o in ipairs(items) do
        if o._kind == "FontString" and type(o._text) == "string" and o._text ~= "" and R.alpha(o) > 0.05 then
          texts[#texts + 1] = o
        end
      end
      ok(#texts > 3, "screen has text")
      local problems = {}
      -- 1) inside the window
      for _, o in ipairs(texts) do
        local r = R.rect(o)
        if r.l < -1 or r.r > F._w + 1 or r.b < -1 or r.t > F._h + 1 then
          problems[#problems + 1] = "outside window: " .. name(o)
        end
      end
      -- 2) no two texts on the same layer group collide (texts on a higher frame level are
      --    allowed to cover lower ones: overlays deliberately sit on top of the HUD)
      for i = 1, #texts do
        for j = i + 1, #texts do
          local a, b = texts[i], texts[j]
          if R.level(a) == R.level(b) and overlap(R.rect(a), R.rect(b), 1) then
            problems[#problems + 1] = "text overlap: " .. name(a) .. " / " .. name(b)
          end
        end
      end
      -- 3) button labels fit inside their buttons; buttons don't overlap each other
      local buttons = L.buttons(M, R)
      for _, b in ipairs(buttons) do
        if b.fs and type(b.fs._text) == "string" and b.fs._text ~= "" then
          local br, size = R.rect(b), b.fs._font[2]
          local lw = L.textWidth(b.fs._text, size)
          if not b.noPress and lw > (br.r - br.l) - 4 then
            problems[#problems + 1] = string.format("label too wide for button: %s (%.0f > %.0f)", name(b.fs), lw, br.r - br.l - 4)
          end
        end
      end
      for i = 1, #buttons do
        for j = i + 1, #buttons do
          local a, b = buttons[i], buttons[j]
          if R.level(a) == R.level(b) and overlap(R.rect(a), R.rect(b), 0) then
            problems[#problems + 1] = "buttons overlap: " .. name(a.fs or {}) .. " / " .. name(b.fs or {})
          end
        end
      end
      -- 4) text never sits on top of a button it doesn't belong to (same frame level), and text
      --    inside a button stays inside it
      for _, o in ipairs(texts) do
        for _, b in ipairs(buttons) do
          local own = (o._parent == b)
          local r, br = R.rect(o), R.rect(b)
          if own then
            if r.l < br.l - 1 or r.r > br.r + 1 or r.b < br.b - 1 or r.t > br.t + 1 then
              problems[#problems + 1] = "text leaves its button: " .. name(o)
            end
          elseif (o._parent == b._parent or R.level(o) == R.level(b)) and overlap(r, br, 1) then
            problems[#problems + 1] = "text over a button: " .. name(o) .. " / button " .. name(b.fs or {})
          end
        end
      end
      if #problems > 0 then error(table.concat(problems, "\n    ")) end
    end)
  end
end)

return H
