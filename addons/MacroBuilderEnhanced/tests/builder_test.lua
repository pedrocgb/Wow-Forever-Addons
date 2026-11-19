-- Run from the addon folder: luajit tests/builder_test.lua
local ns = {}
local function load(path) assert(loadfile(path))("MacroBuilderEnhanced", ns) end
load("Builder.lua")
load("IconSearch.lua")
local B = ns.Builder

local function eq(got, want)
	if got ~= want then error(("\n got: %s\nwant: %s"):format(tostring(got), tostring(want)), 2) end
end
local function action(key)
	for _, a in ipairs(B.ACTIONS) do if a.key == key then return a end end
end

-- conditionals
eq(B.Conditional({ "" }, {}), "")
eq(B.Conditional({ "focus" }, {}), "[@focus]")
eq(B.Conditional({ "mouseover", "" }, { "help", "nodead" }), "[@mouseover,help,nodead][help,nodead]")
eq(B.Conditional({ "mouseover", "" }, {}), "[@mouseover,exists][]")
eq(B.Conditional({ "mouseover", "", "player" }, { "help" }), "[@mouseover,help][help][@player,help]")
eq(B.Conditional({ "" }, { "mod:shift", "combat" }), "[mod:shift,combat]")

-- spells & sequences
eq(B.SpellArg("Frostbolt", "Rank 1"), "Frostbolt(Rank 1)")
eq(B.SpellArg(" Auto Shot ", nil, true), "!Auto Shot")
eq(B.SequenceArg("Immolate,Corruption , Curse of Agony", { seconds = "10", target = true, shift = true }),
	"reset=10/target/shift Immolate, Corruption, Curse of Agony")
eq(B.SequenceArg("A, B"), "A, B")

-- full lines
eq(B.BuildLine(action("cast"), { spell = "Flash Heal", rank = "Rank 3", target = "mouseover", fallback = "*", conds = { "help", "nodead" } }),
	"/cast [@mouseover,help,nodead][help,nodead] Flash Heal(Rank 3)")
eq(B.BuildLine(action("cast"), { spell = "Frostbolt", conds = {} }), "/cast Frostbolt")
eq(B.BuildLine(action("use"), { slot = "13", item = "ignored", conds = { "combat" } }), "/use [combat] 13")
eq(B.BuildLine(action("chat"), { sub = "/whisper", name = "Bob", text = "hi %t", target = "focus", conds = { "combat" } }), "/whisper Bob hi %t")
eq(B.BuildLine(action("attack"), { sub = "/stopattack", target = "focus" }), "/stopattack")
eq(B.BuildLine(action("stop"), { sub = "/cancelaura", text = "Ice Block", target = "focus", conds = { "mod:alt" } }), "/cancelaura [mod:alt] Ice Block")
eq(B.BuildLine(action("marker"), { sub = "/tm", marker = "8", keep = true, target = "mouseover" }), "/tm [@mouseover] !8")
eq(B.BuildLine(action("marker"), { sub = "/cwm", marker = "0" }), "/cwm all")
eq(B.BuildLine(action("pet"), { sub = "/cast", text = "Claw", target = "target", conds = { "pet" } }), "/cast [@target,pet] Claw")
eq(B.BuildLine(action("pet"), { sub = "/petautocasttoggle", text = "Growl", target = "focus" }), "/petautocasttoggle Growl")
eq(B.BuildLine(action("equip"), { sub = "/equipslot", slot = "16", item = "Thunderfury" }), "/equipslot 16 Thunderfury")
eq(B.BuildLine(action("tooltip"), { sub = "#showtooltip", spell = "", conds = {} }), "#showtooltip")
eq(B.BuildLine(action("sequence"), { list = "A, B", seconds = "5", combat = true, conds = {} }), "/castsequence reset=5/combat A, B")

-- emotes (no @unit support: name argument, or a secure target swap)
eq(B.BuildLine(action("emote"), { emote = "/spit" }), "/spit")
eq(B.BuildLine(action("emote"), { emote = "/spit", at = "name", name = " Bob " }), "/spit Bob")
eq(B.BuildLine(action("emote"), { emote = "/spit", at = "mouseover" }),
	"/target [@mouseover,exists]\n/spit\n/targetlasttarget [@mouseover,exists]")
eq(B.BuildLine(action("emote"), {}), nil)
eq(select(2, B.BuildLine(action("emote"), { emote = "/hug", at = "name" })), "Type the player's name.")
eq(B.InsertLine("/cast A", "/target [@focus,exists]\n/hug\n/targetlasttarget [@focus,exists]"),
	"/cast A\n/target [@focus,exists]\n/hug\n/targetlasttarget [@focus,exists]")

-- body editing
eq(B.InsertLine("/cast A\n\n", "/cast B"), "/cast A\n/cast B")
eq(B.InsertLine("/cast A", "#showtooltip"), "#showtooltip\n/cast A")
eq(B.InsertLine("#show X\n/cast A", "#showtooltip"), "#showtooltip\n/cast A")
eq(B.AppendToLast("/cast [harm] A\n/use 13", "/cast", "[help] B"), "/cast [harm] A; [help] B\n/use 13")
eq(B.AppendToLast("/use 13", "/cast", "B"), nil)

-- icon search
_G.bit = _G.bit or require("bit")
ns.IconNames = { [1] = "ability_warrior_charge", [2] = "inv_sword_04", [3] = "spell_frost_frostbolt02" }
ns.IconClass = { [1] = 1, [3] = 128 }
ns.IconItem = { [2] = 4 }
local all = { 1, 2, 3, "custom_path" }
eq(#ns.FilterIcons(all, "", 0, 0), 4)
eq(ns.FilterIcons(all, "FROST bolt", 0, 0)[1], 3)
eq(#ns.FilterIcons(all, "", 1 + 128, 0), 2)
eq(ns.FilterIcons(all, "", 0, 4)[1], 2)
eq(#ns.FilterIcons(all, "sword", 1, 0), 0)
eq(ns.FilterIcons(all, "custom", 0, 0)[1], "custom_path")

print("builder_test: all passed")
