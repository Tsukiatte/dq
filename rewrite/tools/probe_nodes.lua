-- probe_nodes.lua: what the safety nodes are actually seeing, and whether anything they refuse is real.
--
-- Twice a second it takes the live candidate ring and every hazard box, works out which box is refusing each
-- refused node, and audits every tracked thing for whether its object still exists in the world. Anything whose
-- window is open while its part or model has left the world is an orphan: a node reacting to something that is not
-- there. Prints only when something is wrong, writes dq_nodes.json for the whole picture.
local Players, Workspace = game:GetService("Players"), game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local lp = Players.LocalPlayer
if _G.DQNodes and _G.DQNodes.stop then pcall(_G.DQNodes.stop) end
local N = { started = os.clock(), samples = {}, orphans = {}, why = {}, stopped = false }
_G.DQNodes = N
local function r1(v) return math.floor(v * 10 + 0.5) / 10 end

-- Signed depth, positive inside the box. Kept local so the probe does not depend on the bundle's internals.
local function depth(b, x, z, t)
    t = t or 0
    if b.moving then
        local along = b.offset + b.speed * math.max(os.clock() + t - b.pathStart, 0)
        local qx, qz = x - (b.ox + b.dx * along), z - (b.oz + b.dz * along)
        local a = math.abs(qx * b.dx + qz * b.dz) - b.halfL
        local s = math.abs(-qx * b.dz + qz * b.dx) - b.halfW
        if a <= 0 and s <= 0 then return -math.max(a, s) end
        return -math.sqrt(math.max(a, 0) ^ 2 + math.max(s, 0) ^ 2)
    end
    if b.r then
        local d = b.r - math.sqrt((x - b.cx) ^ 2 + (z - b.cz) ^ 2)
        if b.ring then
            local qx, qz = x - b.cx, z - b.cz
            if qx * (b.sx or 0) + qz * (b.sz or 0) < 0 then return -999 end
            d = math.min(d, math.sqrt(qx * qx + qz * qz) - b.ring)
        end
        return d
    end
    if not b.ax then return -999 end
    local qx, qz = x - b.cx, z - b.cz
    local oa = math.abs(qx * b.ax + qz * b.az) - b.ha
    local ob = math.abs(qx * b.bx + qz * b.bz) - b.hb
    if oa <= 0 and ob <= 0 then return -math.max(oa, ob) end
    return -math.sqrt(math.max(oa, 0) ^ 2 + math.max(ob, 0) ^ 2)
end

