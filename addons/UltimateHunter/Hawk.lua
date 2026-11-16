-- Summon Hawk tracker: one icon per active hawk (18 s), like a buff, growing right to left.
-- Hawks are temporary guardians: no pet or totem slot, no unit token of their own.
-- Cast: UNIT_SPELLCAST_SUCCEEDED (never secret for the player). Landing: the triggered summon
-- spell, or the hawk's nameplate appearing. Death: UNIT_DIED with the hawk's GUID, which we learn
-- from any token that shows the hawk (friendly guardian nameplate, mouseover, target). A player's
-- guardian is player-controlled, so its GUID and owner checks are not secret.
local _, ns = ...

local HAWK_SPELL = 1293241
local SUMMON_SPELL = 1312639 -- triggered when the hawk lands (Wowhead: Trigger Missile -> Summon Hawk)
local HAWK_NPC = 264850 -- seen in game 2026-11-16; other NPC IDs are still learned at runtime
local RANKS = { [1293241] = true, [1293525] = true, [1293526] = true, [1293527] = true }
local WHITE = "Interface\\Buttons\\WHITE8X8"
local LATIN = { enUS = 1, enGB = 1, deDE = 1, frFR = 1, esES = 1, esMX = 1, itIT = 1, ptBR = 1 }
local FONT = LATIN[GetLocale()] and "Fonts\\ARIALN.TTF" or STANDARD_TEXT_FONT
local BORDER = { 0.2, 0.216, 0.263, 1 }
local WARN_AT = 3 -- seconds left when the number turns red
local WARN = { 0.93, 0.36, 0.36 }

local hawks = {}
local icons = {}
local holder = CreateFrame("Frame", "UltimateHunterHawks", UIParent)

