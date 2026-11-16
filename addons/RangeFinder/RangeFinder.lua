local addonName, ns = ...

local DEFAULTS = {
    source = "melee",   -- default ring, see ns.ParseSource
    hover = false,      -- show the hovered action button's range instead
    calibrate = false,  -- extra 5/10/20/30 yd reference rings
    height = 1.5,       -- yards from the feet up to the camera's focus point
    scale = 1,          -- size correction on top of the field of view
    pitchOffset = 0,    -- degrees added to the tracked camera pitch
    pitchSpeed = 0.1,   -- degrees of pitch per pixel of mouse movement while turning the camera
    thickness = 2,
    alpha = 0.9,
}
local SEGMENTS = 72
local CALIBRATION_YARDS = { 5, 10, 20, 30 }
local MELEE_YARDS = 5 -- melee abilities report maxRange 0; the colour still comes from the game
local ATTACK_SPELL = 6603 -- "Attack" (auto-attack)
-- First one the player knows wins: Auto Shot, Shoot (wand), Throw, Shoot Bow, Shoot Gun, Shoot Crossbow.
-- shortcut: classic IDs, the last three are unverified on Forever; check with /dump C_Spell.GetSpellInfo(id).
local RANGED_SPELLS = { 75, 5019, 2764, 2480, 7918, 7919 }
local COLOR = {
    [true] = { 0.2, 1, 0.2 },      -- in range
    [false] = { 1, 0.25, 0.25 },   -- out of range
    unknown = { 0.8, 0.8, 0.8 },   -- no target, or the game gave no answer
    deadzone = { 1, 0.6, 0 },
    calibration = { 1, 1, 1 },
}

local db, category
local overlay = CreateFrame("Frame", nil, UIParent)
overlay:SetAllPoints(WorldFrame) -- same box as the 3D viewport, so its centre is the camera's focus
overlay:SetFrameStrata("BACKGROUND")
overlay:Hide()

local function say(text)
    print("|cff33ff99Range Finder|r: " .. text)
end

