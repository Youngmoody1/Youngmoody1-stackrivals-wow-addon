--[[
  StackRivals - build flavour.

  "full"  : everything (the default; duels on).
  "vsbot" : a test build of Spell Battle vs Bot with guild duels switched off: no addon messages
            are registered or answered, the Duel card and /sr duel say so. Made by
            `FLAVOR=vsbot tools/build_release.sh`, which rewrites the line below in the packaged
            copy only (the source always stays "full").
]]
local _, ns = ...
ns = ns or {}
ns.BUILD = { flavour = "full", duels = true }
return ns.BUILD
