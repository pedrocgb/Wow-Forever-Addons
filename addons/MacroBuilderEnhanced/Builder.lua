-- Pure macro-text building: no WoW API calls, so tests/builder_test.lua can run it under luajit.
local _, ns = ...
local B = {}
ns.Builder = B

B.MAX_CHARS = 255

-- @unit choices for the temporary target. "" = whatever the command defaults to (usually your target).
B.TARGETS = {
	{ "", "Default (current target)" },
	{ "target", "Target" },
	{ "mouseover", "Mouseover" },
	{ "focus", "Focus" },
	{ "player", "Myself" },
	{ "cursor", "Cursor (ground spells)" },
	{ "targettarget", "Target of target" },
	{ "focustarget", "Focus's target" },
	{ "pet", "Pet" },
	{ "pettarget", "Pet's target" },
	{ "party1", "Party 1" }, { "party2", "Party 2" }, { "party3", "Party 3" }, { "party4", "Party 4" },
	{ "none", "None (always show targeting cursor)" },
}

-- Second (and third) unit tried when the first one fails its conditions: "[@mouseover,help][@target,help][@player]".
B.FALLBACKS = {
	{ "", "No fallback" },
	{ "*", "then current target" },
	{ "player", "then myself" },
	{ "focus", "then focus" },
	{ "*,player", "then current target, then myself" },
}

-- Each row = one dropdown; value "" means "don't care". All are real conditionals of SecureCmdOptionParse.
-- 3rd field "common" = shown without expanding "More conditions".
B.CONDITIONS = {
	{ "Unit reaction", { { "help", "Friendly (help)" }, { "harm", "Hostile (harm)" } }, "common" },
	{ "Unit is", { { "nodead", "Alive" }, { "dead", "Dead" } }, "common" },
	{ "Unit exists", { { "exists", "Exists" }, { "noexists", "Doesn't exist" } } },
	{ "Unit in group", { { "party", "In my party" }, { "raid", "In my raid" } } },
	{ "Modifier key", { { "nomod", "No modifier" }, { "mod", "Any modifier" }, { "mod:shift", "Shift" }, { "mod:ctrl", "Ctrl" }, { "mod:alt", "Alt" }, { "mod:shift/ctrl", "Shift or Ctrl" } }, "common" },
	{ "Mouse button", { { "btn:1", "Left click" }, { "btn:2", "Right click" }, { "btn:3", "Middle click" }, { "btn:4", "Button 4" }, { "btn:5", "Button 5" } } , "common" },
	{ "Combat", { { "combat", "In combat" }, { "nocombat", "Out of combat" } }, "common" },
	{ "Stance / form", { { "noform", "No form (caster)" }, { "form:1", "Form 1" }, { "form:2", "Form 2" }, { "form:3", "Form 3" }, { "form:4", "Form 4" }, { "form:5", "Form 5" }, { "form:6", "Form 6" }, { "form:1/2", "Form 1 or 2" } } , "common" },
	{ "Stealth", { { "stealth", "Stealthed" }, { "nostealth", "Not stealthed" } } },
	{ "Mounted", { { "mounted", "Mounted" }, { "nomounted", "Not mounted" } } },
	{ "Flying", { { "flying", "Flying" }, { "noflying", "Not flying" } } },
	{ "Location", { { "indoors", "Indoors" }, { "outdoors", "Outdoors" } } },
	{ "Swimming", { { "swimming", "Swimming" }, { "noswimming", "Not swimming" } } },
	{ "Resting", { { "resting", "In a rested area" }, { "noresting", "Not resting" } } },
	{ "My group", { { "group", "In a group" }, { "group:party", "In a party" }, { "group:raid", "In a raid" }, { "nogroup", "Solo" } } },
	{ "Channeling", { { "channeling", "Channeling" }, { "nochanneling", "Not channeling" } } },
	{ "Pet", { { "pet", "Pet is out" }, { "nopet", "No pet" } } },
	{ "Action bar page", { { "bar:1", "Page 1" }, { "bar:2", "Page 2" }, { "bar:3", "Page 3" }, { "bar:4", "Page 4" }, { "bar:5", "Page 5" }, { "bar:6", "Page 6" } } },
}
-- Conditionals that take a name: "equipped:Shields", "known:Charge", "channeling:Arcane Missiles", "pet:Imp".
-- source = where the UI gets the dropdown entries from (item subclasses, spellbook, pet families).
B.NAMED_CONDITIONS = {
	{ "equipped", "Wearing", "itemtype" },
	{ "known", "Knows spell", "spell" },
	{ "channeling", "Channeling", "spell" },
	{ "pet", "Active pet", "pet" },
}

