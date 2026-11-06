"""Collects every English UI text (scenes + tr("...") in scripts + a few constant tables) into translations/keys.json.
   python3 tools/i18n_extract.py            -> writes translations/keys.json, prints the count
   python3 tools/i18n_extract.py --missing  -> per language, the keys that have no translation yet"""
import re, json, glob, os, sys
ROOT = os.path.join(os.path.dirname(__file__), "..")
def unesc(s):
    return s.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\").replace("\\t", "\t")
LIT = r'"((?:[^"\\]|\\.)*)"'
keys = set()
def add(t):
    t = unesc(t)
    if len(re.findall(r"[A-Za-z]{2,}", t)) and not t.startswith(("res://", "user://")):
        keys.add(t)
# scenes
for f in glob.glob(ROOT + "/scenes/*.tscn"):
    for m in re.finditer(r'^(?:text|tooltip_text|placeholder_text|title|popup/item_\d+/text) = ' + LIT, open(f).read(), re.M):
        add(m.group(1))
# scripts
for f in glob.glob(ROOT + "/scripts/**/*.gd", recursive=True):
    src = open(f).read()
    for m in re.finditer(r'\btr\(' + LIT, src):
        add(m.group(1))
    if f.endswith("settings.gd"):
        for m in re.finditer(r'\b_(?:slider|check|row)\(\w+, ' + LIT + r'(?:, [^"\n]*?(?:, ' + LIT + r')?)?\)', src):
            add(m.group(1))
        for m in re.finditer(r'_(?:slider)\(.*?"[^"]*", [-\d.]+, [-\d.]+, [-\d.]+, "[^"]*", ' + LIT, src):
            add(m.group(1))
        for m in re.finditer(r'_check\(p, "[^"]*", "[^"]*", ' + LIT, src):
            add(m.group(1))
        for m in re.finditer(r'_page\(' + LIT, src):
            add(m.group(1))
        for m in re.finditer(r'_row\(p, ' + LIT + r', ' + LIT, src):
            add(m.group(1)); add(m.group(2))
    if f.endswith("flight_controls.gd"):
        for m in re.finditer(LIT, src[src.index("const NAMES"):src.index("var lever")]):
            add(m.group(1))
    if f.endswith("prefs.gd"):
        blk = src[src.index("const REBINDABLE"):src.index("const LANGUAGES") if "const LANGUAGES" in src else src.index("var scheme")]
        for m in re.finditer(r'\["\w+", ' + LIT + r'\]', blk):
            add(m.group(1))
    if f.endswith("scoreboard.gd"):
        for m in re.finditer(LIT, re.search(r"const HEADERS.*", src).group(0)):
            add(m.group(1))
    if f.endswith("hud.gd"):
        for m in re.finditer(r'str\(' + LIT, src): add(m.group(1))
    if f.endswith("net.gd"):
        for m in re.finditer(r'(?:reason = |join_rejected\.emit\(|Data\.notice = )' + LIT, src):
            add(m.group(1))
    if f.endswith("ship/stations.gd") or f.endswith("ship.gd"):
        pass
EXTRA = ["Mouse steering strength", "Dead zone", "Invert mouse pitch (cursor up = nose down)", "Throttle lever speed", "Orbit / keep-at-range distance",
	"Field of view", "Camera distance at start", "Camera orbit speed", "Invert camera vertical", "Fullscreen", "V-Sync", "3D render scale",
	"Maximum frames per second (0 = unlimited)", "Interface scale", "Show FPS counter", "Master volume", "Camera orbit speed",
	"No turning inside this circle", "Players", "Hide", "Show"]
for e in EXTRA: keys.add(e)
keys.discard("")
out = sorted(keys)
if "--missing" in sys.argv:
    for code in ["fr", "de", "es", "ru", "zh_CN", "ja"]:
        p = os.path.join(ROOT, "translations", code + ".json")
        have = json.load(open(p)) if os.path.exists(p) else {}
        miss = [k for k in out if k not in have]
        print(code, "missing", len(miss))
        if "-v" in sys.argv:
            for k in miss: print("   ", repr(k))
else:
    json.dump(out, open(os.path.join(ROOT, "translations", "keys.json"), "w"), ensure_ascii=False, indent=1)
    print(len(out), "keys")
