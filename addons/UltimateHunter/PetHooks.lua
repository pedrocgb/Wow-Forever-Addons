local _, ns = ...

-- Pet training hooks: "Teaches" tooltip lines, recording tames, beast waypoints.

local function say(text)
	print("|cff4f8fffThe Ultimate Hunter Addon|r: " .. text)
end

local known = {}  -- ability -> highest rank in the pet spellbook
local petFamily   -- familyID of the current pet, nil if none/secret
local TAME_BEAST = 1515
local tameAt      -- GetTime() of our last successful Tame Beast

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
	-- A freshly tamed pet knows exactly what its beast teaches; the pet GUID keeps the beast's npcID.
	-- Keep overwriting for a few seconds: the pet spellbook can fill in over several events.
	if tameAt and GetTime() - tameAt < 10 and n > 0 and ns.db then
		local npc = ns.NpcIDFromGUID(UnitGUID("pet"))
		if npc then
			local first = not ns.db.tamed[npc]
			ns.db.tamed[npc] = ns.PetTamedTeaches(known)
			if first then say("recorded what " .. (UnitName("pet") or npc) .. " teaches.") end
		end
	end
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
	local lines, confirmed
	if npcID then lines, confirmed = ns.PetTeachesText(npcID, known, petFamily) end
	if not lines then return end
	tooltip:AddLine(confirmed and "Teaches:" or "Teaches (Classic data, unconfirmed):", 0.67, 0.83, 0.45) -- hunter class colour
	for _, s in ipairs(lines) do tooltip:AddLine(s, 1, 1, 1) end
end)

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

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterUnitEvent("UNIT_PET", "player")
frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
frame:SetScript("OnEvent", function(_, event, _, _, spellID)
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if not issecretvalue(spellID) and spellID == TAME_BEAST then tameAt = GetTime() refreshPet() end
	else
		refreshPet()
	end
end)
