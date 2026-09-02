-- hazards.lua - Telegraph classification, hazard geometry, overlays, telegraph feed, catalog filter, picker.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local RT = S.RT
local LocalPlayer = S.LocalPlayer
local HZ = S.HZ
local LD = S.LD
local heavyDebugThrottled = S.heavyDebugThrottled
local CFG = S.CFG
local NAV = S.NAV
local Players = S.Players
local UI = S.UI
local heavyDebug = S.heavyDebug
local Workspace = S.Workspace
local getVisualRoot = S.getVisualRoot
local ZN = S.ZN
local PC = S.PC
local isKnownEnemyAttack = S.isKnownEnemyAttack
local isKnownOwnEffect = S.isKnownOwnEffect
local isSafeZoneMarker = S.isSafeZoneMarker

-- Realistic Player Hitbox
local function getPlayerHitboxMetrics()
    local character = LocalPlayer.Character
    if not character then
        return Vector3.new(2, 5, 2), 1.25, 5.0, Vector3.zero
    end

    local hrp = character:FindFirstChild("HumanoidRootPart")
    local size = hrp and hrp.Size or Vector3.new(2, 5, 2)
    local radius = math.max(size.X, size.Z) * 0.6
    local totalHeight = size.Y + 0.5

    return size, radius, totalHeight, Vector3.zero
end

local function clearHitboxVisualizer()
    if HZ.hitboxFolder then
        HZ.hitboxFolder:Destroy()
        HZ.hitboxFolder = nil
    end
end

-- Player-adorned visuals: the hitbox outline and (2.2.0) the ability radius
-- sphere. Both are adornments on the root, so they cost nothing per frame; this
-- only runs on its own 0.25s clock. The adornee is re-pointed every refresh
-- because a respawn replaces the root and a stale adornee simply vanishes.
local function updateHitboxVisualizer()
    local wantHitbox = RT.renderHitboxEnabled and RT.farmEnabled
    local wantRadius = CFG.showAbilityRadius

    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root or (not wantHitbox and not wantRadius) then
        clearHitboxVisualizer()
        return
    end

    if not HZ.hitboxFolder or not HZ.hitboxFolder.Parent then
        HZ.hitboxFolder = Instance.new("Folder")
        HZ.hitboxFolder.Name = "PlayerAdornments"
        HZ.hitboxFolder.Parent = getVisualRoot()
    end
    local folder = HZ.hitboxFolder

    local cylAdorn = folder:FindFirstChild("HitboxPlanarCylinder")
    local boxAdorn = folder:FindFirstChild("HitboxSolidBox")
    if wantHitbox then
        local size, radius, totalHeight = getPlayerHitboxMetrics()
        if not cylAdorn then
            cylAdorn = Instance.new("CylinderHandleAdornment")
            cylAdorn.Name = "HitboxPlanarCylinder"
            cylAdorn.Color3 = CFG.colorHitbox
            cylAdorn.Transparency = 0.65
            cylAdorn.ZIndex = 3
            cylAdorn.AlwaysOnTop = true
            cylAdorn.CFrame = CFrame.Angles(math.rad(90), 0, 0)
            cylAdorn.Parent = folder
        end
        if cylAdorn.Adornee ~= root then cylAdorn.Adornee = root end
        if cylAdorn.Height ~= totalHeight then cylAdorn.Height = totalHeight end
        if cylAdorn.Radius ~= radius then cylAdorn.Radius = radius end

        if not boxAdorn then
            boxAdorn = Instance.new("SelectionBox")
            boxAdorn.Name = "HitboxSolidBox"
            boxAdorn.Color3 = CFG.colorHitbox
            boxAdorn.LineThickness = 0.03
            boxAdorn.SurfaceColor3 = CFG.colorHitbox
            boxAdorn.SurfaceTransparency = 0.8
            boxAdorn.Parent = folder
        end
        if boxAdorn.Adornee ~= root then boxAdorn.Adornee = root end
    else
        if cylAdorn then cylAdorn:Destroy() end
        if boxAdorn then boxAdorn:Destroy() end
    end

    local sphere = folder:FindFirstChild("AbilityRadius")
    if wantRadius then
        if not sphere then
            sphere = Instance.new("SphereHandleAdornment")
            sphere.Name = "AbilityRadius"
            sphere.Color3 = CFG.colorAbilityRadius
            sphere.Transparency = 0.82
            sphere.ZIndex = 1
            sphere.AlwaysOnTop = false
            sphere.Parent = folder
        end
        if sphere.Adornee ~= root then sphere.Adornee = root end
        if sphere.Radius ~= CFG.abilityRadius then sphere.Radius = CFG.abilityRadius end
    elseif sphere then
        sphere:Destroy()
    end
end

-- Memo tables for the three classifiers that dominated the per-frame cost.
-- Answers are stable for a given instance; the whole cache is dropped every
-- CFG.classificationCacheLifetime seconds so late-attached ownership still lands.
local ownershipCache = {}
local mapGeometryCache = {}
local partShapeCache = {}
-- Invisible-wall answers are stable per part, but the overlay tests every part on
-- the map, so the result is memoised like the rest and dropped on the flush.
local invisWallCache = {}
-- Attack-book matches are stable per part; cleared here and whenever the book changes.
local attackMatchCache = {}
RT.lastCacheFlushTime = os.clock()

local function flushClassificationCaches()
    table.clear(ownershipCache)
    table.clear(mapGeometryCache)
    table.clear(partShapeCache)
    table.clear(invisWallCache)
    table.clear(attackMatchCache)
    RT.lastCacheFlushTime = os.clock()

    -- Benched enemies that died or despawned would otherwise sit in the table
    -- forever, since the expiry is only checked when the scanner sees them again.
    local now = RT.lastCacheFlushTime
    for part, stamp in pairs(HZ.seenAt) do
        if not part.Parent or (now - stamp) > (CFG.telegraphRecentSpawnWindow * 3) then
            HZ.seenAt[part] = nil
        end
    end

    for model, expiry in pairs(NAV.benched) do
        if not model.Parent or now >= expiry then
            NAV.benched[model] = nil
        end
    end
end

local function computeOwnedByPlayerOrTeammate(instance)
    if not instance then return false end
    local character = LocalPlayer.Character

    if character and instance:IsDescendantOf(character) then
        return true
    end

    -- Both of these were being redone once per player. They do not depend on the
    -- player, so they are computed once: GetAttributes in particular allocates a
    -- fresh table on every call.
    local creator = instance:FindFirstChild("Creator")
        or instance:FindFirstChild("creator")
        or instance:FindFirstChild("Owner")
        or instance:FindFirstChild("Player")
        or instance:FindFirstChild("Caster")

    local ownershipAttributes = nil
    for attr, val in pairs(instance:GetAttributes()) do
        local lowered = attr:lower()
        if lowered:find("creator") or lowered:find("owner") or lowered:find("player") or lowered:find("caster") then
            ownershipAttributes = ownershipAttributes or {}
            table.insert(ownershipAttributes, val)
        end
    end

    for _, player in ipairs(Players:GetPlayers()) do
        local pChar = player.Character
        if pChar and instance:IsDescendantOf(pChar) then
            return true
        end

        if creator and (creator.Value == player or creator.Value == pChar or creator.Value == player.Name or creator.Value == player.UserId) then
            return true
        end

        if ownershipAttributes then
            for _, val in ipairs(ownershipAttributes) do
                if val == player.Name or val == player.UserId or (character and val == character.Name) then
                    return true
                end
            end
        end
    end

    if instance.Parent and instance.Parent ~= Workspace then
        return computeOwnedByPlayerOrTeammate(instance.Parent)
    end

    return false
end

local function isOwnedByPlayerOrTeammate(instance)
    if not instance then return false end
    local cached = ownershipCache[instance]
    if cached ~= nil then return cached end
    local result = computeOwnedByPlayerOrTeammate(instance)
    ownershipCache[instance] = result
    return result
end

-- "effects", "props", "lighting" and "decorations" were removed. This veto only
-- ever runs on non-collidable parts, and an Effects folder is precisely where a
-- game puts its attack telegraphs, so those entries were rejecting the very
-- thing the scan is looking for.
local mapFolderNames = {
    "map", "rooms", "room", "geometry", "terrain", "dungeonmap",
    "environment", "structures", "spawns", "doors", "walls", "floors",
    "arena", "gate", "door"
}

local function isMapGeometry(part)
    local cached = mapGeometryCache[part]
    if cached ~= nil then return cached end

    local result = false
    local cur = part
    while cur and cur ~= Workspace do
        local lowerName = string.lower(cur.Name)
        for _, name in ipairs(mapFolderNames) do
            if string.find(lowerName, name, 1, true) then
                result = true
                break
            end
        end
        if result then break end
        cur = cur.Parent
    end

    mapGeometryCache[part] = result
    return result
end

local nonDamagingKeywords = {
    "entry", "intro", "cutscene", "cinematic", "spawn", "trigger",
    "door", "gate", "transition", "portal", "barrier", "camera", "boundary",
    "blade", "staff", "sword", "weapon", "bow", "wand", "hammer", "axe"
}

-- Names that identify a telegraph on their own, whatever contains them.
local strongTelegraphNames = {
    "telegraph", "precast", "aoe", "indicator", "warning",
    "dangerzone", "damagezone", "attackzone", "hitzone"
}

-- Names that only count as a telegraph inside an enemy attack container.
local weakTelegraphNames = {
    "hitbox", "hitpart", "damage", "circle", "ring", "zone", "shockwave"
}

local function matchesAny(name, list)
    for _, word in ipairs(list) do
        if string.find(name, word, 1, true) then
            return true
        end
    end
    return false
end

-- Shape classification never changes for a part, but this used to run a pcall
-- and two string searches on every hazard, three times per frame.
local SHAPE_BOX, SHAPE_CYLINDER, SHAPE_SPHERE = 0, 1, 2

local function classifyPartShape(part)
    local cached = partShapeCache[part]
    if cached ~= nil then return cached end

    local isCylinder = false
    local isSphere = false

    if part:IsA("Part") then
        local success, shape = pcall(function() return part.Shape end)
        if success then
            isCylinder = (shape == Enum.PartType.Cylinder)
            isSphere = (shape == Enum.PartType.Ball)
        end
    end

    local partNameLower = part.Name:lower()
    if not isCylinder then
        isCylinder = part:IsA("CylinderHandleAdornment") or (partNameLower:find("cylinder") ~= nil) or (partNameLower:find("ring") ~= nil)
    end
    if not isSphere then
        isSphere = (partNameLower:find("sphere") ~= nil) or (partNameLower:find("ball") ~= nil)
    end

    local result = isCylinder and SHAPE_CYLINDER or (isSphere and SHAPE_SPHERE or SHAPE_BOX)
    partShapeCache[part] = result
    return result
end

-- Reds, oranges and yellows: the near-universal telegraph palette.
local function isWarningColor(color)
    return color.R >= 0.45
        and (color.R - color.B) >= 0.12
        and color.R >= (color.G - 0.10)
end

