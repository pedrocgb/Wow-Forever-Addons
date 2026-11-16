-- luajit tests/logic_test.lua (from the addon folder)
local ns = {}
assert(loadfile("Logic.lua"))("RangeBox", ns)

assert(ns.Classify(0, 5, 30) == true)
assert(ns.Classify(25, 30, 30) == true)
assert(ns.Classify(30, 35, 30) == false)
assert(ns.Classify(40, nil, 30) == false)
assert(ns.Classify(20, 35, 30) == "edge")
assert(ns.Classify(20, nil, 30) == "edge")
assert(ns.Classify(nil, nil, 30) == nil)

assert(ns.FormatRange(20, 25) == "20\226\128\14725")
assert(ns.FormatRange(40, nil) == "40+")
assert(ns.FormatRange(nil, nil) == "--")
print("logic ok")
