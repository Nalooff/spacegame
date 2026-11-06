"""Merges t*.py into ../fr.json ... ../ja.json and reports gaps. python3 translations/src/build.py"""
import json, os, glob, importlib.util, sys
here = os.path.dirname(os.path.abspath(__file__))
codes = ["fr", "de", "es", "ru", "zh_CN", "ja"]
allT = {}
for f in sorted(glob.glob(here + "/t*.py")):
    spec = importlib.util.spec_from_file_location("m", f); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    for k, v in m.T.items():
        assert len(v) == 6, (f, k, len(v))
        allT[k] = v
keys = json.load(open(here + "/../keys.json"))
missing = [k for k in keys if k not in allT]
stale = [k for k in allT if k not in keys]
for i, c in enumerate(codes):
    json.dump({k: v[i] for k, v in allT.items() if k in keys}, open(here + "/../%s.json" % c, "w"), ensure_ascii=False, indent=1)
print(len(allT), "translated;", len(missing), "missing;", len(stale), "stale")
for k in missing: print("MISSING", repr(k))
for k in stale: print("STALE", repr(k))
# placeholder check: same % placeholders as English
import re
bad = 0
for k, v in allT.items():
    ph = sorted(re.findall(r"%[-+ 0#]*\d*(?:\.\d+)?[sdfx%]", k))
    for i, t in enumerate(v):
        if sorted(re.findall(r"%[-+ 0#]*\d*(?:\.\d+)?[sdfx%]", t)) != ph:
            bad += 1; print("PLACEHOLDER", codes[i], repr(k)[:70], "->", repr(t)[:70])
print("placeholder problems:", bad)