-- Name matching alone cannot catch a telegraph the game called "Part" or gave
-- some internal id. This scores appearance instead, which is far more stable
-- across games than naming: telegraphs are anchored, non-collidable, flat on the
-- floor or cylindrical, usually translucent, usually warm-coloured or glowing,
-- and they appear moments before the attack lands.
local function looksLikeTelegraph(part, now)
    if not part.Anchored then return false end

    local size = part.Size
    local footprint = math.max(size.X, size.Z)

    -- Rule out dust motes and whole-room slabs alike.
    if footprint < 3 or footprint > 160 then return false end

    local shapeKind = classifyPartShape(part)
    local isFlat = size.Y <= 2.5 and footprint >= 3
    local isDisc = shapeKind == SHAPE_CYLINDER and footprint >= 3
    if not isFlat and not isDisc then return false end

    local signals = 0

    if part.Transparency > 0.05 and part.Transparency < CFG.telegraphTransparencyCutoff then
        signals = signals + 1
    end

    if isWarningColor(part.Color) then
        signals = signals + 1
    end

    local material = part.Material
    if material == Enum.Material.Neon or material == Enum.Material.ForceField then
        signals = signals + 1
    end

    -- Appeared in the last few seconds. The strongest signal available: map
    -- decoration is present from the start, an attack marker is not.
    local seenAt = HZ.seenAt[part]
    if seenAt and (now - seenAt) <= CFG.telegraphRecentSpawnWindow then
        signals = signals + 2
    end

    return signals >= 3
end

-- =========================================================================
-- ATTACK BOOK + MOTION (2.3.0)
--
-- The attack book is evidence-based detection: a record is only written when
-- we actually took damage with that kind of part next to us (see
-- the picker and the drawn zones). Each record is a plain-data signature of
-- the part - name, parent name, class, material, shape, colour, size - plus a
-- display name, hit count and an enabled flag, so it can be saved as JSON and
-- shown in a panel. A part matches a record by name when the name is specific,
-- or by look when the name is generic ("Part").
--
-- Motion: parts that appeared recently, and every detected hazard, have their
-- velocity tracked. A hazard that is moving is a projectile for dodging
-- purposes: it is treated as occupying the strip it will sweep over the next
-- CFG.projectileLookahead seconds (hazardClosestPoint, below closestPointOnPart).
-- =========================================================================

-- Names that say nothing about what a part is; never learned or matched by name.
local GENERIC_PART_NAMES = {
    part = true, meshpart = true, union = true, unionoperation = true, handle = true,
    wedge = true, wedgepart = true, cylinder = true, ball = true, block = true, [""] = true,
    model = true, folder = true, workspace = true, effects = true, effect = true, fx = true,
}
local SHAPE_NAMES = { [SHAPE_BOX] = "box", [SHAPE_CYLINDER] = "disc", [SHAPE_SPHERE] = "ball" }

local function isGenericName(lname)
    return GENERIC_PART_NAMES[lname] == true
end

local function partSignature(part)
    local color = part.Color
    local size = part.Size
    local parent = part.Parent
    return {
        partName = string.lower(part.Name),
        parentName = (parent and parent ~= Workspace) and string.lower(parent.Name) or "",
        className = part.ClassName,
        material = part.Material.Name,
        shape = classifyPartShape(part),
        anchored = part.Anchored,
        r = color.R, g = color.G, b = color.B,
        sx = size.X, sy = size.Y, sz = size.Z,
    }
end

local function sizeClose(a, b)
    local tolerance = CFG.attackSizeTolerance
    local function close(x, y)
        return math.abs(x - y) / math.max(x, y, 0.5) <= tolerance
    end
    return close(a.sx, b.sx) and close(a.sy, b.sy) and close(a.sz, b.sz)
end

local function matchesAttackRecord(sig, record)
    if not isGenericName(record.partName) then
        if sig.partName ~= record.partName then return false end
        -- A specific name under a specific parent: both must match, so "Slam"
        -- under "FireBoss" is not confused with "Slam" under something else.
        if not isGenericName(record.parentName) and sig.parentName ~= record.parentName then
            return false
        end
        return true
    end
    -- Generic name: match by look.
    if sig.material ~= record.material or sig.shape ~= record.shape or sig.anchored ~= record.anchored then
        return false
    end
    local dr, dg, db = sig.r - record.r, sig.g - record.g, sig.b - record.b
    if math.sqrt(dr * dr + dg * dg + db * db) > CFG.attackColorTolerance then return false end
    return sizeClose(sig, record)
end

local function findAttackRecord(part)
    local cached = attackMatchCache[part]
    if cached ~= nil then return cached or nil end
    local found = false
    if #HZ.attackBook > 0 then
        local sig = partSignature(part)
        for _, record in ipairs(HZ.attackBook) do
            if matchesAttackRecord(sig, record) then
                found = record
                break
            end
        end
    end
    attackMatchCache[part] = found
    return found or nil
end

local function invalidateAttackBook()
    table.clear(attackMatchCache)
    if S.refreshAttackBookPanel then S.refreshAttackBookPanel() end
end

local function describeRecord(record)
    return string.format("%s %s %.0fx%.0fx%.0f", record.material,
        SHAPE_NAMES[record.shape] or "box", record.sx, record.sy, record.sz)
end

-- Velocity tracking. Smoothed half/half so one frame of teleport (a projectile
-- being positioned at its spawn point) does not read as speed.
local function updateMotion(part, now)
    local record = HZ.motion[part]
    local position = part.Position
    if not record then
        HZ.motion[part] = { position = position, time = now, velocity = Vector3.zero, moving = false }
        return
    end
    local dt = now - record.time
    if dt < 0.03 then return end
    local instant = (position - record.position) / dt
    local velocity = record.velocity * 0.5 + instant * 0.5
    record.position = position
    record.time = now
    record.velocity = velocity
    record.moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude >= CFG.projectileMinSpeed
end

-- The flat velocity of a hazard that is moving, or nil.
local function getHazardMotion(part)
    local record = HZ.motion[part]
    if record and record.moving then return record.velocity end
    return nil
end

-- A small thing that appeared moments ago and is moving fast is a projectile,
-- whatever it is called and however it is anchored.
local function looksLikeProjectile(part, now)
    local addedAt = HZ.recentParts[part]
    if not addedAt or now - addedAt > CFG.projectileTrackWindow then return false end
    if not getHazardMotion(part) then return false end
    local size = part.Size
    local longest = math.max(size.X, size.Y, size.Z)
    return longest >= 0.5 and longest <= CFG.projectileMaxSize
end

local function isDamageBrick(part)
    if not part:IsA("BasePart") then return false end

    -- Everything this script draws lives under one folder; one ancestor test
    -- replaces the six per-folder tests this used to run on every part.
    local visualRoot = RT.visualRoot
    if visualRoot and part:IsDescendantOf(visualRoot) then return false end
    if part.Name == "Terrain" or part.Name == "Baseplate" then return false end

    -- A fully faded telegraph has already resolved. Checked ahead of every other
    -- rule, manual picks included, so a marked part stops counting once it fades.
    if part.Transparency >= CFG.telegraphTransparencyCutoff then return false end

    -- A hand-drawn zone IS the hazard: it exists only because someone said so.
    if part:GetAttribute("DQZone") then return true end

    -- A hand-picked telegraph outranks everything, including a name that was
    -- learned as our own effect (the pick unlearns it, but be explicit here).
    if HZ.manualParts[part] then return true end

    -- Our own attacks (2.2.0). Recognised at spawn by timing against our own
    -- casts, or by a name learned that way / picked by hand. They used to sail
    -- through the appearance test - a fresh, glowing, warm-coloured disc at our
    -- feet is exactly what a telegraph looks like - and the bot dodged its own
    -- slashes.
    if HZ.ownParts[part] then return false end
    local partName = string.lower(part.Name)
    if HZ.ownNames[partName] then return false end

    -- The game's own answer, ahead of every heuristic below (3.0.0). It keeps
    -- its attack visuals in ReplicatedStorage.enemyProjectiles and ours in
    -- .projectiles / .abilities, so "is this mine or theirs" is a lookup, not
    -- a guess. See game/GAME_NOTES.md.
    if isKnownOwnEffect(part) then return false end
    -- Workspace.vfxPool holds the player's own hit effects (Ability Attack Hit,
    -- Melee Attack V1..V3), pooled and reused. Their parts carry generic names
    -- like "Part", so nothing else would catch them, and the bot was fleeing
    -- from its own ability the moment it landed.
    if RT.vfxPool and part:IsDescendantOf(RT.vfxPool) then return false end
    -- A safe-spot marker is the opposite of a hazard: it is where you must
    -- stand. Treating it as damage would drive the bot out of the one survivable
    -- circle on the floor.
    if isSafeZoneMarker(part) then return false end
    if isKnownEnemyAttack(part) then return true end

    if isOwnedByPlayerOrTeammate(part) then return false end

    -- The attack book (2.3.0): evidence that this kind of part hurt us. It
    -- outranks the creature-part veto below because a record learned from a
    -- part inside a creature is exactly a swing hitbox - but those records are
    -- OFF by default when picked from inside a creature model.
    local record = findAttackRecord(part)
    if record then
        return record.enabled ~= false
    end

    local ancestorModel = part:FindFirstAncestorOfClass("Model")
    if ancestorModel and ancestorModel:FindFirstChildOfClass("Humanoid") then
        return false
    end

    -- Learned names outrank the heuristics below, including the CanCollide and
    -- map-geometry filters that were causing the missed hitboxes.
    if HZ.learnedNames[partName] then return true end

    local now = os.clock()

    -- Projectiles (2.3.0) are often collidable, unanchored, or both, so they are
    -- tested before the anchored/non-collidable telegraph rules.
    if looksLikeProjectile(part, now) then return true end

    if part.CanCollide then return false end

    local telegraphShaped = looksLikeTelegraph(part, now)

    -- Map geometry only vetoes parts that do not look like an attack marker.
    if not telegraphShaped and isMapGeometry(part) then return false end

    local parent = part.Parent
    if not parent then return false end

    -- A part parented straight to Workspace used to be rejected outright, on
    -- the theory that real attacks live inside a model. This game does the
    -- opposite: PrecastHitbox does `Part.Parent = workspace` literally, and so
    -- do the boss beams. That one line was vetoing precisely the things most
    -- worth seeing. Loose parts now fall through to the appearance test, which
    -- is what it was there to approximate in the first place.
    if parent == Workspace then return telegraphShaped end

    local parentName = string.lower(parent.Name)

    for _, word in ipairs(nonDamagingKeywords) do
        if string.find(parentName, word, 1, true) or string.find(partName, word, 1, true) then
            return false
        end
    end

    -- Strong names stand alone. Weak names need an enemy attack container.
    if matchesAny(partName, strongTelegraphNames) then
        return true
    end

    -- Falls through to appearance when the name says nothing useful.
    if not matchesAny(partName, weakTelegraphNames) then
        return telegraphShaped
    end

    local isEnemyAttackContainer = string.find(parentName, "^npc")
        or string.find(parentName, "^boss")
        or string.find(parentName, "^mob")
        or string.find(parentName, "^enemy")
        or string.find(parentName, "flameshot", 1, true)
        or string.find(parentName, "middlefire", 1, true)
        or string.find(parentName, "strike", 1, true)
        or string.find(parentName, "slam", 1, true)
        or string.find(parentName, "cleave", 1, true)
        or string.find(parentName, "blast", 1, true)
        or string.find(parentName, "spin", 1, true)
        or string.find(parentName, "fire", 1, true)

    if isEnemyAttackContainer then
        return true
    end

    return false
