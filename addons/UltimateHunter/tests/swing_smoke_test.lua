-- Headless smoke test: loads the real addon files against a permissive fake WoW API, then drives
-- a ranged swing through its phases. Catches wiring bugs, not visuals.
-- Run from the addon folder: luajit tests/swing_smoke_test.lua
local M -- "anything" object: every field/call yields itself, so unknown APIs don't crash
M = setmetatable({}, { __index = function() return M end, __call = function() return M end })

local Frame = {}
local fmeta = { __index = function(_, k) return Frame[k] or (k:match("^%u") and function() return M end) or nil end }
local frames = {}
local function newFrame()
	local f = setmetatable({ _scripts = {}, _shown = true, _events = {} }, fmeta)
	frames[#frames + 1] = f
	return f
end
function Frame:SetScript(n, fn) self._scripts[n] = fn end
function Frame:Fire(n, ...) if self._scripts[n] then return self._scripts[n](self, ...) end end
function Frame:RegisterEvent(e) self._events[e] = true end
function Frame:RegisterUnitEvent(e) self._events[e] = true end
function Frame:UnregisterEvent(e) self._events[e] = nil end
function Frame:Show() self._shown = true end
function Frame:Hide() self._shown = false end
function Frame:SetShown(v) self._shown = v and true or false end
function Frame:IsShown() return self._shown end
function Frame:SetText(t) self._text = t end
function Frame:SetPoint(...) self._point = { ... } end
function Frame:ClearAllPoints() self._point = nil end
function Frame:GetWidth() return 200 end
function Frame:GetStringHeight() return 14 end
function Frame:GetStringWidth() return 50 end
function Frame:GetName() return self._name end
function Frame:HookScript(n, fn)
	local old = self._scripts[n]
	self._scripts[n] = old and function(...) old(...) fn(...) end or fn
end
function Frame:SetupMenu(fn) self._menu = fn end
function Frame:SetAlpha(a) self._alpha = a end
function Frame:GetFrameLevel() return 1 end
function Frame:CreateTexture() return newFrame() end
function Frame:CreateFontString() return newFrame() end
function Frame:CreateAnimationGroup() local g = newFrame() function g:Play() played = (played or 0) + 1 end return g end

local now, speed, sounds = 100, 2, 0
CreateFrame = function(_, name) local f = newFrame() if name then _G[name] = f f._name = name end return f end
CreateFont = function() return newFrame() end
AnchorUtil, ScrollUtil = M, M -- Skin.lua
tDeleteItem = function(t, v) for i = #t, 1, -1 do if t[i] == v then table.remove(t, i) end end end
issecretvalue = function() return false end
UIParent = newFrame()
Enum = { PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 } }
SOUNDKIT = setmetatable({}, { __index = function(_, k) return k end })
GetLocale = function() return "enUS" end
GetTime = function() return now end
GetNetStats = function() return 0, 0, 40, 60 end
UnitAttackSpeed = function() return 2.6, nil, speed end
IsPlayerMoving = function() return false end
InCombatLockdown = function() return false end
PlaySound = function() sounds = sounds + 1 end
Settings = setmetatable({ RegisterVerticalLayoutCategory = function() return M, M end,
	RegisterVerticalLayoutSubcategory = function() return M, M end }, { __index = M })
CreateSettingsListSectionHeaderInitializer = M
MinimalSliderWithSteppersMixin = M
SlashCmdList = {}
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
C_Spell = { GetSpellName = function(id) return (id == 1293241 or id == 1312639 or id == 9999) and "Summon Hawk" or "Other" end,
	GetSpellTexture = function() return 132172 end }
local units, inGroup = {}, false -- token -> { guid, owned, minion }
UnitExists = function(u) return units[u] ~= nil end
UnitIsMinion = function(u) return units[u] and units[u].minion end
UnitIsOwnerOrControllerOfUnit = function(_, u) return units[u] and units[u].owned end
UnitGUID = function(u) return units[u] and units[u].guid end
C_CreatureInfo = { GetCreatureID = function(guid) return tonumber(guid:match("%-(%d+)%-%w+$")) end,
	GetCreatureFamilyInfo = function(id) return id == 2 and { id = 2, name = "Cat", iconFile = 132185 } or nil end }
IsInGroup = function() return inGroup end
local plates = {}
C_NamePlate = { GetNamePlateForUnit = function(u) plates[u] = plates[u] or newFrame() return plates[u] end }
UnitIsFriend = function() return true end
CreateSettingsButtonInitializer = M
local inRange, autoSlot
C_SwingTimer = { EnableRangeCheck = function() end, IsTargetWithinSwingRange = function() return inRange end }
C_ActionBar = { IsAutoRepeatAction = function(slot) return slot == autoSlot end }

