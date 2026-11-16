local addonName, ns = ...

local rc = LibStub("LibRangeCheck-3.0")

local DEFAULTS = {
    spell = "auto",  -- "auto" (class default) or "spell:<id>"
    yards = 0,       -- custom range in yards; 0 = use the spell
    hover = true,    -- second box for the mouseover unit
    locked = true,
    scale = 1,
    pos = {},
}
local MELEE_YARDS = 5 -- melee abilities report maxRange 0
local ATTACK_SPELL = 6603
local WIDTH, HEIGHT = 210, 70
local FONT_NUMBER, FONT_TEXT = "Fonts\\ARIALN.TTF", "Fonts\\FRIZQT__.TTF"
local STATE = {
    [true] = { 0.27, 0.85, 0.48, "IN RANGE" },
    [false] = { 0.96, 0.32, 0.36, "OUT OF RANGE" },
    edge = { 1, 0.70, 0.26, "EDGE" },
    none = { 0.62, 0.66, 0.74 },
}

local db, category

local function say(text)
    print("|cff4dd97aRange Box|r: " .. text)
end

-- Secret values can't be compared, so they count as "no answer".
local function plain(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

---------------------------------------------------------------------------
-- Which spell decides "in range"
---------------------------------------------------------------------------

-- Returns { name, max } for a spell id, or nil if it has no usable range.
local function spellRange(id)
    local info = id and C_Spell.GetSpellInfo(id)
    local maxRange = info and plain(info.maxRange)
    if not maxRange then return end
    if maxRange == 0 then
        if id ~= ATTACK_SPELL and not (C_Spell.SpellHasRange(id) or C_Spell.IsSpellHarmful(id)) then return end
        maxRange = MELEE_YARDS
    end
    return { name = info.name, max = maxRange }
end

local function classSpell()
    local list = ns.CLASS_SPELLS[select(2, UnitClass("player"))] or { ATTACK_SPELL }
    for _, id in ipairs(list) do
        if C_SpellBook.IsSpellKnown(id) then return spellRange(id) end
    end
    return spellRange(list[1]) -- shortcut: rank-1 IDs may read as unknown on Forever; the name check still works
end

local function currentSpell()
    if db.spell == "auto" then return classSpell() end
    return spellRange(tonumber(db.spell:match("^spell:(%d+)$"))) or classSpell()
end

-- true / false / "edge" / nil, plus the bracket and the limit used.
local function evaluate(unit)
    local minRange, maxRange = rc:GetRange(unit, true)
    minRange, maxRange = plain(minRange), plain(maxRange)
    if db.yards > 0 then
        return ns.Classify(minRange, maxRange, db.yards), minRange, maxRange, db.yards .. " yd"
    end
    local spell = currentSpell()
    if not spell then return nil, minRange, maxRange end
    -- The game's own answer is exact; the bracket is the fallback (e.g. a harmful spell on a friend).
    local inRange = plain(C_Spell.IsSpellInRange(spell.name, unit))
    if inRange == nil then inRange = ns.Classify(minRange, maxRange, spell.max) end
    return inRange, minRange, maxRange, spell.name
end

---------------------------------------------------------------------------
-- Boxes
---------------------------------------------------------------------------

local function font(parent, file, size, layer)
    local text = parent:CreateFontString(nil, layer or "OVERLAY")
    text:SetFont(file, size, "")
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 0.8)
    text:SetJustifyH("LEFT")
    return text
end