end


local function closestPointOnPart(part, worldPosition)
    local localPos = part.CFrame:PointToObjectSpace(worldPosition)
    local size = part.Size
    local halfSize = size * 0.5
    local clampedLocal = localPos

    local shapeKind = classifyPartShape(part)
    local isCylinder = shapeKind == SHAPE_CYLINDER
    local isSphere = shapeKind == SHAPE_SPHERE

    if isCylinder then
        local halfLength = halfSize.X
        local radius = math.min(halfSize.Y, halfSize.Z)
        local clampedX = math.clamp(localPos.X, -halfLength, halfLength)
        local yzVec = Vector2.new(localPos.Y, localPos.Z)
        local yzDist = yzVec.Magnitude

        if yzDist > radius then
            local norm = yzVec.Unit * radius
            clampedLocal = Vector3.new(clampedX, norm.X, norm.Y)
        else
            clampedLocal = Vector3.new(clampedX, localPos.Y, localPos.Z)
        end
    elseif isSphere then
        local radius = math.min(halfSize.X, halfSize.Y, halfSize.Z)
        if localPos.Magnitude > radius then
            clampedLocal = localPos.Unit * radius
        else
            clampedLocal = localPos
        end
    else
        clampedLocal = Vector3.new(
            math.clamp(localPos.X, -halfSize.X, halfSize.X),
            math.clamp(localPos.Y, -halfSize.Y, halfSize.Y),
            math.clamp(localPos.Z, -halfSize.Z, halfSize.Z)
        )
    end

    return part.CFrame:PointToWorldSpace(clampedLocal)
end

-- The closest point of a hazard to `position`, including where it is GOING:
-- for a moving hazard the point is taken along the strip it will sweep over
-- the next CFG.projectileLookahead seconds. Everything that decides "am I in
-- danger here" goes through this, so a projectile heading at the character
-- reads as a hazard before it arrives, and stepping sideways out of its line
-- reads as safe even while it is still close.
local function hazardClosestPoint(part, position)
    local closest = closestPointOnPart(part, position)
    local velocity = getHazardMotion(part)
    if not velocity then return closest end
    local sweep = Vector3.new(velocity.X, 0, velocity.Z) * CFG.projectileLookahead
    local lengthSq = sweep:Dot(sweep)
    if lengthSq < 0.01 then return closest end
    local toPoint = Vector3.new(position.X - closest.X, 0, position.Z - closest.Z)
    local t = math.clamp(toPoint:Dot(sweep) / lengthSq, 0, 1)
    return closest + sweep * t
end

-- `atTime` (3.0.0) asks the question in the future: "would this spot be safe
-- when I actually get there?" Physical hazards are judged as they are now;
-- announced ground attacks are judged against their real impact time, which
-- the game tells us. That is what lets the bot cross a marker that fires in a
-- second and a half to reach real safety, instead of treating every marker as
-- a wall and getting cornered by the third one.
--
-- `exactClearance` (3.0.2) replaces the computed distance outright. The Legacy
-- escape wants CFG.damageBrickClearance on top of the body, because it commits
-- to one dash and a fat hedge is cheap insurance. The clone grid wants the
-- honest question - would my body overlap this - because 3.5 studs of hedge on
-- every attack stacks, and three overlapping attacks then leave nowhere green
-- to stand at all.
-- Defined with the volume builder further down; declared here because the
-- two safety tests below are what use it.
local volumeClosestPoint

local function isPositionSafeFromDamageBricks(position, extraClearance, atTime, exactClearance, dwell)
    local _, playerRadius, totalHeight = getPlayerHitboxMetrics()
    local clearance = exactClearance
        or (CFG.damageBrickClearance + playerRadius + (extraClearance or 0))
    local halfHeight = (totalHeight * 0.5) + 2.0

    if CFG.usePrecast and #PC.zones > 0 then
        if not S.isPositionSafeFromPrecast(position, clearance, atTime, dwell) then
            return false
        end
    end

    for _, volume in ipairs(HZ.volumes) do
        if not volume.part or volume.part.Parent then
            local closest = volumeClosestPoint(volume, position)
            local horizontalDist = Vector2.new(position.X - closest.X, position.Z - closest.Z).Magnitude
            local verticalBlocked = CFG.hazardIgnoreVertical or math.abs(position.Y - closest.Y) < halfHeight

            if horizontalDist < clearance and verticalBlocked then
                return false
            end
        end
    end
    return true
end

