"""One-off helper: wraps the English UI string literals of selected GDScript lines in tr("..."). Prints every change.
   python3 tools/i18n_wrap.py scripts/ui/lobby.gd ...  (files are rewritten; review with git diff)"""
import re, sys
CTX = re.compile(r'(draw_string\(|\.text\s*\+?=|tooltip_text\s*=|placeholder_text\s*=|notify\.emit\(|show_banner\(|add_item\(|\bnote\s*=|title_label\.text|\bmessage\.text)')
LIT = re.compile(r'(?<![\w&\\])"((?:[^"\\]|\\.)*)"')
def wrap_line(line):
    if "tr(" in line and 'tr("' in line:
        return line
    out, pos = [], 0
    for m in LIT.finditer(line):
        text = m.group(1)
        before = line[:m.start()]
        after = line[m.end():]
        if len(re.findall(r'[A-Za-z]{3,}', text)) == 0:
            continue
        if before.rstrip().endswith("[") and after.lstrip().startswith("]"):
            continue
        if re.search(r'\.get\(\s*$', before) or re.search(r'\.get\([^)]*,\s*$', before):
            # a dictionary key or its default: only default text that is a phrase is wrapped
            if " " not in text: continue
        if re.search(r'(preload|load)\(\s*$', before) or text.startswith("res://") or text.startswith("user://"):
            continue
        if text.startswith("[") and "]" not in text[:3]: pass
        out.append((m.start(), m.end(), text))
    if not out: return line
    res, last = [], 0
    for a, b, t in out:
        res.append(line[last:a]); res.append('tr("%s")' % t); last = b
    res.append(line[last:])
    return "".join(res)
for path in sys.argv[1:]:
    lines = open(path).read().split("\n")
    changed = 0
    for i, l in enumerate(lines):
        if CTX.search(l) and not l.lstrip().startswith("#") and "print(" not in l and "push_" not in l:
            n = wrap_line(l)
            if n != l:
                lines[i] = n; changed += 1
    open(path, "w").write("\n".join(lines))
    print(path, changed)
