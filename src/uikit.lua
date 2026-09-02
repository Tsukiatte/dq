-- uikit.lua - The widget kit. Every panel in the script is built from these.
-- Module contract: receives the shared table S. Everything this module needs from
-- earlier modules is pulled into locals below; everything later modules need is
-- assigned onto S at the bottom. Load order is fixed by main.lua / build.py.
return function(S)
local RT = S.RT
local CFG = S.CFG
local LocalPlayer = S.LocalPlayer
local UserInputService = S.UserInputService
local RunService = S.RunService

-- =========================================================================
-- THE KIT
--
-- A faithful port of the Figma kit (file z7K7RSX8F911V8r4Q01nSU). Every number
-- here - colour, radius, gap, font size - comes from that file's variables, so
-- the two stay comparable. Three rules carried over from the design notes:
--
--   * No image assets. Chevrons, the tick, the pencil and the bin are all
--     built from Frames, so there is nothing that can fail to load.
--   * The accent gradient is defined once (Theme.AccentA/Mid/B). Every window,
--     button, toggle and slider fill reads it from here.
--   * Roblox has no box-shadow, so panel elevation is stacked Frames behind
--     the panel at low alpha. Also no asset, and it matches the design's
--     0 14px 34px rgba(0,0,0,.45) closely enough at these sizes.
-- =========================================================================

local Theme = {
    TextPrimary  = Color3.fromHex("f0f0f4"),
    TextSub      = Color3.fromHex("9898a2"),
    TextMuted    = Color3.fromHex("686872"),
    TextOnAccent = Color3.fromHex("1c1606"),
    StatusBad    = Color3.fromHex("ff6060"),
    StatusGood   = Color3.fromHex("5ce08a"),

    SurfaceHeader  = Color3.fromHex("18181c"),
    SurfaceElement = Color3.fromHex("26262c"),
    SurfaceHover   = Color3.fromHex("303038"),
    SurfaceField   = Color3.fromHex("1c1c21"),
    SurfaceChip    = Color3.fromHex("0c0c0f"),
    Hairline       = Color3.fromHex("323338"),

    -- Window body: a 3-stop vertical fade with per-stop alpha.
    BodyTop = Color3.fromHex("2a2a2f"), BodyMid = Color3.fromHex("1a1a1e"), BodyBot = Color3.fromHex("101013"),
    BodyTopA = 0.05, BodyMidA = 0.13, BodyBotA = 0.42,

    AccentA   = Color3.fromHex("ff841a"),
    AccentMid = Color3.fromHex("ffb626"),
    AccentB   = Color3.fromHex("ffec52"),

    RadiusSm = 5, RadiusMd = 6, RadiusLg = 8,
    GapSm = 6, GapMd = 8, GapLg = 12, GapXl = 14,
    RowH = 34, HeaderH = 40,
}

-- Montserrat and Roboto Mono, per the design. FontFace carries a real weight;
-- the Enum fallback is for any client where the family will not resolve.
local FONT_FAMILY = {
    sans = "rbxasset://fonts/families/Montserrat.json",
    mono = "rbxasset://fonts/families/RobotoMono.json",
}
local FALLBACK = {
    [Enum.FontWeight.Regular] = Enum.Font.Gotham,
    [Enum.FontWeight.Medium] = Enum.Font.GothamMedium,
    [Enum.FontWeight.SemiBold] = Enum.Font.GothamBold,
    [Enum.FontWeight.Bold] = Enum.Font.GothamBold,
}

local function setFont(label, family, weight)
    local ok = pcall(function()
        label.FontFace = Font.new(FONT_FAMILY[family], weight)
    end)
    if not ok then
        label.Font = FALLBACK[weight] or Enum.Font.Gotham
    end
end

-- The named text styles from the Figma file, so a call site says what a piece
-- of text IS rather than restating three properties.
local STYLES = {
    windowTitle = { family = "sans", weight = Enum.FontWeight.SemiBold, size = 15, color = "TextPrimary" },
    windowChip  = { family = "sans", weight = Enum.FontWeight.Bold,     size = 15, color = "TextPrimary" },
    rowLabel    = { family = "sans", weight = Enum.FontWeight.Medium,   size = 13, color = "TextPrimary" },
    rowButton   = { family = "sans", weight = Enum.FontWeight.SemiBold, size = 13, color = "TextOnAccent" },
    rowEntry    = { family = "sans", weight = Enum.FontWeight.SemiBold, size = 13, color = "TextPrimary" },
    rowStat     = { family = "sans", weight = Enum.FontWeight.Medium,   size = 14, color = "TextPrimary" },
    captionKey  = { family = "sans", weight = Enum.FontWeight.Medium,   size = 12, color = "TextSub" },
    captionSub  = { family = "sans", weight = Enum.FontWeight.Regular,  size = 10, color = "TextMuted" },
    captionStat = { family = "sans", weight = Enum.FontWeight.Bold,     size = 12, color = "TextSub" },
    monoValue   = { family = "mono", weight = Enum.FontWeight.Medium,   size = 11, color = "TextOnAccent" },
    monoMeta    = { family = "mono", weight = Enum.FontWeight.Medium,   size = 10, color = "TextMuted" },
    monoStat    = { family = "mono", weight = Enum.FontWeight.Medium,   size = 13, color = "TextSub" },
}