-- Live safe-spot markers, refreshed with the catalog. Several bosses spawn a
-- circle you must stand IN; for those the whole polarity of the dodge flips,
-- and a grid that only avoids red would calmly walk you out of the one place
-- that survives.
local function collectSafeZones()
    table.clear(HZ.safeZones)
    if not CFG.safeZoneEnabled then return end
    for _, part in ipairs(HZ.partPool) do
        if part.Parent and isSafeZoneMarker(part) then
            HZ.safeZones[#HZ.safeZones + 1] = part
        end
    end
end

-- 0 when there is no safe zone on the floor, or when `pos` is inside one;
-- CFG.safeZonePull when a zone exists and this spot is outside every one.
local function safeZonePenalty(pos)
    local zones = HZ.safeZones
    if #zones == 0 then return 0 end
    for _, part in ipairs(zones) do
        if part.Parent then
            local size = part.Size
            local reach = math.max(size.X, size.Z) * 0.5
            local d = Vector3.new(pos.X - part.Position.X, 0, pos.Z - part.Position.Z).Magnitude
            if d < reach then return 0 end
        end
    end
    return CFG.safeZonePull
end

local function evaluateHazardPenaltyAtPoint(pos)
    local totalPenalty = 0
    local now = os.clock()
    local _, playerRadius, totalHeight = getPlayerHitboxMetrics()
    local effectivePreemptive = CFG.preemptiveClearance + playerRadius
    local halfHeight = (totalHeight * 0.5) + 2.0

    for _, volume in ipairs(HZ.volumes) do
        if not volume.part or volume.part.Parent then
            local closest = volumeClosestPoint(volume, pos)
            local horizontalDist = Vector2.new(pos.X - closest.X, pos.Z - closest.Z).Magnitude
            local verticalBlocked = CFG.hazardIgnoreVertical or math.abs(pos.Y - closest.Y) < halfHeight

            if horizontalDist < effectivePreemptive and verticalBlocked then
                local depth = (effectivePreemptive - horizontalDist) / effectivePreemptive
                local spawnTime = volume.spawn or (volume.part and HZ.spawnTimes[volume.part]) or now
                local age = math.clamp(now - spawnTime, 0.1, 4.0)

                local ageWeight = (1.0 + age * 4.5) ^ 2
                totalPenalty = totalPenalty + (depth * depth * 350 * ageWeight)
            end
        end
    end

    return totalPenalty + safeZonePenalty(pos)
end

local function getActiveHazardRepulsionVector(pos)
    local repulsion = Vector3.zero
    local now = os.clock()
    local _, playerRadius, totalHeight = getPlayerHitboxMetrics()
    local effectivePreemptive = CFG.preemptiveClearance + playerRadius
    local halfHeight = (totalHeight * 0.5) + 2.0

    for _, part in ipairs(HZ.detected) do
        if part.Parent then
            local closest = hazardClosestPoint(part, pos)
            local flatOffset = Vector3.new(pos.X - closest.X, 0, pos.Z - closest.Z)
            local dist = flatOffset.Magnitude
            local verticalBlocked = CFG.hazardIgnoreVertical or math.abs(pos.Y - closest.Y) < halfHeight

            if dist < effectivePreemptive and verticalBlocked then
                local spawnTime = HZ.spawnTimes[part] or now
                local ageWeight = (1.0 + math.clamp(now - spawnTime, 0.1, 4.0) * 3.5) ^ 2
                local strength = ((effectivePreemptive - dist) / effectivePreemptive) * ageWeight

                local dir = dist > 0.01 and flatOffset.Unit or Vector3.new(pos.X - part.Position.X, 0, pos.Z - part.Position.Z).Unit
                if dir.Magnitude < 0.01 then dir = Vector3.new(0, 0, 1) end

                repulsion = repulsion + (dir * strength * 25)
            end
        end
    end

    return repulsion
end

local function clearHazardHighlights()
    if HZ.highlightsFolder then
        HZ.highlightsFolder:Destroy()
        HZ.highlightsFolder = nil
    end
end

-- What a hazard is called on its tag: the attack-book name if it has earned one,
-- otherwise the part's own name.
local function hazardDisplayName(part)
    local record = findAttackRecord(part)
    if record then return record.name end
    return part.Name
end

-- Always on (2.3.0): every detected enemy attack is highlighted, tagged with its
-- name, and - if it is moving - drawn with the path it is predicted to sweep.
-- Nearest N only. Three hundred BillboardGuis is what actually freezes the
-- frame, and the far ones are not what you are about to be hit by.
local function overlayShortlist()
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local list = HZ.detected
    if not root or #list <= CFG.maxHazardOverlays then return list end

    local origin = root.Position
    local scored = table.create(#list)
    for i, part in ipairs(list) do
        scored[i] = { part = part, d = (part.Position - origin).Magnitude }
    end
    table.sort(scored, function(a, b) return a.d < b.d end)
    local out = table.create(CFG.maxHazardOverlays)
    for i = 1, CFG.maxHazardOverlays do out[i] = scored[i].part end
    return out
end

local function updateHazardHighlights()
    -- Nearest few only. Anything drawn last frame and not in the list is
    -- cleaned up by the same pass, so this shrinks as well as caps.
    local shortlist = overlayShortlist()
    if not HZ.highlightsFolder or not HZ.highlightsFolder.Parent then
        HZ.highlightsFolder = Instance.new("Folder")
        HZ.highlightsFolder.Name = "HazardHighlights"
        HZ.highlightsFolder.Parent = getVisualRoot()
        table.clear(HZ.predictionOwner)
    end
    local folder = HZ.highlightsFolder
    local now = os.clock()

    -- Set lookup instead of a table.find per child, which made cleanup O(n*m).
    local activeSet = {}
    for _, part in ipairs(shortlist) do
        activeSet[part] = true
    end

    for _, child in ipairs(folder:GetChildren()) do
        local adornee
        if child:IsA("BasePart") then
            adornee = HZ.predictionOwner[child]
        else
            adornee = child.Adornee   -- Highlight, HandleAdornments, SelectionBox, BillboardGui
        end
        if not adornee or not adornee.Parent or not activeSet[adornee] then
            if child:IsA("BasePart") then HZ.predictionOwner[child] = nil end
            child:Destroy()
        end
    end

    for _, part in ipairs(shortlist) do
        if part.Parent then
            local debugId = part:GetDebugId()
            local velocity = getHazardMotion(part)

            -- Name tag.
            if CFG.hazardTagEnabled then
                local tagId = "Tag_" .. debugId
                local tag = folder:FindFirstChild(tagId)
                if not tag then
                    tag = Instance.new("BillboardGui")
                    tag.Name = tagId
                    tag.Adornee = part
                    tag.Size = UDim2.fromOffset(180, 34)
                    tag.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y * 0.5 + 2.5, 0)
                    tag.AlwaysOnTop = true
                    tag.MaxDistance = 250
                    local label = Instance.new("TextLabel")
                    label.Name = "Label"
                    label.Size = UDim2.fromScale(1, 1)
                    label.BackgroundTransparency = 1
                    label.Font = Enum.Font.GothamBold
                    label.TextColor3 = CFG.colorTelegraph
                    label.TextStrokeTransparency = 0.15
                    label.TextSize = 14
                    label.TextScaled = false
                    label.Parent = tag
                    tag.Parent = folder
                end
                local label = tag:FindFirstChild("Label")
                if label then
                    local text
                    if velocity then
                        text = string.format("%s  >> %.0f st/s", hazardDisplayName(part),
                            Vector3.new(velocity.X, 0, velocity.Z).Magnitude)
                    else
                        text = string.format("%s  %.1fs", hazardDisplayName(part),
                            math.max(now - (HZ.spawnTimes[part] or now), 0))
                    end
                    if label.Text ~= text then label.Text = text end
                end
            end

            -- Predicted path of a moving hazard: a thin neon line along the sweep.
            local lineId = "Pred_" .. debugId
            local line = folder:FindFirstChild(lineId)
            if velocity then
                local sweep = Vector3.new(velocity.X, 0, velocity.Z) * CFG.projectileLookahead
                local from = part.Position
                local to = from + sweep
                if not line then
                    line = Instance.new("Part")
                    line.Name = lineId
                    line.Anchored = true
                    line.CanCollide = false
                    line.CanQuery = false
                    line.CanTouch = false
                    line.CastShadow = false
                    line.Material = Enum.Material.Neon
                    line.Color = CFG.colorTelegraph
                    line.Transparency = 0.35
                    line.Parent = folder
                    HZ.predictionOwner[line] = part
                end
                line.Size = Vector3.new(0.3, 0.3, math.max(sweep.Magnitude, 0.1))
                line.CFrame = CFrame.lookAt(from:Lerp(to, 0.5), to)
            elseif line then
                HZ.predictionOwner[line] = nil
                line:Destroy()
            end

            local highlightId = "Highlight_" .. debugId
            if not folder:FindFirstChild(highlightId) then
                local isCylinder = false
                local isSphere = false
                if part:IsA("Part") then
                    local success, shape = pcall(function() return part.Shape end)
                    if success then
                        isCylinder = (shape == Enum.PartType.Cylinder)
                        isSphere = (shape == Enum.PartType.Ball)
                    end
                end

                local partNameLower = part.Name:lower()
                if not isCylinder then
                    isCylinder = (partNameLower:find("cylinder") ~= nil) or (partNameLower:find("ring") ~= nil)
                end
                if not isSphere then
                    isSphere = (partNameLower:find("sphere") ~= nil) or (partNameLower:find("ball") ~= nil)
                end

                if part:IsA("MeshPart") then
                    local hl = Instance.new("Highlight")
                    hl.Name = highlightId
                    hl.Adornee = part
                    hl.FillColor = CFG.colorTelegraph
                    hl.FillTransparency = 0.65
                    hl.OutlineColor = CFG.colorTelegraph
                    hl.OutlineTransparency = 0.1
                    hl.Parent = HZ.highlightsFolder
                elseif isCylinder then
                    local adorn = Instance.new("CylinderHandleAdornment")
                    adorn.Name = highlightId
                    adorn.Adornee = part
                    adorn.Height = part.Size.X
                    adorn.Radius = math.min(part.Size.Y, part.Size.Z) * 0.5
                    adorn.Color3 = CFG.colorTelegraph
                    adorn.Transparency = 0.5
                    adorn.ZIndex = 2
                    adorn.AlwaysOnTop = true
                    adorn.CFrame = CFrame.Angles(0, math.rad(90), 0)
                    adorn.Parent = HZ.highlightsFolder
                elseif isSphere then
                    local adorn = Instance.new("SphereHandleAdornment")
                    adorn.Name = highlightId
                    adorn.Adornee = part
                    adorn.Radius = math.min(part.Size.X, part.Size.Y, part.Size.Z) * 0.5
                    adorn.Color3 = CFG.colorTelegraph
                    adorn.Transparency = 0.5
                    adorn.ZIndex = 2
                    adorn.AlwaysOnTop = true
                    adorn.Parent = HZ.highlightsFolder
                else
                    local box = Instance.new("SelectionBox")
                    box.Name = highlightId
                    box.Adornee = part
                    box.Color3 = CFG.colorTelegraph
                    box.LineThickness = 0.04
                    box.SurfaceColor3 = CFG.colorTelegraph
                    box.SurfaceTransparency = 0.65
                    box.Parent = HZ.highlightsFolder
                end
            end
        end
    end
end

local function clearWallHighlights()
    if HZ.wallHighlightsFolder then
        HZ.wallHighlightsFolder:Destroy()
        HZ.wallHighlightsFolder = nil
    end
end

-- Draws the wall overlay: every invisible collision wall in green. Pooled and
-- incremental like the hazard overlay - only new adornees get a box, stale ones
-- are destroyed - so a static set costs nothing to hold on screen.
-- Read from CFG each draw so the Overlays colour picker takes effect live.

local function updateWallHighlights()
    if not CFG.showWalls then
        clearWallHighlights()
        return
    end

    if not HZ.wallHighlightsFolder then
        HZ.wallHighlightsFolder = Instance.new("Folder")
        HZ.wallHighlightsFolder.Name = "DungeonWallHighlights"
        HZ.wallHighlightsFolder.Parent = getVisualRoot()
    end

    local wanted = {}
    for _, part in ipairs(HZ.invisWalls) do
        if part.Parent then wanted[part] = true end
    end

    for _, child in ipairs(HZ.wallHighlightsFolder:GetChildren()) do
        local adornee = child:IsA("SelectionBox") and child.Adornee
        if not adornee or not adornee.Parent or not wanted[adornee] then
            child:Destroy()
        end
    end

    for part in pairs(wanted) do
        local id = "Wall_" .. part:GetDebugId()
        if not HZ.wallHighlightsFolder:FindFirstChild(id) then
            local box = Instance.new("SelectionBox")
            box.Name = id
            box.Adornee = part
            box.Color3 = CFG.colorWall
            box.LineThickness = 0.05
            box.SurfaceColor3 = CFG.colorWall
            box.SurfaceTransparency = 0.75
            box.Parent = HZ.wallHighlightsFolder
        end
    end
end

local function clearHoverHighlight()
    if HZ.hoverFolder then
        HZ.hoverFolder:Destroy()
        HZ.hoverFolder = nil
    end
end

local function setHoverHighlight(part)
    clearHoverHighlight()
    if not part or not part.Parent then return end

    HZ.hoverFolder = Instance.new("Folder")
    HZ.hoverFolder.Name = "DungeonHoverInspect"
    HZ.hoverFolder.Parent = getVisualRoot()

    local hl = Instance.new("Highlight")
    hl.Adornee = part
    hl.FillColor = Color3.fromRGB(0, 255, 255)
    hl.FillTransparency = 0.4
    hl.OutlineColor = Color3.fromRGB(255, 255, 0)
    hl.OutlineTransparency = 0
    hl.Parent = HZ.hoverFolder

    local box = Instance.new("SelectionBox")
    box.Adornee = part
    box.Color3 = Color3.fromRGB(255, 255, 0)
    box.LineThickness = 0.08
    box.Parent = HZ.hoverFolder
end

-- Telegraph feed rows are pooled (2.1.0). The feed used to destroy and rebuild
-- five Instances per hazard four times a second; now a row is built once, hidden
-- when unused, and only its text is rewritten.
local feedRows = {}
local feedRowsOwner = nil     -- the list the rows were built into (rebuilt if the UI is)
local feedEmptyLabel = nil

local function buildFeedRow(list)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 36)
    row.BackgroundColor3 = Color3.fromRGB(35, 38, 47)
    row.BorderSizePixel = 0
    row.AutoButtonColor = false
    row.Text = ""
    row.Visible = false
    row.Parent = list

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 5)
    corner.Parent = row

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(0.65, -6, 0, 18)
    nameLabel.Position = UDim2.fromOffset(6, 2)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextColor3 = Color3.fromRGB(255, 95, 95)
    nameLabel.TextSize = 12
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Parent = row

    local parentLabel = Instance.new("TextLabel")
    parentLabel.Size = UDim2.new(0.65, -6, 0, 14)
    parentLabel.Position = UDim2.fromOffset(6, 18)
    parentLabel.BackgroundTransparency = 1
    parentLabel.Font = Enum.Font.Gotham
    parentLabel.TextColor3 = Color3.fromRGB(170, 175, 190)
    parentLabel.TextSize = 11
    parentLabel.TextXAlignment = Enum.TextXAlignment.Left
    parentLabel.TextTruncate = Enum.TextTruncate.AtEnd
    parentLabel.Parent = row

    local ageLabel = Instance.new("TextLabel")
    ageLabel.Size = UDim2.new(0.35, -6, 1, 0)
    ageLabel.Position = UDim2.new(0.65, 0, 0, 0)
    ageLabel.BackgroundTransparency = 1
    ageLabel.Font = Enum.Font.GothamMedium
    ageLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    ageLabel.TextSize = 11
    ageLabel.TextXAlignment = Enum.TextXAlignment.Right
    ageLabel.Parent = row

    local entry = { row = row, nameLabel = nameLabel, parentLabel = parentLabel, ageLabel = ageLabel, part = nil }
    row.MouseEnter:Connect(function()
        row.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
        if entry.part then setHoverHighlight(entry.part) end
    end)
    row.MouseLeave:Connect(function()
        row.BackgroundColor3 = Color3.fromRGB(35, 38, 47)
        clearHoverHighlight()
    end)
    return entry
end

local function updateTelegraphFeedUI()
    local list = UI.telegraphFeedList
    if not list then return end

    if feedRowsOwner ~= list then
        -- The control window was rebuilt; the old rows died with it.
        table.clear(feedRows)
        feedEmptyLabel = nil
        feedRowsOwner = list
    end

    local detected = HZ.detected
    if #detected == 0 then
        if not feedEmptyLabel or not feedEmptyLabel.Parent then
            feedEmptyLabel = Instance.new("TextLabel")
            feedEmptyLabel.Size = UDim2.new(1, 0, 0, 24)
            feedEmptyLabel.BackgroundTransparency = 1
            -- Enum.Font has no GothamItalic member; assigning it throws and killed
            -- the whole tick whenever the hazard list was empty.
            feedEmptyLabel.Font = Enum.Font.Gotham
            feedEmptyLabel.Text = "No active hazards detected"
            feedEmptyLabel.TextColor3 = Color3.fromRGB(150, 153, 165)
            feedEmptyLabel.TextSize = 12
            feedEmptyLabel.Parent = list
        end
        feedEmptyLabel.Visible = true
    elseif feedEmptyLabel then
        feedEmptyLabel.Visible = false
    end

    local now = os.clock()
    for i, part in ipairs(detected) do
        local entry = feedRows[i]
        if not entry then
            entry = buildFeedRow(list)
            feedRows[i] = entry
        end
        if entry.part ~= part then
            entry.part = part
            entry.nameLabel.Text = string.format("%d. %s", i, part.Name)
            entry.parentLabel.Text = part.Parent and part.Parent.Name or "Workspace"
        end
        local spawnTime = HZ.spawnTimes[part] or now
        entry.ageLabel.Text = string.format("Age: %.1fs", math.max(now - spawnTime, 0))
        if not entry.row.Visible then entry.row.Visible = true end
    end
    for i = #detected + 1, #feedRows do
        local entry = feedRows[i]
        entry.part = nil
        if entry.row.Visible then entry.row.Visible = false end
    end
