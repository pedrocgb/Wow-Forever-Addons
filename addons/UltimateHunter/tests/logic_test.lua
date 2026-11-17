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
