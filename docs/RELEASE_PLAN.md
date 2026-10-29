# Release plan

## Stages

**Prelaunch (now → 4 Nov)**
- [x] Automated tests pass (`lua5.1 tests/run.lua`)
- [x] Installed in Retail and Classic Era on the owner's PC (29 Oct)
- [ ] Real Retail and/or Classic Era pass (TESTING_IN_WOW.md) — owner
- [ ] Fix what that pass finds; rebuild
- [ ] CurseForge project page created; first file uploaded as **Beta** (owner approval)
- [x] Launch-night guide (LAUNCH_DAY.md)

**Launch (5 Nov from 00:00 CET)**
- [ ] Confirm Forever interface number; update TOC if needed
- [ ] Install latest build in Forever; real-client pass
- [ ] Fix critical issues
- [ ] Owner approves → upload as **Release** for flavor Forever

## Versions

| Version | Content | Gate |
|---|---|---|
| 0.2.x | Fixes only, from real-client tests (Retail/Classic now, Forever on launch night) | Tests green + client pass on the target client |
| 0.3.0 | Polish from first player feedback (readability, sound balance, keybind defaults) | Forever CLIENT TESTED |
| 0.4.0 | Retail and Classic Era officially supported on CurseForge | Each client CLIENT TESTED |
| 1.0.0 | Stable on Forever + the clients above, no open crash/blocker reports for a week | Owner sign-off |

Multiplayer (guild challenges/duels over addon messages) is explicitly after 1.0.0.

## Fallbacks

- **Forever changes an API we use** → it can only be the UI layer (see COMPATIBILITY.md): patch that
  call behind a feature check, ship 0.2.x. Players can keep playing with *Load out of date AddOns* if only
  the interface number changed.
- **Forever interface number isn't 16001** → one-line TOC change, rebuild, re-upload.
- **CurseForge hasn't approved the project by launch** → share the GitHub release ZIP (manual install
  guide in README) and point CurseForge visitors there once approved; upload the launch build as soon as
  the project is live. Wago Addons is a possible second channel later.
- **A blocking bug we can't fix that night** → don't publish; keep the Beta file only.

## Support and bug reports

- GitHub issues: https://github.com/Youngmoody1/Youngmoody1-stackrivals-wow-addon/issues
- CurseForge comments once the project is live.
- Ask reporters for: client (Forever/Retail/Classic), `/sr version` output, the error text, and steps.
