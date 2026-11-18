-- luajit tests/pethooks_test.lua (from the addon folder)
local printed = {}
print = function(s) printed[#printed + 1] = s end -- capture say()
function issecretvalue() return false end
function strsplit(sep, s)
	local t = {}
	for p in (s .. sep):gmatch("(.-)" .. sep) do t[#t + 1] = p end
	return unpack(t)
end
Enum = { TooltipDataType = { Unit = 2 }, SpellBookSpellBank = { Pet = 1 }, TrainerType = { Pet = 3 } }
TooltipDataProcessor = { AddTooltipPostCall = function() end }
C_AddOns = { IsAddOnLoaded = function() return false end }
local frameStub = setmetatable({}, { __index = function() return function() end end })
function CreateFrame() return frameStub end
local mapCalls = {}
C_Map = {
	CanSetUserWaypointOnMap = function() return true end,
	SetUserWaypoint = function(p) mapCalls[#mapCalls + 1] = p end,
}
UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m, x, y } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) mapCalls.tracked = v end }

local ns = {}
assert(loadfile("Logic.lua"))("UltimateHunter", ns)
assert(loadfile("PetHooks.lua"))("UltimateHunter", ns)
ns.PetData = { beasts = {
	[1] = { name = "Wolf", zone = "Elwynn", map = 37, x = 50, y = 25 },
	[2] = { name = "Ghost Cat" },
	[3] = { name = "Prairie Wolf", zone = "Mulgore", map = 1412 },
} }

assert(ns.NpcIDFromGUID("Creature-0-1-2-3-299-0000ABCDEF") == 299)
assert(ns.NpcIDFromGUID("Player-1-0ABCDEF") == nil)
assert(ns.NpcIDFromGUID(nil) == nil)

ns.PetWaypoint(1) -- no TomTom: C_Map path
assert(mapCalls[1][1] == 37 and mapCalls[1][2] == 0.5 and mapCalls[1][3] == 0.25 and mapCalls.tracked == true)
assert(printed[#printed]:find("Waypoint set: Wolf %(Elwynn 50.0, 25.0%)"))

local tt
TomTom = { AddWaypoint = function(self, m, x, y, opts) tt = { m, x, y, opts.title } end }
ns.PetWaypoint(1)
assert(tt[1] == 37 and tt[2] == 0.5 and tt[4] == "Wolf" and #mapCalls == 1, "TomTom wins over C_Map")

ns.PetWaypoint(2)
assert(printed[#printed]:find("No coordinates for Ghost Cat"))

local opened
OpenWorldMap = function(m) opened = m end
ns.PetWaypoint(3) -- zone only: opens the zone map
assert(opened == 1412 and printed[#printed]:find("Prairie Wolf lives in Mulgore"))
io.write("pethooks ok\n")
