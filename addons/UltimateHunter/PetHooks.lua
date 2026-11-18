local _, ns = ...

-- Pet training hooks: "Teaches" tooltip lines, trainer TP-left line, beast waypoints.

local function say(text)
	print("|cff4f8fffThe Ultimate Hunter Addon|r: " .. text)
end

local known = {}  -- ability -> highest rank in the pet spellbook
local petFamily   -- familyID of the current pet, nil if none/secret

local function refreshPet()
	local ids = {}
	local n = C_SpellBook.HasPetSpells() or 0
	for i = 1, n do
		local info = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Pet)
		if info and info.spellID then ids[#ids + 1] = info.spellID end
	end
	known = ns.PetKnownRanks(ids)
	local fam = select(2, UnitCreatureFamily("pet"))
	petFamily = (fam and not issecretvalue(fam)) and fam or nil
end

-- "Creature-0-server-instance-zone-npcID-spawn" -> npcID; nil for players etc.
function ns.NpcIDFromGUID(guid)
	if not guid or issecretvalue(guid) then return nil end
	return tonumber((select(6, strsplit("-", guid))))
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
	if tooltip ~= GameTooltip or not (ns.db and ns.db.petTooltip) then return end
	if select(2, UnitClass("player")) ~= "HUNTER" then return end
	local _, unit = tooltip:GetUnit()
	if not unit or issecretvalue(unit) then return end
	local npcID = ns.NpcIDFromGUID(UnitGUID(unit))
	local lines = npcID and ns.PetTeachesText(npcID, known, petFamily)
	if not lines then return end
	tooltip:AddLine("Teaches:", 0.67, 0.83, 0.45) -- hunter class colour
	for _, s in ipairs(lines) do tooltip:AddLine(s, 1, 1, 1) end
end)

---------------------------------------------------------------------------
-- Trainer overlay (Blizzard_TrainerUI is load-on-demand)
---------------------------------------------------------------------------

local overlay

local function updateOverlay()
	if not overlay then return end
	local skill = GetTrainerSelectionIndex()
	local cost = skill and skill > 0 and GetTrainerServiceCost(skill)
	if not (ns.db and ns.db.petTrainerOverlay) or C_Trainer.GetTrainerType() ~= Enum.TrainerType.Pet
		or not cost or cost <= 0 then
		overlay:Hide()
		return
	end
	local total, used = C_PetInfo.GetPetTrainingPoints()
	local left = ns.PetTPAfter(total, used, cost)
	if not left then overlay:Hide() return end
	overlay:SetText("TP left after training: " .. left)
	if left < 0 then overlay:SetTextColor(1, 0.2, 0.2) else overlay:SetTextColor(1, 0.82, 0) end
	overlay:Show()
end

local function hookTrainer()
	if overlay then return end
	-- trainingPoints is only shown in pet mode, so the overlay hides with it.
	local tp = ClassTrainerFrame.trainingPoints
	overlay = tp:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	overlay:SetPoint("LEFT", tp.text, "RIGHT", 12, 0)
	overlay:Hide()
	hooksecurefunc("ClassTrainer_SetSelection", updateOverlay)
	hooksecurefunc("ClassTrainerFrame_UpdateTrainingPoints", updateOverlay)
end

---------------------------------------------------------------------------
-- Waypoints
---------------------------------------------------------------------------

function ns.PetWaypoint(npcID)
	local b = ((ns.PetData or {}).beasts or {})[npcID]
	if not b then return end
	if not (b.map and b.x and b.y) then
		-- Wowhead harvest has zones but no spawn coordinates: show the zone map instead.
		if b.map and OpenWorldMap then
			OpenWorldMap(b.map)
			say((b.name or npcID) .. " lives in " .. (b.zone or "this zone") .. ".")
		else
			say("No coordinates for " .. (b.name or npcID))
		end
		return
	end
	local tomtom = _G.TomTom
	if tomtom and tomtom.AddWaypoint then
		tomtom:AddWaypoint(b.map, b.x / 100, b.y / 100, { title = b.name })
	elseif C_Map.CanSetUserWaypointOnMap(b.map) then
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(b.map, b.x / 100, b.y / 100))
		C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	else
		say("Can't place a waypoint on that map for " .. (b.name or npcID))
		return
	end
	say(string.format("Waypoint set: %s (%s %.1f, %.1f)", b.name, b.zone or "?", b.x, b.y))
end

---------------------------------------------------------------------------

ns.modules[#ns.modules + 1] = updateOverlay

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterUnitEvent("UNIT_PET", "player")
frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == "Blizzard_TrainerUI" then hookTrainer() end
	else
		refreshPet()
	end
end)
if C_AddOns.IsAddOnLoaded("Blizzard_TrainerUI") then hookTrainer() end
