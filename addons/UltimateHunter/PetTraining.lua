-- Pet Training guide window: how training works, the current pet, families, abilities and where to
-- tame each rank. Pet APIs (C_PetInfo, pet spellbook) return no secrets. Built lazily on first open;
-- each page is built on its first visit and only the shown page renders.
local _, ns = ...
local S = ns.Skin
local C = S.C

local W, H, SIDE, PAD, GAP = 860, 560, 170, 16, 8
local INNER = W - 2 - SIDE - 2 * PAD -- content width
local SCROLLED = INNER - 14         -- content width beside a scroll bar
local COL2 = math.floor((SCROLLED - GAP) / 2)
local COL3 = math.floor((SCROLLED - 2 * GAP) / 3)
local CARD_H, ROW_H = 78, 40
local QUESTION = S.QUESTION
local SPELL = { tame = 1515, training = 5149, feed = 6991, lore = 1462, call = 883, claw = 16827 }
local SOURCES = { tame = { "Tame", C.accent }, trainer = { "Trainer", C.info }, family = { "Family", C.warn } }
local HAPPINESS = { { "Unhappy", C.danger }, { "Content", C.warn }, { "Happy", C.success } }
local PET_EVENTS = { "UNIT_PET", "UNIT_PET_TRAINING_POINTS", "UNIT_HAPPINESS", "UNIT_PET_EXPERIENCE",
	"PET_STABLE_UPDATE", "SPELLS_CHANGED" }
local NOTES = {
	family = "Family ability, new in Forever: no beast teaches it. Check the Beast Training window.",
	trainer = "Bought from a pet trainer, not learned by taming.",
}
local STEPS = { -- icon (spell ID or ability name), title, text
	{ SPELL.tame, "Tame a beast",
		"Hunters learn Tame Beast at level 10. The tamed beast becomes your pet and keeps its family: Cat, Wolf, Boar..." },
	{ SPELL.lore, "Learn from the wild",
		"Tame a beast that knows the rank you want and keep it until it uses the ability in combat: you, the hunter, learn that rank." },
	{ SPELL.training, "Teach your pet",
		"Open Beast Training and teach any rank you know to a pet whose family can learn it. Each rank needs a minimum pet level." },
	{ SPELL.call, "Training points",
		"Pets earn TP from their level and loyalty. The training window shows each rank's cost, and this addon adds the TP you'd have left." },
	{ "Growl", "Pet trainer",
		"Resistances, Great Stamina and Natural Armor are bought from a pet trainer; some, like Growl, come from either. The trainer can also untrain your pet to refund its TP." },
	{ SPELL.feed, "Happiness",
		"Feed your pet food from its family's diet. An unhappy pet deals less damage and loses loyalty." },
}

local frame, body, footer
local nav, PAGES = {}, {}
local GUIDE, PET, FAMILIES, ABILITIES, FINDER = 1, 2, 3, 4, 5
local state = { page = GUIDE, filter = "all", rank = 1, search = "" }
local render, show, openFinder -- forward

------------------------------------------------------------------------------- data helpers
local function data() return ns.PetData or {} end
local function abilities() return data().abilities or {} end
local function families() return data().families or {} end

local function sorted(t, key)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return key(a) < key(b) end)
	return keys
end
local function familyIDs() return sorted(families(), function(k) return families()[k].name or "" end) end

local function spellIcon(id) return C_Spell.GetSpellTexture(id) or QUESTION end
local function abilityIcon(name)
	local a = abilities()[name]
	local r = a and a.ranks and a.ranks[1]
	return r and r.spell and spellIcon(r.spell) or QUESTION
end
local function familyIcon(id)
	local info = id and C_CreatureInfo.GetCreatureFamilyInfo(id)
	return info and info.iconFile or QUESTION
end

-- name, familyID of the summoned pet; nil when there's none or its identity is restricted.
local function petFamily()
	if not UnitExists("pet") then return end
	local name, id = UnitCreatureFamily("pet")
	if issecretvalue(name) or issecretvalue(id) then return end
	return name, id
end