local function corner(instance, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = instance
    return c
end

local function stroke(instance, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or Theme.Hairline
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = instance
    return s
end

local function pad(instance, top, right, bottom, left)
    local p = Instance.new("UIPadding")
    p.PaddingTop = UDim.new(0, top)
    p.PaddingRight = UDim.new(0, right)
    p.PaddingBottom = UDim.new(0, bottom)
    p.PaddingLeft = UDim.new(0, left)
    p.Parent = instance
    return p
end

local function vlist(instance, gap, order)
    local l = Instance.new("UIListLayout")
    l.FillDirection = Enum.FillDirection.Vertical
    l.Padding = UDim.new(0, gap or Theme.GapSm)
    l.SortOrder = order or Enum.SortOrder.LayoutOrder
    l.Parent = instance
    return l
end

-- Let a child eat the slack in a horizontal list: `reserve` is the width its
-- siblings and the gaps between them take up.
--
-- This used to add a UIFlexItem in Fill mode, and that is what made every row
-- label render blank in 2.7.0. Flex GROWS an item from its base size, and the
-- labels had a base width of 100% - so the pass had negative slack to hand out
-- and collapsed them to nothing. The buttons were fine because their base width
-- was already 0. Explicit arithmetic is one line, needs no guessing about how
-- flex distributes, and cannot fail silently: a wrong `reserve` gives a label
-- that is slightly the wrong width, not an invisible one.
local function flexFill(instance, reserve, heightScale, heightOffset)
    if not reserve then return false end
    -- Height is passed in rather than read back off the instance: every caller
    -- wants full height, and reading Size just to rebuild it was one more thing
    -- to get wrong.
    instance.Size = UDim2.new(1, -reserve, heightScale or 1, heightOffset or 0)
    return true
end

local function hlist(instance, gap)
    local l = Instance.new("UIListLayout")
    l.FillDirection = Enum.FillDirection.Horizontal
    l.VerticalAlignment = Enum.VerticalAlignment.Center
    l.Padding = UDim.new(0, gap or Theme.GapMd)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Parent = instance
    return l
end

local function label(parent, text, style, order)
    local st = STYLES[style] or STYLES.rowLabel
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = text or ""
    l.TextColor3 = Theme[st.color]
    l.TextSize = st.size
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.LayoutOrder = order or 1
    l.Size = UDim2.new(1, 0, 1, 0)
    setFont(l, st.family, st.weight)
    l.Parent = parent
    return l
end

-- The accent gradient, in one place. `rotation` 0 is left-to-right.
local function accentGradient(instance, rotation)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.AccentA),
        ColorSequenceKeypoint.new(0.5, Theme.AccentMid),
        ColorSequenceKeypoint.new(1, Theme.AccentB),
    })
    g.Rotation = rotation or 0
    g.Parent = instance
    return g
end

-- The window body fade: colour and alpha together, as one UIGradient.
local function bodyGradient(instance)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.BodyTop),
        ColorSequenceKeypoint.new(0.45, Theme.BodyMid),
        ColorSequenceKeypoint.new(1, Theme.BodyBot),
    })
    g.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, Theme.BodyTopA),
        NumberSequenceKeypoint.new(0.45, Theme.BodyMidA),
        NumberSequenceKeypoint.new(1, Theme.BodyBotA),
    })
    g.Rotation = 90
    g.Parent = instance
    return g
end

-- Elevation. Roblox has no box-shadow and the kit takes no image assets, so a
-- soft edge is approximated with N frames behind the panel, each a little
-- larger and pushed a little further down, all at low alpha. Eight at 0.07
-- accumulate to about 0.44 in the middle, which is the design's 0.45.
local function shadow(frame, layers, step, drop, alpha, radius)
    layers = layers or 8
    step = step or 2.2
    drop = drop or 14
    alpha = alpha or 0.07
    radius = radius or Theme.RadiusLg
    local holder = Instance.new("Frame")
    holder.Name = "Shadow"
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.fromScale(1, 1)
    holder.ZIndex = frame.ZIndex - 1
    holder.Parent = frame

    for i = 1, layers do
        local spread = i * step
        local offset = drop * (i / layers)
        local layer = Instance.new("Frame")
        layer.Name = "L" .. i
        layer.BackgroundColor3 = Color3.new(0, 0, 0)
        layer.BackgroundTransparency = 1 - alpha
        layer.BorderSizePixel = 0
        layer.ZIndex = frame.ZIndex - 1
        layer.Position = UDim2.fromOffset(-spread, -spread + offset)
        layer.Size = UDim2.new(1, spread * 2, 1, spread * 2)
        corner(layer, radius + spread)
        layer.Parent = holder
    end
    return holder
end

-- =========================================================================
-- Tooltip: one shared box, shown after a second of hovering, following the
-- mouse. Everything with an explanation registers through `tip`.
-- =========================================================================
local Tip = { frame = nil, label = nil, target = nil, showAt = nil, conn = nil }

local function ensureTip(screenGui)
    if Tip.frame and Tip.frame.Parent then return end
    local f = Instance.new("Frame")
    f.Name = "Tooltip"
    f.BackgroundColor3 = Color3.fromHex("3a3a42")
    f.BorderSizePixel = 0
    f.Visible = false
    f.ZIndex = 500
    f.AutomaticSize = Enum.AutomaticSize.XY
    f.Size = UDim2.fromOffset(0, 0)
    f.Parent = screenGui
    corner(f, Theme.RadiusSm)
    stroke(f, Color3.fromHex("4a4a55"), 1)
    pad(f, 6, 8, 6, 8)

    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.AutomaticSize = Enum.AutomaticSize.XY
    l.Size = UDim2.fromOffset(0, 0)
    l.TextWrapped = true
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Top
    l.TextColor3 = Color3.fromHex("e8e8ee")
    l.TextSize = 11
    l.ZIndex = 501
    setFont(l, "sans", Enum.FontWeight.Medium)
    l.Parent = f

    -- AutomaticSize with wrapping needs an upper bound or a long line runs off
    -- the screen; 240px matches the design's tooltip.
    local size = Instance.new("UISizeConstraint")
    size.MaxSize = Vector2.new(240, math.huge)
    size.Parent = l

    Tip.frame, Tip.label = f, l

    -- One clock for every tooltip: the delay, and the follow.
    if Tip.conn then Tip.conn:Disconnect() end
    Tip.conn = RunService.RenderStepped:Connect(function()
        if not Tip.target then return end
        local now = os.clock()
        if not Tip.frame.Visible then
            if now < Tip.showAt then return end
            Tip.frame.Visible = true
        end
        local m = UserInputService:GetMouseLocation()
        local camera = workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
        local w, h = Tip.frame.AbsoluteSize.X, Tip.frame.AbsoluteSize.Y
        -- Flip to the other side of the cursor near an edge rather than
        -- letting the box hang off screen.
        local x = (m.X + 16 + w > viewport.X) and (m.X - 16 - w) or (m.X + 16)
        local y = (m.Y + 18 + h > viewport.Y) and (m.Y - 12 - h) or (m.Y + 18)
        Tip.frame.Position = UDim2.fromOffset(x, y)
    end)
end

local function hideTip()
    Tip.target = nil
    if Tip.frame then Tip.frame.Visible = false end
end

-- Attaches an explanation to any GuiObject.
local function tip(instance, text)
    if not text or text == "" then return instance end
    instance.MouseEnter:Connect(function()
        if not Tip.frame then return end
        Tip.target = instance
        Tip.showAt = os.clock() + 1.0
        Tip.frame.Visible = false
        Tip.label.Text = text
    end)
    instance.MouseLeave:Connect(function()
        if Tip.target == instance then hideTip() end
    end)
    -- A destroyed widget must not leave its tooltip stranded on screen.
    instance.AncestryChanged:Connect(function()
        if not instance:IsDescendantOf(game) and Tip.target == instance then hideTip() end
    end)
    return instance
