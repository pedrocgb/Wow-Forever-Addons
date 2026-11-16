-- Run from the addon folder: luajit tests/projection_test.lua
local ns = {}
assert(loadfile("Projection.lua"))("RangeFinder", ns)
local P, near = ns.ProjectGroundPoint, function(a, b) return math.abs(a - b) < 1e-9 end

-- Looking straight down: the ring is a true circle of radius focal*R/(distance+height).
local x, y = P(10, 0, 15, math.pi / 2, 1.5, 100)
assert(near(x, 0) and near(y, 100 * 10 / 16.5))
x, y = P(10, math.pi / 2, 15, math.pi / 2, 1.5, 100)
assert(near(x, 100 * 10 / 16.5) and near(y, 0))

-- The feet are below the screen centre; a ground point at R=0 sits there.
x, y = P(0, 0, 15, math.rad(25), 1.5, 100)
assert(near(x, 0) and y < 0)

-- Tilted camera: the far side of the ring is higher on screen and squashed (ellipse).
local _, far = P(10, 0, 15, math.rad(25), 1.5, 100)
local _, nearY = P(10, math.pi, 15, math.rad(25), 1.5, 100)
local side = P(10, math.pi / 2, 15, math.rad(25), 1.5, 100)
assert(far > nearY and (far - nearY) / 2 < side)

-- Left and right halves mirror each other.
local l = P(10, math.rad(60), 15, math.rad(25), 1.5, 100)
local r = P(10, math.rad(-60), 15, math.rad(25), 1.5, 100)
assert(near(l, -r))

-- First person looking level: the point behind the camera is dropped.
assert(P(5, math.pi, 0, 0, 0, 100) == nil)

assert(near(ns.FocalLength(100, 90), 100))
assert(ns.ParseSource("spell:133") == "spell" and select(2, ns.ParseSource("item:5")) == 5)
assert(ns.ParseSource("junk") == nil)
assert(ns.KeyFromText("|cff71d5ff|Hspell:133:0|h[Fireball]|h|r") == "spell:133")
assert(ns.KeyFromText(" Melee ") == "melee")
assert(ns.Label("Auto Shot", 8, 35) == "Auto Shot 8-35 yd" and ns.Label("Fireball", 0, 35) == "Fireball 35 yd")
print("projection_test: ok")