local function newBox(key, title, x, y)
    local box = CreateFrame("Frame", "RangeBox" .. key, UIParent)
    box.key, box.title, box.home = key, title, { "CENTER", "CENTER", x, y }
    box:SetSize(WIDTH, HEIGHT)
    box:SetClampedToScreen(true)
    box:SetMovable(true)
    box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", box.StartMoving)
    box:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, px, py = self:GetPoint()
        db.pos[self.key] = { point, relativePoint, px, py }
    end)

    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.055, 0.07, 0.9)
    -- Hairline border.
    for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 1 },
                            { "TOPLEFT", "BOTTOMLEFT", 1, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 0 } }) do
        local line = box:CreateTexture(nil, "BORDER")
        line:SetColorTexture(1, 1, 1, 0.08)
        line:SetPoint(edge[1])
        line:SetPoint(edge[2])
        if edge[3] > 0 then line:SetWidth(1) else line:SetHeight(1) end
    end

    box.glow = box:CreateTexture(nil, "BORDER")
    box.glow:SetPoint("TOPLEFT")
    box.glow:SetPoint("BOTTOMLEFT")
    box.glow:SetWidth(WIDTH * 0.6)
    box.glow:SetColorTexture(1, 1, 1, 1)
    box.accent = box:CreateTexture(nil, "ARTWORK")
    box.accent:SetPoint("TOPLEFT")
    box.accent:SetPoint("BOTTOMLEFT")
    box.accent:SetWidth(3)

    box.header = font(box, FONT_TEXT, 9)
    box.header:SetPoint("TOPLEFT", 14, -10)
    box.header:SetTextColor(0.55, 0.58, 0.65)

    box.pillText = font(box, FONT_TEXT, 8)
    box.pillText:SetPoint("TOPRIGHT", -16, -10)
    box.pill = box:CreateTexture(nil, "ARTWORK")
    box.pill:SetPoint("TOPLEFT", box.pillText, "TOPLEFT", -6, 3)
    box.pill:SetPoint("BOTTOMRIGHT", box.pillText, "BOTTOMRIGHT", 6, -3)

    box.value = font(box, FONT_NUMBER, 26)
    box.value:SetPoint("TOPLEFT", box.header, "BOTTOMLEFT", 0, -3)
    box.unitLabel = font(box, FONT_NUMBER, 12)
    box.unitLabel:SetPoint("BOTTOMLEFT", box.value, "BOTTOMRIGHT", 3, 3)
    box.unitLabel:SetText("yd")
    box.unitLabel:SetTextColor(0.55, 0.58, 0.65)

    box.name = font(box, FONT_TEXT, 10)
    box.name:SetPoint("BOTTOMLEFT", 14, 9)
    box.name:SetWidth(WIDTH * 0.55)
    box.name:SetWordWrap(false)
    box.spell = font(box, FONT_TEXT, 9)
    box.spell:SetPoint("BOTTOMRIGHT", -12, 9)
    box.spell:SetJustifyH("RIGHT")
    box.spell:SetWidth(WIDTH * 0.4)
    box.spell:SetWordWrap(false)
    box.spell:SetTextColor(0.55, 0.58, 0.65)

    box.color = { unpack(STATE.none, 1, 3) } -- shown colour, eased toward box.target
    box.target = STATE.none
    return box
end

local boxes = {
    target = newBox("Target", "TARGET", 0, -180),
    mouseover = newBox("Hover", "MOUSEOVER", 0, -260),
}

local function nameColor(unit)
    if plain(UnitIsDeadOrGhost(unit)) then return 0.5, 0.5, 0.5 end
    if plain(UnitIsPlayer(unit)) then
        local class = plain(select(2, UnitClass(unit)))
        local color = class and C_ClassColor.GetClassColor(class)
        if color then return color.r, color.g, color.b end
    end
    local reaction = plain(UnitReaction(unit, "player"))
    if not reaction then return 0.9, 0.9, 0.9 end
    if reaction <= 3 then return 1, 0.45, 0.45 end
    if reaction == 4 then return 1, 0.85, 0.35 end
    return 0.45, 0.9, 0.5
end

local function paint(box)
    local r, g, b = unpack(box.color)
    box.accent:SetColorTexture(r, g, b, 1)
    box.glow:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.16), CreateColor(r, g, b, 0))
    box.value:SetTextColor(r, g, b)
    box.pillText:SetTextColor(r, g, b)
    box.pill:SetColorTexture(r, g, b, 0.16)
end

local function refresh(box, unit, show)
    box:SetShown(show or not db.locked)
    if not box:IsShown() then return end
    box.header:SetText(db.locked and box.title or (box.title .. "  |cff8c94a6drag to move|r"))
    if not show then
        box.value:SetText("--")
        box.name:SetText("")
        box.spell:SetText("")
        box.target = STATE.none
    else
        local inRange, minRange, maxRange, limit = evaluate(unit)
        box.value:SetText(ns.FormatRange(minRange, maxRange))
        box.name:SetText((UnitName(unit))) -- SetText accepts secret names
        box.name:SetTextColor(nameColor(unit))
        box.spell:SetText(limit or "")
        box.target = STATE[inRange == nil and "none" or inRange]
    end
    box.pillText:SetText(box.target[4] or "")
    box.pill:SetShown(box.target[4] ~= nil)
end

local function applyLayout()
    for _, box in pairs(boxes) do
        local pos = db.pos[box.key] or box.home
        box:ClearAllPoints()
        box:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        box:SetScale(db.scale)
        box:EnableMouse(not db.locked) -- locked boxes never eat clicks
    end
end