end

-- =========================================================================
-- Primitives
-- =========================================================================

-- Chevron: two rounded bars, never a glyph and never an image.
local function chevron(parent)
    local holder = Instance.new("Frame")
    holder.Name = "Chevron"
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.fromOffset(16, 16)
    holder.LayoutOrder = 99
    holder.Parent = parent

    local function bar(name, x, angle)
        local b = Instance.new("Frame")
        b.Name = name
        b.BackgroundColor3 = Theme.TextSub
        b.BorderSizePixel = 0
        b.AnchorPoint = Vector2.new(0.5, 0.5)
        b.Position = UDim2.fromOffset(x, 8)
        b.Size = UDim2.fromOffset(8, 2)
        b.Rotation = angle
        corner(b, 1)
        b.Parent = holder
        return b
    end
    local left = bar("L", 5, 45)
    local right = bar("R", 11, -45)

    -- A table, not fields on the Instance: Roblox objects reject new members.
    return {
        frame = holder,
        setOpen = function(open)
            left.Rotation = open and -45 or 45
            right.Rotation = open and 45 or -45
            local c = open and Theme.AccentMid or Theme.TextSub
            left.BackgroundColor3 = c
            right.BackgroundColor3 = c
        end,
    }
end

-- A control row: the base for everything with a label on the left.
-- `reserve` is how much room the right-hand controls need (their width plus
-- the gap), used only if UIFlexItem is unavailable.
local function row(parent, text, order, height, reserve)
    local r = Instance.new("Frame")
    r.Name = "Row"
    r.BackgroundColor3 = Theme.SurfaceElement
    r.BorderSizePixel = 0
    r.Size = UDim2.new(1, 0, 0, height or Theme.RowH)
    r.LayoutOrder = order or 1
    r.Parent = parent
    corner(r, Theme.RadiusMd)
    stroke(r, Theme.Hairline, 1)
    pad(r, 0, Theme.GapLg, 0, Theme.GapLg)
    local layout = hlist(r, Theme.GapMd)

    local l = label(r, text, "rowLabel", 1)
    l.Size = UDim2.new(1, 0, 1, 0)
    l.TextTruncate = Enum.TextTruncate.AtEnd
    -- The label takes the slack so the control sits hard right.
    flexFill(l, reserve or 24)

    return r, l, layout
end

-- Rows light up under the cursor, and a clickable row reports clicks on ITSELF.
--
-- This used to drop a full-width invisible TextButton into the row to catch the
-- click. That is what made every row label vanish in 2.7.0/2.7.1: a row has a
-- horizontal UIListLayout, the layout lays out ALL GuiObject children, and the
-- hit button was Size (1,1) scale at LayoutOrder 0 - so it sorted first, took
-- the whole width, and pushed the label and the control off the right-hand edge
-- where the window clipped them. Captions, buttons and list entries were fine
-- precisely because none of them go through row().
--
-- A Frame with Active = true raises InputBegan for mouse buttons on its own, so
-- no extra child is needed and nothing joins the layout.
local function hoverable(frame, clickable)
    local base = Theme.SurfaceElement
    frame.MouseEnter:Connect(function() frame.BackgroundColor3 = Theme.SurfaceHover end)
    frame.MouseLeave:Connect(function() frame.BackgroundColor3 = base end)
    if not clickable then return nil end
    frame.Active = true
    return {
        onClick = function(fn)
            frame.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    fn()
                end
            end)
        end,
    }
end

-- Toggle: 38x20, the knob slides and the track takes the accent when on.
local function toggle(parent, text, get, set, order, explain)
    local r, _, _ = row(parent, text, order, nil, 46)
    local hit = hoverable(r, true)

    local track = Instance.new("Frame")
    track.Name = "Track"
    track.BackgroundColor3 = Theme.SurfaceField
    track.BorderSizePixel = 0
    track.Size = UDim2.fromOffset(38, 20)
    track.LayoutOrder = 2
    track.Parent = r
    corner(track, 10)
    local trackStroke = stroke(track, Theme.Hairline, 1)
    local grad = accentGradient(track, 0)
    grad.Enabled = false

    local knob = Instance.new("Frame")
    knob.Name = "Knob"
    knob.BackgroundColor3 = Theme.TextMuted
    knob.BorderSizePixel = 0
    knob.Size = UDim2.fromOffset(14, 14)
    knob.Position = UDim2.fromOffset(2, 3)
    knob.ZIndex = 2
    corner(knob, 7)
    knob.Parent = track

    local function render()
        local on = get() and true or false
        grad.Enabled = on
        track.BackgroundColor3 = on and Color3.new(1, 1, 1) or Theme.SurfaceField
        trackStroke.Transparency = on and 1 or 0
        knob.BackgroundColor3 = on and Theme.TextOnAccent or Theme.TextMuted
        knob.Position = UDim2.fromOffset(on and 22 or 2, 3)
    end
    render()
    hit.onClick(function()
        set(not get())
        render()
    end)
    tip(r, explain)
    return { row = r, render = render }
end

-- A square toggle, for switching whole modules on and off. Deliberately a
-- different shape from the pill: a pill reads as a setting, and these are not
-- settings - they decide whether a thing exists on screen at all. On takes the
-- accent gradient, off greys out.
local function squareToggle(parent, text, get, set, order, explain)
    local r, _, _ = row(parent, text, order, nil, 32)
    local hit = hoverable(r, true)

    local box = Instance.new("Frame")
    box.Name = "Box"
    box.BackgroundColor3 = Color3.new(1, 1, 1)
    box.BorderSizePixel = 0
    box.Size = UDim2.fromOffset(24, 24)
    box.LayoutOrder = 2
    box.Parent = r
    corner(box, Theme.RadiusMd)
    local boxStroke = stroke(box, Theme.Hairline, 1)
    local grad = accentGradient(box, 45)

    local function render()
        local on = get() and true or false
        grad.Enabled = on
        box.BackgroundColor3 = on and Color3.new(1, 1, 1) or Theme.SurfaceField
        boxStroke.Color = on and Theme.AccentMid or Theme.Hairline
        boxStroke.Transparency = on and 1 or 0
    end
    render()
    hit.onClick(function()
        set(not get())
        render()
    end)
    tip(r, explain)
    return { row = r, render = render }
end

