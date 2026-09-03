-- tools.lua - The Attacks panel's tools: the pickers (add an attack by
-- clicking it, mark your own effects, keep parts visible, draw a zone), the
-- Attack Book helpers, the hand-drawn zones, low detail, and the capture
-- file - the same report the standalone probe writes, from the reader's own
-- records.
return function(S)
local CFG = S.CFG
local RT = S.RT
local HZ = S.HZ
local LD = S.LD
local ZN = S.ZN
local Workspace = S.Workspace
local LocalPlayer = S.LocalPlayer
local heavyDebug = S.heavyDebug
local getVisualRoot = S.getVisualRoot
local addZoneRecord = S.addZoneRecord
local removeZoneRecords = S.removeZoneRecords
local invalidateAttackBook = S.invalidateAttackBook
local attackWindow = S.attackWindow

local V3 = Vector3.new
local clock = os.clock
local fmt = string.format

-- ------------------------------------------------------------------ the book
local function describeRecord(record)
    local st = HZ.stats[string.lower(record.name or "")]
    local parts = {}
    if st then
        parts[#parts + 1] = fmt("%d seen", st.n)
        if st.flashN > 0 then parts[#parts + 1] = fmt("flash %.2fs", st.flashSum / st.flashN) end
    end
    local T = S.FLASH_TIMES and S.FLASH_TIMES[string.lower(record.name or "")]
    if T then parts[#parts + 1] = fmt("table %.2fs", T) end
    if #parts == 0 then return "not seen yet" end
    return table.concat(parts, ", ")
end
local function removeAttackRecord(index)
    local r = table.remove(HZ.attackBook, index)
    if not r then return end
    invalidateAttackBook()
    if S.refreshAttackBookPanel then S.refreshAttackBookPanel() end
end
local function clearAttackBook()
    HZ.attackBook = {}
    invalidateAttackBook()
    if S.refreshAttackBookPanel then S.refreshAttackBookPanel() end
end

-- ------------------------------------------------------------------ zones
local function serializeZones()
    local out = {}
    for _, def in ipairs(ZN.defs) do
        out[#out + 1] = { name = def.name, parentName = def.parentName, shape = def.shape, radius = def.radius, height = def.height }
    end
    return out
end
local function rebuildZones()
    removeZoneRecords()
    if #ZN.defs == 0 then return end
    local map = Workspace:FindFirstChild("Map") or Workspace
    local count = 0
    for _, def in ipairs(ZN.defs) do
        for _, inst in ipairs(map:GetDescendants()) do
            if inst:IsA("BasePart") and inst.Name == def.name
                and (def.parentName == "" or (inst.Parent and inst.Parent.Name == def.parentName)) then
                addZoneRecord(inst, def.shape, def.radius, "zone " .. def.name)
                count = count + 1
                if count > 200 then break end
            end
        end
    end
    heavyDebug("Zone", fmt("%d zone volume(s) live from %d definition(s).", count, #ZN.defs))
end
local function loadZones(list)
    ZN.defs = {}
    if type(list) == "table" then
        for _, z in ipairs(list) do
            if type(z) == "table" and type(z.name) == "string" then
                ZN.defs[#ZN.defs + 1] = { name = z.name, parentName = tostring(z.parentName or ""), shape = z.shape == "square" and "square" or "circle",
                    radius = tonumber(z.radius) or CFG.zoneDefaultRadius, height = tonumber(z.height) or CFG.zoneDefaultHeight }
            end
        end
    end
    rebuildZones()
    if S.refreshZonePanel then S.refreshZonePanel() end
    return #ZN.defs
end
local function addZoneDef(part, shape, radius, height)
    radius = math.max(CFG.zoneMinRadius, math.min(CFG.zoneMaxRadius, radius or CFG.zoneDefaultRadius))
    ZN.defs[#ZN.defs + 1] = { name = part.Name, parentName = part.Parent and part.Parent.Name or "", shape = shape or "circle", radius = radius, height = height or CFG.zoneDefaultHeight }
    rebuildZones()
    if S.refreshZonePanel then S.refreshZonePanel() end
end
local function removeZoneDef(index)
    if table.remove(ZN.defs, index) then
        rebuildZones()
        if S.refreshZonePanel then S.refreshZonePanel() end
    end
end
local preview
local function clearZonePreview()
    if preview then preview:Destroy() preview = nil end
    ZN.dragging = false
    ZN.root = nil
end
local function updateZonePreview()
    if not ZN.root or not ZN.root.Parent then return end
    if not preview then
        preview = Instance.new("Part")
        preview.Name = "ZonePreview"
        preview.Anchored = true
        preview.CanCollide = false
        preview.CanQuery = false
        preview.Material = Enum.Material.Neon
        preview.Color = CFG.colorTelegraphPending
        preview.Transparency = 0.6
        preview.Parent = getVisualRoot()
    end
    local r = ZN.draftRadius
    if ZN.draftShape == "circle" then
        preview.Shape = Enum.PartType.Cylinder
        preview.Size = V3(0.5, r * 2, r * 2)
        preview.CFrame = CFrame.new(ZN.root.Position) * CFrame.Angles(0, 0, math.rad(90))
    else
        preview.Shape = Enum.PartType.Block
        preview.Size = V3(r * 2, 0.5, r * 2)
        preview.CFrame = CFrame.new(ZN.root.Position)
    end
end

-- ------------------------------------------------------------------ pickers
local hover
local function clearHoverHighlight()
    if hover then hover:Destroy() hover = nil end
end
local function setHoverHighlight(target)
    if not target or not target:IsA("BasePart") then clearHoverHighlight() return end
    if not hover then
        hover = Instance.new("SelectionBox")
        hover.Name = "PickerHover"
        hover.LineThickness = 0.04
        hover.Color3 = CFG.accentColor
        hover.Parent = getVisualRoot()
    end
    hover.Adornee = target
end
local function attackNameOf(part)
    local node = part
    for _ = 1, 3 do
        if node:IsA("Model") then return node.Name end
        node = node.Parent
        if not node or node == Workspace then break end
    end
    return part.Name
end
local function togglePickedTelegraph(target)
    if not target or not target:IsA("BasePart") then return end
    local name = attackNameOf(target)
    local key = string.lower(name)
    if HZ.learnedNames[key] then
        HZ.learnedNames[key] = nil
        heavyDebug("Picker", "Forgot '" .. name .. "'.")
    else
        HZ.learnedNames[key] = true
        if not HZ.bookByName[key] then
            HZ.attackBook[#HZ.attackBook + 1] = { name = name, enabled = true, hits = 0, damage = 0 }
            invalidateAttackBook()
        end
        heavyDebug("Picker", "Added '" .. name .. "' to the book; parts of that name are tracked as attacks.")
    end
    if S.refreshNameLists then S.refreshNameLists() end
    if S.refreshAttackBookPanel then S.refreshAttackBookPanel() end
end
local function togglePickedOwn(target)
    if not target or not target:IsA("BasePart") then return end
    local key = string.lower(attackNameOf(target))
    HZ.ownNames[key] = not HZ.ownNames[key] or nil
    heavyDebug("Picker", (HZ.ownNames[key] and "Marked '" or "Unmarked '") .. key .. "' as our own effect.")
    if S.refreshNameLists then S.refreshNameLists() end
end
local function toggleKeepPart(target)
    if not target or not target:IsA("BasePart") then return end
    local name = target.Name
    LD.keepNames[name] = not LD.keepNames[name] or nil
    if S.refreshLowDetail then S.refreshLowDetail() end
    if S.refreshMapPanel then S.refreshMapPanel() end
end

local function setTelegraphPickerEnabled(enabled, mode)
    HZ.pickerEnabled = enabled and true or false
    HZ.ownPickerEnabled = enabled and mode == "own" or false
    LD.pickerEnabled = enabled and mode == "keep" or false
    ZN.pickerEnabled = enabled and mode == "zone" or false
    if not ZN.pickerEnabled then clearZonePreview() end
    for _, c in ipairs(HZ.pickerConnections) do c:Disconnect() end
    HZ.pickerConnections = {}
    if not enabled then clearHoverHighlight() return end
    HZ.pickerMouse = HZ.pickerMouse or LocalPlayer:GetMouse()
    local mouse = HZ.pickerMouse
    table.insert(HZ.pickerConnections, mouse.Move:Connect(function()
        if not HZ.pickerEnabled then return end
        if ZN.pickerEnabled and ZN.dragging and ZN.root and ZN.root.Parent then
            local hit = mouse.Hit
            if hit then
                local offset = hit.Position - ZN.root.Position
                ZN.draftRadius = math.max(CFG.zoneMinRadius, V3(offset.X, 0, offset.Z).Magnitude)
                updateZonePreview()
            end
            return
        end
        setHoverHighlight(mouse.Target)
    end))
    if ZN.pickerEnabled then
        table.insert(HZ.pickerConnections, mouse.Button1Up:Connect(function()
            if not ZN.dragging then return end
            ZN.dragging = false
            if ZN.root and ZN.root.Parent and ZN.draftRadius >= CFG.zoneMinRadius then
                addZoneDef(ZN.root, ZN.draftShape, ZN.draftRadius, CFG.zoneDefaultHeight)
            end
            clearZonePreview()
        end))
    end
    table.insert(HZ.pickerConnections, mouse.Button1Down:Connect(function()
        if not HZ.pickerEnabled then return end
        local target = mouse.Target
        if ZN.pickerEnabled then
            if target and target:IsA("BasePart") then
                ZN.root = target
                ZN.dragging = true
                ZN.draftRadius = CFG.zoneDefaultRadius
                updateZonePreview()
            end
        elseif LD.pickerEnabled then toggleKeepPart(target)
        elseif HZ.ownPickerEnabled then togglePickedOwn(target)
        else togglePickedTelegraph(target) end
    end))
    heavyDebug("Picker", "Picker armed (" .. tostring(mode or "telegraph") .. ").")
end

-- ------------------------------------------------------------------ low detail
local sweepList, sweepCursor
local function restoreAllDetail()
    for part, t in pairs(LD.hidden) do
        pcall(function() part.LocalTransparencyModifier = t end)
    end
    LD.hidden = {}
    for effect in pairs(LD.disabledEffects) do
        pcall(function() effect.Enabled = true end)
    end
    LD.disabledEffects = {}
end
local function refreshLowDetail()
    if not LD.enabled then return end
    local map = Workspace:FindFirstChild("Map")
    sweepList = map and map:GetDescendants() or {}
    sweepCursor = 1
    LD.sweeping = true
end
local function setLowDetailEnabled(enabled)
    LD.enabled = enabled and true or false
    if LD.enabled then
        refreshLowDetail()
    else
        LD.sweeping = false
        restoreAllDetail()
    end
end
local function clearKeepList()
    LD.keepNames = {}
    if LD.enabled then restoreAllDetail() refreshLowDetail() end
    if S.refreshMapPanel then S.refreshMapPanel() end
end
local function lowDetailStep()
    if not LD.enabled or not LD.sweeping or not sweepList then return end
    local budget = CFG.lowDetailBudget
    while budget > 0 do
        local inst = sweepList[sweepCursor]
        if not inst then LD.sweeping = false return end
        sweepCursor = sweepCursor + 1
        budget = budget - 1
        if inst:IsA("BasePart") then
            if LD.keepNames[inst.Name] then
                if LD.hidden[inst] then
                    pcall(function() inst.LocalTransparencyModifier = LD.hidden[inst] end)
                    LD.hidden[inst] = nil
                end
            elseif not LD.hidden[inst] then
                LD.hidden[inst] = inst.LocalTransparencyModifier
                pcall(function() inst.LocalTransparencyModifier = 1 end)
            end
        elseif CFG.lowDetailKillEffects and (inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")) then
            if inst.Enabled and not LD.disabledEffects[inst] then
                LD.disabledEffects[inst] = true
                pcall(function() inst.Enabled = false end)
            end
        end
    end
end

-- ------------------------------------------------------------------ the capture
local function clearAttackLog()
    HZ.finished = {}
    HZ.hitLog = {}
    HZ.stats = {}
    HZ.captureStart = clock()
end
local function recLine(rec)
    local now = clock()
    local spans = table.concat(rec.spans or {}, " ")
    if rec.inside then spans = spans .. (spans ~= "" and " " or "") .. fmt("%.2f-now", rec.insideAt - rec.spawn) end
    return fmt("%-26s @%7.1f %s dist=? size=%s tr0=%s vis@%s flash@%s fade@%s rm@%s T=%s trace=[%s] inside=[%s]",
        rec.name, rec.spawn - (HZ.captureStart or 0), rec.pre and "*" or " ", rec.sizeText or "?",
        rec.trace and rec.trace[1] or "-",
        rec.visAt and fmt("%.2f", rec.visAt - rec.spawn) or "-",
        rec.flashAt and fmt("%.2f", rec.flashAt - rec.spawn) or "-",
        rec.fadeAt and fmt("%.2f", rec.fadeAt - rec.spawn) or "-",
        rec.removed and fmt("%.2f", rec.removed - rec.spawn) or "live",
        rec.flashTime and fmt("%.2f", rec.flashTime) or "-",
        table.concat(rec.trace or {}, " "), spans)
end
local function buildAttackLog()
    local out = {}
    local function w(s) out[#out + 1] = s end
    local map = Workspace:FindFirstChild("dungeonName")
    w(fmt("DungeonAutofarm %s attack capture  map=%s  %s  recording=%s", S.SCRIPT_VERSION, map and map.Value or RT.currentMap, os.date("%Y-%m-%d %H:%M:%S"), tostring(CFG.diagnoseAttacks)))
    w("SUMMARY by name - n seen; measured flash age (mean); inside@age=s: seconds the root spent inside at that age (0.25 s buckets); HIT@age=n: hits while inside")
    local names = {}
    for name in pairs(HZ.stats) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local st = HZ.stats[name]
        local ins, hs, totalIn, totalHits = {}, {}, 0, 0
        for b = 0, 48 do
            if st.inside[b] then ins[#ins + 1] = fmt("%.2f=%.1f", b * 0.25, st.inside[b]) totalIn = totalIn + st.inside[b] end
            if st.hits[b] then hs[#hs + 1] = fmt("%.2f=%d", b * 0.25, st.hits[b]) totalHits = totalHits + st.hits[b] end
        end
        w(fmt("%-28s n=%-4d flash=%s  inside %.1fs [%s]  HITS %d [%s]", name, st.n,
            st.flashN > 0 and fmt("%.2f (%d)", st.flashSum / st.flashN, st.flashN) or "-", totalIn, table.concat(ins, " "), totalHits, table.concat(hs, " ")))
    end
    w("")
    w("HITS")
    for _, line in ipairs(HZ.hitLog) do w(line) end
    w("")
    w("ATTACKS (ended, then live) - spawn age, size, first transparency, first visible, flash, fade, removal, table time, trace=[age:transparency], inside=[spans]")
    for _, rec in ipairs(HZ.finished) do w(recLine(rec)) end
    for _, rec in ipairs(HZ.attacks) do if rec.kind ~= "pred" then w(recLine(rec)) end end
    w("")
    w("EVENTS (projectile-shaped boss events)")
    for _, ev in ipairs(S.readerEvents) do
        w(fmt("%s dist=%.0f dur=%.2f start%+.2f end%+.2f origin=(%.0f,%.0f,%.0f)", ev.name, ev.dist, ev.dur,
            ev.start - S.gameTime(ev.at), ev.stop - S.gameTime(ev.at), ev.origin.X, ev.origin.Y, ev.origin.Z))
    end
    return table.concat(out, "\n")
end
local function saveAttackLog()
    if type(writefile) ~= "function" then return false, "no file access in this executor" end
    local ok, err = pcall(function() writefile(CFG.diagnoseFile, buildAttackLog()) end)
    if ok then heavyDebug("Capture", "Wrote " .. CFG.diagnoseFile) return true end
    return false, tostring(err)
end

S.describeRecord = describeRecord
S.removeAttackRecord = removeAttackRecord
S.clearAttackBook = clearAttackBook
S.serializeZones = serializeZones
S.loadZones = loadZones
S.rebuildZones = rebuildZones
S.addZoneDef = addZoneDef
S.removeZoneDef = removeZoneDef
S.clearZonePreview = clearZonePreview
S.clearHoverHighlight = clearHoverHighlight
S.setTelegraphPickerEnabled = setTelegraphPickerEnabled
S.setLowDetailEnabled = setLowDetailEnabled
S.refreshLowDetail = refreshLowDetail
S.restoreAllDetail = restoreAllDetail
S.clearKeepList = clearKeepList
S.lowDetailStep = lowDetailStep
S.saveAttackLog = saveAttackLog
S.clearAttackLog = clearAttackLog
S.buildAttackLog = buildAttackLog
end
