-- luajit tests/logic_test.lua (from the addon folder)
local ns = {}
assert(loadfile("Logic.lua"))("UltimateHunter", ns)

local function near(a, b) return math.abs(a - b) < 1e-9 end

assert(ns.Progress(10, 10, 2) == 0)
assert(ns.Progress(11, 10, 2) == 0.5)
assert(ns.Progress(15, 10, 2) == 1)
assert(ns.Progress(9, 10, 2) == 0)

-- 2.0 s swing, 0.5 aim + 60 ms latency: stop by 1.44 s.
assert(near(ns.StopAt(0, 2, 0.56), 1.44))
assert(ns.StopAt(0, 0.4, 0.56) == 0) -- swing shorter than the aim: stand still the whole time

assert(ns.RangedPhase(1.0, 0, 2, 0.56, true) == "go")
assert(ns.RangedPhase(1.5, 0, 2, 0.56, false) == "still")
assert(ns.RangedPhase(1.5, 0, 2, 0.56, true) == "late")
assert(ns.RangedPhase(2.1, 0, 2, 0.56, true) == "held")
assert(ns.RangedPhase(2.1, 0, 2, 0.56, false) == "ready")

-- Half way through a 2 s swing, haste makes it 1.5 s: 0.75 s left, still half done.
local s, d = ns.Rescale(11, 10, 2, 1.5)
assert(near(s + d, 11.75) and d == 1.5 and near(ns.Progress(11, s, d), 0.5))
local r, g, b, a = ns.Hex("ff4f8fff")
assert(near(r, 0x4f / 255) and near(g, 0x8f / 255) and b == 1 and a == 1)
assert(select(4, ns.Hex("80000000")) == 128 / 255)
assert(ns.Hex("nope") == 1)
print("logic ok")

