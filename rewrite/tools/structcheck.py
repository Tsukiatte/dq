"""Structural sanity for a bundle.

Checks, in order:
  * block keyword balance against the previous version (function / end / then / do)
  * a module touching another module's table without importing it
  * a module-level table used above the line that declares it
  * a maths or string helper called bare in a module that never localises it

Usage: python structcheck.py <old.lua> <new.lua>
"""
import re
import sys

SUSPECTS = ("DG", "RD", "RT", "MV", "BR", "CFG", "DR", "LB", "UI")
HELPERS = ("sqrt", "abs", "max", "min", "cos", "sin", "tan", "rad", "deg",
           "floor", "ceil", "clamp", "lower", "upper", "huge", "pi")


def strip(text):
    text = re.sub(r"--\[\[.*?\]\]", "", text, flags=re.S)
    text = re.sub(r"--[^\n]*", "", text)
    return re.sub(r'"(?:[^"\\]|\\.)*"', '""', text)


def counts(path):
    text = strip(open(path, encoding="utf-8").read())
    return tuple(len(re.findall(r"\b" + k + r"\b", text)) for k in ("function", "end", "then", "do"))


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
            declared = re.search(r"local[^\n]*\b" + s + r"\b[^\n]*=", body) or re.search(r"\b" + s + r"\s*=\s*S\.", body)
            if not declared:
                out.append(name + " -> " + s)
    return out


def use_before_decl(path):
    out = []
    for name, body in modules(path):
        clean = strip(body)
        for m in re.finditer(r"^local ([A-Z][A-Z0-9_]{2,}) *=", clean, flags=re.M):
            table, at = m.group(1), m.start()
            first = None
            for u in re.finditer(r"(?<![\w.])" + table + r"\b", clean):
                if u.start() != m.start(1):
                    first = u.start()
                    break
            if first is not None and first < at:
                out.append("%s -> %s used at module line %d, declared at %d"
                           % (name, table, clean[:first].count("\n") + 1, clean[:at].count("\n") + 1))
    return out


def bare_helpers(path):
    out = []
    for name, body in modules(path):
        clean = strip(body)
        for h in HELPERS:
            if not re.search(r"(?<![\w.:])" + h + r"\s*\(", clean):
                continue
            if not re.search(r"local[^\n]*\b" + h + r"\b[^\n]*=", clean):
                out.append(name + " -> " + h)
    return out


old, new = sys.argv[1], sys.argv[2]
before, after = counts(old), counts(new)
print("old function/end/then/do:", before)
print("new function/end/then/do:", after)
print("delta:", tuple(y - x for x, y in zip(before, after)))
print("cross-module leaks:", leaks(new) or "none")
print("use before declaration:", use_before_decl(new) or "none")
print("bare helpers:", bare_helpers(new) or "none")