local function plain(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local function debug(...)
	if ns.debug then print("|cff4f8fffUH hawk|r", ...) end
end

-- Any rank: known IDs, or the same name as rank 1 (the summon spell is checked before this).
local function isHawkCast(id)
	if RANKS[id] then return true end
	local name = C_Spell.GetSpellName(HAWK_SPELL)
	return name ~= nil and C_Spell.GetSpellName(id) == name
end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------

local function newIcon()
	local f = CreateFrame("Frame", nil, holder, "BackdropTemplate")
	f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	f:SetBackdropColor(0, 0, 0, 1)
	f:SetBackdropBorderColor(unpack(BORDER))
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetPoint("TOPLEFT", 1, -1)
	f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
	f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- Reverse swipe: starts lit and darkens as the hawk's time runs out, like a buff.
	f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetAllPoints(f.tex)
	f.cd:SetReverse(true)
	f.cd:SetDrawEdge(false)
	f.cd:SetHideCountdownNumbers(true) -- our own number, so it shows regardless of the countdown CVar
	f.cd:SetSwipeColor(0, 0, 0, 0.75)
	local top = CreateFrame("Frame", nil, f)
	top:SetAllPoints()
	top:SetFrameLevel(f.cd:GetFrameLevel() + 1)
	f.text = top:CreateFontString(nil, "OVERLAY")
	f.text:SetPoint("CENTER")
	f.num = top:CreateFontString(nil, "OVERLAY")
	f.num:SetPoint("TOPLEFT", 3, -2)
	return f
end

for i = 1, ns.HAWK_MAX do icons[i] = newIcon() end

local function sorted()
	local list = {}
	for i, h in ipairs(hawks) do list[i] = h end
	table.sort(list, function(a, b) return a.start < b.start end) -- oldest on the right
	return list
end

-- Re-assign icons after any tracker change.
local function render()
	local db = ns.db
	local list = sorted()
	for i, icon in ipairs(icons) do
		local h = list[i]
		icon.hawk = h
		icon:SetShown(h ~= nil or not db.locked) -- unlocked: placeholders to drag
		icon.num:SetText(h and h.num or (db.locked and "" or i))
		if h then
			icon.cd:SetCooldown(h.start, h.dur)
		else
			icon.cd:Clear()
			icon.text:SetText(db.locked and "" or "18")
		end
	end
	holder:SetShown(db.hawkEnabled and (#hawks > 0 or not db.locked))
end

local elapsed = 0
holder:SetScript("OnUpdate", function(_, delta)
	elapsed = elapsed + delta
	if elapsed < 0.1 then return end
	elapsed = 0
	local now = GetTime()
	if ns.HawkExpire(hawks, now) then render() end
	for _, icon in ipairs(icons) do
		local h = icon.hawk
		if h then
			local left = h.start + h.dur - now
			icon.text:SetText(("%d"):format(math.ceil(left)))
			if left <= WARN_AT then
				icon.text:SetTextColor(unpack(WARN))
			else
				icon.text:SetTextColor(ns.Hex(ns.db.hawkColText))
			end
		end
	end
end)

local function apply()
	local db = ns.db
	local size, gap = db.hawkSize, db.hawkSpacing
	holder:SetSize(ns.HAWK_MAX * size + (ns.HAWK_MAX - 1) * gap, size)
	holder:ClearAllPoints()
	local pos = db.hawkPos
	if pos[1] then
		holder:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		holder:SetPoint("CENTER", 0, -120)
	end
	holder:EnableMouse(not db.locked)
	local texture = C_Spell.GetSpellTexture(HAWK_SPELL)
	for i, icon in ipairs(icons) do
		icon:SetSize(size, size)
		icon:ClearAllPoints()
		icon:SetPoint("TOPRIGHT", -(i - 1) * (size + gap), 0) -- right to left
		icon.tex:SetTexture(texture)
		icon.text:SetFont(FONT, db.hawkFontSize, "OUTLINE")
		icon.text:SetTextColor(ns.Hex(db.hawkColText))
		icon.num:SetFont(FONT, math.max(8, math.floor(db.hawkFontSize * 0.6)), "OUTLINE")
		icon.num:SetTextColor(ns.Hex(db.hawkColText))
	end
	render()
end
ns.modules[#ns.modules + 1] = apply

holder:SetMovable(true)
holder:SetClampedToScreen(true)
holder:RegisterForDrag("LeftButton")
holder:SetScript("OnDragStart", holder.StartMoving)
holder:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, relativePoint, x, y = self:GetPoint()
	ns.db.hawkPos = { point, relativePoint, x, y }
end)
holder:Hide()

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

-- If `unit` is one of our guardians (not the pet), its GUID and NPC ID.
local function ownGuardian(unit)
	if not (plain(UnitExists(unit)) and plain(UnitIsMinion(unit))
		and plain(UnitIsOwnerOrControllerOfUnit("player", unit))) then return end
	local guid = plain(UnitGUID(unit))
	if not guid or guid == plain(UnitGUID("pet")) then return end
	return guid, C_CreatureInfo.GetCreatureID(guid)
end

-- A token that may show one of our hawks. An unknown guardian counts as a hawk only when it shows
-- up right after a cast; its NPC ID is then remembered (Wowhead doesn't list it).
-- "Hawk 1" / "Hawk 2" above the hawk's nameplate. Plates are recycled, so every add/remove clears
-- it first. Friendly plates are forbidden to addons in instances: GetNamePlateForUnit gives nil there.
local function label(unit, h)
	if not unit:match("^nameplate") then return end
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then return end
	if not plate.uhHawk then
		plate.uhHawk = plate:CreateFontString(nil, "OVERLAY")
		plate.uhHawk:SetPoint("BOTTOM", plate, "TOP", 0, 2)
		plate.uhHawk:SetFont(FONT, 14, "OUTLINE")
	end
	plate.uhHawk:SetTextColor(ns.Hex(ns.db.hawkColText))
	plate.uhHawk:SetText(h and ("Hawk " .. h.num) or "")
end

local function seen(unit)
	local guid, npc = ownGuardian(unit)
	if ns.debug and #hawks > 0 and plain(UnitExists(unit)) and plain(UnitIsFriend("player", unit)) then
		debug("unit", unit, "minion", tostring(plain(UnitIsMinion(unit))),
			"ours", tostring(plain(UnitIsOwnerOrControllerOfUnit("player", unit))), "npc", tostring(npc))
	end
	if not npc then return end
	local now = GetTime()
	if npc ~= HAWK_NPC and not ns.db.hawkNpcs[npc] then
		if not ns.HawkExpected(hawks, now) then return end
		ns.db.hawkNpcs[npc] = true
		debug("learned hawk NPC", npc)
	end
	debug("seen", unit, guid)
	local h = ns.HawkSeen(hawks, now, guid)
	if h then
		label(unit, h)
		render()
	end
end

local events = {
	UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
		spellID = plain(spellID)
		if unit ~= "player" or not spellID then return end
		local now = GetTime()
		if ns.debug and spellID ~= SUMMON_SPELL and not isHawkCast(spellID) and ns.HawkExpected(hawks, now) then
			debug("spell after cast:", spellID, C_Spell.GetSpellName(spellID)) -- finds the real landing spell
		end
		if spellID == SUMMON_SPELL then
			debug("landed (summon spell)")
			ns.HawkLand(hawks, now)
		elseif isHawkCast(spellID) then
			debug("cast", spellID)
			ns.HawkCast(hawks, now)
		else
			return
		end
		render()
	end,
	NAME_PLATE_UNIT_ADDED = function(unit)
		label(unit, nil)
		seen(unit)
	end,
	NAME_PLATE_UNIT_REMOVED = function(unit) label(unit, nil) end,
	UPDATE_MOUSEOVER_UNIT = function() seen("mouseover") end,
	PLAYER_TARGET_CHANGED = function() seen("target") end,
	UNIT_DIED = function(guid)
		guid = plain(guid)
		local npc = guid and C_CreatureInfo.GetCreatureID(guid)
		if #hawks > 0 then debug("UNIT_DIED", guid or "(secret)", "npc", tostring(npc)) end
		if not guid then return end
		local isHawk = npc and (npc == HAWK_NPC or ns.db.hawkNpcs[npc])
		-- Solo, a hawk death we never matched to a unit is still ours (nobody else's hawk is near).
		if ns.HawkDied(hawks, guid, isHawk and not IsInGroup()) then
			debug("died", guid)
			render()
		elseif isHawk then
			debug("a hawk died that isn't tracked", guid)
		end
	end,
	PLAYER_DEAD = function()
		wipe(hawks)
		render()
	end,
}

holder:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
for event in pairs(events) do
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then holder:RegisterEvent(event) end
end
holder:SetScript("OnEvent", function(_, event, ...)
	if ns.db and ns.db.hawkEnabled then events[event](...) end
end)