local function petSpellIDs()
	local ids = {}
	for i = 1, C_SpellBook.HasPetSpells() or 0 do
		local info = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Pet)
		if info and info.spellID then ids[#ids + 1] = info.spellID end
	end
	return ids
end

local function levelRange(lo, hi)
	lo, hi = lo or hi, hi or lo
	return lo == hi and tostring(lo) or (lo .. "–" .. hi)
end

------------------------------------------------------------------------------- layout helpers
-- Reusable frames: p.reset(), then p.next() per item, then p.done() hides the leftovers.
local function pool(make)
	local p = { n = 0 }
	function p.reset() p.n = 0 end
	function p.next()
		p.n = p.n + 1
		local f = p[p.n] or make()
		p[p.n] = f
		f:Show()
		return f
	end
	function p.done() for i = p.n + 1, #p do p[i]:Hide() end end
	return p
end

-- Puts item i of a cols-wide grid of w x h cells starting at y0; returns the grid's bottom.
local function cell(f, i, cols, w, h, y0)
	local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
	f:SetSize(w, h)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", col * (w + GAP), -(y0 + row * (h + GAP)))
	return y0 + (row + 1) * (h + GAP) - GAP
end

-- Lays pills out left to right from (x0, y0), wrapping at maxW. items: { {text, color, onClick} }.
-- Returns the bottom.
local function flow(p, items, x0, y0, maxW)
	local x, y = 0, y0
	for _, it in ipairs(items) do
		local pill = p.next()
		pill:Set(it[1], it[2], it[3])
		if x > 0 and x + pill.w > maxW then x, y = 0, y + 24 end
		pill:ClearAllPoints()
		pill:SetPoint("TOPLEFT", x0 + x, -y)
		x = x + pill.w + 6
	end
	return #items > 0 and y + 18 or y0
end

local function scrollArea(p, top)
	local sf = S.ScrollArea(p)
	sf:SetPoint("TOPLEFT", 0, -(top or 0))
	sf:SetPoint("BOTTOMRIGHT", -14, 0)
	sf.child:SetWidth(SCROLLED)
	p.sf = sf
	return sf.child
end

local function abilityChip(name)
	local info = abilities()[name] or {}
	local src = SOURCES[info.taught] or { nil, C.muted }
	return { name, src[2], info.taught == "tame" and function() openFinder(name, 1) end or nil }
end

------------------------------------------------------------------------------- ability card
-- Shared by My pet (pips + next rank) and Abilities (rank summary + family icons).
local function abilityCard(parent)
	local card = S.Card(parent, true)
	card.tile = S.IconTile(card, 32)
	card.tile:SetPoint("TOPLEFT", 10, -10)
	card.name = S.Line(card, 13, C.text, COL3 - 62)
	card.name:SetPoint("TOPLEFT", card.tile, "TOPRIGHT", 10, -1)
	card.sub = S.Line(card, 11, C.muted, COL3 - 62)
	card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -6)
	card.foot = S.Line(card, 11, C.muted, COL3 - 84)
	card.foot:SetPoint("BOTTOMLEFT", 10, 11)
	card.chip = S.Pill(card)
	card.chip:SetPoint("BOTTOMRIGHT", -10, 9)
	card.more = S.Text(card, 11, C.muted)
	card.pips, card.fams = {}, {}
	return card
end

local function fillAbility(card, name)
	local info = abilities()[name] or {}
	card.tile:SetIcon(abilityIcon(name))
	card.name:SetText(name)
	local src = SOURCES[info.taught]
	card.chip:SetShown(src ~= nil)
	if src then card.chip:Set(src[1], src[2]) end
	return info
end

