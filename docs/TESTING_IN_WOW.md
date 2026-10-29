# In-client test pass (≈10 minutes)

Automated tests cover the engine, parity with the web game, saved data and a full simulated
session against a WoW API mock. They **cannot** prove rendering, real keyboard focus or real
combat behaviour. This pass does. Do it on every new client build (beta, launch day, patches).

Before you start: **fully restart the game client** after installing or updating (WoW only picks up new
addon files on a full restart, not on `/reload`). Then enable Lua error display — `/console scriptErrors 1` — so errors pop up instead
of being swallowed. Note any red error text exactly (a screenshot is perfect).

| # | Step | Expected | ✔ |
|---|---|---|---|
| 1 | Character screen → AddOns | **StackRivals** listed with its red/steel icon, enabled. If "Out of date": tick *Load out of date AddOns* and write down the client's interface number (`/dump select(4, GetBuildInfo())` in game) | |
| 2 | Log in | One chat line: "StackRivals: loaded. Type /sr …". Minimap button visible | |
| 3 | `/sr version` | Shows version, engine v1 and the interface number | |
| 4 | `/sr` | Window opens on the mode menu. You can still walk with WASD while the menu is open | |
| 5 | Drag the window by its background, then `/reload`, `/sr` | Window reopens where you left it | |
| 6 | Click **Classic** | 3-2-1 countdown with ticks, then pieces fall. Arrows, Up/Z, Space, C all work. Ghost piece visible | |
| 7 | Hold ← for a second | Piece slides smoothly to the wall (auto-repeat) | |
| 8 | Clear a line or two | Flash + "SINGLE/DOUBLE…" callout + sound. Score/Lines update | |
| 9 | Press **P** | Pause screen. Now WASD moves your character again | |
| 10 | Resume, then press **Enter** | Game pauses and chat opens. Type a message — it works | |
| 11 | Resume, then attack a training dummy / mob (or get attacked) | Game pauses instantly, window hides, you can fight with all your keys. **No "Interface action failed" messages** | |
| 12 | Leave combat | Window comes back, paused, "You entered combat" text. Resume works | |
| 13 | Play a **Blitz 2:00** to the end | "TIME!" screen, score, "NEW BEST". Minimap tooltip shows the Blitz best | |
| 14 | Start Classic, place a few pieces, then `/reload` | After reload `/sr` shows **Continue last run**; it restores the exact board | |
| 15 | Settings → rebind *Hold* to `V`, play, press V | Hold works with V; the footer hint shows V | |
| 16 | Settings → window size − / + | Window scales. `/sr reset` puts it back | |
| 17 | Settings → Sound off | No game sounds | |
| 18 | Right-click minimap button, drag it around the minimap | Settings open; button moves and keeps its place after `/reload` | |
| 19 | In a guild: finish a run → **Share to guild** | One line in guild chat: "[StackRivals] … Can you beat it?" | |
| 20 | Log out fully and back in | Records, settings and keybinds still there | |

Performance: during play, `/dump GetAddOnMemoryUsage and "n/a"` is not needed — just watch for
FPS drops while playing in a city. Report anything noticeable.

## Files to send back for analysis

- Screenshots: `World of Warcraft\<game folder>\Screenshots\`
- Saved data: `World of Warcraft\<game folder>\WTF\Account\<ACCOUNT>\SavedVariables\StackRivals.lua`
- Any error text (scriptErrors popup or BugSack if installed)