local NO_EXISTS_NEEDED = { player = true, cursor = true, none = true, [""] = true }
local UNIT_STATE = { help = true, harm = true, exists = true, noexists = true, dead = true, nodead = true }

-- targets: ordered list of units ("" = default); conds: list of conditional strings.
function B.Conditional(targets, conds)
	targets = (#targets > 0) and targets or { "" }
	if #targets == 1 and targets[1] == "" and #conds == 0 then return "" end
	local hasUnitState = false
	for _, c in ipairs(conds) do
		if UNIT_STATE[c] then hasUnitState = true end
	end
	local groups = {}
	for i, unit in ipairs(targets) do
		local parts = {}
		if unit ~= "" then parts[1] = "@" .. unit end
		-- A missing mouseover/focus still "matches" [@mouseover]; require it to exist so the fallback can kick in.
		if i < #targets and not hasUnitState and not NO_EXISTS_NEEDED[unit] then parts[#parts + 1] = "exists" end
		for _, c in ipairs(conds) do parts[#parts + 1] = c end
		groups[i] = "[" .. table.concat(parts, ",") .. "]"
	end
	return table.concat(groups)
end

-- Expand a fallback key into the full target chain.
function B.TargetChain(target, fallback)
	local chain = { target or "" }
	if fallback and fallback ~= "" then
		for unit in fallback:gmatch("[^,]+") do chain[#chain + 1] = (unit == "*") and "" or unit end
	end
	return chain
end

function B.Clause(conditional, arg)
	arg = arg or ""
	if conditional == "" then return arg end
	return arg == "" and conditional or (conditional .. " " .. arg)
end

function B.Line(cmd, clause)
	return (clause and clause ~= "") and (cmd .. " " .. clause) or cmd
end

-- "/cast [harm] Frostbolt" + "[help] Heal" -> "/cast [harm] Frostbolt; [help] Heal"
function B.AppendAlternative(line, clause)
	return line .. "; " .. clause
end

function B.CommandOf(line)
	return (line or ""):match("^%s*([/#]%S+)")
end

-- rank: nil/"" = highest known (plain name); otherwise e.g. "Rank 3".
function B.SpellArg(name, rank, noToggle)
	name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then return "" end
	if rank and rank ~= "" then name = name .. "(" .. rank .. ")" end
	return (noToggle and "!" or "") .. name
end

-- list: "A, B, C" (any separators); reset: { seconds = 10, target = true, combat = true, shift = true, alt = true, ctrl = true }
local RESET_ORDER = { "target", "combat", "shift", "alt", "ctrl" }
function B.SequenceArg(list, reset)
	local items = {}
	for item in (list or ""):gmatch("[^,]+") do
		item = item:gsub("^%s+", ""):gsub("%s+$", "")
		if item ~= "" then items[#items + 1] = item end
	end
	local resets = {}
	reset = reset or {}
	local secs = tonumber(reset.seconds)
	if secs and secs > 0 then resets[1] = tostring(secs) end
	for _, k in ipairs(RESET_ORDER) do
		if reset[k] then resets[#resets + 1] = k end
	end
	local arg = table.concat(items, ", ")
	if #resets > 0 then arg = "reset=" .. table.concat(resets, "/") .. " " .. arg end
	return arg
end

local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

B.MARKERS = {
	-- Labels are /tm icons; /wm and /cwm use the same 1-8 numbers but different colors.
	{ "8", "8 - Skull" }, { "7", "7 - Cross" }, { "6", "6 - Square" }, { "5", "5 - Moon" },
	{ "4", "4 - Triangle" }, { "3", "3 - Diamond" }, { "2", "2 - Circle" }, { "1", "1 - Star" }, { "0", "0 - Clear / all" },
}
B.SLOTS = {
	{ "", "(item name)" }, { "13", "Trinket 1 (slot 13)" }, { "14", "Trinket 2 (slot 14)" },
	{ "16", "Main hand (16)" }, { "17", "Off hand (17)" }, { "18", "Ranged (18)" }, { "1", "Head (1)" },
	{ "2", "Neck (2)" }, { "5", "Chest (5)" }, { "6", "Waist (6)" }, { "8", "Feet (8)" },
	{ "10", "Hands (10)" }, { "11", "Finger 1 (11)" }, { "12", "Finger 2 (12)" }, { "15", "Back (15)" },
}

-- Emote commands take no [@unit]: whatever follows the command is used as a target *name*, and with nothing
-- they hit your current target. Mouseover/focus therefore go through a brief, secure target swap.
B.EMOTE_TARGETS = {
	{ "", "My current target" },
	{ "mouseover", "Mouseover (target swap)" },
	{ "focus", "Focus (target swap)" },
	{ "name", "A player by name" },
}

function B.EmoteLine(v)
	local cmd = v.emote or ""
	if cmd == "" then return nil, "Pick an emote first." end
	if v.at == "name" then
		local name = trim(v.name)
		if name == "" then return nil, "Type the player's name." end
		return cmd .. " " .. name
	end
	if v.at == "mouseover" or v.at == "focus" then
		-- if the unit doesn't exist nothing is swapped and the emote hits the current target
		local cond = "[@" .. v.at .. ",exists]"
		return "/target " .. cond .. "\n" .. cmd .. "\n/targetlasttarget " .. cond
	end
	return cmd
end

--[[ Actions shown as buttons in the builder.
	subs   : { cmd, label, flags } — flags: nocond (command ignores [conditions]), notarget (no @unit), noarg
	fields : form fields, rendered in order. Kinds: spell (with rank), petspell (active pet's spellbook), item, text, list, number, check, choice
	build  : values -> argument string
	line   : optional; values -> whole line(s), or nil + error. Replaces subs/build/conditions.
]]
B.ACTIONS = {
	{
		key = "cast", label = "Cast spell", subs = { { "/cast", "Cast" } },
		fields = {
			{ "spell", "spell", "Spell" },
			{ "noToggle", "check", "Don't toggle off if already active (Auto Shot, stances, auras)", "Options" },
		},
		build = function(v) return B.SpellArg(v.spell, v.rank, v.noToggle) end,
	},
	{
		key = "use", label = "Use item", subs = { { "/use", "Use" } },
		fields = {
			{ "slot", "choice", "Equipped slot", B.SLOTS },
			{ "item", "item", "Item (or bag slot: \"0 1\")" },
		},
		build = function(v) return (v.slot and v.slot ~= "") and v.slot or trim(v.item) end,
	},
	{
		key = "sequence", label = "Cast sequence", subs = { { "/castsequence", "Cast sequence" } },
		fields = {
			{ "list", "list", "Spells / items" },
			{ "seconds", "number", "Reset after (seconds idle)" },
			-- check fields that follow each other share one row; the 4th value labels that row
			{ "target", "check", "Target changes", "Also reset when" },
			{ "combat", "check", "Leaving combat" },
			{ "shift", "check", "Shift" },
			{ "alt", "check", "Alt" },
			{ "ctrl", "check", "Ctrl" },
		},
		build = function(v) return B.SequenceArg(v.list, v) end,
	},
	{
		key = "random", label = "Random", subs = { { "/castrandom", "Cast a random spell" }, { "/userandom", "Use a random item" } },
		fields = { { "list", "list", "Spells / items" } },
		build = function(v) return B.SequenceArg(v.list) end,
	},
	{
		key = "targeting", label = "Targeting",
		subs = {
			{ "/target", "Target (unit or name)" }, { "/targetexact", "Target exact name" },
			{ "/targetenemy", "Nearest enemy", "notarget" }, { "/targetenemyplayer", "Nearest enemy player", "notarget" },
			{ "/targetfriend", "Nearest friend", "notarget" }, { "/targetfriendplayer", "Nearest friendly player", "notarget" },
			{ "/targetparty", "Nearest party member", "notarget" }, { "/targetraid", "Nearest raid member", "notarget" },
			{ "/targetlasttarget", "Last target", "notarget noarg" }, { "/targetlastenemy", "Last enemy", "notarget noarg" },
			{ "/targetlastfriend", "Last friend", "notarget noarg" }, { "/cleartarget", "Clear target", "notarget noarg" },
			{ "/assist", "Assist (target their target)" }, { "/focus", "Set focus" }, { "/clearfocus", "Clear focus", "notarget noarg" },
		},
		fields = { { "text", "text", "Name (optional; leave empty to use the @unit above)" } },
		build = function(v) return trim(v.text) end,
	},
	{
		key = "attack", label = "Auto attack",
		subs = { { "/startattack", "Start attacking" }, { "/stopattack", "Stop attacking", "notarget noarg" } },
		fields = {},
		build = function() return "" end,
	},
	{
		key = "pet", label = "Pet",
		subs = {
			{ "/cast", "Use a pet ability" },
			{ "/petattack", "Attack" }, { "/petfollow", "Follow", "notarget noarg" }, { "/petstay", "Stay", "notarget noarg" },
			{ "/petmoveto", "Move to (use @cursor)" }, { "/petpassive", "Passive", "notarget noarg" },
			{ "/petdefensive", "Defensive", "notarget noarg" }, { "/petaggressive", "Aggressive", "notarget noarg" },
			{ "/petautocaston", "Autocast ON", "notarget" }, { "/petautocastoff", "Autocast OFF", "notarget" },
			{ "/petautocasttoggle", "Autocast toggle", "notarget" }, { "/petdismiss", "Dismiss", "notarget noarg" },
		},
		fields = { { "text", "petspell", "Pet ability (for Use and Autocast)" } },
		build = function(v) return trim(v.text) end,
	},
	{
		key = "stop", label = "Stop / cancel",
		subs = {
			{ "/stopcasting", "Stop casting", "notarget noarg" }, { "/stopspelltarget", "Cancel targeting cursor", "notarget noarg" },
			{ "/cancelqueuedspell", "Cancel queued spell", "notarget noarg" }, { "/stopmacro", "Stop the macro here", "notarget noarg" },
			{ "/cancelaura", "Cancel a buff", "notarget" }, { "/cancelform", "Leave shapeshift form", "notarget noarg" },
			{ "/dismount", "Dismount", "notarget noarg" },
		},
		fields = { { "text", "text", "Buff name (for /cancelaura)" } },
		build = function(v) return trim(v.text) end,
	},
	{
		key = "equip", label = "Equip",
		subs = { { "/equip", "Equip to default slot", "notarget" }, { "/equipslot", "Equip to a slot", "notarget" } },
		fields = {
			{ "slot", "choice", "Slot (for /equipslot)", B.SLOTS },
			{ "item", "item", "Item" },
		},
		build = function(v)
			local item = trim(v.item)
			if v.sub == "/equipslot" and v.slot and v.slot ~= "" then return v.slot .. " " .. item end
			return item
		end,
	},
	{
		key = "marker", label = "Raid marker",
		subs = { { "/tm", "Mark unit" }, { "/wm", "Place world marker (use @cursor)" }, { "/cwm", "Clear world marker", "notarget" } },
		fields = {
			{ "marker", "choice", "Marker", B.MARKERS },
			{ "keep", "check", "Don't remove the marker if the unit already has it", "Options" },
		},
		build = function(v)
			local m = v.marker or "8"
			if v.sub == "/tm" and v.keep and m ~= "0" then return "!" .. m end
			if v.sub == "/cwm" and m == "0" then return "all" end
			return m
		end,
	},
	{
		key = "bar", label = "Action bar",
		subs = { { "/changeactionbar", "Switch to page", "notarget" }, { "/swapactionbar", "Swap between two pages", "notarget" } },
		fields = { { "text", "text", "Page (\"2\") or two pages to swap (\"1 2\")" } },
		build = function(v) return trim(v.text) end,
	},
	{
		key = "chat", label = "Chat / emote",
		subs = {
			{ "/say", "Say", "nocond" }, { "/yell", "Yell", "nocond" }, { "/party", "Party", "nocond" },
			{ "/raid", "Raid", "nocond" }, { "/rw", "Raid warning", "nocond" }, { "/guild", "Guild", "nocond" },
			{ "/officer", "Officer", "nocond" }, { "/emote", "Custom emote", "nocond" }, { "/whisper", "Whisper", "nocond" },
		},
		fields = {
			{ "name", "text", "Whisper to (player name)" },
			{ "text", "text", "Message — %t target, %f focus, %m mouseover" },
		},
		build = function(v)
			if v.sub == "/whisper" then return trim(trim(v.name) .. " " .. trim(v.text)) end
			return trim(v.text)
		end,
	},
	{
		key = "emote", label = "Emote", subs = { { "", "Emote", "nocond notarget" } },
		fields = {
			{ "emote", "emote", "Emote" },
			{ "at", "choice", "Do it at", B.EMOTE_TARGETS },
			{ "name", "text", "Player name (only for \"by name\")" },
		},
		line = B.EmoteLine,
	},
	{
		key = "social", label = "Player actions",
		subs = {
			{ "/follow", "Follow", "nocond" }, { "/inspect", "Inspect", "nocond" }, { "/trade", "Trade", "nocond" },
			{ "/duel", "Duel", "nocond" }, { "/invite", "Invite", "nocond" }, { "/uninvite", "Remove from group", "nocond" },
			{ "/readycheck", "Ready check", "nocond noarg" },
		},
		fields = { { "text", "text", "Player name (optional, default = target)" } },
		build = function(v) return trim(v.text) end,
	},
	{
		key = "click", label = "Click button", subs = { { "/click", "Click a UI button", "notarget" } },
		fields = {
			{ "text", "text", "Frame name (use /fstack to find it)" },
			{ "button", "choice", "Mouse button", { { "", "Left" }, { "RightButton", "Right" }, { "MiddleButton", "Middle" } } },
		},
		build = function(v) return trim(trim(v.text) .. " " .. (v.button or "")) end,
	},
	{
		key = "script", label = "Lua script", subs = { { "/run", "Run Lua", "nocond" } },
		fields = { { "text", "text", "Lua code" } },
		build = function(v) return trim(v.text) end,
	},
	{
		key = "tooltip", label = "Icon & tooltip",
		subs = {
			{ "#showtooltip", "Show tooltip + icon", "notarget" },
			{ "#show", "Show icon only", "notarget" },
		},
		fields = { { "spell", "spell", "Spell or item (empty = automatic)" } },
		build = function(v) return B.SpellArg(v.spell, v.rank) end,
	},
}

function B.HasFlag(sub, flag)
	return sub[3] ~= nil and sub[3]:find(flag, 1, true) ~= nil
end

function B.FindSub(action, cmd)
	for _, s in ipairs(action.subs) do
		if s[1] == cmd then return s end
	end
	return action.subs[1]
end

-- values: { sub, target, fallback, conds = {...}, ...fields } -> full line, or nil + reason
function B.BuildLine(action, values)
	if action.line then return action.line(values) end
	local sub = B.FindSub(action, values.sub)
	local arg = B.HasFlag(sub, "noarg") and "" or (action.build(values) or "")
	local cond = ""
	if not B.HasFlag(sub, "nocond") then
		local chain = B.HasFlag(sub, "notarget") and { "" } or B.TargetChain(values.target, values.fallback)
		cond = B.Conditional(chain, values.conds or {})
	end
	return B.Line(sub[1], B.Clause(cond, arg)), B.Clause(cond, arg)
end

-- Put #show/#showtooltip on line 1 (replacing an existing one); everything else goes at the end.
function B.InsertLine(body, line)
	local lines = {}
	for l in ((body or "") .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
	while #lines > 0 and lines[#lines]:match("^%s*$") do lines[#lines] = nil end
	if line:sub(1, 1) == "#" then
		if lines[1] and lines[1]:match("^#show") then lines[1] = line else table.insert(lines, 1, line) end
	else
		lines[#lines + 1] = line
	end
	return table.concat(lines, "\n")
end

-- Append "; clause" to the last line that uses the same command. Returns nil when there's none.
function B.AppendToLast(body, cmd, clause)
	local lines = {}
	for l in ((body or "") .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
	for i = #lines, 1, -1 do
		if B.CommandOf(lines[i]) == cmd then
			lines[i] = B.AppendAlternative(lines[i], clause)
			return table.concat(lines, "\n")
		end
	end
end
