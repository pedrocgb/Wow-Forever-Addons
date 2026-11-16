-- Run from the addon folder: luajit tests/folders_test.lua
local ns = {}
assert(loadfile("Folders.lua"))("MacroBuilderEnhanced", ns)
local F = ns.Folders

local function eq(got, want)
	if got ~= want then error(("\n got: %s\nwant: %s"):format(tostring(got), tostring(want)), 2) end
end
local function names(rows)
	local t = {}
	for _, r in ipairs(rows) do t[#t + 1] = string.rep(">", r.depth) .. r.name .. (r.kind == "folder" and ("(" .. r.count .. ")") or "") end
	return table.concat(t, " ")
end

local s = F.Init({})
local pvp = F.Create(s, "PvP", nil)
local arena = F.Create(s, "arena", pvp)
local deep = F.Create(s, "Deep", arena)
eq(F.Depth(s, deep), 3)
eq(F.Create(s, "Too deep", deep), nil) -- max 3 levels
local raid = F.Create(s, "Raid", nil)

local macros = { { index = 1, name = "Bolt" }, { index = 2, name = "Heal" }, { index = 3, name = "Trap" } }
F.SetMacroFolder(s, "Heal", raid)
F.SetMacroFolder(s, "Trap", deep)
eq(names(F.Rows(s, macros)), "PvP(1) >arena(1) >>Deep(1) >>>Trap Raid(1) >Heal Bolt")

-- collapse hides contents but keeps counts
s.folders[pvp].open = false
eq(names(F.Rows(s, macros)), "PvP(1) Raid(1) >Heal Bolt")
s.folders[pvp].open = true

-- moving folders respects depth and cycles
eq(F.CanMoveFolder(s, pvp, raid), false) -- PvP subtree is 3 deep, under Raid would be 4
eq(F.CanMoveFolder(s, raid, deep), false) -- Deep is already level 3
eq(F.CanMoveFolder(s, arena, deep), false) -- into its own descendant
eq(F.MoveFolder(s, deep, raid), true)
eq(F.Depth(s, deep), 2)
eq(F.MoveFolder(s, raid, nil), true)

-- delete moves children and macros up one level
F.Delete(s, raid)
eq(s.folders[deep].parent, nil)
eq(s.macros["Heal"], nil)
eq(s.macros["Trap"], deep)

-- rename + prune
F.RenameMacro(s, "Trap", "Frost Trap")
eq(s.macros["Frost Trap"], deep)
F.Prune(s, { ["Bolt"] = true })
eq(s.macros["Frost Trap"], nil)

eq(#F.List(s), 3)
print("folders_test: all passed")