end

-- A section barrier: an anchored, wall-sized part named (or contained in a model
-- named) like a barrier. Kept name-driven rather than appearance-driven on
-- purpose - a wall-shaped part is otherwise indistinguishable from ordinary map
-- geometry, and a false positive would send the idle bot walking off at a wall.
-- An invisible collision wall: solid, effectively see-through, anchored, and
-- wall-shaped (thin in one horizontal axis) so invisible floors, ceilings and
-- whole-room trigger volumes are not swept up. Purely for the green overlay.
local function isInvisibleWall(part)
    local cached = invisWallCache[part]
    if cached ~= nil then return cached end

    local result = false
    if part:IsA("BasePart") and part.Anchored and part.CanCollide
        and part.Transparency >= CFG.invisibleWallTransparencyCutoff then
        -- Cheap size gates first, before any tree walking.
        local size = part.Size
        local footprint = math.max(size.X, size.Z)
        local thin = math.min(size.X, size.Z) <= CFG.invisibleWallMaxThickness
        if footprint >= CFG.invisibleWallMinFootprint and (thin or size.Y >= footprint) then
            -- Skip our own instances and creature parts.
            local ours = RT.visualRoot and part:IsDescendantOf(RT.visualRoot)
            local model = part:FindFirstAncestorWhichIsA("Model")
            local onCreature = model and model:FindFirstChildWhichIsA("Humanoid") ~= nil
            result = not ours and not onCreature
        end
    end

    invisWallCache[part] = result
    return result
end

-- =========================================================================
-- WORLD INDEX (2.1.0)
--
-- The per-scan Workspace:GetDescendants() walk WAS the lag spike. On a full
-- dungeon it allocated an array of every instance on the map and ran the
-- classifiers over every BasePart, three times a second, all inside one
-- Heartbeat - and every four seconds the memo caches were flushed, so the very
-- next scan recomputed ownership (GetAttributes, a Players loop, a parent walk)
-- for every part on the map at once. That is a spike every 0.35s with a bigger
-- one every 4s, from the moment the script starts, on any map size.
--
-- The index below is built once - in slices, so even the first walk never lands
-- as a single pass - and then kept current by DescendantAdded / Removing,
-- which are O(1) per instance. Each frame re-classifies a bounded slice of the
-- part pool round-robin, so a pooled effect part that is turned INTO a telegraph
-- by changing its properties is still caught within a second, and a part that
-- has just been added goes to the front of the queue and is classified the
-- frame it appears (that is the telegraph case that matters).
-- =========================================================================

-- (GENERIC_PART_NAMES - names never learned as "ours" or as an attack - is
-- declared with the attack book above, since both use it.)

-- Stamps that one of OUR casts just happened. Fed by the Animator (an
-- Action-priority animation starting on our character) and by the remote hook
-- (this client firing an attack-ish remote). Not by the auto-clicker or the
-- Q/E key spam: those fire ten times a second whether anything casts or not,
-- which would leave the window permanently open.
local function noteOwnAction(source)
    RT.lastOwnActionTime = os.clock()
    RT.lastOwnActionSource = source
end

-- A part appearing right after our own cast, right next to us, is our effect.
-- Its name is learned unless it is generic, so the next cast is recognised on
-- sight even outside the timing window.
local function markOwnIfRecent(part, now)
    local sinceCast = now - RT.lastOwnActionTime
    if sinceCast > CFG.ownAttackWindow then return false end
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    local offset = part.Position - root.Position
    if Vector3.new(offset.X, 0, offset.Z).Magnitude > CFG.ownAttackRadius then return false end

    HZ.ownParts[part] = true
    local lname = string.lower(part.Name)
    if not GENERIC_PART_NAMES[lname] and not HZ.learnedNames[lname] and not HZ.ownNames[lname] then
        HZ.ownNames[lname] = true
        heavyDebug("OwnAttack", string.format(
            "Learned '%s' as our own effect (appeared %.2fs after our %s, %.1f studs away). Saved with the config.",
            part.Name, sinceCast, tostring(RT.lastOwnActionSource or "cast"), offset.Magnitude))
    end
    return true
end

local function poolAdd(part)
    if HZ.partPoolIndex[part] then return end
    local n = #HZ.partPool + 1
    HZ.partPool[n] = part
    HZ.partPoolIndex[part] = n
end

-- Swap-remove keeps the pool a dense array, which the round-robin needs.
local function poolRemove(part)
    local i = HZ.partPoolIndex[part]
    if not i then return end
    local pool = HZ.partPool
    local n = #pool
    local last = pool[n]
    pool[i] = last
    HZ.partPoolIndex[last] = i
    pool[n] = nil
    HZ.partPoolIndex[part] = nil
end

local function setCandidate(part, isHazard, now)
    if isHazard then
        if not HZ.candidateSet[part] then
            HZ.candidateSet[part] = true
            HZ.catalogDirty = true
            if not HZ.spawnTimes[part] then HZ.spawnTimes[part] = now end
        end
    elseif HZ.candidateSet[part] then
        HZ.candidateSet[part] = nil
        HZ.catalogDirty = true
    end
end

local function setInvisWall(part, isWall)
    if isWall then
        if not HZ.invisWallSet[part] then
            HZ.invisWallSet[part] = true
            HZ.catalogDirty = true
        end
    elseif HZ.invisWallSet[part] then
        HZ.invisWallSet[part] = nil
        HZ.catalogDirty = true
    end
end

