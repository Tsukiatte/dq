"""Smoke run: executes the built bundle (or the src modules in order) under a
stub Roblox environment, right through startAutofarm(). There is no physics and
nothing moves, but every module body runs, every import is dereferenced, the
whole control UI is built, the config loader runs, and the Heartbeat callbacks
are invoked a few times - so a nil import, a typo in a table field used at
startup, a missing `end`-level bug the parser cannot see, or an Enum spelled
wrong in UI construction shows up here instead of in-game.

    python tools/smoke.py

The stubs are permissive on purpose: any property read on a Roblox object
returns another stub, method calls return stubs, numbers come back where the
code expects numbers (Vector3 components, Magnitude, Health...). It does not
prove behaviour; it proves the code path does not throw on the way in.

Requires: pip install lupa
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from modules import ROOT, SRC, BUNDLE, ORDER  # noqa: E402

STUB_ENV = r"""
-- ---------------------------------------------------------------- Lua 5.4 gaps
math.clamp = math.clamp or function(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
table.clear = table.clear or function(t) for k in pairs(t) do t[k] = nil end end
table.find = table.find or function(t, v) for i, x in ipairs(t) do if x == v then return i end end return nil end
table.clone = table.clone or function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
if not unpack then unpack = table.unpack end

-- ---------------------------------------------------------------- vectors
local VectorMT = {}
VectorMT.__index = function(v, k)
    if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
    if k == "Unit" then local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z); if m == 0 then m = 1 end return Vector3.new(v.X / m, v.Y / m, v.Z / m) end
    if k == "Lerp" then return function(a, b, t) return Vector3.new(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t) end end
    if k == "Dot" then return function(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end end
    return rawget(v, k)
end
VectorMT.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
VectorMT.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
VectorMT.__mul = function(a, b)
    if type(a) == "number" then return Vector3.new(a * b.X, a * b.Y, a * b.Z) end
    if type(b) == "number" then return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
    return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
VectorMT.__div = function(a, b) return Vector3.new(a.X / b, a.Y / b, a.Z / b) end
VectorMT.__unm = function(a) return Vector3.new(-a.X, -a.Y, -a.Z) end
VectorMT.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
VectorMT.__tostring = function(v) return string.format("(%g, %g, %g)", v.X, v.Y, v.Z) end
Vector3 = { new = function(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, VectorMT) end }
Vector3.zero = Vector3.new(0, 0, 0)
Vector2 = { new = function(x, y) return setmetatable({ X = x or 0, Y = y or 0, Z = 0 }, VectorMT) end }

-- ---------------------------------------------------------------- generic stub
-- Every Roblox object the script touches that is not a vector/number. Indexing
-- gives a child stub (memoised per key), calling gives a stub, arithmetic gives
-- 0, comparisons never throw. Some properties return numbers/strings/booleans
-- because the script does arithmetic or string work on them.
local Stub
local NUMERIC = { Health = 100, MaxHealth = 100, HipHeight = 2, Transparency = 0, TextSize = 12,
    UserId = 1, Value = 2, LineThickness = 0.03, Radius = 1, Height = 1, Responsiveness = 40, MaxTorque = 1e6 }
local STRINGY = { Name = "Stub", Text = "", Image = "", ClassName = "Stub", DisplayName = "Stub" }
local BOOLY = { Anchored = true, CanCollide = true, CanQuery = true, Visible = true, Enabled = false,
    Parent = false, AutoRotate = true, RigidityEnabled = false, AlwaysOnTop = false }
local VECTORY = { Position = true, Size = true, LookVector = true, AbsoluteSize = true, AbsolutePosition = true,
    AssemblyLinearVelocity = true, AssemblyAngularVelocity = true, Delta = true, Normal = true }
local CALLERS = {
    IsA = function() return false end,
    IsDescendantOf = function() return false end,
    -- The character's parts exist so the main loop gets past "no character"
    -- and into the idle/path branch; everything else is absent.
    FindFirstChild = function(self, name) if CHARACTER_PARTS[name] then return self[name] end return nil end,
    FindFirstChildWhichIsA = function(self, class) if CHARACTER_PARTS[class] then return self[class] end return nil end,
    FindFirstChildOfClass = function(self, class) if CHARACTER_PARTS[class] then return self[class] end return nil end,
    FindFirstAncestorOfClass = function() return nil end,
    FindFirstAncestorWhichIsA = function() return nil end,
    GetChildren = function() return {} end,
    GetDescendants = function() return {} end,
    GetAttributes = function() return {} end,
    GetPlayers = function() return {} end,
    GetPlayerFromCharacter = function() return nil end,
    GetMouseLocation = function() return Vector2.new(0, 0) end,
    Raycast = function() return nil end,
    ComputeAsync = function() end,
    GetWaypoints = function() return {} end,
    JSONEncode = function(_, t) return "{}" end,
    JSONDecode = function() return {} end,
    GetDebugId = function() return "id" end,
    ToOrientation = function() return 0, 0, 0 end,
    Destroy = function() end,
    Disconnect = function() end,
    Connect = function(self, fn)
        SMOKE_CONNECTIONS[#SMOKE_CONNECTIONS + 1] = { name = rawget(self, "__name"), fn = fn }
        return Stub("Connection")
    end,
    Wait = function() return Stub("Character") end,
    WaitForChild = function(self, name) return Stub(name) end,
    MoveTo = function() end,
    SendKeyEvent = function() end,
    SendMouseButtonEvent = function() end,
    HttpGet = function() return "" end,
    SetAttribute = function() end,
    GetPivot = function() return Stub("CFrame") end,
    GetMouse = function() return Stub("Mouse") end,
    PointToObjectSpace = function() return Vector3.new() end,
    PointToWorldSpace = function() return Vector3.new() end,
    VectorToWorldSpace = function() return Vector3.new() end,
    Lerp = function() return Vector3.new() end,
}
SMOKE_CONNECTIONS = {}
CHARACTER_PARTS = { Humanoid = true, HumanoidRootPart = true, Animator = true, PlayerGui = true }
local StubMT = {}
StubMT.__index = function(self, key)
    if CALLERS[key] then return CALLERS[key] end
    if NUMERIC[key] then return NUMERIC[key] end
    if STRINGY[key] then return STRINGY[key] end
    if BOOLY[key] ~= nil then return BOOLY[key] end
    if VECTORY[key] then return Vector3.new(0, 3, 0) end
    local children = rawget(self, "__children")
    local child = children[key]
    if not child then child = Stub(key) children[key] = child end
    return child
end
StubMT.__newindex = function(self, key, value) rawget(self, "__set")[key] = value end
StubMT.__call = function() return Stub("call") end
StubMT.__add = function() return 0 end
StubMT.__sub = function() return 0 end
StubMT.__mul = function(a, b)
    -- CFrame * CFrame stays a CFrame so the free-fly camera maths keeps working.
    local an = type(a) == "table" and rawget(a, "__name")
    local bn = type(b) == "table" and rawget(b, "__name")
    if an == "CFrame" or bn == "CFrame" then return Stub("CFrame") end
    return 0
end
StubMT.__div = function() return 0 end
StubMT.__unm = function() return 0 end
StubMT.__len = function() return 0 end
StubMT.__lt = function() return false end
StubMT.__le = function() return true end
StubMT.__concat = function(a, b) return tostring(a) .. tostring(b) end
StubMT.__tostring = function(s) return "Stub<" .. rawget(s, "__name") .. ">" end
Stub = function(name)
    return setmetatable({ __name = name or "?", __children = {}, __set = {} }, StubMT)
end

-- ---------------------------------------------------------------- globals
game = Stub("game")
workspace = Stub("Workspace")
Instance = { new = function(class) local s = Stub(class) s.__set.ClassName = class return s end }
CFrame = setmetatable({}, { __index = function() return function() return Stub("CFrame") end end })
Color3 = setmetatable({}, { __index = function() return function() return Stub("Color3") end end })
UDim = { new = function() return Stub("UDim") end }
UDim2 = setmetatable({}, { __index = function() return function() return Stub("UDim2") end end })
Enum = setmetatable({}, { __index = function(_, k) return setmetatable({}, { __index = function(_, item) return { Name = item, Value = 2, EnumType = k } end }) end })
RaycastParams = { new = function() return Stub("RaycastParams") end }
task = { spawn = function(fn, ...) return fn(...) end, defer = function(fn, ...) return fn(...) end, delay = function() end, wait = function() end }
_G = _G or {}
debug = debug or {}
debug.traceback = debug.traceback or function(m) return m end
typeof = function(v) return type(v) end
getgenv = nil

-- Executor file API: report no access, exactly like an executor without it.
writefile, readfile, isfile = nil, nil, nil
getrawmetatable, setreadonly, newcclosure, getnamecallmethod = nil, nil, nil, nil
"""

RUNNER = r"""
local ok, err = xpcall(function()
    local chunk = assert(load(BUNDLE_SOURCE, "=DungeonAutofarm", "t"))
    chunk()
end, function(m) return debug.traceback(m, 2) end)
if not ok then return "STARTUP ERROR: " .. tostring(err) end

-- Drive every connected callback (Heartbeat loops, input handlers, index
-- events...) a few times. The argument is a stub: it serves as `dt`, as an
-- InputObject, as a descendant, as an animation track.
local fired = 0
local eventArg = Instance.new("SmokeEvent")
local function fire(entry, round)
    local cok, cerr = xpcall(entry.fn, function(m) return debug.traceback(m, 2) end, eventArg, false)
    fired = fired + 1
    if not cok then
        return "CALLBACK ERROR (" .. tostring(entry.name) .. ", round " .. round .. "): " .. tostring(cerr)
    end
end
-- Loops, index events, input handlers first, several rounds; button clicks
-- last and once (one of them is Destruct, and a click toggles every mode).
for round = 1, 3 do
    for _, entry in ipairs(SMOKE_CONNECTIONS) do
        if entry.name ~= "MouseButton1Click" then
            local err = fire(entry, round)
            if err then return err end
        end
    end
end
local clicks = 0
for _, entry in ipairs(SMOKE_CONNECTIONS) do
    if entry.name == "MouseButton1Click" then
        clicks = clicks + 1
        local err = fire(entry, "click")
        if err then return err end
    end
end
-- And one more pass of everything after the clicks (modes toggled, Destruct ran).
for _, entry in ipairs(SMOKE_CONNECTIONS) do
    if entry.name ~= "MouseButton1Click" then
        local err = fire(entry, "post-click")
        if err then return err end
    end
end
return "OK: startup ran, " .. #SMOKE_CONNECTIONS .. " connections (" .. clicks .. " buttons), " .. fired .. " callback invocations"
"""


def main():
    from lupa import LuaRuntime
    lua = LuaRuntime(unpack_returned_tuples=True)
    if os.path.exists(BUNDLE):
        source = open(BUNDLE, encoding="utf-8").read()
        print("running bundle", os.path.relpath(BUNDLE, ROOT))
    else:
        print("no bundle yet; concatenating src/ in load order")
        parts = ["local S = {}\n"]
        for name in ORDER:
            body = open(os.path.join(SRC, f"{name}.lua"), encoding="utf-8").read()
            parts.append("do local module = (function()\n" + body + "\nend)() module(S) end\n")
        source = "".join(parts)

    # print() from the script is noise here: swallow it but keep FATAL lines.
    lua.execute(STUB_ENV)
    lua.execute("""
        SMOKE_PRINTS = {}
        local realprint = print
        print = function(...)
            local parts = {}
            for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
            local line = table.concat(parts, ' ')
            SMOKE_PRINTS[#SMOKE_PRINTS + 1] = line
            if line:find('FATAL', 1, true) or line:find('Traceback', 1, true) then realprint(line) end
        end
    """)
    lua.globals()["BUNDLE_SOURCE"] = source
    result = lua.execute(RUNNER)
    prints = lua.globals()["SMOKE_PRINTS"]
    print(f"script printed {len(prints)} lines; first few:")
    for i in range(1, min(len(prints), 6) + 1):
        print("   ", prints[i][:110])
    print(result)
    return 0 if str(result).startswith("OK") else 1


if __name__ == "__main__":
    sys.exit(main())
