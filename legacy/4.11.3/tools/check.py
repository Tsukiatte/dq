"""Pre-flight checker for the module sources. Run after every edit:

    python tools/check.py

Exits non-zero on failure. There is no Roblox here, so the first in-game run is
still the real test - but everything below is something that has actually shipped
broken at least once, and all of it is caught before the file leaves this machine.

  1. Real parse of every src/*.lua with an actual Lua interpreter (lupa). This
     replaces the old keyword/bracket balance heuristics and the dotted-key check:
     "{ HZ.learnedNames = x }", a missing `end`, a stray `=` - all parse errors.
  2. Free-name audit: every identifier a module uses must be a local, an import
     (`local x = S.x`), a known Roblox/Luau/executor global, or `S` itself. This is
     what catches a function referenced from a module that never imported it, or a
     bare variable that should have become RT.<name>. (This is the use-before-
     definition sweep, done properly with scopes.)
  3. Cross-module wiring: every `S.name` a module imports or reads is exported
     (`S.name = ...`) somewhere, and every `local x = S.x` import comes from a
     module EARLIER in the load order (a later module's export is still nil at
     import time).
  4. Register budget: top-level locals per module function (Luau caps at 200).
  5. Version consistency: SCRIPT_VERSION == first SCRIPT_CHANGELOG entry ==
     first CHANGELOG.md heading. The working agreement is "bump on every edit";
     a stale badge has cost several debugging rounds.

Requires: pip install lupa luaparser
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from modules import ROOT, SRC, ORDER  # noqa: E402
import luatools  # noqa: E402

REGISTER_WARN = 170


def main():
    failed = False
    sources = {}
    for name in ORDER:
        path = os.path.join(SRC, f"{name}.lua")
        if not os.path.exists(path):
            print(f"MISSING {path}")
            failed = True
            continue
        sources[name] = open(path, encoding="utf-8").read()

    # 1 + 2: parse and free names, per module
    exports, reads, imports = {}, {}, {}
    for name, src in sources.items():
        err = luatools.lua_parse_error(src, name)
        if err:
            print(f"PARSE ERROR in src/{name}.lua: {err}")
            failed = True
            continue
        free = luatools.free_names(src)
        bad = {k: v for k, v in free.items() if k not in luatools.KNOWN_GLOBALS}
        for sym, line in sorted(bad.items(), key=lambda kv: kv[1]):
            print(f"FREE NAME in src/{name}.lua line {line}: '{sym}' is neither local, imported, nor a known global")
            failed = True

        code = luatools.strip_strings_and_comments(src)
        exports[name] = set(re.findall(r"^\s*S\.([A-Za-z_]\w*)\s*=[^=]", code, re.M))
        reads[name] = set(re.findall(r"(?<![\w.:])S\.([A-Za-z_]\w*)", code))
        imports[name] = set(re.findall(r"^local ([A-Za-z_]\w*) = S\.\1\s*$", code, re.M))

        # 4: register budget. Top-level = one indent level inside `return function(S)`;
        # the module bodies are written unindented, so count column-0 locals.
        decl_re = re.compile(r"^local\s+(?:function\s+)?([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)", re.M)
        count = sum(len(re.split(r"\s*,\s*", m.group(1))) for m in decl_re.finditer(code))
        flag = "  <-- approaching the 200-register cap" if count >= REGISTER_WARN else ""
        print(f"src/{name}.lua: parse OK, {count} top-level locals{flag}")

    # 3: cross-module wiring
    all_exports = {}
    for name in ORDER:
        for sym in exports.get(name, ()):
            all_exports.setdefault(sym, name)
    for name in ORDER:
        for sym in sorted(reads.get(name, ())):
            owner = all_exports.get(sym)
            if owner is None:
                print(f"WIRING in src/{name}.lua: S.{sym} is read but no module exports it")
                failed = True
            elif sym in imports.get(name, ()) and ORDER.index(owner) >= ORDER.index(name):
                print(f"WIRING in src/{name}.lua: imports S.{sym} at load time but it is exported by "
                      f"'{owner}', which loads {'later' if ORDER.index(owner) > ORDER.index(name) else 'in the same module'}; "
                      f"use S.{sym} at call time instead")
                failed = True

    # 5: version consistency
    core = sources.get("core", "")
    ver = re.search(r'^local SCRIPT_VERSION = "([^"]+)"', core, re.M)
    top = re.search(r'^local SCRIPT_CHANGELOG = \{\s*\n\s*\{ version = "([^"]+)"', core, re.M)
    changelog_path = os.path.join(ROOT, "CHANGELOG.md")
    md = open(changelog_path, encoding="utf-8").read() if os.path.exists(changelog_path) else ""
    md_top = re.search(r"^## (\d+\.\d+\.\d+)", md, re.M)
    v = ver.group(1) if ver else None
    print(f"version: SCRIPT_VERSION={v} changelog-table={top.group(1) if top else None} CHANGELOG.md={md_top.group(1) if md_top else None}")
    if not (ver and top and ver.group(1) == top.group(1)):
        print("VERSION: SCRIPT_VERSION and the first SCRIPT_CHANGELOG entry disagree")
        failed = True
    if md and not (md_top and ver and md_top.group(1) == ver.group(1)):
        print("VERSION: CHANGELOG.md top entry does not match SCRIPT_VERSION")
        failed = True

    print("RESULT:", "FAIL" if failed else "OK")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
