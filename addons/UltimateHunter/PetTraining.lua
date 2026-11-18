-- Pet Training guide: a window explaining how pet ability training works, the current pet's
-- abilities and training points, each family's abilities and where to tame each rank.
-- Pet APIs (C_PetInfo, pet spellbook) return no secrets. Built lazily on first open.
local _, ns = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local GOLD, GREY, AMBER = "|cffffd100", "|cff9da3ae", "|cffffb847"
local W, H = 560, 440
local TABS = { "How it works", "My pet", "Abilities", "Where to tame" }
local HAPPINESS = { "Unhappy", "Content", "Happy" }
local PET_EVENTS = { "UNIT_PET", "UNIT_PET_TRAINING_POINTS", "UNIT_HAPPINESS", "UNIT_PET_EXPERIENCE",
	"PET_STABLE_UPDATE", "SPELLS_CHANGED" }

local FAMILY_NOTE = "family ability, new in Forever: no beast teaches it. Check the Beast Training window."

local HOW = {
	GOLD .. "Taming|r",
	"Hunters learn Tame Beast at level 10. Tame a beast and it becomes your pet; it keeps its family (Cat, Wolf, Boar...).",
	GOLD .. "Each family has its own abilities|r",
	"A family can learn only certain abilities: cats learn Claw and Prowl, boars learn Charge, and so on. The Abilities tab lists them.",
	GOLD .. "Learning an ability by taming|r",
	"Most abilities are learned from the wild. Tame a beast that knows the rank you want and keep it as your pet until it has used " ..
	"the ability in combat: you, the hunter, learn that rank. Then you can abandon it or stable it.",
	GOLD .. "Teaching it to your pet|r",
	"Open Beast Training (from your spellbook) and teach any rank you know to any pet whose family can learn it. " ..
	"Each rank needs a minimum pet level and costs training points (TP).",
	GOLD .. "Training points|r",
	"A pet gains TP as it levels up and as its loyalty grows. Each rank's TP cost shows in the training window, " ..
	"and this addon adds the TP you'd have left. The My pet tab shows your pet's TP used and total.",
	GOLD .. "Abilities from the pet trainer|r",
	"Some abilities can't be learned by taming: the resistances, Great Stamina and Natural Armor come from a pet trainer. " ..
	"A few, like Growl, can come from either.",
	GOLD .. "Family abilities (new in Forever)|r",
	"Several families have their own signature ability, e.g. Swipe (Bear), Sonic Blast (Bat), Pinch (Crab), Dismember (Crocolisk). " ..
	"No beast teaches these: look for them in the Beast Training window.",
	GOLD .. "Untraining|r",
	"A pet trainer can untrain your pet: it forgets all its abilities and gets its TP back to spend again (fee: check with your trainer).",
	GOLD .. "Happiness and loyalty|r",
	"Keep your pet happy by feeding it food from its diet. An unhappy pet deals less damage, loses loyalty and may run away.",
}

local frame, scroll, content, bar, abilityDD, rankDD, nearCheck
local tabButtons, rows = {}, {}
local tab = 1
local sel = { rank = 1 } -- Where to tame: ability, rank, near

local function data() return ns.PetData or {} end

local function sortedKeys(t, by)
	local keys = {}
	for k in pairs(t or {}) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return by(a) < by(b) end)
	return keys
end

local function abilityNames()
	return sortedKeys(data().abilities, function(k) return k end)
end

local function levels(b)
	local lo, hi = b.min or b.max, b.max or b.min
	if not lo then return "" end
	return lo == hi and ("lvl " .. lo) or ("lvl " .. lo .. "-" .. hi)
end

local function beastText(b)
	return (b.name or "?") .. "  " .. levels(b) .. "  " .. (b.zone or "") .. (b.rare and (AMBER .. " (rare)|r") or "")
end

local render -- forward

local function showWhere(ability, rank)
	sel.ability, sel.rank = ability, rank or 1
	tab = 4
	render()
end

