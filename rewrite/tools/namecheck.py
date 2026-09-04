# namecheck.py - every identifier that is read but never declared anywhere in the file.
#
# Written after 6.6.91, where a patch called floorY(x, oy, z, params) with a variable that did not exist. Luau is
# happy to read a nil global, so it compiled, loaded and then threw on the first candidate of every tick: the field
# stage died sixty times a second and nothing dodged at all.
#
# This is not scope-aware - a name declared in one function and used in another will not be caught - but it catches
# the typo and the invented variable, which is the failure that actually happens when patching by text.
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "DungeonAutofarm.lua"
src = open(path, encoding="utf-8").read()

code = re.sub(r"--\[(=*)\[.*?\]\1\]", " ", src, flags=re.S)
code = re.sub(r"\[(=*)\[.*?\]\1\]", '""', code, flags=re.S)
code = re.sub(r"--[^\n]*", " ", code)
code = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', code)
code = re.sub(r"'(?:[^'\\\n]|\\.)*'", "''", code)

declared = set()
# local a, b, c = ...   /   local function f(...)   /   function M.f(a, b)
for m in re.finditer(r"\blocal\s+function\s+([A-Za-z_]\w*)", code):
    declared.add(m.group(1))
for m in re.finditer(r"\blocal\s+([A-Za-z_][\w\s,]*?)\s*(?:=|\n)", code):
    for n in m.group(1).split(","):
        n = n.strip()
        if re.fullmatch(r"[A-Za-z_]\w*", n):
            declared.add(n)
for m in re.finditer(r"\bfunction\s*[A-Za-z_][\w.:]*\s*\(([^)]*)\)|\bfunction\s*\(([^)]*)\)", code):
    for n in (m.group(1) or m.group(2) or "").split(","):
        n = n.strip().lstrip(".")
        if re.fullmatch(r"[A-Za-z_]\w*", n):
            declared.add(n)
for m in re.finditer(r"\bfor\s+([A-Za-z_][\w\s,]*?)\s+(?:=|in)\b", code):
    for n in m.group(1).split(","):
        n = n.strip()
        if re.fullmatch(r"[A-Za-z_]\w*", n):
            declared.add(n)

KEYWORDS = set("""and break do else elseif end false for function if in local nil not or repeat return then true until
while continue export type""".split())
GLOBALS = set("""game workspace script math table string os task pcall xpcall ipairs pairs next select type tostring
tonumber setmetatable getmetatable rawget rawset rawequal rawlen unpack error assert print warn require Instance
Vector3 Vector2 CFrame Color3 UDim UDim2 Enum Ray Region3 TweenInfo NumberRange NumberSequence ColorSequence
NumberSequenceKeypoint ColorSequenceKeypoint BrickColor Random Font Rect PhysicalProperties DateTime buffer bit32
utf8 coroutine debug delay spawn wait tick time typeof newproxy loadstring readfile writefile isfile listfiles
appendfile delfile makefolder isfolder getgenv gethui setclipboard identifyexecutor firetouchinterest
getconnections hookfunction hookmetamethod checkcaller islclosure getrawmetatable setreadonly cloneref
getcustomasset queue_on_teleport syn shared _G""".split())

used = {}
# Read positions only: not a table key or an assignment target (name followed by a single =), and not a field
# after a dot or colon. Lowercase-initial only, which is every local this codebase writes; Roblox's own properties
# and enum members are PascalCase and would otherwise drown the signal.
for m in re.finditer(r"(?<![\w.:])([a-z_]\w*)", code):
    n = m.group(1)
    rest = code[m.end():m.end() + 3]
    if re.match(r"\s*=[^=]", rest):
        continue
    used[n] = used.get(n, 0) + 1

unknown = sorted(n for n in used if n not in declared and n not in KEYWORDS and n not in GLOBALS and not n.startswith("_"))
real = [n for n in unknown if used[n] > 0]
counts = used

print("declared names: %d | suspicious: %d" % (len(declared), len(real)))
for n in real[:40]:
    print("   %-24s used %d time(s)" % (n, counts[n]))
sys.exit(1 if real else 0)