-- The per-frame filter and the overlay iterate arrays; rebuilt from the sets
-- only when membership actually changed.
local function rebuildCatalogArrays()
    if not HZ.catalogDirty then return end
    HZ.catalogDirty = false
    local candidates = {}
    for part in pairs(HZ.candidateSet) do candidates[#candidates + 1] = part end
    HZ.candidates = candidates
    local walls = {}
    for part in pairs(HZ.invisWallSet) do walls[#walls + 1] = part end
    HZ.invisWalls = walls
    HZ.lastCatalogTime = os.clock()
end

-- Turning the wall overlay off drops the wall catalog; the sweep only runs while
-- the overlay is on, so entries would otherwise linger until the part left.
local function resetWallCatalog()
    table.clear(HZ.invisWallSet)
    HZ.invisWalls = {}
    HZ.catalogDirty = true
end

-- =========================================================================
-- HAND-DRAWN HAZARD ZONES (2.11.0)
--
-- Some attacks are announced by something that is not the damage. A rune on
-- the floor, a glow, a decal - no amount of appearance scoring turns a
-- decoration into a hitbox, because it genuinely is not one. So you point at
-- the decoration and draw the volume yourself, once, and from then on every
-- copy of that decoration carries one.
--
-- A definition is a signature (name + parent name) plus a shape. The volumes
-- are real Parts placed in Workspace rather than a parallel list, because
-- everything downstream - the safety test, the penalty field, the clone ring -
-- already understands Parts. They carry a DQZone attribute so isDamageBrick
-- takes them at their word.
-- =========================================================================

local function zoneFolder()
    if ZN.folder and ZN.folder.Parent then return ZN.folder end
    local folder = Instance.new("Folder")
    folder.Name = "DungeonAutofarmZones"
    -- Deliberately NOT under the visual root: that subtree is excluded from
    -- hazard classification, and these have to be classified as hazards.
    folder.Parent = Workspace
    ZN.folder = folder
    return folder
end

local function clearZones()
    if ZN.folder then ZN.folder:Destroy() end
    ZN.folder = nil
    for part, volume in pairs(ZN.live) do
        if volume and volume.Parent then volume:Destroy() end
        ZN.live[part] = nil
    end
end

local function zoneMatches(def, part)
    if string.lower(part.Name) ~= def.partName then return false end
    if def.parentName ~= "" then
        local parent = part.Parent
        if not parent or string.lower(parent.Name) ~= def.parentName then return false end
    end
    return true
end

-- Attaches a volume to `part` if any definition claims it and it has none yet.
local function ensureZoneFor(part)
    if ZN.live[part] then return end
    for _, def in ipairs(ZN.defs) do
        if zoneMatches(def, part) then
            local volume = Instance.new("Part")
            volume.Name = "Zone_" .. part.Name
            volume.Shape = def.shape == "circle" and Enum.PartType.Cylinder or Enum.PartType.Block
            volume.Size = def.shape == "circle"
                and Vector3.new(def.height, def.radius * 2, def.radius * 2)
                or Vector3.new(def.radius * 2, def.height, def.radius * 2)
            volume.Anchored = true
            volume.CanCollide = false
            volume.CanQuery = false
            volume.CanTouch = false
            volume.CastShadow = false
            volume.Material = Enum.Material.ForceField
            volume.Color = CFG.zoneColor
            volume.Transparency = CFG.zoneTransparency
            volume:SetAttribute("DQZone", true)
            -- A cylinder's length runs along X, so it has to be laid on its side
            -- to stand up as a disc.
            volume.CFrame = def.shape == "circle"
                and (CFrame.new(part.Position) * CFrame.Angles(0, 0, math.rad(90)))
                or CFrame.new(part.Position)
            volume.Parent = zoneFolder()
            ZN.live[part] = volume
            HZ.manualParts[volume] = true
            poolAdd(volume)
            return
        end
    end
end

-- Per frame: keep each volume on its decoration, and drop the ones whose
-- decoration has gone.
local function updateZones()
    if not next(ZN.live) then return end
    local dead = nil
    for part, volume in pairs(ZN.live) do
        if not part.Parent or not volume.Parent then
            dead = dead or {}
            dead[#dead + 1] = part
        else
            local position = part.Position
            if (volume.Position - position).Magnitude > 0.05 then
                local _, yaw = volume.CFrame:ToOrientation()
                volume.CFrame = volume.Size.X == volume.Size.Y
                    and CFrame.new(position)
                    or (volume:GetAttribute("DQZoneCircle")
                        and (CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)))
                        or CFrame.new(position))
            end
        end
    end
    if dead then
        for _, part in ipairs(dead) do
            local volume = ZN.live[part]
            if volume then
                HZ.manualParts[volume] = nil
                poolRemove(volume)
                if volume.Parent then volume:Destroy() end
            end
            ZN.live[part] = nil
        end
    end
end

-- Rebuilds every live volume from the current definitions. Called when the
-- definitions change or the map does.
local function rebuildZones()
    clearZones()
    for _, part in ipairs(HZ.partPool) do
        if part.Parent and not part:GetAttribute("DQZone") then ensureZoneFor(part) end
    end
    heavyDebug("Zone", string.format("%d zone definition(s); %d volume(s) placed.",
        #ZN.defs, (function() local c = 0 for _ in pairs(ZN.live) do c = c + 1 end return c end)()))
end

-- The draft volume shown while you drag one out.
local function updateZonePreview()
    if not ZN.root or not ZN.root.Parent then return end
    local preview = ZN.preview
    if not preview or not preview.Parent then
        preview = Instance.new("Part")
        preview.Name = "ZonePreview"
        preview.Anchored = true
        preview.CanCollide = false
        preview.CanQuery = false
        preview.CanTouch = false
        preview.CastShadow = false
        preview.Material = Enum.Material.ForceField
        preview.Color = CFG.zoneColor
        preview.Transparency = 0.55
        preview.Parent = getVisualRoot()
        ZN.preview = preview
    end
    local radius = math.clamp(ZN.draftRadius, CFG.zoneMinRadius, CFG.zoneMaxRadius)
    local height = CFG.zoneDefaultHeight
    if ZN.draftShape == "circle" then
        preview.Shape = Enum.PartType.Cylinder
        preview.Size = Vector3.new(height, radius * 2, radius * 2)
        preview.CFrame = CFrame.new(ZN.root.Position) * CFrame.Angles(0, 0, math.rad(90))
    else
        preview.Shape = Enum.PartType.Block
        preview.Size = Vector3.new(radius * 2, height, radius * 2)
        preview.CFrame = CFrame.new(ZN.root.Position)
    end
end

local function clearZonePreview()
    if ZN.preview then ZN.preview:Destroy() end
    ZN.preview = nil
    ZN.root = nil
    ZN.dragging = false
end

local function addZoneDef(part, shape, radius, height)
    if not part or not part:IsA("BasePart") then return false end
    local def = {
        name = part.Name,
        partName = string.lower(part.Name),
        parentName = (part.Parent and part.Parent ~= Workspace) and string.lower(part.Parent.Name) or "",
        shape = shape == "square" and "square" or "circle",
        radius = math.clamp(radius, CFG.zoneMinRadius, CFG.zoneMaxRadius),
        height = height or CFG.zoneDefaultHeight,
    }
    for i, existing in ipairs(ZN.defs) do
        if existing.partName == def.partName and existing.parentName == def.parentName then
            ZN.defs[i] = def
            rebuildZones()
            heavyDebug("Zone", string.format("Updated the zone on '%s' (%s, %.0f studs).",
                def.name, def.shape, def.radius))
            if S.refreshZonePanel then S.refreshZonePanel() end
            return true
        end
    end
    table.insert(ZN.defs, def)
    rebuildZones()
    heavyDebug("Zone", string.format("Zone drawn on '%s': %s, %.0f studs. Every copy of it now carries one.",
        def.name, def.shape, def.radius))
    if S.refreshZonePanel then S.refreshZonePanel() end
    return true
end

local function removeZoneDef(index)
    local def = table.remove(ZN.defs, index)
    if not def then return end
    rebuildZones()
    heavyDebug("Zone", string.format("Removed the zone on '%s'.", def.name))
    if S.refreshZonePanel then S.refreshZonePanel() end
end

local function serializeZones()
    local out = {}
    for _, def in ipairs(ZN.defs) do
        table.insert(out, {
            name = def.name, partName = def.partName, parentName = def.parentName,
            shape = def.shape, radius = def.radius, height = def.height,
        })
    end
    return out
end

local function loadZones(list)
    table.clear(ZN.defs)
    if type(list) == "table" then
        for _, def in ipairs(list) do
            if type(def) == "table" and type(def.partName) == "string" and tonumber(def.radius) then
                table.insert(ZN.defs, {
                    name = def.name or def.partName,
                    partName = def.partName,
                    parentName = type(def.parentName) == "string" and def.parentName or "",
                    shape = def.shape == "square" and "square" or "circle",
                    radius = tonumber(def.radius),
                    height = tonumber(def.height) or CFG.zoneDefaultHeight,
                })
            end
        end
    end
    rebuildZones()
    if S.refreshZonePanel then S.refreshZonePanel() end
    return #ZN.defs
end

local function classifyPoolPart(part, now)
    if not part.Parent then
        poolRemove(part)
        setCandidate(part, false, now)
        setInvisWall(part, false)
        return
    end
    -- Cheap gate ahead of the full classifier: a telegraph is non-collidable
    -- unless the user marked the part (or its name) by hand.
    local maybeTelegraph = not part.CanCollide or HZ.manualParts[part]
    if not maybeTelegraph and next(HZ.learnedNames) ~= nil then
        maybeTelegraph = HZ.learnedNames[string.lower(part.Name)] == true
    end
    -- A part matching a zone definition gets a volume attached to it, so the
    -- decoration that only announces an attack starts carrying one.
    if #ZN.defs > 0 and not part:GetAttribute("DQZone") then ensureZoneFor(part) end

    setCandidate(part, maybeTelegraph and isDamageBrick(part), now)
    if CFG.showWalls then
        setInvisWall(part, isInvisibleWall(part))
    end
end

-- `initial` = ingesting the pre-existing world: nothing "just appeared", so no
-- seen-at stamp, no own-attack timing, and no fresh-queue priority.
local function indexAdded(inst, now, initial)
    local visualRoot = RT.visualRoot
    if visualRoot and inst:IsDescendantOf(visualRoot) then return end

    if inst:IsA("BasePart") then
        if not initial then
            -- Stamped before any filtering: "appeared just now" is only
            -- meaningful if it is recorded the moment the part appears.
            if inst.Anchored and not inst.CanCollide then
                HZ.seenAt[inst] = now
            end
            markOwnIfRecent(inst, now)
            HZ.freshParts[#HZ.freshParts + 1] = inst
            -- Motion-tracked while young (2.3.0), so a projectile is caught by
            -- its speed and a hit can be correlated with what just appeared.
            -- Big anchored collidable parts are map geometry streaming in and
            -- are skipped, or a streaming burst would cost a frame.
            local size = inst.Size
            if not inst.CanCollide or not inst.Anchored
                or math.max(size.X, size.Y, size.Z) <= CFG.projectileMaxSize then
                HZ.recentParts[inst] = now
            end
        end
        poolAdd(inst)
        if LD.enabled and not initial then LD.sweeping = true end
    elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
        or inst:IsA("Smoke") or inst:IsA("Fire") or inst:IsA("Sparkles") then
        -- Indexed for low detail: these are the other half of the frame cost.
        LD.effects[inst] = true
        if LD.enabled and CFG.lowDetailKillEffects and inst.Enabled then
            LD.disabledEffects[inst] = true
            pcall(function() inst.Enabled = false end)
        end
    elseif inst:IsA("Humanoid") then
        local model = inst.Parent
        if model and model:IsA("Model") then
            HZ.enemyModels[model] = true
        end
    elseif inst:IsA("BillboardGui") then
        HZ.billboards[inst] = true
    end
end

local function indexRemoving(inst)
    if inst:IsA("BasePart") then
        poolRemove(inst)
        if HZ.candidateSet[inst] then
            HZ.candidateSet[inst] = nil
            HZ.catalogDirty = true
        end
        if HZ.invisWallSet[inst] then
            HZ.invisWallSet[inst] = nil
            HZ.catalogDirty = true
        end
        HZ.seenAt[inst] = nil
        HZ.spawnTimes[inst] = nil
        HZ.recentParts[inst] = nil
        HZ.motion[inst] = nil
        LD.hidden[inst] = nil
    elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
        or inst:IsA("Smoke") or inst:IsA("Fire") or inst:IsA("Sparkles") then
        LD.effects[inst] = nil
        LD.disabledEffects[inst] = nil
    elseif inst:IsA("Humanoid") then
        local model = inst.Parent
        if model then HZ.enemyModels[model] = nil end
    elseif inst:IsA("Model") then
        HZ.enemyModels[inst] = nil
    elseif inst:IsA("BillboardGui") then
        HZ.billboards[inst] = nil
    end
end

local function stopWorldIndex()
    for _, connection in ipairs(RT.indexConnections) do
        connection:Disconnect()
    end
    table.clear(RT.indexConnections)
    HZ.indexBuild = nil
end

-- The pool exists from map load; finding it once beats an ancestor walk per
-- part per frame.
local function findVfxPool()
    RT.vfxPool = Workspace:FindFirstChild("vfxPool")
    if RT.vfxPool then
        heavyDebug("Own", "Found Workspace.vfxPool; our own hit effects will not be dodged.")
    end
end

local function startWorldIndex()
    findVfxPool()
    stopWorldIndex()
    table.clear(HZ.enemyModels)
    table.clear(HZ.billboards)
    table.clear(HZ.partPool)
    table.clear(HZ.partPoolIndex)
    table.clear(HZ.freshParts)
    table.clear(HZ.candidateSet)
    table.clear(HZ.invisWallSet)
    table.clear(LD.effects)
    table.clear(LD.disabledEffects)
    table.clear(LD.hidden)
    LD.cursor = 1
    HZ.poolCursor = 1
    HZ.catalogDirty = true
    HZ.indexReady = false

    table.insert(RT.indexConnections, Workspace.DescendantAdded:Connect(function(inst)
        indexAdded(inst, os.clock(), false)
    end))
    table.insert(RT.indexConnections, Workspace.DescendantRemoving:Connect(indexRemoving))

    -- The one full walk. The GetDescendants call is a single allocation; the
    -- ingest of its result is sliced across frames by worldIndexStep.
    HZ.indexBuild = { list = Workspace:GetDescendants(), cursor = 1 }
    heavyDebug("Index", string.format("World index: ingesting %d instances at %d per frame.",
        #HZ.indexBuild.list, CFG.indexBuildBudget))
end

-- Runs every frame from the scanner loop. Bounded work: a slice of the initial
-- ingest, then every freshly added part, then a slice of the pool.
-- Per frame: motion for every young part (projectile discovery) and every
-- current candidate, and pruning of parts that have aged out.
local function trackRecentParts(now)
    for part, addedAt in pairs(HZ.recentParts) do
        if not part.Parent or now - addedAt > CFG.projectileTrackWindow then
            HZ.recentParts[part] = nil
            if not HZ.candidateSet[part] then HZ.motion[part] = nil end
        else
            updateMotion(part, now)
            local motion = HZ.motion[part]
            if motion and motion.moving and not HZ.candidateSet[part] and HZ.partPoolIndex[part] then
                -- It started moving: it may be a projectile now.
                classifyPoolPart(part, now)
            end
        end
    end
end

-- =========================================================================
-- FREEZE (2.4.0)
--
-- A telegraph is on screen for well under a second. That is not long enough to
-- point a mouse at it, which made "Pick Telegraph" nearly unusable for exactly

local FROZEN_ORIG_NAME = "DQOriginalName"
local FROZEN_ORIG_PARENT = "DQOriginalParent"

-- The real name and parent behind a picked part: a copy answers for the
-- original it was made from.
local function resolvePickedIdentity(part)
    local originalName = part:GetAttribute(FROZEN_ORIG_NAME)
    if type(originalName) == "string" then
        local originalParent = part:GetAttribute(FROZEN_ORIG_PARENT)
        return originalName, type(originalParent) == "string" and originalParent or "", true
    end
    return part.Name, part.Parent and part.Parent ~= Workspace and part.Parent.Name or "", false
end

-- =========================================================================
-- LOW DETAIL (2.4.0)
--
-- Hides everything in the world except the part names the user picked. Hiding
-- is Transparency 1 + no shadow, never destruction: collision is untouched, so
-- a hidden floor is still solid and the character still walks on it. Enemies,
-- anything currently classified as an attack, and our own markers are always
-- kept - hiding those would defeat the point of running the bot at all.
--
-- Parts are swept from the world index pool a bounded slice per frame, so
-- turning it on across a whole dungeon costs a little work for a couple of
-- =========================================================================

local function shouldKeepVisible(part)
    if LD.keepNames[string.lower(part.Name)] then return true end
    if HZ.candidateSet[part] then return true end      -- an attack: always visible
    if part.Name == "Terrain" or part.Name == "Baseplate" then return true end
    local model = part:FindFirstAncestorWhichIsA("Model")
    if model and model:FindFirstChildWhichIsA("Humanoid") then return true end
    return false
end

local function restorePart(part)
    local snapshot = LD.hidden[part]
    if not snapshot then return end
    LD.hidden[part] = nil
    if not part.Parent then return end
    pcall(function()
        part.Transparency = snapshot.transparency
        part.CastShadow = snapshot.castShadow
    end)
end

local function hidePart(part)
    if LD.hidden[part] then return end
    local ok = pcall(function()
        LD.hidden[part] = { transparency = part.Transparency, castShadow = part.CastShadow }
        part.Transparency = 1
        part.CastShadow = false
    end)
    if not ok then LD.hidden[part] = nil end
end

-- Particles, trails and beams are the other half of the frame cost, and they
-- are indexed separately because they are not BaseParts.
local function applyEffectState()
    if LD.enabled and CFG.lowDetailKillEffects then
        for effect in pairs(LD.effects) do
            if effect.Parent then
                if effect.Enabled and not LD.disabledEffects[effect] then
                    LD.disabledEffects[effect] = true
                    pcall(function() effect.Enabled = false end)
                end
            else
                LD.effects[effect] = nil
                LD.disabledEffects[effect] = nil
            end
        end
    else
        for effect in pairs(LD.disabledEffects) do
            LD.disabledEffects[effect] = nil
            if effect.Parent then pcall(function() effect.Enabled = true end) end
        end
    end
end

local function restoreAllDetail()
    for part in pairs(LD.hidden) do restorePart(part) end
    table.clear(LD.hidden)
    applyEffectState()
end

local function setLowDetailEnabled(enabled)
    LD.enabled = enabled
    LD.cursor = 1
    if enabled then
        LD.sweeping = true
        local count = 0
        for _ in pairs(LD.keepNames) do count = count + 1 end
        heavyDebug("LowDetail", string.format(
            "Low detail ON: hiding everything except %d picked name(s), enemies and attacks. Collision is unchanged.",
            count))
    else
        LD.sweeping = false
        restoreAllDetail()
        heavyDebug("LowDetail", "Low detail off; the world is visible again.")
    end
    applyEffectState()
end

-- The keep list changed: re-sweep so newly kept parts come back and newly
-- dropped ones disappear, without a full restore in between.
local function refreshLowDetail()
    if not LD.enabled then return end
    LD.cursor = 1
    LD.sweeping = true
end

local function toggleKeepPart(part)
    if not part or not part:IsA("BasePart") then return end
    local name = select(1, resolvePickedIdentity(part))
    local key = string.lower(name)
    if LD.keepNames[key] then
        LD.keepNames[key] = nil
        heavyDebug("LowDetail", string.format("'%s' removed from the keep list.", name))
    else
        LD.keepNames[key] = true
        heavyDebug("LowDetail", string.format("'%s' kept visible in low detail.", name))
    end
    refreshLowDetail()
    if S.refreshMapPanel then S.refreshMapPanel() end
end

local function clearKeepList()
    table.clear(LD.keepNames)
    heavyDebug("LowDetail", "Keep list cleared.")
    refreshLowDetail()
    if S.refreshMapPanel then S.refreshMapPanel() end
end

-- One bounded slice of the hide/restore sweep, run every frame from the index.
local function lowDetailStep()
    if not LD.enabled then
        -- Anything still hidden after the mode went off is restored by
        -- setLowDetailEnabled; nothing to do here.
        return
    end
    local pool = HZ.partPool
    local n = #pool
    if n == 0 then return end

    local cursor = LD.cursor
    if cursor > n then cursor = 1 end
    local budget = math.min(CFG.lowDetailBudget, n)
    for _ = 1, budget do
        local part = pool[cursor]
        if not part then break end
        if part.Parent then
            if shouldKeepVisible(part) then
                restorePart(part)
            else
                hidePart(part)
            end
        else
            LD.hidden[part] = nil
        end
        cursor = cursor + 1
        if cursor > #pool then
            cursor = 1
            if LD.sweeping then
                LD.sweeping = false      -- a full pass has completed
            end
            if #pool == 0 then break end
        end
    end
    LD.cursor = cursor
end

local function worldIndexStep()
    local now = os.clock()

    local build = HZ.indexBuild
    if build then
        local list = build.list
        local stop = math.min(#list, build.cursor + CFG.indexBuildBudget - 1)
        for k = build.cursor, stop do
            local inst = list[k]
            if inst.Parent then indexAdded(inst, now, true) end
        end
        build.cursor = stop + 1
        if build.cursor > #list then
            HZ.indexBuild = nil
            HZ.indexReady = true
            local enemies = 0
            for _ in pairs(HZ.enemyModels) do enemies = enemies + 1 end
            heavyDebug("Index", string.format(
                "World index ready: %d parts pooled, %d humanoid models, %d billboards.",
                #HZ.partPool, enemies, (function() local c = 0 for _ in pairs(HZ.billboards) do c = c + 1 end return c end)()))
        end
    end

    local fresh = HZ.freshParts
    local budget = CFG.freshEvalBudget
    while #fresh > 0 and budget > 0 do
        local part = table.remove(fresh)
        if HZ.partPoolIndex[part] then classifyPoolPart(part, now) end
        budget = budget - 1
    end

    local pool = HZ.partPool
    local n = #pool
    if n > 0 then
        local cursor = HZ.poolCursor
        if cursor > n then cursor = 1 end
        -- Scale the slice with the pool so a full lap never takes more than
        -- about two seconds even on a huge map (a pooled part turned into a
        -- telegraph by a property change is caught within a lap).
        local budget = math.max(CFG.partEvalBudget, math.ceil(n / 120))
        for _ = 1, math.min(budget, n) do
            local part = pool[cursor]
            if not part then break end
            classifyPoolPart(part, now)
            cursor = cursor + 1
            if cursor > #pool then
                cursor = 1
                if #pool == 0 then break end
            end
        end
        HZ.poolCursor = cursor
    end

    -- Motion tracking and the pruning of aged-out parts are index maintenance,
    -- not combat work: they run here rather than in scanDamageBricks so they
    -- keep happening (and HZ.recentParts keeps being pruned) with the loop off.
    trackRecentParts(now)
    updateZones()
    collectSafeZones()
    S.precastStep()
    lowDetailStep()
end

local function removeAttackRecord(index)
    if not HZ.attackBook[index] then return end
    local record = table.remove(HZ.attackBook, index)
    heavyDebug("Trial", string.format("Forgot attack '%s'.", record.name))
    invalidateAttackBook()
end

local function clearAttackBook()
    table.clear(HZ.attackBook)
    heavyDebug("Book", "Attack book cleared.")
    invalidateAttackBook()
end

-- The catalog (which parts are telegraphs / invisible walls) is maintained by
-- the world index above, not here. This function only does the cheap per-frame
-- work: filter the catalogued telegraphs down to the ones actually in range
-- and still active.
local rebuildHazardVolumes

-- =========================================================================
-- HAZARD VOLUMES
--
-- A single attack in this game can be several hundred MeshParts. Tested one by
-- one that is (cells x parts) distance computations per evaluation - a 17x17
-- grid against 300 parts is 86,000 - and drawn one by one it is 300
-- BillboardGuis, which is what actually freezes the frame.
--
-- A dense cluster of parts under one model is, for dodging purposes, one solid
-- volume: nobody threads between the meshes of a lava pool. So a model with
-- enough parts collapses to its bounding box and is tested once. Sparse groups
-- and loose parts are left alone, because there the gaps are real and worth
-- keeping.
-- =========================================================================
volumeClosestPoint = function(volume, position)
    if volume.part then return hazardClosestPoint(volume.part, position) end
    local c, h = volume.center, volume.half
    return Vector3.new(
        math.clamp(position.X, c.X - h.X, c.X + h.X),
        math.clamp(position.Y, c.Y - h.Y, c.Y + h.Y),
        math.clamp(position.Z, c.Z - h.Z, c.Z + h.Z))
end

rebuildHazardVolumes = function()
    local groups, loose = {}, {}
    for _, part in ipairs(HZ.detected) do
        local model = part:FindFirstAncestorOfClass("Model")
        if model then
            local g = groups[model]
            if not g then g = {} groups[model] = g end
            g[#g + 1] = part
        else
            loose[#loose + 1] = part
        end
    end

    local volumes = {}
    local function addPart(part) volumes[#volumes + 1] = { part = part } end

    for _, parts in pairs(groups) do
        if #parts >= CFG.hazardClusterMin then
            local lo, hi, spawn = nil, nil, math.huge
            for _, part in ipairs(parts) do
                local pos, half = part.Position, part.Size * 0.5
                local a, b = pos - half, pos + half
                if lo then
                    lo = Vector3.new(math.min(lo.X, a.X), math.min(lo.Y, a.Y), math.min(lo.Z, a.Z))
                    hi = Vector3.new(math.max(hi.X, b.X), math.max(hi.Y, b.Y), math.max(hi.Z, b.Z))
                else
                    lo, hi = a, b
                end
                spawn = math.min(spawn, HZ.spawnTimes[part] or math.huge)
            end
            volumes[#volumes + 1] = {
                center = (lo + hi) * 0.5, half = (hi - lo) * 0.5,
                spawn = spawn < math.huge and spawn or nil, count = #parts,
            }
        else
            for _, part in ipairs(parts) do addPart(part) end
        end
    end
    for _, part in ipairs(loose) do addPart(part) end
    HZ.volumes = volumes
end

local function scanDamageBricks(rootPosition)
    local now = os.clock()
    rebuildCatalogArrays()

    local found = {}
    for _, instance in ipairs(HZ.candidates) do
        -- Transparency is re-tested per frame, not per catalog refresh, so a
        -- telegraph that fades mid-cycle stops being dodged immediately.
        if instance.Parent
            and instance.Transparency < CFG.telegraphTransparencyCutoff
            and not isOwnedByPlayerOrTeammate(instance) then
            if not HZ.recentParts[instance] then updateMotion(instance, now) end
            local closestPoint = hazardClosestPoint(instance, rootPosition)
            if (rootPosition - closestPoint).Magnitude <= CFG.damageBrickDetectionRange then
                table.insert(found, instance)
                if not HZ.spawnTimes[instance] then
                    HZ.spawnTimes[instance] = now
                end
            end
        else
            HZ.spawnTimes[instance] = nil
        end
    end
    HZ.detected = found
    rebuildHazardVolumes()

    if UI.damageBrickCountLabel then
        UI.damageBrickCountLabel.Text = "Telegraphs Active: " .. tostring(#found)
    end

    -- Visualisers create and destroy Instances, so they run on their own clock
    -- rather than once per Heartbeat, and only when the hazard set actually moved.
    if now - HZ.lastVisualTime >= CFG.visualRefreshInterval or #found ~= HZ.lastRenderedCount then
        HZ.lastVisualTime = now
        updateHazardHighlights()
    end

    if now - HZ.lastFeedTime >= CFG.telegraphFeedRefreshInterval or #found ~= HZ.lastRenderedCount then
        HZ.lastFeedTime = now
        updateTelegraphFeedUI()
    end

    HZ.lastRenderedCount = #found
end

-- Telegraph picker. Click a part to mark it as a hazard the heuristics missed.
-- Marking learns the part's name AND writes an Attack Book entry (2.4.0), so a
-- hand pick and a trial-run discovery end up in the same place, with the same
-- rename / disable / delete controls. Clicking a marked part undoes both.
--
-- The part clicked is resolved to its underlying identity, which is what a
-- telegraph that only exists for half a second: the identity used is the
-- original's, recorded on the copy when it was made.
local function togglePickedTelegraph(part)
    if not part or not part:IsA("BasePart") then return end

    local originalName, originalParent, isCopy = resolvePickedIdentity(part)
    local partName = string.lower(originalName)
    local now = os.clock()

    local existing = findAttackRecord(part)
    if HZ.learnedNames[partName] or (existing and existing.source == "picked") then
        HZ.manualParts[part] = nil
        HZ.learnedNames[partName] = nil
        for i = #HZ.attackBook, 1, -1 do
            local record = HZ.attackBook[i]
            if record.source == "picked" and record.partName == partName then
                table.remove(HZ.attackBook, i)
            end
        end
        invalidateAttackBook()
        heavyDebug("Picker", string.format(
            "UNMARKED '%s' (parent '%s'). Name unlearned and its Attack Book entry removed.",
            originalName, originalParent ~= "" and originalParent or "Workspace"))
    else
        HZ.learnedNames[partName] = true
        -- A hand pick is the user overruling the own-attack learner.
        HZ.ownNames[partName] = nil
        if not isCopy then
            HZ.manualParts[part] = true
            HZ.ownParts[part] = nil
            HZ.spawnTimes[part] = now
        end

        if not existing then
            local record = partSignature(part)
            record.partName = partName
            record.parentName = string.lower(originalParent)
            record.name = isGenericName(partName)
                and (isGenericName(record.parentName) and string.format("Attack %d", #HZ.attackBook + 1) or originalParent)
                or originalName
            record.hits = 0
            record.damage = 0
            record.melee = false
            record.enabled = true
            record.moving = false
            record.source = "picked"
            record.learnedAt = os.time()
            table.insert(HZ.attackBook, record)
            invalidateAttackBook()
            heavyDebug("Picker", string.format(
                "MARKED '%s' (parent '%s', %s%s). Added to the Attack Book - rename it there, then Save.",
                originalName, originalParent ~= "" and originalParent or "Workspace",
                describeRecord(record), ""))
        else
            heavyDebug("Picker", string.format(
                "MARKED '%s'; it already has the Attack Book entry '%s'.", originalName, existing.name))
        end
    end

    -- Re-classify right away rather than waiting for the round-robin.
    if not isCopy then
        poolAdd(part)
        classifyPoolPart(part, now)
    end
    NAV.forceRescan = true
end

-- Own-attack picker (2.2.0): click one of your own ability effects to mark it,
-- and its name, as ours so it is never treated as a telegraph. Click again to
-- unmark. For anything the automatic timing signal misses.
local function togglePickedOwn(part)
    if not part or not part:IsA("BasePart") then return end

    local originalName, _, isCopy = resolvePickedIdentity(part)
    local partName = string.lower(originalName)
    local now = os.clock()

    if isCopy then
        -- The picked part is something the script CLASSIFIED as an enemy
        -- attack; marking it as ours only needs the name.
        if HZ.ownNames[partName] then
            HZ.ownNames[partName] = nil
            heavyDebug("Picker", string.format("UNMARKED '%s' as our own effect.", originalName))
        else
            HZ.ownNames[partName] = true
            HZ.learnedNames[partName] = nil
            heavyDebug("Picker", string.format(
                "MARKED '%s' as our OWN effect. Saved with the config.", originalName))
        end
        invalidateAttackBook()
        NAV.forceRescan = true
        return
    end

    if HZ.ownNames[partName] or HZ.ownParts[part] then
        HZ.ownNames[partName] = nil
        HZ.ownParts[part] = nil
        heavyDebug("Picker", string.format("UNMARKED '%s' as our own effect. Name forgotten.", part.Name))
    else
        HZ.ownNames[partName] = true
        HZ.ownParts[part] = true
        HZ.manualParts[part] = nil
        HZ.learnedNames[partName] = nil
        heavyDebug("Picker", string.format(
            "MARKED '%s' (parent '%s') as our OWN effect. Name learned; saved with the config.",
            part.Name, part.Parent and part.Parent.Name or "Workspace"))
    end

    poolAdd(part)
    classifyPoolPart(part, now)
    NAV.forceRescan = true
end

-- mode: "telegraph" (default), "own", or "keep" (low-detail keep list).
-- One picker at a time.
local function setTelegraphPickerEnabled(enabled, mode)
    HZ.pickerEnabled = enabled
    HZ.ownPickerEnabled = enabled and mode == "own" or false
    LD.pickerEnabled = enabled and mode == "keep" or false
    ZN.pickerEnabled = enabled and mode == "zone" or false
    if not ZN.pickerEnabled then clearZonePreview() end

    for _, connection in ipairs(HZ.pickerConnections) do
        connection:Disconnect()
    end
    table.clear(HZ.pickerConnections)

    if not enabled then
        clearHoverHighlight()
        return
    end

    HZ.pickerMouse = HZ.pickerMouse or LocalPlayer:GetMouse()

    table.insert(HZ.pickerConnections, HZ.pickerMouse.Move:Connect(function()
        if not HZ.pickerEnabled then return end
        -- While dragging a zone the radius follows the cursor across the world,
        -- measured flat from the decoration you started on.
        if ZN.pickerEnabled and ZN.dragging and ZN.root and ZN.root.Parent then
            local hit = HZ.pickerMouse.Hit
            if hit then
                local offset = hit.Position - ZN.root.Position
                ZN.draftRadius = Vector3.new(offset.X, 0, offset.Z).Magnitude
                updateZonePreview()
            end
            return
        end
        setHoverHighlight(HZ.pickerMouse.Target)
    end))

    if ZN.pickerEnabled then
        table.insert(HZ.pickerConnections, HZ.pickerMouse.Button1Up:Connect(function()
            if not ZN.pickerEnabled or not ZN.dragging then return end
            ZN.dragging = false
            if ZN.root and ZN.root.Parent and ZN.draftRadius >= CFG.zoneMinRadius then
                addZoneDef(ZN.root, ZN.draftShape, ZN.draftRadius, CFG.zoneDefaultHeight)
            else
                heavyDebug("Zone", "Drag was too small to be a zone; nothing added.")
            end
            clearZonePreview()
        end))
    end

    table.insert(HZ.pickerConnections, HZ.pickerMouse.Button1Down:Connect(function()
        if not HZ.pickerEnabled then return end
        local target = HZ.pickerMouse.Target
        if ZN.pickerEnabled then
            -- Point at the decoration that announces the attack, then drag
            -- outwards to size the volume around it.
            if target and target:IsA("BasePart") then
                ZN.root = target
                ZN.dragging = true
                ZN.draftRadius = CFG.zoneDefaultRadius
                updateZonePreview()
                heavyDebug("Zone", string.format(
                    "Root set to '%s'. Drag outwards to size the zone, release to keep it.", target.Name))
            end
        elseif LD.pickerEnabled then
            toggleKeepPart(target)
        elseif HZ.ownPickerEnabled then
            togglePickedOwn(target)
        else
            togglePickedTelegraph(target)
        end
    end))

    heavyDebug("Picker", ZN.pickerEnabled
        and "Picker armed (DRAW ZONE). Press on the decoration that announces the attack, drag outwards, release."
        or (LD.pickerEnabled
        and "Picker armed (KEEP VISIBLE). Click a part to keep or drop its name in low detail."
        or (HZ.ownPickerEnabled
            and "Picker armed (OWN ATTACKS). Click one of your own effects to mark or unmark it."
            or "Picker armed (TELEGRAPH). Click an attack to add it to the Attack Book.")))
end

S.clearHazardHighlights = clearHazardHighlights
S.clearHitboxVisualizer = clearHitboxVisualizer
S.clearHoverHighlight = clearHoverHighlight
S.clearWallHighlights = clearWallHighlights
S.evaluateHazardPenaltyAtPoint = evaluateHazardPenaltyAtPoint
S.flushClassificationCaches = flushClassificationCaches
S.getActiveHazardRepulsionVector = getActiveHazardRepulsionVector
S.getPlayerHitboxMetrics = getPlayerHitboxMetrics
S.isDamageBrick = isDamageBrick
S.isInvisibleWall = isInvisibleWall
S.isPositionSafeFromDamageBricks = isPositionSafeFromDamageBricks
S.scanDamageBricks = scanDamageBricks
S.setTelegraphPickerEnabled = setTelegraphPickerEnabled
S.updateHazardHighlights = updateHazardHighlights
S.updateHitboxVisualizer = updateHitboxVisualizer
S.updateWallHighlights = updateWallHighlights
S.noteOwnAction = noteOwnAction
S.getHazardMotion = getHazardMotion
S.findAttackRecord = findAttackRecord
S.invalidateAttackBook = invalidateAttackBook
S.describeRecord = describeRecord
S.removeAttackRecord = removeAttackRecord
S.clearAttackBook = clearAttackBook
S.setLowDetailEnabled = setLowDetailEnabled
S.refreshLowDetail = refreshLowDetail
S.restoreAllDetail = restoreAllDetail
S.clearKeepList = clearKeepList
S.rebuildCatalogArrays = rebuildCatalogArrays
S.resetWallCatalog = resetWallCatalog
S.startWorldIndex = startWorldIndex
S.stopWorldIndex = stopWorldIndex
S.worldIndexStep = worldIndexStep
S.addZoneDef = addZoneDef
S.removeZoneDef = removeZoneDef
S.serializeZones = serializeZones
S.loadZones = loadZones
S.rebuildZones = rebuildZones
S.clearZones = clearZones
S.clearZonePreview = clearZonePreview
-- The game fires abilityCast / abilityUsed when WE use an ability (3.0.0).
-- That is a far better signal than watching our animations: it is exact, it
-- fires before the effect spawns, and it cannot be confused by an enemy
-- playing a similar animation.
local function watchOwnAbilityRemotes()
    local remotes = S.ReplicatedStorage:FindFirstChild("remotes")
    if not remotes then return false end
    local hooked = 0
    for _, name in ipairs({ "abilityCast", "abilityUsed" }) do
        local remote = remotes:FindFirstChild(name)
        if remote and remote:IsA("RemoteEvent") then
            table.insert(RT.indexConnections, remote.OnClientEvent:Connect(function()
                RT.lastOwnActionTime = os.clock()
            end))
            hooked = hooked + 1
        end
    end
    if hooked > 0 then
        heavyDebug("Own", string.format(
            "Watching %d of the game's own ability remotes; our casts are now known exactly, not guessed from animations.",
            hooked))
    end
    return hooked > 0
end

S.watchOwnAbilityRemotes = watchOwnAbilityRemotes
S.collectSafeZones = collectSafeZones
S.safeZonePenalty = safeZonePenalty
end