-- Slider: label + description, then an 18px track whose fill carries the
-- readout on its right edge, so the number always sits on the accent.
local function slider(parent, text, desc, minVal, maxVal, isFloat, get, set, order, explain)
    local holder = Instance.new("Frame")
    holder.Name = "Slider"
    holder.BackgroundTransparency = 1
    holder.AutomaticSize = Enum.AutomaticSize.Y
    holder.Size = UDim2.new(1, 0, 0, 0)
    holder.LayoutOrder = order or 1
    holder.Parent = parent
    vlist(holder, Theme.GapSm)

    local head = Instance.new("Frame")
    head.Name = "Head"
    head.BackgroundTransparency = 1
    head.AutomaticSize = Enum.AutomaticSize.Y
    head.Size = UDim2.new(1, 0, 0, 0)
    head.LayoutOrder = 1
    head.Parent = holder
    vlist(head, 1)

    local title = label(head, text, "rowLabel", 1)
    title.Size = UDim2.new(1, 0, 0, 18)
    if desc and desc ~= "" then
        local sub = label(head, desc, "captionSub", 2)
        sub.Size = UDim2.new(1, 0, 0, 12)
    end

    local track = Instance.new("Frame")
    track.Name = "Track"
    track.BackgroundColor3 = Theme.SurfaceField
    track.BorderSizePixel = 0
    track.Size = UDim2.new(1, 0, 0, 18)
    track.ClipsDescendants = true
    track.LayoutOrder = 2
    track.Active = true
    track.Parent = holder
    corner(track, Theme.RadiusSm)
    stroke(track, Theme.Hairline, 1)

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.BackgroundColor3 = Color3.new(1, 1, 1)
    fill.BorderSizePixel = 0
    fill.Size = UDim2.fromScale(0, 1)
    fill.Parent = track
    corner(fill, Theme.RadiusSm)
    accentGradient(fill, 0)

    -- The readout rides the fill's right edge while there is room for it, and
    -- steps outside onto the dark remainder when the fill gets too short.
    local readout = Instance.new("TextLabel")
    readout.Name = "Value"
    readout.BackgroundTransparency = 1
    readout.Size = UDim2.new(1, -8, 1, 0)
    readout.Position = UDim2.fromOffset(0, 0)
    readout.TextXAlignment = Enum.TextXAlignment.Right
    readout.TextColor3 = Theme.TextOnAccent
    readout.TextSize = 11
    readout.ZIndex = 3
    setFont(readout, "mono", Enum.FontWeight.Medium)
    readout.Parent = fill

    local function format(value)
        if isFloat then return string.format("%.1f", value) end
        return tostring(math.floor(value + 0.5))
    end

    local function render()
        local value = get()
        local alpha = math.clamp((value - minVal) / (maxVal - minVal), 0, 1)
        fill.Size = UDim2.fromScale(alpha, 1)
        readout.Text = format(value)
        if alpha < 0.22 then
            -- Outside the fill, in primary, per the design note.
            readout.Parent = track
            readout.Size = UDim2.new(1, -8, 1, 0)
            readout.TextColor3 = Theme.TextPrimary
        else
            readout.Parent = fill
            readout.Size = UDim2.new(1, -8, 1, 0)
            readout.TextColor3 = Theme.TextOnAccent
        end
    end
    render()

    local dragging = false
    local function setFromX(x)
        if track.AbsoluteSize.X <= 0 then return end
        local alpha = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local value = minVal + (maxVal - minVal) * alpha
        if isFloat then
            value = math.floor(value * 10 + 0.5) / 10
        else
            value = math.floor(value + 0.5)
        end
        set(value)
        render()
    end
    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromX(input.Position.X)
        end
    end)
    table.insert(S.sliderConnections, UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            setFromX(input.Position.X)
        end
    end))
    table.insert(S.sliderConnections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))

    tip(holder, explain)
    return { holder = holder, render = render }
end

-- Dropdown row: the current value, a chevron, and a list that drops under it.
local function dropdown(parent, text, options, get, set, order, explain)
    local holder = Instance.new("Frame")
    holder.Name = "Dropdown"
    holder.BackgroundTransparency = 1
    holder.AutomaticSize = Enum.AutomaticSize.Y
    holder.Size = UDim2.new(1, 0, 0, 0)
    holder.LayoutOrder = order or 1
    holder.Parent = parent
    vlist(holder, 4)

    local r, _, _ = row(holder, text, 1, nil, 90)
    local hit = hoverable(r, true)

    local value = label(r, "", "captionKey", 2)
    value.Size = UDim2.fromOffset(0, 18)
    value.AutomaticSize = Enum.AutomaticSize.X
    value.TextXAlignment = Enum.TextXAlignment.Right

    local chev = chevron(r)

    local menu = Instance.new("Frame")
    menu.Name = "Menu"
    menu.BackgroundColor3 = Theme.SurfaceField
    menu.BorderSizePixel = 0
    menu.AutomaticSize = Enum.AutomaticSize.Y
    menu.Size = UDim2.new(1, 0, 0, 0)
    menu.Visible = false
    menu.LayoutOrder = 2
    menu.Parent = holder
    corner(menu, Theme.RadiusMd)
    stroke(menu, Theme.Hairline, 1)
    pad(menu, 4, 4, 4, 4)
    vlist(menu, 2)

    local optionButtons = {}
    local function render()
        local current = get()
        value.Text = tostring(current)
        for optValue, button in pairs(optionButtons) do
            local on = optValue == current
            button.BackgroundColor3 = on and Theme.SurfaceHover or Theme.SurfaceElement
            button.TextColor3 = on and Theme.AccentMid or Theme.TextSub
        end
    end

    for i, option in ipairs(options) do
        local b = Instance.new("TextButton")
        b.Name = tostring(option.value)
        b.BackgroundColor3 = Theme.SurfaceElement
        b.BorderSizePixel = 0
        b.Size = UDim2.new(1, 0, 0, 26)
        b.Text = option.label or tostring(option.value)
        b.TextColor3 = Theme.TextSub
        b.TextSize = 12
        b.LayoutOrder = i
        setFont(b, "sans", Enum.FontWeight.Medium)
        b.Parent = menu
        corner(b, 4)
        b.MouseButton1Click:Connect(function()
            set(option.value)
            menu.Visible = false
            chev.setOpen(false)
            render()
        end)
        optionButtons[option.value] = b
    end
    render()

    hit.onClick(function()
        menu.Visible = not menu.Visible
        chev.setOpen(menu.Visible)
    end)
    -- Clicking an option closes the menu; keep the chevron honest.
    render()
    tip(r, explain)
    return { holder = holder, render = render }
end

