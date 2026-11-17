-- Ammo counter: the equipped ammo (ammo slot) counted across the bags, split into what sits in a
-- quiver / ammo pouch (those give the ranged haste bonus) and what sits in normal bags.
-- Bag APIs are never secret for the player's own bags.
local _, ns = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local LATIN = { enUS = 1, enGB = 1, deDE = 1, frFR = 1, esES = 1, esMX = 1, itIT = 1, ptBR = 1 }
local FONT = LATIN[GetLocale()] and "Fonts\\ARIALN.TTF" or STANDARD_TEXT_FONT
local TEXT = { 0.93, 0.94, 0.96 }
local LOW = { 0.93, 0.36, 0.36 }
local AMBER = "|cffffb847"
local EMPTY_ICON = 134400 -- question mark, for the placeholder while unlocked

local armed = true
local frame = CreateFrame("Frame", "UltimateHunterAmmo", UIParent, "BackdropTemplate")
frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
frame:SetBackdropColor(0, 0, 0, 0.6)
frame:SetBackdropBorderColor(0.2, 0.216, 0.263, 1)
local icon = frame:CreateTexture(nil, "ARTWORK")
icon:SetPoint("TOPLEFT", 3, -3)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
-- Hover-only area over the icon: the equipped ammo's real tooltip. Clicks pass through so the
-- frame can still be dragged while unlocked.
local hover = CreateFrame("Frame", nil, frame)
hover:SetAllPoints(icon)
hover:SetMouseMotionEnabled(true)
hover:SetMouseClickEnabled(false)
hover:SetScript("OnEnter", function(self)
	if not GetInventoryItemID("player", INVSLOT_AMMO) then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetInventoryItem("player", INVSLOT_AMMO)
	GameTooltip:Show()
end)
hover:SetScript("OnLeave", GameTooltip_Hide)
local total = frame:CreateFontString(nil, "OVERLAY")
total:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, 0)
local where = frame:CreateFontString(nil, "OVERLAY")
where:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 6, 0)

-- Returns the equipped ammo's item ID, count in quivers/pouches, count in normal bags, has a quiver.
local function count()
	local id = GetInventoryItemID("player", INVSLOT_AMMO)
	local quiver, bags, hasQuiver = 0, 0, false
	if not id then return nil, 0, 0, false end
	for bag = 0, NUM_BAG_SLOTS do
		local _, family = C_Container.GetContainerNumFreeSlots(bag)
		local special = bag ~= 0 and family and family ~= 0 -- non-zero family: quiver or ammo pouch
		if special then hasQuiver = true end
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID == id then
				if special then quiver = quiver + info.stackCount else bags = bags + info.stackCount end
			end
		end
	end
	return id, quiver, bags, hasQuiver
end

local function update()
	local db = ns.db
	if not db.ammoEnabled then frame:Hide() return end
	local id, quiver, bags, hasQuiver = count()
	frame:SetShown(id ~= nil or not db.locked) -- unlocked: placeholder to drag
	if not id then
		icon:SetTexture(EMPTY_ICON)
		total:SetText("Ammo")
		total:SetTextColor(unpack(TEXT))
		where:SetText("no ammo equipped")
		return
	end
	local sum = quiver + bags
	icon:SetTexture(C_Item.GetItemIconByID(id))
	total:SetText(sum)
	total:SetTextColor(unpack(sum <= db.ammoWarnAt and LOW or TEXT))
	local bagText = bags > 0 and (AMBER .. "Bags " .. bags .. "|r") or ("Bags " .. bags)
	where:SetText((hasQuiver and ("Quiver " .. quiver) or (AMBER .. "No quiver|r")) .. " · " .. bagText)

	local fire
	fire, armed = ns.AmmoAlert(armed, sum, db.ammoWarnAt)
	if fire and db.ammoAlert then ns.AmmoWarn(sum) end
end

-- Also the settings' test button.
function ns.AmmoWarn(sum)
	RaidWarningUtil.AddMessage(("Almost out of ammo! (%d left)"):format(sum), ChatTypeInfo.RAID_WARNING)
	ns.PlaySound(ns.db.ammoSound)
end

local function apply()
	local db = ns.db
	local size = db.ammoFontSize
	local iconSize = math.floor(size * 2.2)
	icon:SetSize(iconSize, iconSize)
	total:SetFont(FONT, size, "OUTLINE")
	where:SetFont(FONT, math.max(8, math.floor(size * 0.7)), "OUTLINE")
	where:SetTextColor(unpack(TEXT))
	where:SetShown(db.ammoShowBags)
	frame:SetSize(iconSize + size * 9, iconSize + 6)
	frame:ClearAllPoints()
	local pos = db.ammoPos
	if pos[1] then
		frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		frame:SetPoint("CENTER", 0, -180)
	end
	frame:EnableMouse(not db.locked)
	update()
end
ns.modules[#ns.modules + 1] = apply

frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, relativePoint, x, y = self:GetPoint()
	ns.db.ammoPos = { point, relativePoint, x, y }
end)
frame:Hide()

frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function()
	if ns.db then update() end
end)