-- Everything the reader is tracking, checked against the world it came from.
local function audit(S, now)
    local live, gone, list = 0, {}, {}
    local function note(kind, name, inst, from, untilAt)
        local open = now >= (from or 0) and now <= (untilAt or 0)
        if not open then return end
        live = live + 1
        local there = inst ~= nil and inst.Parent ~= nil
        if not there then
            gone[#gone + 1] = string.format("%s %s (window has %.1f s left)", kind, name, (untilAt or now) - now)
            list[#list + 1] = { kind = kind, name = name, left = r1((untilAt or now) - now) }
        end
    end
    for model, r in pairs(S.RD.models or {}) do
        note("model", r.name or model.Name, (r.hb and r.hb.Parent and r.hb) or (r.pc and r.pc.Parent and r.pc) or model, r.from, r.long and (now + 1) or r.untilAt)
    end
    for part, r in pairs(S.RD.parts or {}) do
        note("part", (r.box and r.box.name) or part.Name, part, r.from, r.untilAt)
    end
    for _, z in ipairs(S.RD.zones or {}) do
        if z.model then note("zone", z.name or "?", z.model, z.from, z.untilAt) end
    end
    return live, gone, list
end

task.spawn(function()
    while _G.DQNodes == N and not N.stopped do
        task.wait(0.5)
        local S = _G.DungeonAutofarmState
        local c = lp.Character
        local rt = c and c:FindFirstChild("HumanoidRootPart")
        if S and rt and S.DG and S.DG.cands then
            local now, rp = os.clock(), rt.Position
            local boxes = S.hazards(now)
            local cands = S.DG.cands
            local refused, blame, total, usable, warm, blameBox = 0, {}, #cands, 0, 0, {}
            for _, cd in ipairs(cands) do
                if (cd.danger or 0) < 0.999 and (cd.endDanger or 0) < 0.999 then
                    usable = usable + 1                                   -- nothing lethal on the way there or when we arrive
                    if (cd.danger or 0) > 0.2 or (cd.endDanger or 0) > 0.2 then warm = warm + 1 end
                end
                if (cd.danger or 0) >= 0.999 or (cd.endDanger or 0) >= 0.999 then
                    refused = refused + 1
                    local x, z = rp.X + cd.ox, rp.Z + cd.oz
                    local arrive = (cd.dist or 0) / 22   -- a node is refused for what is there when we get there
                    local who, best, when = nil, -1e9, ""
                    for _, b in ipairs(boxes) do
                        if not b.weight then                      -- warm boxes cost, they do not refuse
                            for _, t in ipairs({ 0, arrive }) do
                                local openAt = now + t
                                if openAt >= (b.from or 0) - 0.05 and openAt <= (b.untilAt or 0) + 0.05 then
                                    local d = depth(b, x, z, t)
                                    if d > best then best, who, when = d, b, (t > 0.05 and " on arrival" or "") end
                                end
                            end
                        end
                    end
                    if who and best >= -2 then
                        local key = (who.name or "?") .. when
                        blame[key] = (blame[key] or 0) + 1
                        blameBox[key] = who
                    else
                        blame["(nothing covers it: check the walk, not the spot)"] = (blame["(nothing covers it: check the walk, not the spot)"] or 0) + 1
                    end
                end
            end
            local liveN, gone, goneList = audit(S, now)
            local top, topN = nil, 0
            for k, v in pairs(blame) do if v > topN then top, topN = k, v end end
            local st = S.DG.evalStats or {}
            local e = { t = r1(now - N.started), nodes = total, refused = refused, usable = usable, warm = warm, valid = st.valid, noFloor = st.noFloor,
                notWalkable = st.notWalkable, boxes = #boxes, tracked = liveN, top = top, topN = topN, orphans = #gone }
            N.samples[#N.samples + 1] = e
            if #N.samples > 400 then table.remove(N.samples, 1) end
            if #gone > 0 then
                for _, g in ipairs(goneList) do N.orphans[#N.orphans + 1] = { t = e.t, what = g } end
                while #N.orphans > 200 do table.remove(N.orphans, 1) end
                warn(string.format("[DQ nodes] %d live box(es) whose object is GONE: %s", #gone, table.concat(gone, "; ", 1, math.min(#gone, 3))))
            end
            -- The line Chris wants when the ring goes solid red: what refused it, and whether anything was left at all.
            -- Nearly solid: say what each refusing box IS right now. A window that opened long ago on a part that no
            -- longer exists is a phantom; a window that has not opened yet is a prediction; a live one is real.
            if total > 0 and usable <= 10 then
                local lines = {}
                for key, cnt in pairs(blame) do
                    local b = blameBox[key]
                    if b and cnt >= 3 then
                        local opened, closes = now - (b.from or 0), (b.untilAt or 0) - now
                        local src = b.model or b.part or b.hb or b.pc
                        local there = src == nil and "no source recorded" or (src.Parent and "source present" or "SOURCE GONE")
                        lines[#lines + 1] = string.format("%s: %d nodes, opened %+.1fs ago, closes in %.1fs, %s%s", key, cnt, opened, closes, there,
                            (src and src.Parent and src:IsA("BasePart") and (" tr" .. string.format("%.2f", src.Transparency))) or "")
                    end
                end
                table.sort(lines)
                if #lines > 0 then
                    N.why[#N.why + 1] = { t = r1(now - N.started), usable = usable, lines = lines }
                    while #N.why > 60 do table.remove(N.why, 1) end
                    if now - (N.lastWhy or 0) > 4 then N.lastWhy = now warn("[DQ nodes why] usable " .. usable .. " | " .. table.concat(lines, " || ")) end
                end
            end
            if total > 0 and usable == 0 then
                warn(string.format("[DQ nodes] EVERY node refused (%d of %d), most by %s (%d) | %d boxes live, %d tracked, %d no floor, %d unwalkable",
                    refused, total, tostring(top), topN, #boxes, liveN, st.noFloor or -1, st.notWalkable or -1))
            elseif total > 0 and usable <= 3 then
                warn(string.format("[DQ nodes] only %d of %d nodes left (%d of them warm), most refused by %s (%d)", usable, total, warm, tostring(top), topN))
            end
            if (e.t % 10) < 0.5 then pcall(writefile, "dq_nodes.json", HttpService:JSONEncode({ samples = N.samples, orphans = N.orphans, why = N.why })) end
        end
    end
end)
function N.stop() N.stopped = true end
return { ok = true, note = "node probe running: prints when a node refuses something that is not there, or when nothing is usable" }