-- A small right-aligned number field on a row.
local function numberBox(parent, text, get, set, order, explain)
    local r, _, _ = row(parent, text, order, nil, 69)

    local box = Instance.new("TextBox")
    box.Name = "Value"
    box.BackgroundColor3 = Theme.SurfaceField
    box.BorderSizePixel = 0
    box.Size = UDim2.fromOffset(61, 20)
    box.LayoutOrder = 2
    box.Text = tostring(get())
    box.TextColor3 = Theme.TextSub
    box.TextSize = 12
    box.TextXAlignment = Enum.TextXAlignment.Right
    box.ClearTextOnFocus = false
    box.ClipsDescendants = true
    setFont(box, "sans", Enum.FontWeight.Medium)
    box.Parent = r
    corner(box, Theme.RadiusSm)
    stroke(box, Theme.Hairline, 1)
    pad(box, 0, 8, 0, 6)

    local function render() box.Text = tostring(get()) end
    box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        if n then set(n) end
        render()
    end)
    tip(r, explain)
    return { row = r, render = render }
end

-- Swatch + colour picker. The SV square is one frame with two stacked fills -
-- white to hue horizontally, clear to black vertically - exactly as the design
-- describes; changing the hue only touches the first gradient's second stop.
local function colorRow(parent, text, get, set, order, explain)
    local holder = Instance.new("Frame")
    holder.Name = "Color"
    holder.BackgroundTransparency = 1
    holder.AutomaticSize = Enum.AutomaticSize.Y
    holder.Size = UDim2.new(1, 0, 0, 0)
    holder.LayoutOrder = order or 1
    holder.Parent = parent
    vlist(holder, Theme.GapSm)

    local r, _, _ = row(holder, text, 1, nil, 54)
    local hit = hoverable(r, true)

    local swatch = Instance.new("Frame")
    swatch.Name = "Swatch"
    swatch.BackgroundColor3 = get()
    swatch.BorderSizePixel = 0
    swatch.Size = UDim2.fromOffset(46, 20)
    swatch.LayoutOrder = 2
    swatch.Parent = r
    corner(swatch, Theme.RadiusSm)
    stroke(swatch, Theme.Hairline, 1)

    local picker = Instance.new("Frame")
    picker.Name = "Picker"
    picker.BackgroundTransparency = 1
    picker.Size = UDim2.new(1, 0, 0, 140)
    picker.Visible = false
    picker.LayoutOrder = 2
    picker.Parent = holder
    hlist(picker, Theme.GapMd)

    local sv = Instance.new("Frame")
    sv.Name = "SV"
    sv.BackgroundColor3 = Color3.new(1, 1, 1)
    sv.BorderSizePixel = 0
    sv.Size = UDim2.new(1, -22, 1, 0)
    sv.Active = true
    sv.LayoutOrder = 1
    sv.Parent = picker
    corner(sv, Theme.RadiusMd)
    flexFill(sv, 22)   -- the hue rail (14) plus the gap (8)

    local hueGradient = Instance.new("UIGradient")
    hueGradient.Rotation = 0
    hueGradient.Parent = sv

    local shade = Instance.new("Frame")
    shade.Name = "Shade"
    shade.BackgroundColor3 = Color3.new(0, 0, 0)
    shade.BorderSizePixel = 0
    shade.Size = UDim2.fromScale(1, 1)
    shade.Parent = sv
    corner(shade, Theme.RadiusMd)
    local shadeGradient = Instance.new("UIGradient")
    shadeGradient.Rotation = 90
    shadeGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, 0),
    })
    shadeGradient.Parent = shade

    local cursor = Instance.new("Frame")
    cursor.Name = "Cursor"
    cursor.BackgroundTransparency = 1
    cursor.AnchorPoint = Vector2.new(0.5, 0.5)
    cursor.Size = UDim2.fromOffset(12, 12)
    cursor.ZIndex = 4
    cursor.Parent = sv
    corner(cursor, 6)
    stroke(cursor, Color3.new(1, 1, 1), 2)

    local hue = Instance.new("Frame")
    hue.Name = "Hue"
    hue.BackgroundColor3 = Color3.new(1, 1, 1)
    hue.BorderSizePixel = 0
    hue.Size = UDim2.new(0, 14, 1, 0)
    hue.Active = true
    hue.LayoutOrder = 2
    hue.Parent = picker
    corner(hue, Theme.RadiusSm)
    local rail = Instance.new("UIGradient")
    rail.Rotation = 90
    rail.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
        ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
        ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
        ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
        ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
        ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
    })
    rail.Parent = hue

    local marker = Instance.new("Frame")
    marker.Name = "Marker"
    marker.BackgroundColor3 = Color3.new(1, 1, 1)
    marker.BorderSizePixel = 0
    marker.AnchorPoint = Vector2.new(0.5, 0.5)
    marker.Size = UDim2.fromOffset(20, 3)
    marker.Position = UDim2.new(0.5, 0, 0, 0)
    marker.ZIndex = 4
    corner(marker, 2)
    marker.Parent = hue

    local h, s, v = get():ToHSV()

    local function apply()
        local color = Color3.fromHSV(h, s, v)
        swatch.BackgroundColor3 = color
        hueGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(h, 1, 1))
        cursor.Position = UDim2.fromScale(s, 1 - v)
        marker.Position = UDim2.new(0.5, 0, h, 0)
        set(color)
    end
    apply()

    local draggingSV, draggingHue = false, false
    local function svFromPosition(x, y)
        if sv.AbsoluteSize.X <= 0 then return end
        s = math.clamp((x - sv.AbsolutePosition.X) / sv.AbsoluteSize.X, 0, 1)
        v = 1 - math.clamp((y - sv.AbsolutePosition.Y) / sv.AbsoluteSize.Y, 0, 1)
        apply()
    end
    local function hueFromPosition(y)
        if hue.AbsoluteSize.Y <= 0 then return end
        h = math.clamp((y - hue.AbsolutePosition.Y) / hue.AbsoluteSize.Y, 0, 1)
        apply()
    end

    sv.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            draggingSV = true
            svFromPosition(input.Position.X, input.Position.Y)
        end
    end)
    hue.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            draggingHue = true
            hueFromPosition(input.Position.Y)
        end
    end)
    table.insert(S.sliderConnections, UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        if draggingSV then svFromPosition(input.Position.X, input.Position.Y) end
        if draggingHue then hueFromPosition(input.Position.Y) end
    end))
    table.insert(S.sliderConnections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            draggingSV, draggingHue = false, false
        end
    end))

    hit.onClick(function()
        picker.Visible = not picker.Visible
    end)
    tip(r, explain)
    return { holder = holder, render = apply }
end