local driver = CreateFrame("Frame")
local elapsed = 1
driver:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed >= 0.1 then
        elapsed = 0
        refresh(boxes.target, "target", UnitExists("target"))
        local hover = db.hover and UnitExists("mouseover") and not plain(UnitIsUnit("mouseover", "target"))
        if db.hover then
            refresh(boxes.mouseover, "mouseover", hover)
        else
            boxes.mouseover:Hide()
        end
    end
    local t = math.min(1, delta * 12) -- ease colours over ~0.1 s
    for _, box in pairs(boxes) do
        local c, goal = box.color, box.target
        if box:IsShown() and box.settled ~= goal then
            c[1], c[2], c[3] = c[1] + (goal[1] - c[1]) * t, c[2] + (goal[2] - c[2]) * t, c[3] + (goal[3] - c[3]) * t
            if math.abs(goal[1] - c[1]) + math.abs(goal[2] - c[2]) + math.abs(goal[3] - c[3]) < 0.003 then
                c[1], c[2], c[3] = goal[1], goal[2], goal[3]
                box.settled = goal
            end
            paint(box)
        end
    end
end)
driver:Hide()

---------------------------------------------------------------------------
-- Settings panel
---------------------------------------------------------------------------

local function label(range)
    return range and ("%s  %g yd"):format(range.name, range.max)
end

local function spellOptions()
    local container = Settings.CreateControlTextContainer()
    local default = classSpell()
    container:Add("auto", "Class default" .. (default and (" (" .. label(default) .. ")") or ""))
    local seen = { auto = true }
    local function add(key, id)
        local range = not seen[key] and spellRange(id)
        if range then
            seen[key] = true
            container:Add(key, label(range))
        end
    end
    add(db.spell, tonumber(db.spell:match("(%d+)$")))
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
            local item = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
            if item and item.itemType == Enum.SpellBookItemType.Spell and item.spellID
                and not item.isPassive and not item.isOffSpec then
                add("spell:" .. item.spellID, item.spellID)
            end
        end
    end
    return container:GetData()
end

local function setting(key, varType, name)
    return Settings.RegisterProxySetting(category, "RANGEBOX_" .. key:upper(), varType, name, DEFAULTS[key],
        function() return db[key] end, function(value) db[key] = value; applyLayout() end)
end

local function createSettings()
    category = Settings.RegisterVerticalLayoutCategory("Range Box")
    Settings.CreateDropdown(category, setting("spell", Settings.VarType.String, "Range check spell"), spellOptions,
        "The box turns green when this spell can reach the unit. Class default is your main attack.")

    local yards = Settings.CreateSliderOptions(0, 45, 1)
    yards:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return value == 0 and "Use spell" or ("%d yd"):format(value)
    end)
    Settings.CreateSlider(category, setting("yards", Settings.VarType.Number, "Custom range"), yards,
        "Use a fixed distance instead of a spell. 0 uses the spell above.")

    Settings.CreateCheckbox(category, setting("hover", Settings.VarType.Boolean, "Show mouseover box"),
        "A second box with the distance to whatever unit is under the mouse.")
    Settings.CreateCheckbox(category, setting("locked", Settings.VarType.Boolean, "Lock boxes"),
        "Uncheck to drag the boxes around.")

    local scale = Settings.CreateSliderOptions(0.6, 1.6, 0.05)
    scale:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value) return ("x%.2f"):format(value) end)
    Settings.CreateSlider(category, setting("scale", Settings.VarType.Number, "Scale"), scale)

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
    RangeBoxDB = RangeBoxDB or {} -- SavedVariables exist only from here on
    db = RangeBoxDB
    for key, value in pairs(DEFAULTS) do
        if db[key] == nil then db[key] = type(value) == "table" and {} or value end
    end
    createSettings()
    applyLayout()
    driver:Show()
end)

SLASH_RANGEBOX1 = "/rb"
SLASH_RANGEBOX2 = "/rangebox"
SlashCmdList.RANGEBOX = function(msg)
    local command = msg:lower():match("^%s*(%S*)")
    if command == "lock" or command == "unlock" then
        db.locked = command == "lock"
        applyLayout()
        say(db.locked and "boxes locked." or "boxes unlocked, drag them where you like.")
    elseif command == "reset" then
        db.pos = {}
        applyLayout()
        say("positions reset.")
    elseif command == "" then
        if InCombatLockdown() then
            say("the settings panel can't open in combat.")
        else
            Settings.OpenToCategory(category:GetID())
        end
    else
        say("/rb (settings) | /rb lock | /rb unlock | /rb reset")
    end
end