-- Secret values can't be compared or used in maths, so they count as "no answer".
local function plain(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function cvarNumber(name)
    return tonumber(plain(C_CVar.GetCVar(name)))
end

---------------------------------------------------------------------------
-- Camera: zoom and field of view are readable, pitch is not, so it is tracked.
---------------------------------------------------------------------------

local camera = { pitch = 20, source = "default" }

-- The client keeps the camera pitch in cameraSavedPitch. When that value moves while playing
-- it is used directly; between changes the pitch follows mouse drags on the 3D world.
local function updatePitch()
    local saved = cvarNumber("cameraSavedPitch")
    if saved and saved ~= camera.saved then
        camera.saved, camera.pitch, camera.source = saved, saved, "cameraSavedPitch"
        return
    end
    local down = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
    if down and not camera.down then
        local focus = GetMouseFoci()[1]
        camera.dragging = focus == nil or focus == WorldFrame -- a drag that started on the world turns the camera
    end
    camera.down = down
    if not down then camera.dragging = false end
    if camera.dragging or (IsMouselooking and IsMouselooking()) then
        local _, dy = GetCursorDelta()
        if dy ~= 0 then
            if C_CVar.GetCVarBool("mouseInvertPitch") then dy = -dy end
            camera.pitch = math.max(-88, math.min(88, camera.pitch - dy * db.pitchSpeed))
            camera.source = "mouse"
        end
    end
end

local function cameraView()
    local zoom = GetCameraZoom and plain(GetCameraZoom()) or cvarNumber("cameraSavedDistance") or 15
    local width = overlay:GetWidth()
    local focal = ns.FocalLength(width / 2, cvarNumber("cameraFov") or 90) * db.scale
    return zoom, math.rad(camera.pitch + db.pitchOffset), db.height, focal
end

---------------------------------------------------------------------------
-- Sources: turn a key into { name, min, max, check }
---------------------------------------------------------------------------

local function meleeCheck()
    local inRange = plain(C_Spell.IsSpellInRange(ATTACK_SPELL, "target"))
    if inRange == nil then
        -- "Attack" may have no range data; an Attack button on the bars answers instead.
        local slots = C_ActionBar.FindSpellActionButtons(ATTACK_SPELL)
        if slots and slots[1] then
            inRange = plain(C_ActionBar.IsActionInRange(slots[1], "target"))
        end
    end
    return inRange
end

-- Returns nil when the source is unknown or has no range.
local function resolve(key)
    local kind, id = ns.ParseSource(key)
    if kind == "melee" then
        return { name = "Melee", min = 0, max = MELEE_YARDS, check = meleeCheck }
    elseif kind == "ranged" then
        for _, spellID in ipairs(RANGED_SPELLS) do
            local source = C_SpellBook.IsSpellKnown(spellID) and resolve("spell:" .. spellID)
            if source then return source end
        end
    elseif kind == "spell" then
        local info = C_Spell.GetSpellInfo(id)
        local minRange, maxRange = info and plain(info.minRange), info and plain(info.maxRange)
        if not minRange or not maxRange then return end
        if maxRange == 0 then
            -- Melee abilities report 0, and so do self-casts; keep only ones that can hit something.
            if not (C_Spell.SpellHasRange(id) or C_Spell.IsSpellHarmful(id)) then return end
            maxRange = MELEE_YARDS
        end
        return {
            name = info.name, min = minRange, max = maxRange,
            check = function() return C_Spell.IsSpellInRange(id, "target") end,
        }
    elseif kind == "item" then
        local _, spellID = C_Item.GetItemSpell(id)
        local source = spellID and resolve("spell:" .. spellID)
        if source then
            source.name = C_Item.GetItemNameByID(id) or source.name
            source.check = function()
                -- Item range checks on non-enemies are blocked in combat.
                if InCombatLockdown() and not UnitCanAttack("player", "target") then return end
                return C_Item.IsItemInRange(id, "target")
            end
            return source
        end
    end
end

---------------------------------------------------------------------------
-- Action buttons
---------------------------------------------------------------------------

-- Polls the mouse focus instead of hooking buttons: works with any action bar addon
-- (EllesmereUI included) that keeps the Blizzard "action" field or attribute.
local function hoveredSlot()
    for _, region in ipairs(GetMouseFoci()) do
        if not region:IsForbidden() then
            local slot = tonumber(plain(region.action))
            if not slot and region.GetAttribute then
                slot = tonumber(plain(region:GetAttribute("action")))
            end
            -- pcall: an unrelated frame may carry a number in .action that is no valid slot.
            if slot and slot > 0 and select(2, pcall(C_ActionBar.HasAction, slot)) == true then return slot end
        end
    end
end

local function keyForSlot(slot)
    local actionType, id = GetActionInfo(slot)
    id = plain(id)
    if actionType == "item" and id then return "item:" .. id end
    local spellID = plain(C_ActionBar.GetSpell(slot)) -- spells, and macros that cast one
    if spellID and spellID > 0 then return "spell:" .. spellID end
end

local function setDefault(key)
    local source = key and resolve(key)
    if not source then
        say("that has no range. Default ring unchanged.")
        return
    end
    db.source = key
    say("default ring is now " .. ns.Label(source.name, source.min, source.max))
end

-- Keybinding (Bindings.xml)
BINDING_NAME_RANGEFINDER_SETDEFAULT = "Set hovered action as default ring"
function RangeFinder_SetFromHover()
    local slot = hoveredSlot()
    if not slot then
        say("hover an action button first.")
        return
    end
    setDefault(keyForSlot(slot))
end

---------------------------------------------------------------------------
-- Ground rings
---------------------------------------------------------------------------

local rings = {}

local function newRing()
    local ring = {}
    for i = 1, SEGMENTS do
        ring[i] = overlay:CreateLine(nil, "ARTWORK")
    end
    rings[#rings + 1] = ring
    return ring
end

local function setRingStyle(ring, color, thickness)
    local alpha = db.alpha * (ring.faint and 0.5 or 1)
    local key = color[1] .. color[2] .. color[3] .. alpha .. thickness
    if ring.style == key then return end
    ring.style = key
    for _, line in ipairs(ring) do
        line:SetThickness(thickness)
        line:SetColorTexture(color[1], color[2], color[3], alpha)
    end
end

-- Draws the ring on the ground around the feet; returns the screen offset of its far point.
local function drawRing(ring, radius, distance, pitch, height, focal)
    if not radius or radius <= 0 then
        for _, line in ipairs(ring) do line:Hide() end
        return
    end
    local project = ns.ProjectGroundPoint
    local farX, farY = project(radius, 0, distance, pitch, height, focal)
    local lastX, lastY = farX, farY
    for i, line in ipairs(ring) do
        local x, y = project(radius, i / SEGMENTS * 2 * math.pi, distance, pitch, height, focal)
        if lastX and x then
            line:SetStartPoint("CENTER", overlay, lastX, lastY)
            line:SetEndPoint("CENTER", overlay, x, y)
            line:Show()
        else
            line:Hide()
        end
        lastX, lastY = x, y
    end
    return farX, farY
end

local maxRing, minRing = newRing(), newRing()
local calibrationRings = {}
for i = 1, #CALIBRATION_YARDS do
    calibrationRings[i] = newRing()
    calibrationRings[i].faint = true
end
local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
local calibrationLabels = {}
for i = 1, #CALIBRATION_YARDS do
    calibrationLabels[i] = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    calibrationLabels[i]:SetText(CALIBRATION_YARDS[i] .. " yd")
end

-- What to show, refreshed 10 times a second: { source, inRange, hovering }
local shown = {}

local function refreshSource()
    local source, slot
    if db.hover then
        slot = hoveredSlot()
        source = slot and resolve(keyForSlot(slot))
    end
    shown.hovering = source ~= nil
    shown.source = source or resolve(db.source)
    shown.inRange = nil
    if shown.source and UnitExists("target") then
        if shown.hovering then
            shown.inRange = plain(C_ActionBar.IsActionInRange(slot, "target"))
        else
            shown.inRange = plain(shown.source.check())
        end
    end
end

local function draw()
    local distance, pitch, height, focal = cameraView()
    local source = shown.source
    setRingStyle(maxRing, COLOR[shown.inRange == nil and "unknown" or shown.inRange], db.thickness)
    setRingStyle(minRing, COLOR.deadzone, db.thickness)
    local x, y = drawRing(maxRing, source and source.max, distance, pitch, height, focal)
    drawRing(minRing, source and source.min, distance, pitch, height, focal)
    label:SetShown(x ~= nil)
    if x then
        label:SetPoint("BOTTOM", overlay, "CENTER", x, y + 2)
        -- White text marks a temporary (hovered) ring.
        label:SetText((shown.hovering and "|cffffffff" or "") .. ns.Label(source.name, source.min, source.max))
    end
    for i, ring in ipairs(calibrationRings) do
        setRingStyle(ring, COLOR.calibration, 1)
        local cx, cy = drawRing(ring, db.calibrate and CALIBRATION_YARDS[i], distance, pitch, height, focal)
        calibrationLabels[i]:SetShown(cx ~= nil)
        if cx then calibrationLabels[i]:SetPoint("BOTTOM", overlay, "CENTER", cx, cy + 2) end
    end
end

local elapsed = 1
overlay:SetScript("OnUpdate", function(_, delta)
    updatePitch()
    elapsed = elapsed + delta
    if elapsed >= 0.1 then
        elapsed = 0
        refreshSource()
    end
    draw() -- every frame, so the ring stays glued to the ground while the camera moves
end)

---------------------------------------------------------------------------
-- Settings panel
---------------------------------------------------------------------------

-- Built each time the dropdown opens: attacks, the current default, then every
-- spellbook spell and every equipped or carried item that has a range.
local function sourceOptions()
    local container = Settings.CreateControlTextContainer()
    local seen = {}
    local function add(key, always)
        if seen[key] then return end
        local source = resolve(key)
        if source or always then
            seen[key] = true
            container:Add(key, source and ns.Label(source.name, source.min, source.max) or key)
        end
    end
    add("melee")
    add("ranged")
    add(db.source, true)
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
            local item = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
            if item and item.itemType == Enum.SpellBookItemType.Spell and item.spellID
                and not item.isPassive and not item.isOffSpec then
                add("spell:" .. item.spellID)
            end
        end
    end
    for slot = 1, 19 do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then add("item:" .. itemID) end
    end
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID then add("item:" .. itemID) end
        end
    end
    return container:GetData()
end

-- Proxy settings read db on every display, so /rf commands and the panel never disagree.
local function setting(key, varType, name, set)
    return Settings.RegisterProxySetting(category, "RANGEFINDER_" .. key:upper(), varType, name, DEFAULTS[key],
        function() return db[key] end, set or function(value) db[key] = value end)
end

local function slider(key, name, min, max, step, format, tooltip)
    local options = Settings.CreateSliderOptions(min, max, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value) return format:format(value) end)
    Settings.CreateSlider(category, setting(key, Settings.VarType.Number, name), options, tooltip)
end

local function checkbox(key, name, tooltip)
    Settings.CreateCheckbox(category, setting(key, Settings.VarType.Boolean, name), tooltip)
end

local function createSettings()
    category = Settings.RegisterVerticalLayoutCategory("Range Finder")

    Settings.CreateDropdown(category,
        setting("source", Settings.VarType.String, "Default ring", function(key) if resolve(key) then db.source = key end end),
        sourceOptions,
        "The range drawn around you all the time. Also: /rf spell <name or id>, /rf item <name or id>, "
        .. "/rf <shift-clicked link>, or the Range Finder keybinding while hovering an action button.")
    checkbox("hover", "Show hovered action button",
        "While the mouse is over an action button, draw that button's range. The default ring returns when the mouse leaves.")

    checkbox("calibrate", "Show calibration rings",
        "Faint 5, 10, 20 and 30 yd rings. Stand next to a target dummy and adjust the sliders below until they match the ground.")
    slider("height", "Camera focus height", 0, 4, 0.05, "%.2f yd",
        "How far above your feet the camera looks. Moves the ring up or down on screen. Taller races need more.")
    slider("scale", "Size correction", 0.5, 1.5, 0.01, "x%.2f",
        "Grows or shrinks every ring. Use it if a 10 yd ring is the wrong size at every camera angle.")
    slider("pitchOffset", "Camera angle correction", -30, 30, 0.5, "%+.1f°",
        "Adds to the tracked camera angle. Use it if the ring is too round or too flat.")
    slider("pitchSpeed", "Mouse turn speed", 0, 0.5, 0.005, "%.3f°/px",
        "How much the camera angle changes per pixel of mouse movement while you turn the camera. "
        .. "If the ring flattens too fast or too slow when you tilt the camera, change this.")
    slider("thickness", "Line thickness", 1, 6, 1, "%d px")
    slider("alpha", "Opacity", 0.1, 1, 0.05, "%.2f")

    Settings.RegisterAddOnCategory(category)
end

---------------------------------------------------------------------------
-- Startup and slash command
---------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    RangeFinderDB = RangeFinderDB or {} -- SavedVariables exist only from here on
    db = RangeFinderDB
    for key, value in pairs(DEFAULTS) do
        if db[key] == nil then db[key] = value end
    end
    createSettings()
    overlay:Show()
end)