-- Button. "accent" is the primary action; "ghost" is the in-section default.
local function button(parent, text, style, onClick, order, explain)
    local b = Instance.new("TextButton")
    b.Name = "Button"
    b.BorderSizePixel = 0
    b.Size = UDim2.new(1, 0, 0, 32)
    b.Text = text
    b.TextSize = 13
    b.AutoButtonColor = false
    b.LayoutOrder = order or 1
    setFont(b, "sans", Enum.FontWeight.SemiBold)
    b.Parent = parent
    corner(b, Theme.RadiusMd)

    if style == "accent" then
        b.BackgroundColor3 = Color3.new(1, 1, 1)
        b.TextColor3 = Theme.TextOnAccent
        accentGradient(b, 0)
    elseif style == "danger" then
        b.BackgroundColor3 = Theme.StatusBad
        -- Dark on the red, as the design has it. #ff6060 is light enough that
        -- dark type has more contrast on it than white does.
        b.TextColor3 = Theme.TextOnAccent
    else
        b.BackgroundColor3 = Theme.SurfaceElement
        b.TextColor3 = Theme.TextPrimary
        stroke(b, Theme.Hairline, 1)
        b.MouseEnter:Connect(function() b.BackgroundColor3 = Theme.SurfaceHover end)
        b.MouseLeave:Connect(function() b.BackgroundColor3 = Theme.SurfaceElement end)
    end

    if onClick then b.MouseButton1Click:Connect(onClick) end
    tip(b, explain)
    return b
end

-- A horizontal strip of equal-width buttons.
local function buttonRow(parent, order)
    local holder = Instance.new("Frame")
    holder.Name = "Buttons"
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.new(1, 0, 0, 32)
    holder.LayoutOrder = order or 1
    holder.Parent = parent
    hlist(holder, Theme.GapMd)

    local count = 0
    local buttons = {}
    -- Equal widths without UIFlexItem would need to know the final count up
    -- front, so the fallback re-sizes every sibling as each one is added.
    local api = { frame = holder }
    function api.add(text, style, onClick, explain)
        count = count + 1
        local b = button(holder, text, style, onClick, count, explain)
        b.Size = UDim2.new(0, 0, 1, 0)
        buttons[count] = b
        -- Equal widths, recomputed as each button is added.
        for _, sibling in ipairs(buttons) do
            sibling.Size = UDim2.new(1 / count, -(Theme.GapMd * (count - 1)) / count, 1, 0)
        end
        return b
    end
    return api
end

-- The add-an-entry field. The round confirm is the only round thing in the
-- kit, deliberately: it reads as the commit action.
local function textField(parent, placeholder, onSubmit, order, explain)
    local holder = Instance.new("Frame")
    holder.Name = "TextField"
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.new(1, 0, 0, 30)
    holder.LayoutOrder = order or 1
    holder.Parent = parent
    hlist(holder, Theme.GapMd)

    local box = Instance.new("TextBox")
    box.Name = "Input"
    box.BackgroundColor3 = Theme.SurfaceField
    box.BorderSizePixel = 0
    box.Size = UDim2.new(1, -36, 1, 0)
    box.Text = ""
    box.PlaceholderText = placeholder or ""
    box.PlaceholderColor3 = Theme.TextMuted
    box.TextColor3 = Theme.TextPrimary
    box.TextSize = 12
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.ClearTextOnFocus = false
    box.ClipsDescendants = true
    box.LayoutOrder = 1
    setFont(box, "sans", Enum.FontWeight.Medium)
    box.Parent = holder
    corner(box, Theme.RadiusMd)
    stroke(box, Theme.Hairline, 1)
    pad(box, 0, 10, 0, 10)
    flexFill(box, 36)   -- the confirm button (28) plus the gap (8)

    local confirm = Instance.new("TextButton")
    confirm.Name = "Confirm"
    confirm.BackgroundColor3 = Color3.new(1, 1, 1)
    confirm.BorderSizePixel = 0
    confirm.Size = UDim2.fromOffset(28, 28)
    confirm.Text = ""
    confirm.AutoButtonColor = false
    confirm.LayoutOrder = 2
    confirm.Parent = holder
    corner(confirm, 14)
    accentGradient(confirm, 45)

    -- Tick, from two bars.
    local function bar(w, h, x, y, angle)
        local f = Instance.new("Frame")
        f.BackgroundColor3 = Theme.TextOnAccent
        f.BorderSizePixel = 0
        f.AnchorPoint = Vector2.new(0.5, 0.5)
        f.Size = UDim2.fromOffset(w, h)
        f.Position = UDim2.fromOffset(x, y)
        f.Rotation = angle
        f.ZIndex = 2
        corner(f, 1)
        f.Parent = confirm
    end
    bar(2, 7, 11, 17, -45)
    bar(2, 12, 16, 13, 35)

    local function submit()
        local text = box.Text:gsub("^%s+", ""):gsub("%s+$", "")
        if text == "" then return end
        box.Text = ""
        onSubmit(text)
    end
    confirm.MouseButton1Click:Connect(submit)
    box.FocusLost:Connect(function(enter) if enter then submit() end end)
    tip(confirm, explain)
    return { holder = holder, box = box }
end

-- A bordered, scrolling container for list entries.
local function list(parent, height, order)
    local holder = Instance.new("Frame")
    holder.Name = "List"
    holder.BackgroundColor3 = Theme.SurfaceField
    holder.BorderSizePixel = 0
    holder.Size = UDim2.new(1, 0, 0, height or 160)
    holder.LayoutOrder = order or 1
    holder.Parent = parent
    corner(holder, Theme.RadiusMd)
    stroke(holder, Theme.Hairline, 1)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "Scroll"
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.Size = UDim2.fromScale(1, 1)
    scroll.CanvasSize = UDim2.new()
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = Color3.fromHex("50505f")
    scroll.Parent = holder
    pad(scroll, 6, 6, 6, 6)
    vlist(scroll, Theme.GapSm)
    return scroll
end