-- Rank pips: filled accent for known ranks, outlined for the rest.
local function setPips(card, known, total)
	for i = 1, math.max(total, #card.pips) do
		local pip = card.pips[i]
		if not pip then
			pip = S.Circle(card, 8, C.accent)
			pip.hole = S.Circle(card, 6, C.raised, "OVERLAY")
			pip:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", (i - 1) * 12, -7)
			pip.hole:SetPoint("CENTER", pip)
			card.pips[i] = pip
		end
		pip:SetShown(i <= total)
		pip:SetVertexColor(unpack(i <= known and C.accent or C.muted))
		pip.hole:SetShown(i <= total and i > known)
	end
end

local MAX_FAMS = 6
local function setFamilies(card, ids)
	local n = math.min(#ids, MAX_FAMS)
	for i = 1, MAX_FAMS do
		local t = card.fams[i]
		if not t and i <= n then
			t = S.IconTile(card, 16)
			t:SetPoint("BOTTOMLEFT", 10 + (i - 1) * 18, 10)
			card.fams[i] = t
		end
		if t then
			t:SetShown(i <= n)
			if i <= n then t:SetIcon(familyIcon(ids[i])) end
		end
	end
	card.more:SetText(#ids > n and ("+" .. (#ids - n)) or "")
	card.more:SetPoint("BOTTOMLEFT", 12 + n * 18, 12)
end

------------------------------------------------------------------------------- 1. Guide
PAGES[GUIDE] = { label = "Guide", icon = SPELL.training }

local function textCard(parent, bg, border)
	local card = S.Frame(parent, bg, border)
	card.title = S.Line(card, 13, C.text)
	card.body = S.Text(card, 12, C.muted)
	card.body:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)
	card.body:SetWordWrap(true)
	return card
end

PAGES[GUIDE].build = function(p)
	local c = scrollArea(p)
	S.SectionTitle(c, "How pet training works", "From taming your first beast to a fully trained pet."):SetPoint("TOPLEFT")
	p.cards = {}
	for i, s in ipairs(STEPS) do
		local card = textCard(c, C.raised)
		card.tile = S.IconTile(card, 32)
		card.tile:SetPoint("TOPLEFT", 12, -12)
		S.Badge(card, i):SetPoint("TOPRIGHT", -12, -12)
		card.title:SetPoint("TOPLEFT", card.tile, "TOPRIGHT", 12, -1)
		card.title:SetWidth(COL2 - 98)
		card.body:SetWidth(COL2 - 68)
		card.title:SetText(s[2])
		card.body:SetText(s[3])
		p.cards[i] = card
	end
	local co = textCard(c, C.accentSoft, { 0, 0, 0, 0 })
	local edge = S.Fill(co, C.accent, "ARTWORK")
	edge:SetPoint("TOPLEFT")
	edge:SetPoint("BOTTOMLEFT")
	edge:SetWidth(2)
	co.title:SetPoint("TOPLEFT", 16, -14)
	co.title:SetTextColor(unpack(C.accent))
	co.title:SetText("New in Forever: family abilities")
	co.body:SetWidth(SCROLLED - 32)
	co.body:SetText("Swipe (Bear), Sonic Blast (Bat), Pinch (Crab), Dismember (Crocolisk)... " ..
		"No beast teaches these: find them in your Beast Training window.")
	p.callout = co
end

PAGES[GUIDE].render = function(p)
	local y = 48
	for i = 1, #p.cards, 2 do
		local h = 0
		for j = i, math.min(i + 1, #p.cards) do
			local s = STEPS[j]
			p.cards[j].tile:SetIcon(type(s[1]) == "number" and spellIcon(s[1]) or abilityIcon(s[1]))
			h = math.max(h, 60, 47 + p.cards[j].body:GetStringHeight())
		end
		for j = i, math.min(i + 1, #p.cards) do
			p.cards[j]:SetSize(COL2, h)
			p.cards[j]:SetPoint("TOPLEFT", (j - i) * (COL2 + GAP), -y)
		end
		y = y + h + GAP
	end
	local coH = 49 + p.callout.body:GetStringHeight()
	p.callout:SetSize(SCROLLED, coH)
	p.callout:SetPoint("TOPLEFT", 0, -(y + GAP))
	p.sf.child:SetHeight(y + GAP + coH)
end

------------------------------------------------------------------------------- 2. My pet
PAGES[PET] = { label = "My pet", icon = SPELL.call }

local function stat(parent, label)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(240, 30)
	S.Text(f, 11, C.muted, label):SetPoint("TOPLEFT")
	f.value = S.Text(f, 11, C.text)
	f.value:SetPoint("TOPRIGHT")
	f.value:SetJustifyH("RIGHT")
	f.bar = S.ProgressBar(f, 8)
	f.bar:SetPoint("BOTTOMLEFT")
	f.bar:SetPoint("BOTTOMRIGHT")
	return f
end

PAGES[PET].build = function(p)
	p.empty = S.Empty(p)
	p.empty:SetPoint("CENTER", 0, 20)
	local c = scrollArea(p)
	local hero = S.Card(c)
	hero:SetSize(SCROLLED, 96)
	hero:SetPoint("TOPLEFT")
	local ring = S.Circle(hero, 68, C.accent)
	ring:SetPoint("LEFT", 14, 0)
	p.portrait = hero:CreateTexture(nil, "OVERLAY")
	p.portrait:SetSize(64, 64)
	p.portrait:SetPoint("CENTER", ring)
	p.name = S.Line(hero, 18, C.text, 300)
	p.name:SetPoint("TOPLEFT", ring, "TOPRIGHT", 16, -4)
	p.sub = S.Line(hero, 12, C.muted, 300)
	p.sub:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -5)
	p.happy = S.Pill(hero)
	p.happy:SetPoint("TOPLEFT", p.sub, "BOTTOMLEFT", 0, -9)
	p.loyal = S.Pill(hero)
	p.loyal:SetPoint("LEFT", p.happy, "RIGHT", 6, 0)
	p.xp = stat(hero, "Experience")
	p.xp:SetPoint("TOPRIGHT", -16, -14)
	p.tp = stat(hero, "Training points")
	p.tp:SetPoint("TOPRIGHT", p.xp, "BOTTOMRIGHT", 0, -10)
	S.SectionTitle(c, "Abilities", "Click a tameable ability to find beasts that teach its next rank.")
		:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, -20)
	p.none = S.Text(c, 12, C.muted, "No data yet for this family.")
	p.none:SetPoint("TOPLEFT", 0, -160)
	p.cards = pool(function() return abilityCard(c) end)
end

PAGES[PET].render = function(p)
	local famName, famID = petFamily()
	p.sf:SetShown(UnitExists("pet"))
	if not UnitExists("pet") then
		p.empty:Set(spellIcon(SPELL.call), "No pet summoned", "Call your pet to see its abilities.")
		return
	end
	p.empty:Hide()
	SetPortraitTexture(p.portrait, "pet")
	local level = UnitLevel("pet")
	p.name:SetText(UnitName("pet") or "Your pet")
	p.sub:SetText((famName or "Unknown family") .. " · Level " .. tostring(level))
	local happy = HAPPINESS[C_PetInfo.GetPetHappiness() or 0]
	p.happy:SetShown(happy ~= nil)
	if happy then p.happy:Set(happy[1], happy[2]) end
	p.loyal:Set(C_PetInfo.GetPetLoyalty() or "Loyalty unknown", C.muted)
	local cur, nextXP = GetPetExperience()
	p.xp.bar:Set(cur, nextXP)
	p.xp.value:SetText(tostring(cur or 0) .. " / " .. tostring(nextXP or 0))
	local total, used = C_PetInfo.GetPetTrainingPoints()
	total, used = total or 0, used or 0
	p.tp.bar:Set(used, total, C.info)
	p.tp.value:SetText(used .. " / " .. total .. "   " .. S.Hex(C.accent) .. (total - used) .. " free|r")

	local family = famID and families()[famID]
	local list = family and family.abilities or {}
	local known = ns.PetKnownRanks(petSpellIDs())
	p.none:SetShown(#list == 0)
	p.cards.reset()
	local bottom = 160
	for i, a in ipairs(list) do
		local card = p.cards.next()
		bottom = cell(card, i, 3, COL3, CARD_H, 160)
		local info = fillAbility(card, a)
		card.sub:SetText("")
		setFamilies(card, {})
		setPips(card, known[a] or 0, #(info.ranks or {}))
		local rank, entry, lvlRank, lvlEntry = ns.PetNextRank(a, known[a], level)
		local want = rank or lvlRank
		if rank then
			card.foot:SetText("Next: Rank " .. rank .. " · pet lvl " .. tostring(entry.level or "?"))
			card.foot:SetTextColor(unpack(C.muted))
		elseif entry == "level" then
			card.foot:SetText("Needs pet lvl " .. tostring(lvlEntry.level))
			card.foot:SetTextColor(unpack(C.warn))
		else
			card.foot:SetText("Max rank")
			card.foot:SetTextColor(unpack(C.success))
		end
		card.onClick = (info.taught == "tame" and want) and function() openFinder(a, want) end or nil
	end
	p.cards.done()
	p.sf.child:SetHeight(bottom + 4)
end

------------------------------------------------------------------------------- 3. Families
PAGES[FAMILIES] = { label = "Families", icon = SPELL.lore }

PAGES[FAMILIES].build = function(p)
	local list = S.ScrollArea(p)
	list:SetPoint("TOPLEFT")
	list:SetPoint("BOTTOMLEFT")
	list:SetWidth(196)
	list.child:SetWidth(196)
	p.list = list
	p.rows = pool(function()
		local row = S.NavItem(list.child, 32, 22, function(self) state.family = self.id render() end)
		row:SetWidth(196)
		return row
	end)
	local d = S.Frame(p, C.surface)
	d:SetPoint("TOPLEFT", 220, 0)
	d:SetPoint("BOTTOMRIGHT")
	p.detail = d
	d.tile = S.IconTile(d, 48)
	d.tile:SetPoint("TOPLEFT", 16, -16)
	d.name = S.Text(d, 18)
	d.name:SetPoint("TOPLEFT", d.tile, "TOPRIGHT", 14, -4)
	d.yours = S.Pill(d)
	d.yours:SetPoint("LEFT", d.name, "RIGHT", 10, 0)
	d.yours:Set("Your pet", C.accent)
	d.sub = S.Text(d, 12, C.muted)
	d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -6)
	d.diet = S.SectionTitle(d, "Diet", "Feed any of these to keep your pet happy.")
	d.abilities = S.SectionTitle(d, "Abilities", "Green: tame it from a beast (click). Blue: pet trainer. Amber: family ability.")
	d.chips = pool(function() return S.Pill(d) end)
	p.empty = S.Empty(p)
	p.empty:SetPoint("CENTER", 0, 20)
end

PAGES[FAMILIES].render = function(p)
	local ids, fams = familyIDs(), families()
	local _, petID = petFamily()
	p.empty:SetShown(#ids == 0)
	p.list:SetShown(#ids > 0)
	p.detail:SetShown(#ids > 0)
	if #ids == 0 then
		p.empty:Set(spellIcon(SPELL.lore), "No data yet", "Pet family data didn't load.")
		return
	end
	if not fams[state.family] then state.family = fams[petID] and petID or ids[1] end
	p.rows.reset()
	for i, id in ipairs(ids) do
		local row = p.rows.next()
		row:SetPoint("TOPLEFT", 0, -(i - 1) * 34)
		row.id = id
		row:SetText(fams[id].name or "?")
		row.tile:SetIcon(familyIcon(id))
		row:SetSelected(id == state.family)
	end
	p.rows.done()
	p.list.child:SetHeight(#ids * 34)

	local d, f = p.detail, fams[state.family]
	local diet, abil = f.diet or {}, f.abilities or {}
	d.tile:SetIcon(familyIcon(state.family))
	d.name:SetText(f.name or "?")
	d.yours:SetShown(state.family == petID)
	d.sub:SetText(#abil .. " abilities · eats " .. #diet .. (#diet == 1 and " food type" or " food types"))
	local maxW = INNER - 220 - 32
	d.chips.reset()
	d.diet:SetPoint("TOPLEFT", 16, -88)
	local items = {}
	for i, food in ipairs(diet) do items[i] = { food, C.text } end
	local y = flow(d.chips, items, 16, 88 + 40, maxW)
	d.abilities:SetPoint("TOPLEFT", 16, -(y + 24))
	items = {}
	for i, a in ipairs(abil) do items[i] = abilityChip(a) end
	flow(d.chips, items, 16, y + 24 + 40, maxW)
	d.chips.done()
end

------------------------------------------------------------------------------- 4. Abilities
PAGES[ABILITIES] = { label = "Abilities", icon = SPELL.claw }

PAGES[ABILITIES].build = function(p)
	p.seg = S.Segmented(p, 320, { { "all", "All" }, { "tame", "Tame" }, { "trainer", "Trainer" }, { "family", "Family" } },
		function() return state.filter end, function(v) state.filter = v render() end)
	p.seg:SetPoint("TOPLEFT")
	p.count = S.Text(p, 11, C.muted)
	p.count:SetPoint("RIGHT", p, "TOPRIGHT", -14, -14)
	local c = scrollArea(p, 28 + 16)
	p.cards = pool(function() return abilityCard(c) end)
	p.empty = S.Empty(p)
	p.empty:SetPoint("CENTER", 0, 20)
end

PAGES[ABILITIES].render = function(p)
	local learners = {} -- ability -> family IDs that can learn it
	for _, id in ipairs(familyIDs()) do
		for _, a in ipairs(families()[id].abilities or {}) do
			learners[a] = learners[a] or {}
			learners[a][#learners[a] + 1] = id
		end
	end
	p.cards.reset()
	local n, bottom = 0, 0
	for _, name in ipairs(sorted(abilities(), tostring)) do
		local info = abilities()[name]
		if state.filter == "all" or info.taught == state.filter then
			n = n + 1
			local card = p.cards.next()
			bottom = cell(card, n, 3, COL3, CARD_H, 0)
			fillAbility(card, name)
			local ranks = info.ranks or {}
			local lo, hi = ranks[1] and ranks[1].level, ranks[#ranks] and ranks[#ranks].level
			card.sub:SetText(#ranks .. (#ranks == 1 and " rank" or " ranks") .. (lo and (" · lvl " .. levelRange(lo, hi)) or ""))
			card.foot:SetText("")
			setPips(card, 0, 0)
			local fams = learners[name] or {}
			setFamilies(card, fams)
			if info.taught == "tame" then
				card.onClick = function() openFinder(name, 1) end
			elseif fams[1] then
				card.onClick = function() state.family = fams[1] show(FAMILIES) end
			else
				card.onClick = nil
			end
		end
	end
	p.cards.done()
	p.sf.child:SetHeight(bottom + 4)
	p.seg:Refresh()
	p.count:SetText(n .. (n == 1 and " ability" or " abilities"))
	if n == 0 then p.empty:Set(spellIcon(SPELL.claw), "No abilities", "No ability data for this filter.") else p.empty:Hide() end
end

------------------------------------------------------------------------------- 5. Tame finder
PAGES[FINDER] = { label = "Tame finder", icon = SPELL.tame }

local function abilityOptions()
	local out = {}
	for i, name in ipairs(sorted(abilities(), tostring)) do out[i] = { name, name } end
	return out
end

local function rankOptions()
	local out, info = {}, abilities()[state.ability]
	for i, r in ipairs(info and info.ranks or {}) do
		out[i] = { i, "Rank " .. i .. (r.level and (" · lvl " .. r.level) or "") }
	end
	return out
end

local function beastRow(parent)
	local r = CreateFrame("Button", nil, parent)
	r:SetSize(SCROLLED, ROW_H)
	r.tint = S.Fill(r, { 1, 1, 1, 0.025 })
	r.tint:SetAllPoints()
	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.05)
	r.tile = S.IconTile(r, 28)
	r.tile:SetPoint("LEFT", 8, 0)
	r.name = S.Line(r, 13, C.text, 240)
	r.name:SetPoint("TOPLEFT", r.tile, "TOPRIGHT", 10, -1)
	r.zone = S.Line(r, 11, C.muted, 240)
	r.zone:SetPoint("BOTTOMLEFT", r.tile, "BOTTOMRIGHT", 10, 1)
	r.level = S.Pill(r)
	r.level:SetPoint("LEFT", 300, 0)
	r.rare = S.Pill(r)
	r.rare:SetPoint("LEFT", 372, 0)
	r.rare:Set("Rare", C.silver)
	r.map = S.Button(r, "Map", 56, 24, "default", function(self) ns.PetWaypoint(self.npc) end)
	r.map:SetPoint("RIGHT", -8, 0)
	return r
end

local function fillRow(r, i, hit)
	local b = hit.beast
	r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	r.tint:SetShown(i % 2 == 0)
	r.tile:SetIcon(familyIcon(b.family))
	r.name:SetText(b.name or "?")
	r.name:SetTextColor(unpack(b.rare and C.silver or C.text))
	r.zone:SetText(b.zone or "Unknown zone")
	r.level:SetShown((b.min or b.max) ~= nil)
	if b.min or b.max then r.level:Set("Lv " .. levelRange(b.min, b.max), C.text) end
	r.rare:SetShown(b.rare and true or false)
	r.map.npc = hit.npc
	r.map:SetShown(ns.PetWaypoint ~= nil)
end

PAGES[FINDER].build = function(p)
	p.ability = S.Dropdown(p, 200, abilityOptions, function() return state.ability end,
		function(v) state.ability, state.rank = v, 1 render() end, "Choose an ability")
	p.ability:SetPoint("TOPLEFT")
	p.rank = S.Dropdown(p, 150, rankOptions, function() return state.rank end, function(v) state.rank = v render() end)
	p.rank:SetPoint("LEFT", p.ability, "RIGHT", GAP, 0)
	p.search = S.Input(p, INNER - 350 - 2 * GAP, 26, "Search beast or zone",
		function(text) state.search = text:lower() render() end)
	p.search:SetPoint("LEFT", p.rank, "RIGHT", GAP, 0)
	p.near = S.Check(p, "Near my level", function() return state.near end, function(v) state.near = v render() end)
	p.near:SetPoint("TOPLEFT", p.ability, "BOTTOMLEFT", 0, -10)
	p.rare = S.Check(p, "Rares only", function() return state.rare end, function(v) state.rare = v render() end)
	p.rare:SetPoint("LEFT", p.near, "RIGHT", 16, 0)
	p.count = S.Text(p, 11, C.muted)
	p.count:SetPoint("RIGHT", p, "TOPRIGHT", 0, -46)
	p.count:SetJustifyH("RIGHT")
	local line = S.Fill(p, C.border, "ARTWORK")
	line:SetPoint("TOPLEFT", 0, -66)
	line:SetPoint("TOPRIGHT", 0, -66)
	line:SetHeight(1)
	local c = scrollArea(p, 74)
	p.rows = pool(function() return beastRow(c) end)
	p.empty = S.Empty(p)
	p.empty:SetPoint("CENTER", 0, -10)
end

PAGES[FINDER].render = function(p)
	if not abilities()[state.ability] then
		local names = sorted(abilities(), tostring)
		state.ability, state.rank = names[1], 1
		for _, name in ipairs(names) do
			if abilities()[name].taught == "tame" then state.ability = name break end
		end
	end
	local info = abilities()[state.ability]
	p.ability:Refresh()
	p.rank:Refresh()
	p.near:Refresh()
	p.rare:Refresh()
	local hits, q = {}, state.search
	if info and info.taught == "tame" then
		local filter = { rareOnly = state.rare or nil }
		if state.near then
			local lvl = UnitLevel("player")
			filter.minLvl, filter.maxLvl = lvl - 5, lvl + 5
		end
		for _, hit in ipairs(ns.PetBeastsFor(state.ability, state.rank, filter)) do
			local b = hit.beast
			if q == "" or (b.name or ""):lower():find(q, 1, true) or (b.zone or ""):lower():find(q, 1, true) then
				hits[#hits + 1] = hit
			end
		end
	end
	p.rows.reset()
	for i, hit in ipairs(hits) do fillRow(p.rows.next(), i, hit) end
	p.rows.done()
	p.sf.child:SetHeight(math.max(1, #hits * ROW_H))
	p.count:SetText(info and info.taught == "tame" and
		(#hits .. (#hits == 1 and " beast" or " beasts") .. (info.trainer and " · also sold by pet trainers" or "")) or "")
	if not info then
		p.empty:Set(spellIcon(SPELL.tame), "No data yet", "Pet ability data didn't load.")
	elseif info.taught ~= "tame" then
		p.empty:Set(abilityIcon(state.ability), state.ability, NOTES[info.taught] or NOTES.trainer)
	elseif #hits == 0 then
		local filtered = q ~= "" or state.near or state.rare
		p.empty:Set(abilityIcon(state.ability), "No beast found",
			filtered and "Try clearing the search or filters." or "No beast in the data teaches this rank.")
	else
		p.empty:Hide()
	end
end

------------------------------------------------------------------------------- window
function render()
	if not (frame and frame:IsShown()) then return end
	local source = data().source
	footer:SetText("Data: " .. (source and source:match("^[^,]+") or "none"))
	local page = PAGES[state.page]
	page.render(page.frame)
end

function show(i)
	state.page = i
	for j, b in ipairs(nav) do b:SetSelected(j == i) end
	for j, page in ipairs(PAGES) do
		if j == i and not page.frame then
			page.frame = CreateFrame("Frame", nil, body)
			page.frame:SetAllPoints()
			page.build(page.frame)
		end
		if page.frame then page.frame:SetShown(j == i) end
	end
	if PAGES[i].frame.sf then PAGES[i].frame.sf:SetVerticalScroll(0) end
	render()
end

function openFinder(ability, rank)
	state.ability, state.rank, state.search = ability, rank or 1, ""
	if PAGES[FINDER].frame then PAGES[FINDER].frame.search:SetValue("") end
	show(FINDER)
end

local function restorePos()
	frame:ClearAllPoints()
	local pos = ns.db.petGuidePos
	if pos[1] then
		frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		frame:SetPoint("CENTER")
	end
end

local function build()
	frame = S.Window("UltimateHunterPetGuide", W, H, "Pet Training")
	frame.subtitle:SetText("Hunter pet guide · WoW Forever")
	frame.bar:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		local point, _, relativePoint, x, y = frame:GetPoint()
		ns.db.petGuidePos = { point, relativePoint, x, y }
	end)

	local side = CreateFrame("Frame", nil, frame)
	side:SetPoint("TOPLEFT", 1, -43)
	side:SetPoint("BOTTOMLEFT", 1, 1)
	side:SetWidth(SIDE)
	S.Fill(side, C.surface):SetAllPoints()
	local edge = S.Fill(side, C.border, "ARTWORK")
	edge:SetPoint("TOPRIGHT")
	edge:SetPoint("BOTTOMRIGHT")
	edge:SetWidth(1)
	for i, page in ipairs(PAGES) do
		local item = S.NavItem(side, 36, 20, function() show(i) end)
		item:SetPoint("TOPLEFT", 0, -(12 + (i - 1) * 40))
		item:SetPoint("TOPRIGHT", -1, -(12 + (i - 1) * 40))
		item:SetText(page.label)
		item.tile:SetIcon(spellIcon(page.icon))
		nav[i] = item
	end
	footer = S.Text(side, 11, C.muted)
	footer:SetPoint("BOTTOMLEFT", 14, 14)
	footer:SetPoint("BOTTOMRIGHT", -14, 14)
	footer:SetWordWrap(true)

	body = CreateFrame("Frame", nil, frame)
	body:SetPoint("TOPLEFT", side, "TOPRIGHT", PAD, -PAD)
	body:SetPoint("BOTTOMRIGHT", -1 - PAD, 1 + PAD)

	for _, e in ipairs(PET_EVENTS) do frame:RegisterEvent(e) end
	frame:SetScript("OnEvent", function(_, event, unit)
		if event == "UNIT_PET" and unit ~= "player" then return end
		if state.page == PET or state.page == FAMILIES then render() end -- render() skips while hidden
	end)
	restorePos()
end

function ns.TogglePetGuide()
	if not ns.db or not ns.db.petGuideEnabled then return end
	if not frame then build() end
	if frame:IsShown() then frame:Hide() else frame:Show() show(state.page) end
end

ns.modules[#ns.modules + 1] = function()
	if not frame then return end
	restorePos() -- after /uh reset
	if not ns.db.petGuideEnabled then frame:Hide() end
end