local function petSpellIDs()
	local ids = {}
	for i = 1, C_SpellBook.HasPetSpells() or 0 do
		local info = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Pet)
		if info and info.spellID then ids[#ids + 1] = info.spellID end
	end
	return ids
end

-- Each tab returns a list of { text, onClick, npc } entries.
local PAGES = {}

PAGES[1] = function()
	local out = {}
	for _, line in ipairs(HOW) do out[#out + 1] = { line } end
	out[#out + 1] = { GREY .. "Data: " .. tostring(data().source or "none") .. "|r" }
	return out
end

PAGES[2] = function()
	if not UnitExists("pet") then return { { "You have no pet out. Summon or tame one." } } end
	local familyName, familyID = UnitCreatureFamily("pet")
	local level = UnitLevel("pet")
	local cur, nextXP = GetPetExperience()
	local total, used = C_PetInfo.GetPetTrainingPoints()
	local happiness = C_PetInfo.GetPetHappiness()
	local out = {
		{ GOLD .. (familyName or "Unknown family") .. "|r  level " .. tostring(level) .. "  XP " .. tostring(cur) .. " / " .. tostring(nextXP) },
		{ "Loyalty: " .. tostring(C_PetInfo.GetPetLoyalty() or "?") .. "   Happiness: " .. (HAPPINESS[happiness] or "?") },
		{ "Training points: " .. tostring(used) .. " used of " .. tostring(total) ..
			(total and used and ("  (" .. (total - used) .. " free)") or "") },
		{ " " },
	}
	local family = (data().families or {})[familyID]
	if not family or not family.abilities or #family.abilities == 0 then
		out[#out + 1] = { "No data yet for this family." }
		return out
	end
	local known = ns.PetKnownRanks(petSpellIDs())
	for _, a in ipairs(family.abilities) do
		local k = known[a]
		local rank, entry, lvlRank, lvlEntry = ns.PetNextRank(a, k, level)
		local s = GOLD .. a .. "|r " .. (k and ("rank " .. k) or "not learned")
		local want
		if rank then
			want = rank
			s = s .. " - next rank " .. rank .. " (pet lvl " .. tostring(entry.level or "?") ..
				(entry.tp and (", " .. entry.tp .. " TP") or "") .. ")"
		elseif entry == "level" then
			want = lvlRank
			s = s .. " - rank " .. lvlRank .. " at pet lvl " .. tostring(lvlEntry.level)
		else
			s = s .. " - max rank"
		end
		if want then
			local info = (data().abilities or {})[a]
			if info and info.taught == "tame" then
				local b = ns.PetBeastsFor(a, want)[1]
				s = s .. "\n    " .. (b and ("Tame: " .. beastText(b.beast)) or "Tame: no beast data yet") ..
					(info.trainer and (GREY .. "  (or pet trainer)|r") or "")
			elseif info and info.taught == "family" then
				s = s .. "\n    " .. FAMILY_NOTE
			else
				s = s .. "\n    Pet trainer"
			end
		end
		out[#out + 1] = { s, function() showWhere(a, want) end }
	end
	return out
end

PAGES[3] = function()
	local families = data().families or {}
	local out = {}
	for _, id in ipairs(sortedKeys(families, function(k) return families[k].name or "" end)) do
		local f = families[id]
		local diet = f.diet and #f.diet > 0 and table.concat(f.diet, ", ") or "?"
		out[#out + 1] = { GOLD .. (f.name or "?") .. "|r  " .. GREY .. "diet: " .. diet .. "|r" }
		for _, a in ipairs(f.abilities or {}) do
			out[#out + 1] = { "    " .. a, function() showWhere(a, 1) end }
		end
	end
	if #out == 0 then out[1] = { "No data yet." } end
	return out
end

PAGES[4] = function()
	local names = abilityNames()
	if #names == 0 then return { { "No data yet." } } end
	if not (data().abilities or {})[sel.ability] then sel.ability, sel.rank = names[1], 1 end
	local filter
	if sel.near then
		local lvl = UnitLevel("player")
		filter = { minLvl = lvl - 5, maxLvl = lvl + 5 }
	end
	local out = {}
	for _, hit in ipairs(ns.PetBeastsFor(sel.ability, sel.rank, filter)) do
		out[#out + 1] = { beastText(hit.beast), nil, hit.npc }
	end
	if #out == 0 then
		local info = data().abilities[sel.ability]
		out[1] = { info.taught == "trainer" and (sel.ability .. " is learned from a pet trainer, not by taming.")
			or info.taught == "family" and (sel.ability .. ": " .. FAMILY_NOTE)
			or "No beast found for this rank" .. (sel.near and " near your level." or ".") }
	end
	return out
end

local function row(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, content)
	r:SetWidth(W - 60)
	r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	r.text:SetPoint("TOPLEFT")
	r.text:SetWidth(W - 130)
	r.text:SetJustifyH("LEFT")
	r.hl = r:CreateTexture(nil, "HIGHLIGHT")
	r.hl:SetAllPoints()
	r.hl:SetColorTexture(1, 1, 1, 0.08)
	r.map = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
	r.map:SetSize(50, 18)
	r.map:SetPoint("TOPRIGHT")
	r.map:SetText("Map")
	r.map:SetScript("OnClick", function(self) ns.PetWaypoint(self.npc) end)
	r:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
	rows[i] = r
	return r
end

function render()
	if not frame then return end
	for i, b in ipairs(tabButtons) do
		if i == tab then b:LockHighlight() else b:UnlockHighlight() end
	end
	bar:SetShown(tab == 4)
	scroll:ClearAllPoints()
	scroll:SetPoint("TOPLEFT", 14, tab == 4 and -104 or -70)
	scroll:SetPoint("BOTTOMRIGHT", -32, 14)
	if tab == 4 then
		abilityDD:GenerateMenu() -- refresh the shown selections
		rankDD:GenerateMenu()
	end
	local y = 0
	local entries = PAGES[tab]()
	for i, e in ipairs(entries) do
		local r = row(i)
		r.text:SetText(e[1])
		r.onClick = e[2]
		r.hl:SetShown(e[2] ~= nil)
		r.map.npc = e[3]
		r.map:SetShown(e[3] ~= nil and ns.PetWaypoint ~= nil)
		local h = math.max(18, r.text:GetStringHeight() + 6)
		r:SetHeight(h)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 0, -y)
		r:Show()
		y = y + h
	end
	for i = #entries + 1, #rows do rows[i]:Hide() end
	content:SetHeight(math.max(y, 1))
end

local function place()
	frame:ClearAllPoints()
	local pos = ns.db.petGuidePos
	if pos[1] then
		frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		frame:SetPoint("CENTER")
	end
end

local function build()
	frame = CreateFrame("Frame", "UltimateHunterPetGuide", UIParent, "BackdropTemplate")
	frame:SetSize(W, H)
	frame:SetFrameStrata("DIALOG")
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	frame:SetBackdropColor(0.05, 0.055, 0.07, 0.95)
	frame:SetBackdropBorderColor(0.2, 0.216, 0.263, 1)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relativePoint, x, y = self:GetPoint()
		ns.db.petGuidePos = { point, relativePoint, x, y }
	end)
	tinsert(UISpecialFrames, "UltimateHunterPetGuide") -- Escape closes it

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("Pet Training")
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	for i, name in ipairs(TABS) do
		local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		b:SetSize(128, 22)
		b:SetPoint("TOPLEFT", 14 + (i - 1) * 133, -38)
		b:SetText(name)
		b:SetScript("OnClick", function() tab = i render() scroll:SetVerticalScroll(0) end)
		tabButtons[i] = b
	end

	-- Where to tame controls
	bar = CreateFrame("Frame", nil, frame)
	bar:SetPoint("TOPLEFT", 14, -68)
	bar:SetSize(W - 28, 30)
	abilityDD = CreateFrame("DropdownButton", nil, bar, "WowStyle1DropdownTemplate")
	abilityDD:SetPoint("LEFT")
	abilityDD:SetWidth(180)
	abilityDD:SetupMenu(function(_, root)
		for _, name in ipairs(abilityNames()) do
			root:CreateRadio(name, function() return sel.ability == name end,
				function() sel.ability, sel.rank = name, 1 render() end)
		end
	end)
	rankDD = CreateFrame("DropdownButton", nil, bar, "WowStyle1DropdownTemplate")
	rankDD:SetPoint("LEFT", abilityDD, "RIGHT", 8, 0)
	rankDD:SetWidth(110)
	rankDD:SetupMenu(function(_, root)
		local info = (data().abilities or {})[sel.ability]
		for i, r in ipairs(info and info.ranks or {}) do
			root:CreateRadio("Rank " .. i .. (r.level and (" (lvl " .. r.level .. ")") or ""),
				function() return sel.rank == i end, function() sel.rank = i render() end)
		end
	end)
	nearCheck = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
	nearCheck:SetSize(24, 24)
	nearCheck:SetPoint("LEFT", rankDD, "RIGHT", 10, 0)
	nearCheck:SetScript("OnClick", function(self) sel.near = self:GetChecked() render() end)
	local nearLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	nearLabel:SetPoint("LEFT", nearCheck, "RIGHT", 2, 0)
	nearLabel:SetText("Near my level")

	scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(W - 60, 1)
	scroll:SetScrollChild(content)

	for _, e in ipairs(PET_EVENTS) do frame:RegisterEvent(e) end
	frame:SetScript("OnEvent", function(_, event, unit)
		if event == "UNIT_PET" and unit ~= "player" then return end
		if frame:IsShown() and tab == 2 then render() end
	end)
	place()
end

function ns.TogglePetGuide()
	if not ns.db or not ns.db.petGuideEnabled then return end
	if not frame then build() frame:Hide() end
	if frame:IsShown() then frame:Hide() else frame:Show() render() end
end

ns.modules[#ns.modules + 1] = function()
	if not frame then return end
	place() -- after /uh reset
	if not ns.db.petGuideEnabled then frame:Hide() end
end