-- Hawks ----------------------------------------------------------------
local hawks = {}
local a = ns.HawkCast(hawks, 0)
local b = ns.HawkCast(hawks, 5)
assert(#hawks == 2 and a.dur == 18)
local c = ns.HawkCast(hawks, 10)
assert(#hawks == 2 and c == a and a.start == 10, "third hawk replaces the oldest")
assert(a.num == 1 and b.num == 2, "replacement keeps hawk 1's number")
table.remove(hawks, 1) -- hawk 1 died
assert(ns.HawkCast(hawks, 11).num == 1, "next hawk takes the free number")

-- Landing via the summon spell restarts the timer; seeing the unit later keeps that time.
hawks = {}
a = ns.HawkCast(hawks, 0)
assert(ns.HawkExpected(hawks, 0.5))
assert(ns.HawkLand(hawks, 0.9) == a and a.start == 0.9)
assert(ns.HawkSeen(hawks, 1.2, "G1") == a and a.start == 0.9 and a.id == "G1")
assert(not ns.HawkExpected(hawks, 1.3))
assert(ns.HawkSeen(hawks, 4, "G1") == a, "same unit seen again")

-- No summon spell: the nameplate appearing is the landing.
b = ns.HawkCast(hawks, 2)
assert(ns.HawkSeen(hawks, 2.7, "G2") == b and b.start == 2.7)

-- Death by GUID is exact; an unknown GUID without fallback is ignored.
assert(not ns.HawkDied(hawks, "OTHER"))
assert(ns.HawkDied(hawks, "G1") and #hawks == 1 and hawks[1] == b)

-- Fallback removes the oldest tracker we never matched to a unit.
hawks = {}
a = ns.HawkCast(hawks, 0)
b = ns.HawkCast(hawks, 1)
ns.HawkSeen(hawks, 1.5, "G2") -- b
assert(ns.HawkDied(hawks, "X", true) and #hawks == 1 and hawks[1] == b)

-- A hawk first seen long after its cast is matched to the oldest unmatched tracker.
hawks = {}
a = ns.HawkCast(hawks, 0)
b = ns.HawkCast(hawks, 1)
assert(ns.HawkSeen(hawks, 10, "G9") == a)

-- Expiry.
hawks = {}
a = ns.HawkCast(hawks, 0)
ns.HawkLand(hawks, 0.9)
assert(not ns.HawkExpire(hawks, 18.8) and ns.HawkExpire(hawks, 18.9) and #hawks == 0)
print("hawk logic ok")

-- Ammo alert: once per drop, re-armed by a restock.
local fire, armed = ns.AmmoAlert(true, 400, 200)
assert(not fire and armed)
fire, armed = ns.AmmoAlert(armed, 200, 200)
assert(fire and not armed, "fires at the threshold")
fire, armed = ns.AmmoAlert(armed, 150, 200)
assert(not fire, "no repeat while still low")
fire, armed = ns.AmmoAlert(armed, 1000, 200)
fire, armed = ns.AmmoAlert(armed, 199, 200)
assert(fire, "re-armed after restock")
print("ammo ok")

-- Pet training.
ns.PetData = {
	families = {
		[1] = { name = "Wolf", diet = { "Meat" }, abilities = { "Bite", "Dash", "Growl" } },
		[2] = { name = "Owl", diet = { "Meat" }, abilities = { "Claw", "Growl" } },
	},
	abilities = {
		Bite = { taught = "tame", ranks = { { spell = 101, level = 1, tp = 1 }, { spell = 102, level = 8, tp = 4 }, { spell = 103, level = 16 } } },
		Claw = { taught = "tame", ranks = { { spell = 201, level = 1, tp = 1 }, { spell = 202, level = 8, tp = 4 } } },
		Growl = { taught = "trainer", ranks = { { spell = 301, level = 1, tp = 0 } } },
	},
	beasts = {
		[10] = { name = "Prairie Wolf", family = 1, min = 5, max = 6, zone = "Mulgore", teaches = { { "Bite", 2 } } },
		[11] = { name = "Ash Wolf", family = 1, min = 5, max = 7, zone = "Durotar", teaches = { { "Bite", 2 }, { "Dash", 1 } } },
		[12] = { name = "Old Owl", family = 2, min = 20, max = 21, zone = "Mulgore", rare = true, teaches = { { "Claw", 2 }, { "Bite", 2 } } },
		[13] = { name = "Empty", family = 2, min = 1, max = 1, teaches = {} },
	},
}
assert(ns.PetCanLearn(1, "Bite") and not ns.PetCanLearn(2, "Bite") and not ns.PetCanLearn(99, "Bite"))
local r, e = ns.PetNextRank("Bite", nil, 10)
assert(r == 1 and e.spell == 101, "nil knownRank starts at rank 1")
local r1, why, r2, e2 = ns.PetNextRank("Bite", 1, 5)
assert(r1 == nil and why == "level" and r2 == 2 and e2.spell == 102)
assert(ns.PetNextRank("Bite", 1, 8) == 2 and ns.PetNextRank("Bite", 1) == 2)
assert(select(2, ns.PetNextRank("Bite", 3, 60)) == "max" and select(2, ns.PetNextRank("Nope", 0, 60)) == "max")
local list = ns.PetBeastsFor("Bite", 2)
assert(#list == 3 and list[1].npc == 11 and list[2].npc == 10 and list[3].npc == 12, "sorted by min then name")
assert(#ns.PetBeastsFor("Bite", 2, { minLvl = 7, maxLvl = 19 }) == 1)
assert(#ns.PetBeastsFor("Bite", 2, { zone = "Mulgore" }) == 2)
assert(#ns.PetBeastsFor("Bite", 2, { family = 1 }) == 2)
list = ns.PetBeastsFor("Bite", 2, { rareOnly = true })
assert(#list == 1 and list[1].npc == 12)
assert(#ns.PetBeastsFor("Bite", 3) == 0)
local t = ns.PetTeachesText(12, { Bite = 2 }, 1)
assert(t[1] == "Claw (Rank 2) - your pet can't learn" and t[2] == "Bite (Rank 2) - known", t[1])
assert(ns.PetTeachesText(10)[1] == "Bite (Rank 2)")
assert(ns.PetTeachesText(99) == nil and ns.PetTeachesText(13) == nil)
assert(select(2, ns.PetTeachesText(10)) == false, "shipped data is unconfirmed")
-- recorded in game when tamed: overrides the shipped data, also for beasts the data lacks
local tamed = ns.PetTamedTeaches({ Bite = 3, Growl = 1, Unknown = 2 })
assert(#tamed == 1 and tamed[1][1] == "Bite" and tamed[1][2] == 3, "trainer-only and unknown skills dropped")
ns.db = { tamed = { [10] = {}, [99] = tamed } }
assert(ns.PetTeachesText(10) == nil, "recorded empty beats shipped Bite 2")
local lines, confirmed = ns.PetTeachesText(99)
assert(lines[1] == "Bite (Rank 3)" and confirmed == true)
assert(#ns.PetBeastsFor("Bite", 2) == 2, "recorded beast 10 no longer listed for Bite 2")
ns.db = nil
ns.PetResetIndex()
local known = ns.PetKnownRanks({ 102, 101, 301, 999 })
assert(known.Bite == 2 and known.Growl == 1 and known.Claw == nil)
print("pet logic ok")

-- Real PetData.lua sanity, when present.
if io.open("PetData.lua") then
	local ns2 = {}
	assert(loadfile("PetData.lua"))("UltimateHunter", ns2)
	local pd = ns2.PetData
	for id, b in pairs(pd.beasts) do
		for _, te in ipairs(b.teaches or {}) do
			local a = pd.abilities[te[1]]
			assert(a and a.ranks[te[2]], "beast " .. id .. " teaches unknown " .. tostring(te[1]) .. " " .. tostring(te[2]))
		end
	end
	for id, f in pairs(pd.families) do
		for _, name in ipairs(f.abilities or {}) do
			assert(pd.abilities[name], "family " .. id .. " has unknown ability " .. name)
		end
	end
	print("pet data ok")
end
print("logic ok")