-- One list entry: title / meta on the left, actions on the right.
-- `actionCount` sizes the text column when UIFlexItem is unavailable.
local function listEntry(parent, title, meta, order, actionCount)
    local e = Instance.new("Frame")
    e.Name = "Entry"
    e.BackgroundColor3 = Theme.SurfaceElement
    e.BorderSizePixel = 0
    e.Size = UDim2.new(1, 0, 0, 46)
    e.LayoutOrder = order or 1
    e.Parent = parent
    corner(e, Theme.RadiusSm)
    stroke(e, Theme.Hairline, 1)
    pad(e, 0, 8, 0, 10)
    hlist(e, Theme.GapMd)

    local text = Instance.new("Frame")
    text.Name = "Text"
    text.BackgroundTransparency = 1
    text.Size = UDim2.new(1, -60, 1, 0)
    text.LayoutOrder = 1
    text.Parent = e
    vlist(text, 0)
    local n = actionCount or 2
    flexFill(text, Theme.GapMd + n * 24 + math.max(n - 1, 0) * 2)

    local titleLabel = label(text, title, "rowEntry", 1)
    titleLabel.Size = UDim2.new(1, 0, 0, 16)
    titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    local metaLabel = label(text, meta or "", "monoMeta", 2)
    metaLabel.Size = UDim2.new(1, 0, 0, 12)
    metaLabel.TextTruncate = Enum.TextTruncate.AtEnd

    local actions = Instance.new("Frame")
    actions.Name = "Actions"
    actions.BackgroundTransparency = 1
    actions.AutomaticSize = Enum.AutomaticSize.X
    actions.Size = UDim2.new(0, 0, 1, 0)
    actions.LayoutOrder = 2
    actions.Parent = e
    hlist(actions, 2)

    return { frame = e, title = titleLabel, meta = metaLabel, actions = actions }
end

-- Row action icons, drawn from rectangles: no asset to fail to load.
local function iconButton(parent, kind, onClick, order, explain)
    local b = Instance.new("TextButton")
    b.Name = kind
    b.BackgroundColor3 = Theme.SurfaceHover
    b.BackgroundTransparency = 1
    b.BorderSizePixel = 0
    b.Size = UDim2.fromOffset(24, 24)
    b.Text = ""
    b.AutoButtonColor = false
    b.LayoutOrder = order or 1
    b.Parent = parent
    corner(b, Theme.RadiusSm)
    b.MouseEnter:Connect(function() b.BackgroundTransparency = 0.7 end)
    b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end)

    local function piece(color, w, h, x, y, angle, radius)
        local f = Instance.new("Frame")
        f.BackgroundColor3 = color
        f.BorderSizePixel = 0
        f.AnchorPoint = Vector2.new(0.5, 0.5)
        f.Size = UDim2.fromOffset(w, h)
        f.Position = UDim2.fromOffset(x, y)
        f.Rotation = angle or 0
        f.ZIndex = 2
        if radius then corner(f, radius) end
        f.Parent = b
        return f
    end

    if kind == "edit" then
        piece(Theme.AccentMid, 3, 12, 13, 11, 45, 1)
        piece(Theme.AccentMid, 3, 3, 8, 17, 45)
    elseif kind == "delete" then
        piece(Theme.StatusBad, 11, 2, 12, 7, 0, 1)
        piece(Theme.StatusBad, 9, 9, 12, 14, 0, 2)
    elseif kind == "up" then
        piece(Theme.TextSub, 7, 2, 10, 13, 45, 1)
        piece(Theme.TextSub, 7, 2, 14, 13, -45, 1)
    elseif kind == "down" then
        piece(Theme.TextSub, 7, 2, 10, 11, -45, 1)
        piece(Theme.TextSub, 7, 2, 14, 11, 45, 1)
    elseif kind == "play" then
        piece(Theme.StatusGood, 3, 10, 10, 12, 0, 1)
        piece(Theme.StatusGood, 3, 10, 14, 12, 0, 1)
    end

    if onClick then b.MouseButton1Click:Connect(onClick) end
    tip(b, explain)
    return b
end

-- =========================================================================
-- Window and section
-- =========================================================================

local function makeDraggable(handle, target)
    local dragging, startPos, startOffset = false, nil, nil
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            startPos = input.Position
            startOffset = target.Position
        end
    end)
    handle.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    table.insert(S.sliderConnections, UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = input.Position - startPos
        target.Position = UDim2.new(
            startOffset.X.Scale, startOffset.X.Offset + delta.X,
            startOffset.Y.Scale, startOffset.Y.Offset + delta.Y)
    end))
end

-- A window: accent bar, header (drag handle, accent tile, title, optional ⓘ),
-- hairline divider, then a scrolling body. The body scrolls because a full
-- accordion is taller than a 768p screen, which is the one thing a fixed
-- height would get wrong on half the machines this runs on.
local function window(parent, opts)
    local frame = Instance.new("Frame")
    frame.Name = opts.name or "Window"
    frame.BackgroundColor3 = Color3.new(1, 1, 1)
    frame.BorderSizePixel = 0
    frame.Size = UDim2.fromOffset(opts.width or 310, opts.height or 460)
    frame.Position = opts.position or UDim2.fromOffset(40, 40)
    frame.Visible = opts.visible ~= false
    frame.Active = true
    frame.ClipsDescendants = true
    frame.ZIndex = 2
    frame.Parent = parent
    corner(frame, Theme.RadiusLg)
    stroke(frame, Theme.Hairline, 1)
    bodyGradient(frame)
    shadow(frame)

    local accent = Instance.new("Frame")
    accent.Name = "AccentBar"
    accent.BackgroundColor3 = Color3.new(1, 1, 1)
    accent.BorderSizePixel = 0
    accent.Size = UDim2.new(1, 0, 0, 3)
    accent.ZIndex = 3
    accent.Parent = frame
    accentGradient(accent, 0)

    local header = Instance.new("Frame")
    header.Name = "Header"
    header.BackgroundColor3 = Theme.SurfaceHeader
    header.BorderSizePixel = 0
    header.Size = UDim2.new(1, 0, 0, Theme.HeaderH)
    header.Position = UDim2.fromOffset(0, 3)
    header.Active = true
    header.ZIndex = 3
    header.Parent = frame
    pad(header, 0, 12, 0, 14)
    hlist(header, Theme.GapLg)
    makeDraggable(header, frame)

    local tile = Instance.new("Frame")
    tile.Name = "Icon"
    tile.BackgroundColor3 = Color3.new(1, 1, 1)
    tile.BorderSizePixel = 0
    tile.Size = UDim2.fromOffset(14, 14)
    tile.LayoutOrder = 1
    tile.ZIndex = 4
    tile.Parent = header
    corner(tile, 4)
    accentGradient(tile, 45)

    local title = label(header, opts.title or "Window", "windowTitle", 2)
    title.ZIndex = 4
    -- tile (14) + gap (12), plus the info circle (20) + gap (12) when present.
    flexFill(title, 26 + (opts.info and 32 or 0))

    if opts.info then
        local info = Instance.new("TextLabel")
        info.Name = "Info"
        info.BackgroundColor3 = Theme.SurfaceElement
        info.BorderSizePixel = 0
        info.Size = UDim2.fromOffset(20, 20)
        info.Text = "i"
        info.TextColor3 = Theme.TextSub
        info.TextSize = 12
        info.LayoutOrder = 3
        info.ZIndex = 4
        setFont(info, "sans", Enum.FontWeight.Bold)
        info.Parent = header
        corner(info, 10)
        stroke(info, Theme.Hairline, 1)
        tip(info, opts.info)
    end

    local divider = Instance.new("Frame")
    divider.Name = "Divider"
    divider.BackgroundColor3 = Theme.Hairline
    divider.BorderSizePixel = 0
    divider.Size = UDim2.new(1, 0, 0, 1)
    divider.Position = UDim2.fromOffset(0, 3 + Theme.HeaderH)
    divider.ZIndex = 3
    divider.Parent = frame

    local body = Instance.new("ScrollingFrame")
    body.Name = "Body"
    body.BackgroundTransparency = 1
    body.BorderSizePixel = 0
    body.Position = UDim2.fromOffset(0, 4 + Theme.HeaderH)
    body.Size = UDim2.new(1, 0, 1, -(4 + Theme.HeaderH))
    body.CanvasSize = UDim2.new()
    body.AutomaticCanvasSize = Enum.AutomaticSize.Y
    body.ScrollBarThickness = 4
    body.ScrollBarImageColor3 = Color3.fromHex("50505f")
    body.ZIndex = 3
    body.Parent = frame
    pad(body, 10, Theme.GapLg, Theme.GapXl, Theme.GapLg)
    vlist(body, Theme.GapSm)

    return { frame = frame, header = header, body = body, title = title }