SLASH_RANGEFINDER1 = "/rf"
SLASH_RANGEFINDER2 = "/rangefinder"
SlashCmdList.RANGEFINDER = function(msg)
    local command, text = msg:match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    local key = ns.KeyFromText(msg)
    if command == "" then
        if InCombatLockdown() then
            say("the settings panel can't open in combat.")
        else
            Settings.OpenToCategory(category:GetID())
        end
    elseif command == "calibrate" then
        db.calibrate = not db.calibrate
        say(db.calibrate and "calibration rings on." or "calibration rings off.")
    elseif command == "camera" then
        local distance, pitch = cameraView()
        say(("pitch %.1f° (from %s, saved %s, correction %+.1f), zoom %.1f yd, fov %s, focus %.2f yd")
            :format(math.deg(pitch), camera.source, tostring(camera.saved), db.pitchOffset, distance,
                tostring(cvarNumber("cameraFov")), db.height))
    elseif key then
        setDefault(key)
    elseif command == "spell" and text ~= "" then
        local info = C_Spell.GetSpellInfo(tonumber(text) or text)
        setDefault(info and ("spell:" .. info.spellID))
    elseif command == "item" and text ~= "" then
        local itemID = C_Item.GetItemInfoInstant(tonumber(text) or text)
        setDefault(itemID and ("item:" .. itemID))
    else
        say("/rf (settings) | /rf melee | /rf ranged | /rf spell <name or id> | /rf item <name or id> | /rf <link> | /rf calibrate | /rf camera")
    end
end
