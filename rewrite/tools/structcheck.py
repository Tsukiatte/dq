"""Structural sanity for a bundle: block keywords, cross-module table use, and use-before-declaration."""
import re, sys

SUSPECTS = ("DG", "RD", "RT", "MV", "BR", "CFG", "DR", "LB", "UI")

def strip(t):
    t = re.sub(r"--\[\[.*?\]\]", "", t, flags=re.S)
    t = re.sub(r"--[^\n]*", "", t)
    return re.sub(r'"(?:[^"\\]|\\.)*"', '""', t)

def counts(path):
    t = strip(open(path, encoding="utf-8").read())
    return tuple(len(re.findall(r"\b" + k + r"\b", t)) for k in ("function", "end", "then", "do"))

def modules(path):
    src = open(path, encoding="utf-8").read()
    parts = re.split(r"^-- ===== (src/\S+) =====$", src, flags=re.M)
    return [(parts[i], parts[i + 1]) for i in range(1, len(parts), 2)]

def leaks(path):
    out = []
    for name, body in modules(path):
        for s in SUSPECTS:
            if not re.search(r"(?<![\w.])" + s + r"\.", body):
                continue
            if not (re.search(r"local[^\n]*\b" + s + r"\b[^\n]*=", body) or re.search(r"\b" + s + r"\s*=\s*S\.", body)):
                out.append(name + " -> " + s)
    return out

def use_before_decl(path):
    """A module-level `local NAME = {...}` used earlier in the same module than it is declared."""
    out = []
    for name, body in modules(path):
        clean = strip(body)
        for m in re.finditer(r"^local ([A-Z][A-Z0-9_]{2,}) *=", clean, flags=re.M):
            tbl, at = m.group(1), m.start()
            first = None
            for u in re.finditer(r"(?<![\w.])" + tbl + r"\b", clean):
                if u.start() != m.start(1):
                    first = u.start()
                    break
            if first is not None and first < at:
                line = clean[:first].count("\n") + 1
                out.append("%s -> %s used at module line %d, declared at %d" % (name, tbl, line, clean[:at].count("\n") + 1))
    return out

old, new = sys.argv[1], sys.argv[2]
a, b = counts(old), counts(new)
print("old function/end/then/do:", a)
print("new function/end/then/do:", b)
print("delta:", tuple(y - x for x, y in zip(a, b)))
print("cross-module leaks:", leaks(new) or "none")
print("use before declaration:", use_before_decl(new) or "none")