end

-- A collapsible section: the Row is the header, the content sits under it and
-- the whole thing grows with what is inside.
local function section(parent, title, order, explain)
    local holder = Instance.new("Frame")
    holder.Name = "Section"
    holder.BackgroundTransparency = 1
    holder.AutomaticSize = Enum.AutomaticSize.Y
    holder.Size = UDim2.new(1, 0, 0, 0)
    holder.LayoutOrder = order or 1
    holder.Parent = parent
    vlist(holder, Theme.GapSm)

    local head, headLabel, _ = row(holder, title, 1, nil, 24)
    local hit = hoverable(head, true)
    local chev = chevron(head)

    local content = Instance.new("Frame")
    content.Name = "Content"
    content.BackgroundTransparency = 1
    content.AutomaticSize = Enum.AutomaticSize.Y
    content.Size = UDim2.new(1, 0, 0, 0)
    content.Visible = false
    content.LayoutOrder = 2
    content.Parent = holder
    vlist(content, Theme.GapSm)
    -- Full width, matching the design: the open section's rows line up with the
    -- section header rather than being indented under it.
    pad(content, 2, 0, 4, 0)

    local open = false
    local function setOpen(value)
        open = value and true or false
        content.Visible = open
        chev.setOpen(open)
        headLabel.TextColor3 = open and Theme.AccentMid or Theme.TextPrimary
    end
    setOpen(false)
    hit.onClick(function() setOpen(not open) end)
    tip(head, explain)

    return { holder = holder, content = content, setOpen = setOpen, isOpen = function() return open end }
end

-- A segmented control - the "island" at the top of a window. Exactly one of
-- the options is live, and picking one is a mode switch, not a setting: the
-- sections below it change with the choice.
local function segmented(parent, options, get, set, order, explain)
    local holder = Instance.new("Frame")
    holder.Name = "Segmented"
    holder.BackgroundColor3 = Theme.SurfaceField
    holder.BorderSizePixel = 0
    holder.Size = UDim2.new(1, 0, 0, 34)
    holder.LayoutOrder = order or 1
    holder.Parent = parent
    corner(holder, Theme.RadiusMd)
    stroke(holder, Theme.Hairline, 1)
    pad(holder, 3, 3, 3, 3)
    hlist(holder, 3)

    local buttons = {}
    local render

    for i, option in ipairs(options) do
        local b = Instance.new("TextButton")
        b.Name = tostring(option.value)
        b.BackgroundColor3 = Theme.SurfaceField
        b.BackgroundTransparency = 1
        b.BorderSizePixel = 0
        b.Size = UDim2.new(1 / #options, -(3 * (#options - 1)) / #options, 1, 0)
        b.Text = option.label or tostring(option.value)
        b.TextSize = 12
        b.AutoButtonColor = false
        b.LayoutOrder = i
        setFont(b, "sans", Enum.FontWeight.SemiBold)
        b.Parent = holder
        corner(b, Theme.RadiusSm)
        accentGradient(b, 0).Enabled = false
        buttons[option.value] = b
        tip(b, option.tip)
        b.MouseButton1Click:Connect(function()
            set(option.value)
            render()
        end)
    end

    render = function()
        local current = get()
        for value, b in pairs(buttons) do
            local on = value == current
            local grad = b:FindFirstChildOfClass("UIGradient")
            if grad then grad.Enabled = on end
            b.BackgroundTransparency = on and 0 or 1
            b.BackgroundColor3 = on and Color3.new(1, 1, 1) or Theme.SurfaceField
            b.TextColor3 = on and Theme.TextOnAccent or Theme.TextSub
        end
    end
    render()
    tip(holder, explain)
    return { holder = holder, render = render }
end

-- A plain hairline, used to fence off the master toggle at the top of a window.
local function separator(parent, order)
    local line = Instance.new("Frame")
    line.Name = "Separator"
    line.BackgroundColor3 = Theme.Hairline
    line.BorderSizePixel = 0
    line.Size = UDim2.new(1, 0, 0, 1)
    line.LayoutOrder = order or 1
    line.Parent = parent
    return line
end

-- A caption line, for the notes under a group of controls.
local function caption(parent, text, order)
    local l = label(parent, text, "captionSub", order)
    l.AutomaticSize = Enum.AutomaticSize.Y
    l.Size = UDim2.new(1, 0, 0, 0)
    l.TextWrapped = true
    l.TextYAlignment = Enum.TextYAlignment.Top
    return l
end

S.UIKit = {
    Theme = Theme,
    setFont = setFont, corner = corner, stroke = stroke, pad = pad,
    vlist = vlist, hlist = hlist, label = label, caption = caption, flexFill = flexFill,
    accentGradient = accentGradient, bodyGradient = bodyGradient, shadow = shadow,
    ensureTip = ensureTip, tip = tip, hideTip = hideTip,
    chevron = chevron, row = row, hoverable = hoverable,
    toggle = toggle, squareToggle = squareToggle, slider = slider, dropdown = dropdown, numberBox = numberBox,
    colorRow = colorRow, button = button, buttonRow = buttonRow,
    textField = textField, list = list, listEntry = listEntry, iconButton = iconButton,
    window = window, section = section, separator = separator, segmented = segmented,
    makeDraggable = makeDraggable,
}
end
