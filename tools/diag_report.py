"""Turn a StackRivals report line (/sr report in WoW: "SRDIAG1;v=...;client=...") into a readable
table, with the things that usually explain a problem called out.

  python3 tools/diag_report.py "SRDIAG1;v=0.8.1;..."        # or
  python3 tools/diag_report.py report.txt                   # a file with one or more report lines
  python3 tools/diag_report.py --selftest

Reports contain no character, realm or chat data (Core/Report.lua).
"""
import os
import sys

FIELDS = [
    ("v", "Addon version"), ("engine", "Engine"), ("build", "Build flavour"), ("client", "Client type"),
    ("project", "WOW_PROJECT_ID"), ("iface", "Interface"), ("wow", "WoW version.build"), ("byIface", "Type guessed from interface (no project ID)"),
    ("hc", "Hardcore"), ("sod", "Season of Discovery"), ("trial", "Trial / Veteran account"), ("api", "APIs present"),
    ("locked", "Addon chat lockdown now"), ("why", "Lockdown reason"), ("inst", "Instance"), ("group", "Group channel:size"),
    ("loot", "Loot method"), ("comm", "Messages"), ("codes", "Send result codes"), ("ct", "Last /sr commtest"),
    ("db", "Saved data"), ("err", "Errors caught"), ("utc", "Time (UTC)"),
]
API = {"am": "addon messages", "bn": "Battle.net game data", "lk": "lockdown API", "ra": "restriction API",
       "lm": "loot method API", "sv": "secret values", "cp": "addon compartment", "ii": "item info"}
CODES = {"0": "ok", "3": "throttled (prefix)", "8": "throttled (channel)", "9": "general error", "11": "AddOnMessageLockdown",
         "12": "target offline", "5": "not in group", "10": "not in guild"}
KNOWN_IFACES = {"16001", "11509", "120105", "20506", "50504", "38002"}


def parse(line):
    line = line.strip()
    if not line.startswith("SRDIAG1;"):
        raise ValueError("not a StackRivals report (must start with SRDIAG1;)")
    out = {}
    for part in line.split(";")[1:]:
        if "=" in part:
            k, _, v = part.partition("=")
            out[k] = v
    return out


def findings(r):
    f = []
    if r.get("iface") and r["iface"] not in KNOWN_IFACES:
        f.append(f"interface {r['iface']} is not in the TOC: add it (tools/clients.json) or players see 'out of date'")
    if r.get("byIface") == "1":
        f.append("WOW_PROJECT_ID missing or unknown: client type was guessed from the interface number")
    if r.get("client") == "unknown":
        f.append("unknown client type: check WOW_PROJECT_ID and add it to Core/Client.lua")
    if r.get("trial") == "1":
        f.append("trial / veteran account: no addon messages (duels, Quickplay, Loot Duel can't work)")
    if r.get("locked") == "1":
        f.append(f"WoW's addon chat lockdown was active ({r.get('why', '-')}): messages wait until it lifts")
    if "am0" in r.get("api", ""):
        f.append("C_ChatInfo.SendAddonMessage missing")
    comm = r.get("comm", "")
    if "un1" in comm:
        f.append("addon messages unavailable (prefix registration failed)")
    for c in r.get("codes", "-").split(","):
        code, _, n = c.partition("x")
        if code in ("3", "8"):
            f.append(f"throttled {n} times (code {code})")
        if code == "11":
            f.append(f"lockdown refusals: {n}")
    ct = r.get("ct", "-")
    if ct != "-":
        bits = dict((b[:3], b) for b in ct.split(","))
        ans = bits.get("ans", "")
        if ans.startswith("ans0/") and not ans.endswith("/0"):
            f.append(f"commtest: nobody answered ({ct}) - messages don't arrive here, or nobody else runs StackRivals")
    if r.get("err", "-") != "-":
        f.append("errors caught: " + r["err"])
    return f


def render(r):
    lines = []
    for k, label in FIELDS:
        v = r.get(k)
        if v is None:
            continue
        if k == "api":
            v = ", ".join(f"{API.get(p[:2], p[:2])} {'yes' if p.endswith('1') else 'NO'}" for p in v.split(","))
        if k == "codes" and v != "-":
            v = ", ".join(f"{c.partition('x')[0]} {CODES.get(c.partition('x')[0], '?')} x{c.partition('x')[2]}" for c in v.split(","))
        lines.append(f"{label:44} {v}")
    fs = findings(r)
    lines.append("")
    lines.append("Findings:" if fs else "Findings: none")
    lines += ["  - " + x for x in fs]
    return "\n".join(lines)


def selftest():
    sample = ("SRDIAG1;v=0.8.1;engine=1;build=full;client=forever;project=18;iface=16002;wow=1.60.1.70755;byIface=0;hc=0;sod=0;"
              "trial=0;api=am1,bn1,lk1,ra1,lm1,sv1,cp1,ii1;locked=1;why=encounter;inst=party;group=PARTY:5;loot=group;"
              "comm=en1,un0,reg0,s12,r9,d0,x0,lk1,q0,max3;codes=0x11,11x2;ct=PARTY,code0,ans4/4,ms230,lk0,inparty;"
              "db=classic3,loads9;err=-;utc=2026-11-05 00:12")
    r = parse(sample)
    assert r["client"] == "forever" and r["iface"] == "16002"
    fs = findings(r)
    assert any("16002" in x for x in fs), fs
    assert any("lockdown" in x for x in fs), fs
    out = render(r)
    assert "addon messages yes" in out and "AddOnMessageLockdown x2" in out, out
    try:
        parse("hello")
        raise AssertionError("bad input accepted")
    except ValueError:
        pass
    print("diag_report selftest OK")


def main(argv):
    if len(argv) > 1 and argv[1] == "--selftest":
        selftest()
        return 0
    if len(argv) < 2:
        print(__doc__)
        return 1
    arg = argv[1]
    text = open(arg, encoding="utf-8").read() if os.path.isfile(arg) else arg
    rows = [ln for ln in text.splitlines() if ln.strip().startswith("SRDIAG1;")] or [text]
    for i, ln in enumerate(rows):
        if i:
            print("\n" + "-" * 60 + "\n")
        print(render(parse(ln)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