-- Bags: [bag] = { family, { {itemID, stackCount}... } }. Bag 1 is a quiver.
local ammoID, bagData, warnings = nil, {}, {} -- no ammo until the ammo section
INVSLOT_AMMO, NUM_BAG_SLOTS = 0, 4
GetInventoryItemID = function(_, slot) return slot == 0 and ammoID or nil end
C_Container = {
	GetContainerNumFreeSlots = function(b) return 0, bagData[b] and bagData[b][1] or 0 end,
	GetContainerNumSlots = function(b) return bagData[b] and #bagData[b][2] or 0 end,
	GetContainerItemInfo = function(b, i) local it = bagData[b][2][i] return it and { itemID = it[1], stackCount = it[2] } end,
}
C_Item = { GetItemIconByID = function() return 1 end }
RaidWarningUtil = { AddMessage = function(t) warnings[#warnings + 1] = t end }
ChatTypeInfo = {}
local ns = {}
-- Pets
local pet -- nil: no pet out
C_PetInfo = { GetPetTrainingPoints = function() return 100, 30 end, GetPetLoyalty = function() return "Loyal" end,
	GetPetHappiness = function() return 3, 125, 1 end }
C_SpellBook = { HasPetSpells = function() return pet and 1 or nil end,
	GetSpellBookItemInfo = function() return { spellID = 101 } end }
Enum.SpellBookSpellBank = { Player = 0, Pet = 1 }
UnitCreatureFamily = function() if pet then return "Cat", 2 end end
GetPetExperience = function() return 50, 200 end
UnitLevel = function() return 20 end
UnitName = function() return "Shadow" end
SetPortraitTexture = function() end
UISpecialFrames = {}
tinsert = table.insert
TooltipDataProcessor = M -- PetHooks.lua
Enum.TooltipDataType = { Unit = 2 }
C_AddOns = { IsAddOnLoaded = function() return false end }
for _, file in ipairs({ "Logic.lua", "Skin.lua", "Swing.lua", "Hawk.lua", "Ammo.lua", "PetData.lua", "PetTraining.lua", "PetHooks.lua",
	"Options.lua" }) do
	local f = io.open(file) -- PetHooks.lua is written separately and may not exist yet
	if f then f:close() assert(loadfile(file))("UltimateHunter", ns) else assert(file == "PetHooks.lua", file) end
end
local function broadcast(event, ...)
	for _, f in ipairs(frames) do if f._events[event] then f:Fire("OnEvent", event, ...) end end
end
broadcast("ADDON_LOADED", "UltimateHunter")
autoSlot = 7 -- /reload with Auto Shot already running
broadcast("PLAYER_ENTERING_WORLD")
local ranged, main
for _, f in ipairs(frames) do
	if f.def and f.def.ranged then ranged = f elseif f.def and f.def.key == "main" then main = f end
end
assert(ranged:IsShown(), "auto repeat seeded from the action bars")
assert(not main:IsShown(), "melee bar defaults to in combat only")
broadcast("PLAYER_REGEN_DISABLED") assert(main:IsShown())
broadcast("PLAYER_REGEN_ENABLED") assert(not main:IsShown())
ns.db.mainVisibility = "always" ns.Apply() assert(main:IsShown())
ns.db.mainVisibility = "combat" ns.Apply()
assert(UltimateHunterDB.rangedSound == "tick" and ns.db.locked and ns.db.mainSound == "off")

local holder = UltimateHunterSwing
local function stateText()
	holder:Fire("OnUpdate", 0.016)
	for _, f in ipairs(frames) do if f._text and f._text:match("%u%u%u") then return f._text end end
end

broadcast("START_AUTOREPEAT_SPELL")
assert(ranged:IsShown(), "visible while Auto Shot is on")
broadcast("PLAYER_SWING", 2, 2) -- ranged, 2.0 s; lead = 0.5 + 0.06
broadcast("PLAYER_STARTED_MOVING")
now = 101.0 assert(stateText() == "MOVE")
assert(sounds == 0)
now = 101.5 assert(stateText() == "STOP! SHOT DELAYED")
assert(sounds == 1 and played == 1, "alert once when moving past the stop line")
now = 101.6 stateText()
assert(sounds == 1, "only one alert per swing")
now = 102.2 assert(stateText() == "STOP TO SHOOT")
broadcast("PLAYER_STOPPED_MOVING")
assert(stateText() == "AIMING")

-- Standing still at the stop line: no alert.
broadcast("PLAYER_SWING", 2, 2)
now = 103.9 assert(stateText() == "STAND STILL")
assert(sounds == 1)

-- Haste mid-swing (2.0 -> 1.5 s weapon speed) rescales the running swing.
now = 104.2 broadcast("PLAYER_SWING", 2, 2)
now = 105.2 speed = 1.5 broadcast("UNIT_RANGEDDAMAGE", "player")
now = 105.6 assert(stateText() == "STAND STILL") -- would still be MOVE without the rescale

-- Alert early: 300 ms before the stop line (1.44 s), while the bar still says MOVE.
ns.db.rangedAlertEarly = 300
now = 110 broadcast("PLAYER_SWING", 2, 2)
broadcast("PLAYER_STARTED_MOVING")
now = 111.1 assert(stateText() == "MOVE" and sounds == 1)
now = 111.15 assert(stateText() == "MOVE" and sounds == 2, "early alert")

-- Melee flash and sound on each swing (bar shown in combat).
broadcast("PLAYER_REGEN_DISABLED")
ns.db.mainFlash, ns.db.mainSound = true, "tick"
local before = played
broadcast("PLAYER_SWING", 2.6, 0)
assert(played == before + 1 and sounds == 3)
broadcast("PLAYER_SWING", 2.6, 1) -- off hand has its own (off) alerts
assert(played == before + 1 and sounds == 3, "per-bar alerts")

-- Out of range dims the ranged bar, back in range restores it.
broadcast("PLAYER_SWING_RANGE_UPDATE", 2, false, true)
assert(ranged._alpha < 1)
broadcast("PLAYER_SWING_RANGE_UPDATE", 2, true, true)
assert(ranged._alpha == 1)
broadcast("PLAYER_SWING_RANGE_UPDATE", 2, false, false) -- no check made: not out of range
assert(ranged._alpha == 1)

-- Center style: second half-bar shown, per bar.
assert(not ranged.bar2:IsShown())
ns.db.rangedStyle = "center" ns.Apply()
assert(ranged.bar2:IsShown() and ranged.mark2:IsShown() and not main.bar2:IsShown())
stateText()
-- Anchored: main hangs under ranged. Free: each bar on its own saved position.
assert(main._point[2] == ranged)
ns.db.anchored = false
ns.db.mainPos = { "CENTER", "CENTER", 10, 20 }
ns.Apply()
assert(main._point[2] == UIParent and main._point[4] == 10, "free bar uses its own position")
print("swing smoke ok")

-- Summon Hawk ------------------------------------------------------------
local hawkFrame = UltimateHunterHawks
local function shownIcons()
	local n, texts = 0, {}
	for _, f in ipairs(frames) do
		if f.cd and f._shown then n = n + 1 texts[#texts + 1] = f.text._text end
	end
	return n, texts
end
local function tick() hawkFrame:Fire("OnUpdate", 1) end
local function hawk(n) return "Creature-0-1-2-3-555-" .. n end -- NPC 555
assert(not hawkFrame:IsShown(), "hidden with no hawks")

now = 200 broadcast("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1293241)
assert(hawkFrame:IsShown() and shownIcons() == 1)
-- Its nameplate shows up: NPC learned, timer starts at landing.
now = 200.8 units.nameplate1 = { guid = hawk("A"), owned = true, minion = true }
broadcast("NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(ns.db.hawkNpcs[555], "hawk NPC learned")
assert(plates.nameplate1.uhHawk._text == "Hawk 1", "nameplate labelled")
tick() local _, texts = shownIcons() assert(texts[1] == "18")
-- Another player's guardian nameplate is ignored.
units.nameplate2 = { guid = "Creature-0-1-2-3-777-B", owned = false, minion = true }
broadcast("NAME_PLATE_UNIT_ADDED", "nameplate2")
-- Second hawk, any rank (matched by name).
now = 202 broadcast("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 9999)
now = 202.6 units.nameplate3 = { guid = hawk("C"), owned = true, minion = true }
broadcast("NAME_PLATE_UNIT_ADDED", "nameplate3")
assert(shownIcons() == 2 and plates.nameplate3.uhHawk._text == "Hawk 2")
assert(plates.nameplate2.uhHawk._text == "", "other guardians unlabelled")
broadcast("NAME_PLATE_UNIT_REMOVED", "nameplate3")
assert(plates.nameplate3.uhHawk._text == "", "recycled plate cleared")
-- Someone else's hawk dies in a group: ignored. Ours dies: removed.
inGroup = true
broadcast("UNIT_DIED", hawk("ZZ"))
assert(shownIcons() == 2)
now = 205 broadcast("UNIT_DIED", hawk("A"))
assert(shownIcons() == 1, "dead hawk removed")

-- No nameplates: solo, an unmatched hawk death removes the oldest unmatched tracker.
inGroup = false
now = 206 broadcast("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1293241)
now = 206.7 broadcast("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1312639) -- landed
assert(shownIcons() == 2)
now = 207 broadcast("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 1293241) -- third: replaces the oldest (C)
assert(shownIcons() == 2)
now = 210 broadcast("UNIT_DIED", hawk("Q"))
assert(shownIcons() == 1)
-- Expiry.
now = 207 + 18.1 tick()
assert(shownIcons() == 0 and not hawkFrame:IsShown(), "expired")

-- Other spells are ignored.
broadcast("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 133)
assert(shownIcons() == 0)
print("hawk smoke ok")

-- Ammo -------------------------------------------------------------------
local ammo = UltimateHunterAmmo
local function ammoTexts()
	local t = {}
	for _, f in ipairs(frames) do if f._text then t[#t + 1] = f._text end end
	return t
end
local function has(text) for _, t in ipairs(ammoTexts()) do if t == text then return true end end end
ammoID = 2512
bagData = { [0] = { 0, { { 2512, 200 }, { 9999, 50 } } }, [1] = { 1, { { 2512, 200 }, { 2512, 100 } } } }
broadcast("BAG_UPDATE_DELAYED")
assert(ammo:IsShown() and has(500), "total counts only the equipped ammo")
assert(has("Quiver 300 · |cffffb847Bags 200|r"), "split, bags part amber")
assert(#warnings == 0)
bagData[0][2][1] = nil bagData[1][2][2] = nil -- down to one stack
broadcast("BAG_UPDATE_DELAYED")
assert(has(200) and #warnings == 1 and warnings[1]:match("200 left"), "low ammo warning")
assert(has("Quiver 200 · Bags 0"))
bagData[1][2][1][2] = 150 broadcast("BAG_UPDATE_DELAYED")
assert(#warnings == 1, "warns once per drop")
bagData[1][2][1][2] = 1000 broadcast("BAG_UPDATE_DELAYED")
bagData[1][2][1][2] = 100 broadcast("BAG_UPDATE_DELAYED")
assert(#warnings == 2, "re-armed after restock")
bagData[1] = nil broadcast("BAG_UPDATE_DELAYED")
assert(has("|cffffb847No quiver|r · Bags 0"))
ammoID = nil broadcast("PLAYER_EQUIPMENT_CHANGED")
assert(not ammo:IsShown(), "hidden with no ammo equipped")
print("ammo smoke ok")

-- Settings test buttons.
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
broadcast("PLAYER_REGEN_ENABLED") ns.Apply()
assert(not main:IsShown())
local s0, p0 = sounds, played
ns.TestSwingAlert("main")
assert(main:IsShown() and played == p0 + 1 and sounds == s0 + 1, "melee test shows the bar and fires")
timers[1]() assert(not main:IsShown(), "hidden again after the test")
local w0 = #warnings
ns.AmmoWarn(ns.db.ammoWarnAt)
assert(#warnings == w0 + 1 and warnings[#warnings]:match("200 left"))
print("test buttons ok")

-- Pet training guide ------------------------------------------------------
local realPetData, waypoint = ns.PetData, nil
ns.PetWaypoint = function(npc) waypoint = npc end
ns.TogglePetGuide()
local guide = UltimateHunterPetGuide
assert(guide and guide:IsShown(), "guide opens")
local inSpecial
for _, n in ipairs(UISpecialFrames) do inSpecial = inSpecial or n == "UltimateHunterEscCatcher" end
assert(inSpecial, "Escape catcher registered")
guide:Fire("OnShow") -- the fake Show doesn't run scripts
UltimateHunterEscCatcher:Fire("OnHide") -- what the game does on Escape
assert(not guide:IsShown(), "Escape closes the guide")
ns.TogglePetGuide() assert(guide:IsShown())

local function guideHas(pattern)
	for _, f in ipairs(frames) do if type(f._text) == "string" and f._text:match(pattern) then return true end end
end
local function click(text) -- the clickable frame labelled `text`
	for _, f in ipairs(frames) do
		if f._text == text and f._scripts.OnClick then return f:Fire("OnClick") end
	end
	error("no button " .. text)
end
local function allPages() for _, p in ipairs({ "Guide", "My pet", "Families", "Abilities", "Tame finder" }) do click(p) end end
local function beastRows() -- names on the shown Tame finder rows
	local out = {}
	for _, f in ipairs(frames) do if f.map and f._shown then out[#out + 1] = f.name._text end end
	return out
end
local radios = {}
local function menus() -- runs every dropdown generator, collecting its choices by label
	local root = { SetScrollMode = function() end, CreateRadio = function(_, label, _, set) radios[label] = set end }
	for _, f in ipairs(frames) do if f._menu then f._menu(f, root) end end
end

assert(guideHas("Tame a beast") and guideHas("Data: wowhead.com/forever"))
allPages() -- real data, no pet
click("My pet") assert(guideHas("No pet summoned"))
ns.PetData = {} ns.PetResetIndex()
allPages() assert(guideHas("No data yet"), "empty data")
units.pet = {} pet = true
allPages() -- empty data with a pet
ns.PetData = realPetData ns.PetResetIndex()
allPages() -- real data with a pet
click("My pet") assert(guideHas("Cat · Level 20"))
ns.PetData = {
	families = { [2] = { name = "Cat", diet = { "Meat", "Fish" }, abilities = { "Claw", "Growl", "Swipe" } },
		[1] = { name = "Wolf", diet = { "Meat" }, abilities = { "Bite", "Growl" } } },
	abilities = { Claw = { taught = "tame", ranks = { { spell = 101, level = 8 }, { spell = 102, level = 16 } } },
		Growl = { taught = "trainer", ranks = { { spell = 201, level = 1 } } },
		Swipe = { taught = "family", ranks = { { spell = 301, level = 10 } } } },
	beasts = { [3000] = { name = "Shadow Panther", family = 2, min = 18, max = 20, zone = "Duskwood", teaches = { { "Claw", 2 } } },
		[3001] = { name = "Prowler", family = 2, min = 6, max = 8, zone = "Elwynn", rare = true, teaches = { { "Claw", 1 } } },
		[3002] = { name = "Tabby", family = 2, min = 5, max = 6, zone = "Westfall", teaches = { { "Claw", 1 } } } },
	source = "test data, today",
}
ns.PetResetIndex()
click("Guide") assert(guideHas("Data: test data"))
click("My pet")
assert(guideHas("30 / 100") and guideHas("70 free") and guideHas("Happy") and guideHas("Loyal"), "pet stats")
assert(guideHas("Next: Rank 2 · pet lvl 16"), "Claw rank 1 known, rank 2 next")
broadcast("UNIT_PET_TRAINING_POINTS", "pet")
for _, f in ipairs(frames) do -- My pet's Claw card (the one with a next-rank line)
	if f.name and f.name._text == "Claw" and f.foot and f.foot._text:match("^Next") then f:Fire("OnClick") break end
end
assert(table.concat(beastRows(), ",") == "Shadow Panther", "card opens the finder on the next rank")
click("Families") assert(guideHas("Meat") and guideHas("Your pet") and guideHas("eats 2 food types"))
for _, f in ipairs(frames) do if f.text and f.text._text == "Claw" and f.onClick then f:Fire("OnClick") break end end
assert(table.concat(beastRows(), ",") == "Tabby,Prowler" and guideHas("Rare"), "chip opens the finder, rank 1")
for _, f in ipairs(frames) do if f.npc == 3001 and f._shown then f:Fire("OnClick") end end
assert(waypoint == 3001, "Map button")
for _, f in ipairs(frames) do -- type "ELW" in the search box
	if f.placeholder and f._shown then f.GetText = function() return "ELW" end f:Fire("OnTextChanged", true) end
end
assert(table.concat(beastRows(), ",") == "Prowler", "search filters by zone")
menus()
radios.Growl() assert(#beastRows() == 0 and guideHas("Bought from a pet trainer"), "trainer empty state")
radios.Swipe() assert(guideHas("Family ability, new in Forever"), "family empty state")
click("Abilities") assert(guideHas("3 abilities") and guideHas("2 ranks · lvl 8–16"))
ns.db.petGuideEnabled = false ns.Apply()
assert(not guide:IsShown(), "disabled hides the guide")
ns.PetData = realPetData ns.PetResetIndex()
print("pet guide smoke ok")

