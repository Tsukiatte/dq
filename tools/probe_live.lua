-- probe_live.lua - Run through the Potassium bridge while the autofarm is up.
-- First call installs a hit recorder on the character; every call returns a
-- snapshot: what the reader currently classifies, the dodge and mover state,
-- and every recorded health drop with the attack-like parts near the character
-- at that instant. Attribution is the point: a death with no classified part
-- nearby is an attack the reader did not see.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local S = _G.DungeonAutofarmState
local lp = Players.LocalPlayer
local char = lp.Character
local root = char and char:FindFirstChild("HumanoidRootPart")
local hum = char and char:FindFirstChildOfClass("Humanoid")

local function r1(v) return math.floor(v * 10 + 0.5) / 10 end
local function v3(v) return { r1(v.X), r1(v.Y), r1(v.Z) } end

local ATTACKY = { hitbox = true, precast = true, precasthitbox = true }
local function attackLike(p)
    if not p:IsA("BasePart") then return false end
    if char and p:IsDescendantOf(char) then return false end
    local n = p.Name:lower()
    if ATTACKY[n] or n:find("precast") or n:find("hitbox") or n:find("strike") or n:find("spike")
        or n:find("beam") or n:find("orb") or n:find("shot") or n:find("neon") or n:find("freeze") then
        return true
    end
    local m = p:FindFirstAncestorOfClass("Model")
    if m and not m:FindFirstChildOfClass("Humanoid") and (m:FindFirstChild("hitBox") or m:FindFirstChild("hitbox")) then
        return true
    end
    return false
end

-- Parts within `radius` of the character that look like attacks, with the
-- reader's own verdict where the autofarm is loaded.
local function nearby(radius, limit)
    if not root then return {} end
    local out, pos = {}, root.Position
    for _, d in ipairs(workspace:GetDescendants()) do
        if attackLike(d) then
            local dist = (d.Position - pos).Magnitude
            if dist <= radius then
                local verdict = nil
                if S and S.isDamageBrick then
                    local ok, v = pcall(S.isDamageBrick, d)
                    verdict = ok and (v and "danger" or "ignored") or ("err:" .. tostring(v))
                end
                local m = d:FindFirstAncestorOfClass("Model")
                out[#out + 1] = {
                    name = d.Name, class = d.ClassName, model = m and m.Name or nil,
                    parent = d.Parent and d.Parent.Name or nil,
                    dist = r1(dist), size = v3(d.Size), t = r1(d.Transparency), pos = v3(d.Position),
                    verdict = verdict,
                }
                if #out >= (limit or 40) then break end
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end

-- Hit recorder: one per character, survives re-runs of this probe.
_G.DQHits = _G.DQHits or { log = {}, installedFor = nil }
if hum and _G.DQHits.installedFor ~= char then
    _G.DQHits.installedFor = char
    local last = hum.Health
    hum.HealthChanged:Connect(function(h)
        if h < last - 1 then
            local entry = {
                t = os.clock(), serverT = workspace:GetServerTimeNow(),
                lost = math.floor(last - h), health = math.floor(h),
                pos = root and v3(root.Position) or nil,
                nearby = nearby(45, 12),
                dodge = S and S.DG and { active = S.DG.active, target = S.DG.target and v3(S.DG.target) or nil } or nil,
            }
            table.insert(_G.DQHits.log, entry)
            if #_G.DQHits.log > 40 then table.remove(_G.DQHits.log, 1) end
        end
        last = h
    end)
end

local snap = {
    loaded = S ~= nil, version = _G.DungeonAutofarmVersion,
    dungeon = workspace:FindFirstChild("dungeonName") and workspace.dungeonName.Value or nil,
    health = hum and math.floor(hum.Health) or nil,
    pos = root and v3(root.Position) or nil,
    nearby = nearby(60, 30),
    hits = _G.DQHits.log,
}
if S then
    snap.dodge = S.DG and { active = S.DG.active, target = S.DG.target and v3(S.DG.target) or nil,
        gapWait = S.DG.gapWait, hubHold = S.DG.hubHold, pursuitBlocked = S.DG.pursuitBlocked } or nil
    snap.hazards = S.HZ and { detected = S.HZ.detected and #S.HZ.detected or nil,
        arming = S.HZ.arming and (function() local n = 0 for _ in pairs(S.HZ.arming) do n = n + 1 end return n end)() or nil } or nil
    snap.precastZones = S.PC and S.PC.zones and #S.PC.zones or nil
    -- The reader's own attribution of the last hits, to compare with ours.
    if S.HZ and S.HZ.hitLog then
        local hl, n = {}, #S.HZ.hitLog
        for i = math.max(1, n - 9), n do hl[#hl + 1] = S.HZ.hitLog[i] end
        snap.readerHitLog, snap.readerLastHit = hl, S.HZ.lastHitName
    end
    snap.nav = S.NAV and { driving = S.NAV.driving, recovery = S.NAV.recovery ~= nil,
        enemy = S.NAV.cachedEnemy and S.NAV.cachedEnemy.Name or nil } or nil
    snap.moveMode = S.CFG and S.CFG.moveMode or nil
end
return HttpService:JSONEncode(snap)
