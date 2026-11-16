local addonName, ns = ...
local B, F, S = ns.Builder, ns.Folders, ns.Skin
local C = S.C

local QUESTION_MARK = 134400 -- dynamic icon: the macro shows whatever #showtooltip / the first spell resolves to
local MAX_ACCOUNT = Constants.MacroConsts.MAX_ACCOUNT_MACROS
local MAX_CHAR = Constants.MacroConsts.MAX_CHARACTER_MACROS
local ICON_SIZE, ICON_STRIDE = 36, 7
local ROW_HEIGHT, INDENT = 28, 14

local ACTION_ICONS = {
	cast = "spell_frost_frostbolt02", use = "inv_potion_54", sequence = "spell_nature_timestop",
	random = "inv_misc_dice_02", targeting = "ability_hunter_snipershot", attack = "ability_meleedamage",
	pet = "ability_hunter_beastcall", stop = "ability_kick", equip = "inv_chest_plate16",
	marker = "ability_hunter_markedfordeath", bar = "inv_misc_book_09", chat = "inv_letter_15",
	social = "achievement_guildperk_everybodysfriend", click = "inv_misc_gear_01",
	script = "trade_engineering", tooltip = "inv_misc_questionmark", emote = "spell_holy_silence",
}

local state = { tab = "account", index = nil, icon = QUESTION_MARK, dirty = false, loadedName = nil, folder = nil }
local main, tree, editor, iconPanel, dialog

local function IconTexture(icon)
	if type(icon) == "string" and not icon:find("\\") then return "Interface\\Icons\\" .. icon end
	return icon
end

local function Store()
	return state.tab == "account" and MacroBuilderEnhancedDB.account or MacroBuilderEnhancedCharDB
end

local function IsCharIndex(index) return index > MAX_ACCOUNT end

------------------------------------------------------------------------------- spellbook / bag / item-type data
-- groups { {name, spells = { {name, icon} }} } and ranks[name] = {"Rank 1", ...} for spells that have ranks.
local function ScanSpells()
	local groups, ranks = {}, {}
	local function scanRange(groupName, bank, first, last)
		local group, seen = { name = groupName, spells = {} }, {}
		for slot = first, last do
			local it = C_SpellBook.GetSpellBookItemInfo(slot, bank)
			if it and it.itemType == Enum.SpellBookItemType.Spell and not it.isPassive and it.name then
				if not seen[it.name] then
					seen[it.name] = true
					group.spells[#group.spells + 1] = { it.name, it.iconID }
				end
				local sub = it.subName
				if (not sub or sub == "") and it.spellID then sub = C_Spell.GetSpellSubtext(it.spellID) end
				if sub and sub:find("%d") then
					local r = ranks[it.name] or {}
					ranks[it.name] = r
					if not tContains(r, sub) then r[#r + 1] = sub end
				end
			end
		end
		if #group.spells > 0 then groups[#groups + 1] = group end
	end
	for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(i)
		if info and not info.shouldHide then
			scanRange(info.name, Enum.SpellBookSpellBank.Player, info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems)
		end
	end
	local numPet = C_SpellBook.HasPetSpells()
	if numPet and numPet > 0 then scanRange(PET or "Pet", Enum.SpellBookSpellBank.Pet, 1, numPet) end
	for _, r in pairs(ranks) do
		table.sort(r, function(a, b) return (tonumber(a:match("%d+")) or 0) < (tonumber(b:match("%d+")) or 0) end)
	end
	return groups, ranks
end

local function ScanItems()
	local equipped, bags, seen = {}, {}, {}
	for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
		local id = GetInventoryItemID("player", slot)
		local name = id and C_Item.GetItemNameByID(id)
		if name then equipped[#equipped + 1] = { name, GetInventoryItemTexture("player", slot) } end
	end
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemName and not seen[info.itemName] then
				seen[info.itemName] = true
				bags[#bags + 1] = { info.itemName, info.iconFileID }
			end
		end
	end
	table.sort(bags, function(a, b) return a[1] < b[1] end)
	return equipped, bags
end

local function Entry(name, icon) return icon and ("|T" .. icon .. ":16:16:0:0:64:64:5:59:5:59|t  " .. name) or name end

-- Dropdown option lists for the named conditionals, values already prefixed ("known:Charge").
local NAMED_SOURCES = {
	spell = function(prefix)
		local out = {}
		for _, g in ipairs((ScanSpells())) do
			local children = {}
			for _, s in ipairs(g.spells) do children[#children + 1] = { prefix .. s[1], Entry(s[1], s[2]) } end
			out[#out + 1] = { label = g.name, children = children }
		end
		return out
	end,
	itemtype = function(prefix)
		local out = {}
		for _, cls in ipairs({ 2, 4 }) do -- weapons, armor (incl. shields, librams, idols, totems)
			local children, seen = {}, {}
			for sub = 0, 20 do
				local name = C_Item.GetItemSubClassInfo(cls, sub)
				if name and name ~= "" and not seen[name] then
					seen[name] = true
					children[#children + 1] = { prefix .. name, name }
				end
			end
			out[#out + 1] = { label = C_Item.GetItemClassInfo(cls), children = children }
		end
		return out
	end,
	pet = function(prefix)
		local out = {}
		local current = UnitExists("pet") and UnitName("pet")
		if current then out[1] = { prefix .. current, current .. "  |cff8c96a8(current pet)|r" } end
		for _, fam in ipairs(ns.PetFamilies) do out[#out + 1] = { prefix .. fam, fam } end
		return out
	end,
}

-- Every emote command the client knows ("/spit"), grouped by first letter.
local emoteOptions
local function EmoteOptions()
	if emoteOptions then return emoteOptions end
	local seen, byLetter = {}, {}
	for i = 1, tonumber(MAXEMOTEINDEX) or 0 do
		local cmd = _G["EMOTE" .. i .. "_CMD1"]
		if type(cmd) == "string" and cmd:sub(1, 1) == "/" and not seen[cmd] then
			seen[cmd] = true
			local letter = cmd:sub(2, 2):upper()
			byLetter[letter] = byLetter[letter] or {}
			table.insert(byLetter[letter], { cmd, cmd })
		end
	end
	emoteOptions = {}
	for letter, list in pairs(byLetter) do
		table.sort(list, function(a, b) return a[1] < b[1] end)
		emoteOptions[#emoteOptions + 1] = { label = letter, children = list }
	end
	table.sort(emoteOptions, function(a, b) return a.label < b.label end)
	return emoteOptions
end

local function AddSpellMenu(root, onPick)
	for _, g in ipairs((ScanSpells())) do
		local sub = root:CreateButton(g.name)
		sub:SetScrollMode(420)
		for _, s in ipairs(g.spells) do sub:CreateButton(Entry(s[1], s[2]), function() onPick(s[1]) end) end
	end
end

local function AddItemMenu(root, onPick)
	local equipped, bags = ScanItems()
	for _, part in ipairs({ { "Equipped", equipped }, { "Bags", bags } }) do
		local sub = root:CreateButton(part[1])
		sub:SetScrollMode(420)
		for _, it in ipairs(part[2]) do sub:CreateButton(Entry(it[1], it[2]), function() onPick(it[1]) end) end
	end
end

------------------------------------------------------------------------------- macro data
local function TabMacros()
	local numAccount, numChar = GetNumMacros()
	local first, n = 1, numAccount
	if state.tab == "char" then first, n = MAX_ACCOUNT + 1, numChar end
	local out = {}
	for i = first, first + n - 1 do
		local name, icon = GetMacroInfo(i)
		if name then out[#out + 1] = { index = i, name = name, icon = icon } end
	end
	return out
end

local function UniqueName(base)
	local taken = {}
	for _, m in ipairs(TabMacros()) do taken[m.name] = true end
	if not taken[base] then return base end
	for i = 2, 99 do
		if not taken[base .. " " .. i] then return base .. " " .. i end
	end
	return base
end

local function CanEdit()
	if InCombatLockdown() then
		main.Notify("Macros can't be changed in combat.", C.danger)
		return false
	end
	return true
end

------------------------------------------------------------------------------- sidebar: folder tree
local function CreateTree(parent)
	local t = S.Frame(parent, C.surface)

	local seg = S.Segmented(t, 236, { { "account", "Account" }, { "char", "Character" } },
		function() return state.tab end,
		function(v) if v ~= state.tab then main.SwitchTab(v) end end)
	seg:SetPoint("TOPLEFT", 12, -12)
	t.seg = seg

	local newMacro = S.Button(t, "+  New macro", 140, 28, "primary", function() main.NewMacro() end)
	newMacro:SetPoint("TOPLEFT", seg, "BOTTOMLEFT", 0, -10)
	local newFolder = S.Button(t, "+  Folder", 90, 28, "default", function() main.NewFolder(nil) end)
	newFolder:SetPoint("LEFT", newMacro, "RIGHT", 6, 0)

	t.count = S.Text(t, 11, C.muted)
	t.count:SetPoint("TOPLEFT", newMacro, "BOTTOMLEFT", 2, -10)

	-- the list area doubles as the "move to top level" drop zone
	local area = CreateFrame("Frame", nil, t)
	area:SetPoint("TOPLEFT", t.count, "BOTTOMLEFT", -6, -6)
	area:SetPoint("BOTTOMRIGHT", -8, 44)
	area:EnableMouse(true)
	t.area = area

	local box = CreateFrame("Frame", nil, area, "WowScrollBoxList")
	box:SetPoint("TOPLEFT")
	box:SetPoint("BOTTOMRIGHT", -10, 0)
	t.box = box
	local bar = S.Scroll(box, area)

	t.hint = S.Text(t, 11, C.muted, "")
	t.hint:SetPoint("BOTTOMLEFT", 12, 12)
	t.hint:SetPoint("BOTTOMRIGHT", -12, 12)
	t.hint:SetWordWrap(true)
	t.defaultHint = "Drag macros onto folders or action bars.\nRight-click for more options."
	t.hint:SetText(t.defaultHint)

	local ghost = S.Frame(UIParent, C.raised, C.accent)
	ghost:SetFrameStrata("TOOLTIP")
	ghost:SetSize(160, 24)
	ghost.text = S.Text(ghost, 12)
	ghost.text:SetPoint("LEFT", 8, 0)
	ghost:Hide()
	ghost:SetScript("OnUpdate", function(self)
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		self:ClearAllPoints()
		self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale + 14, y / scale - 30)
	end)

	local function isDragging()
		return t.dragFolder ~= nil or GetCursorInfo() == "macro"
	end

	-- rowData: tree row, or nil for "top level"
	local function targetFolder(rowData)
		if not rowData then return nil end
		if rowData.kind == "folder" then return rowData.id end
		return rowData.folder
	end

	local function dropMacro(rowData)
		local kind, index = GetCursorInfo()
		if kind ~= "macro" then return end
		ClearCursor()
		if IsCharIndex(index) ~= (state.tab == "char") then
			main.Notify("That macro belongs to the other tab.", C.warn)
			return
		end
		local folder = targetFolder(rowData)
		F.SetMacroFolder(Store(), GetMacroInfo(index), folder)
		if folder then Store().folders[folder].open = true end
		main.RefreshList()
	end

	local function dropFolder(rowData)
		local id = t.dragFolder
		t.dragFolder = nil
		ghost:Hide()
		local folder = targetFolder(rowData)
		if folder == id or folder == Store().folders[id].parent then return main.RefreshList() end
		if F.MoveFolder(Store(), id, folder) then
			if folder then Store().folders[folder].open = true end
		else
			main.Notify(("Folders can be nested at most %d levels deep."):format(F.MAX_DEPTH), C.warn)
		end
		main.RefreshList()
	end

	for _, zone in ipairs({ area, box }) do
		zone:SetScript("OnReceiveDrag", function() dropMacro(nil) end)
		zone:SetScript("OnMouseUp", function() if GetCursorInfo() == "macro" then dropMacro(nil) end end)
	end

	local function rowUnderMouse()
		local found
		box:ForEachFrame(function(f) if f:IsMouseOver() then found = f end end)
		return found
	end

	local function contextMenu(row)
		local d = row.data
		MenuUtil.CreateContextMenu(row, function(_, root)
			if d.kind == "folder" then
				root:CreateTitle(d.name)
				local sub = root:CreateButton("New subfolder", function() main.NewFolder(d.id) end)
				sub:SetEnabled(F.CanCreate(Store(), d.id))
				root:CreateButton("Rename", function()
					S.Prompt(main, "Rename folder", "Folder name", d.name, function(name)
						Store().folders[d.id].name = name
						main.RefreshList()
					end)
				end)
				root:CreateButton("|cffee5c5cDelete folder|r", function()
					S.Confirm(main, "Delete folder?", ("\"%s\" will be removed. Its macros and subfolders move up one level; no macro is deleted."):format(d.name), "Delete folder", function()
						F.Delete(Store(), d.id)
						main.RefreshList()
					end)
				end)
			else
				root:CreateTitle(d.name)
				local move = root:CreateButton("Move to")
				local top = move:CreateButton("Top level (no folder)", function() F.SetMacroFolder(Store(), d.name, nil) main.RefreshList() end)
				top:SetEnabled(d.folder ~= nil)
				for _, f in ipairs(F.List(Store())) do
					local b = move:CreateButton(string.rep("    ", f[3] - 1) .. f[2], function()
						F.SetMacroFolder(Store(), d.name, f[1])
						main.RefreshList()
					end)
					b:SetEnabled(f[1] ~= d.folder)
				end
				root:CreateButton("|cffee5c5cDelete macro|r", function() main.DeleteMacro(d.index, d.name) end)
			end
		end)
	end

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(ROW_HEIGHT)
	view:SetElementInitializer("Button", function(row, data)
		if not row.label then
			row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			row:RegisterForDrag("LeftButton")
			row.bg = S.Fill(row, C.hover)
			row.bg:SetAllPoints()
			row.accentBar = S.Fill(row, C.accent, "ARTWORK")
			row.accentBar:SetPoint("TOPLEFT")
			row.accentBar:SetPoint("BOTTOMLEFT")
			row.accentBar:SetWidth(2)
			row.chevron = row:CreateTexture(nil, "ARTWORK")
			row.chevron:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
			row.chevron:SetSize(12, 12)
			row.chevron:SetVertexColor(unpack(C.muted))
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(20, 20)
			row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			row.label = S.Text(row, 12)
			row.label:SetWordWrap(false)
			row.badge = S.Text(row, 11, C.muted)
			row.badge:SetPoint("RIGHT", -8, 0)
			row.label:SetPoint("RIGHT", row.badge, "LEFT", -6, 0)

			row:SetScript("OnClick", function(self, button)
				local d = self.data
				if GetCursorInfo() == "macro" then return dropMacro(d) end
				if button == "RightButton" then return contextMenu(self) end
				if d.kind == "folder" then
					Store().folders[d.id].open = not d.open
					state.folder = d.id
					main.RefreshList()
				else
					main.Select(d.index)
				end
			end)
			row:SetScript("OnDragStart", function(self)
				local d = self.data
				if d.kind == "macro" then
					PickupMacro(d.index)
				else
					t.dragFolder = d.id
					ghost.text:SetText(d.name)
					ghost:Show()
				end
			end)
			row:SetScript("OnDragStop", function()
				if not t.dragFolder then return end
				local target = rowUnderMouse()
				if target then dropFolder(target.data)
				elseif area:IsMouseOver() then dropFolder(nil)
				else t.dragFolder = nil ghost:Hide() end
			end)
			row:SetScript("OnReceiveDrag", function(self) dropMacro(self.data) end)
			row:SetScript("OnEnter", function(self)
				self.bg:Show()
				if isDragging() then
					self.bg:SetColorTexture(unpack(C.accentSoft))
					return
				end
				if self.data.kind == "macro" then
					local name, _, body = GetMacroInfo(self.data.index)
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText(name or "")
					if body and body ~= "" then GameTooltip:AddLine(body, 0.8, 0.84, 0.9, false) end
					GameTooltip:Show()
				end
			end)
			row:SetScript("OnLeave", function(self)
				self.bg:SetColorTexture(unpack(C.hover))
				self.bg:SetShown(self.selected)
				GameTooltip_Hide()
			end)
		end

		row.data = data
		local x = 6 + data.depth * INDENT
		row.chevron:ClearAllPoints()
		row.icon:ClearAllPoints()
		row.label:ClearAllPoints()
		row.label:SetPoint("RIGHT", row.badge, "LEFT", -6, 0)
		if data.kind == "folder" then
			row.chevron:Show()
			row.chevron:SetPoint("LEFT", x, 0)
			row.chevron:SetRotation(data.open and -math.pi / 2 or 0)
			row.icon:Hide()
			row.label:SetPoint("LEFT", row.chevron, "RIGHT", 6, 0)
			row.label:SetText(data.name)
			row.label:SetTextColor(unpack(C.text))
			row.badge:SetText(data.count)
			row.selected = false
		else
			row.chevron:Hide()
			row.icon:Show()
			row.icon:SetPoint("LEFT", x, 0)
			row.icon:SetTexture(data.icon)
			row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
			row.label:SetText(data.name)
			row.badge:SetText("")
			row.selected = data.index == state.index
			row.label:SetTextColor(unpack(row.selected and C.text or { 0.8, 0.83, 0.88, 1 }))
		end
		row.bg:SetColorTexture(unpack(row.selected and C.accentSoft or C.hover))
		row.bg:SetShown(row.selected)
		row.accentBar:SetShown(row.selected)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
	return t
end

------------------------------------------------------------------------------- editor
local function CreateEditor(parent)
	local e = CreateFrame("Frame", nil, parent)

	local iconFrame = S.Frame(e, C.raised, C.border, "Button")
	iconFrame:SetSize(56, 56)
	iconFrame:SetPoint("TOPLEFT", 0, 0)
	e.icon = iconFrame:CreateTexture(nil, "ARTWORK")
	e.icon:SetPoint("TOPLEFT", 3, -3)
	e.icon:SetPoint("BOTTOMRIGHT", -3, 3)
	e.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	iconFrame:RegisterForDrag("LeftButton")
	iconFrame:SetScript("OnDragStart", function() if state.index then PickupMacro(state.index) end end)
	iconFrame:SetScript("OnEnter", function(self)
		self:SetBackdropBorderColor(unpack(C.accent))
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Drag me to an action bar")
		GameTooltip:AddLine("Choose the icon in the panel on the right.", 0.8, 0.84, 0.9)
		GameTooltip:Show()
	end)
	iconFrame:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(C.border)) GameTooltip_Hide() end)

	local nameLabel = S.Text(e, 11, C.muted, "NAME")
	nameLabel:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 14, 0)
	e.name = S.Input(e, 340, 30, "Macro name", function() main.MarkDirty() end)
	e.name:SetMaxLetters(16)
	e.name:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMRIGHT", 14, 0)
	e.name:SetScript("OnEnterPressed", function(self) self:ClearFocus() main.Save() end)

	local textLabel = S.Text(e, 11, C.muted, "MACRO")
	textLabel:SetPoint("TOPLEFT", iconFrame, "BOTTOMLEFT", 0, -18)
	e.status = S.Text(e, 11, C.muted)
	e.status:SetPoint("LEFT", textLabel, "RIGHT", 10, 0)
	e.counter = S.Text(e, 11, C.muted)

	local box = S.Frame(e, C.raised)
	box:SetPoint("TOPLEFT", textLabel, "BOTTOMLEFT", 0, -6)
	box:SetPoint("RIGHT")
	box:SetHeight(200)
	e.box = box
	e.counter:SetPoint("BOTTOMRIGHT", box, "TOPRIGHT", 0, 6)
	local scroll = CreateFrame("ScrollFrame", nil, box)
	scroll:SetPoint("TOPLEFT", 10, -8)
	scroll:SetPoint("BOTTOMRIGHT", -18, 8)
	local bar = CreateFrame("EventFrame", nil, box, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, 0)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 0)
	ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
	local body = CreateFrame("EditBox", nil, scroll)
	body:SetMultiLine(true)
	body:SetAutoFocus(false)
	body:SetFontObject(S.Font(13))
	body:SetWidth(380)
	body:SetMaxLetters(B.MAX_CHARS)
	body:SetCountInvisibleLetters(true)
	body:SetScript("OnEscapePressed", body.ClearFocus)
	body:SetScript("OnEditFocusGained", function() box:SetBackdropBorderColor(unpack(C.accent)) end)
	body:SetScript("OnEditFocusLost", function() box:SetBackdropBorderColor(unpack(C.border)) end)
	body:SetScript("OnTextChanged", function(self, user)
		ScrollingEdit_OnTextChanged(self, scroll)
		if user then main.MarkDirty() else e:UpdateCounter() end
	end)
	body:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
	body:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, scroll) end)
	scroll:SetScrollChild(body)
	scroll:SetScript("OnSizeChanged", function(_, w) body:SetWidth(w) end)
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", function() body:SetFocus() end)
	e.body = body

	e.empty = S.Text(box, 13, C.muted, "Select a macro on the left, or create a new one.")
	e.empty:SetPoint("CENTER")

	-- thin character meter under the text box
	local meterBg = S.Fill(e, C.raised, "ARTWORK")
	meterBg:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -4)
	meterBg:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -4)
	meterBg:SetHeight(3)
	e.meter = S.Fill(e, C.accent, "OVERLAY")
	e.meter:SetPoint("TOPLEFT", meterBg)
	e.meter:SetHeight(3)
	e.meterBg = meterBg

	e.save = S.Button(e, SAVE or "Save", 100, 30, "primary", function() main.Save() body:ClearFocus() end)
	e.save:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -14)
	e.revert = S.Button(e, "Revert", 80, 30, "ghost", function() main.LoadMacro(state.index) end)
	e.revert:SetPoint("RIGHT", e.save, "LEFT", -6, 0)
	e.delete = S.Button(e, DELETE or "Delete", 80, 30, "danger", function()
		if state.index then main.DeleteMacro(state.index, state.loadedName) end
	end)
	e.delete:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -14)

	local addLabel = S.Text(e, 11, C.muted, "ADD A LINE")
	addLabel:SetPoint("TOPLEFT", e.delete, "BOTTOMLEFT", 0, -22)
	local addHint = S.Text(e, 11, C.muted, "— pick what the line should do; you get a form, no typing commands")
	addHint:SetPoint("LEFT", addLabel, "RIGHT", 8, 0)
	e.tiles = {}
	for i, action in ipairs(B.ACTIONS) do
		local tile = S.Button(e, action.label, 105, 32, "default", function()
			if not state.index then main.Notify("Create or select a macro first.", C.warn) return end
			dialog:Open(action)
		end, "Interface\\Icons\\" .. ACTION_ICONS[action.key])
		tile:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", ((i - 1) % 4) * 109, -8 - math.floor((i - 1) / 4) * 36)
		e.tiles[i] = tile
	end

	function e:UpdateCounter()
		local n = #self.body:GetText()
		local ratio = n / B.MAX_CHARS
		local color = ratio > 1 and C.danger or ratio > 0.9 and C.warn or C.accent
		self.counter:SetText(("%d / %d"):format(n, B.MAX_CHARS))
		self.counter:SetTextColor(unpack(ratio > 0.9 and color or C.muted))
		self.meter:SetColorTexture(unpack(color))
		self.meter:SetWidth(math.max(1, math.min(1, ratio) * self.meterBg:GetWidth()))
	end

	function e:SetStatus()
		if not state.index then
			self.status:SetText("")
		elseif state.dirty then
			self.status:SetText("●  Unsaved changes")
			self.status:SetTextColor(unpack(C.warn))
		else
			self.status:SetText("All changes saved")
			self.status:SetTextColor(unpack(C.muted))
		end
		self.save:SetEnabled(state.dirty)
		self.revert:SetEnabled(state.dirty)
	end

	function e:SetHasMacro(has)
		self.empty:SetShown(not has)
		self.body:SetShown(has)
		self.name:SetEnabled(has)
		self.delete:SetEnabled(has)
		for _, tile in ipairs(self.tiles) do tile:SetEnabled(has) end
	end
	return e
end

------------------------------------------------------------------------------- icon picker
local function BuildIconList()
	local raw, out, seen = {}, { QUESTION_MARK }, { [QUESTION_MARK] = true }
	GetLooseMacroIcons(raw)
	GetLooseMacroItemIcons(raw)
	GetMacroIcons(raw)
	GetMacroItemIcons(raw)
	for _, t in ipairs(raw) do
		local icon = tonumber(t) or t
		if not seen[icon] then seen[icon] = true out[#out + 1] = icon end
	end
	-- The client list can miss icons that exist in Interface\Icons; add the rest from our data.
	local extra = {}
	for id in pairs(ns.IconNames) do
		if not seen[id] then extra[#extra + 1] = id end
	end
	table.sort(extra)
	for _, id in ipairs(extra) do out[#out + 1] = id end
	return out
end

local function IconName(icon)
	if icon == QUESTION_MARK then return "Automatic (uses the spell's icon)" end
	return ns.IconNames[icon] or tostring(icon)
end

local function CreateIconPanel(parent)
	local p = S.Frame(parent, C.surface)
	p.classMask, p.itemMask = 0, 0

	local title = S.Text(p, 11, C.muted, "ICON")
	title:SetPoint("TOPLEFT", 14, -14)
	p.current = S.Text(p, 11, C.text)
	p.current:SetPoint("LEFT", title, "RIGHT", 8, 0)
	p.current:SetPoint("RIGHT", -14, 0)
	p.current:SetWordWrap(false)

	local search = S.Input(p, 292, 30, "Search icons… e.g. frost bolt", function() p:Refresh() end)
	search:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	search:SetScript("OnEnterPressed", search.ClearFocus)

	local classes, classNames = {}, {}
	for _, id in ipairs({ 1, 2, 3, 4, 5, 7, 8, 9, 11 }) do
		local info = C_CreatureInfo.GetClassInfo(id)
		if info then
			local color = RAID_CLASS_COLORS[info.classFile]
			local bitv = bit.lshift(1, id - 1)
			classes[#classes + 1] = { bitv, color and color:WrapTextInColorCode(info.className) or info.className }
			classNames[bitv] = info.className
		end
	end
	local items, itemNames = {}, {}
	for _, c in ipairs(ns.ItemClasses) do
		local bitv = bit.lshift(1, c[1])
		local name = C_Item.GetItemClassInfo(c[1]) or c[2]
		items[#items + 1] = { bitv, name }
		itemNames[bitv] = name
	end

	local function summary(field, names, all)
		return function()
			local picked = {}
			for bitv, name in pairs(names) do
				if bit.band(p[field], bitv) ~= 0 then picked[#picked + 1] = name end
			end
			if #picked == 0 then return all, false end
			if #picked == 1 then return picked[1], true end
			return ("%s +%d"):format(picked[1], #picked - 1), true
		end
	end
	local function multi(field, options, names, all)
		return S.MultiDropdown(p, 143, options,
			function(v) return bit.band(p[field], v) ~= 0 end,
			function(v) p[field] = bit.bxor(p[field], v) p:Refresh() end,
			function() p[field] = 0 p:Refresh() end,
			summary(field, names, all))
	end
	p.classDD = multi("classMask", classes, classNames, "All classes")
	p.classDD:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
	p.itemDD = multi("itemMask", items, itemNames, "All item types")
	p.itemDD:SetPoint("LEFT", p.classDD, "RIGHT", 6, 0)

	p.count = S.Text(p, 11, C.muted)
	p.count:SetPoint("TOPLEFT", p.classDD, "BOTTOMLEFT", 0, -10)
	p.clear = S.Button(p, "Clear filters", 84, 20, "ghost", function()
		search:SetText("")
		p.classMask, p.itemMask = 0, 0
		p.classDD:Refresh()
		p.itemDD:Refresh()
		p:Refresh()
	end)
	p.clear:SetPoint("RIGHT", p.itemDD, "RIGHT", 0, 0)
	p.clear:SetPoint("TOP", p.count, "TOP", 0, 4)

	local box = CreateFrame("Frame", nil, p, "WowScrollBoxList")
	box:SetPoint("TOPLEFT", p.count, "BOTTOMLEFT", 0, -8)
	box:SetPoint("BOTTOMRIGHT", -24, 12)
	local bar = S.Scroll(box, p)
	p.box = box

	local view = CreateScrollBoxListGridView(ICON_STRIDE, 0, 0, 0, 0, 3, 3)
	view:SetElementSize(ICON_SIZE, ICON_SIZE)
	view:SetElementInitializer("Button", function(btn, i)
		if not btn.tex then
			btn.ring = S.Fill(btn, C.accent)
			btn.ring:SetAllPoints()
			btn.tex = btn:CreateTexture(nil, "ARTWORK")
			btn.tex:SetPoint("TOPLEFT", 2, -2)
			btn.tex:SetPoint("BOTTOMRIGHT", -2, 2)
			btn.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
			btn.hl:SetAllPoints(btn.tex)
			btn.hl:SetColorTexture(1, 1, 1, 0.18)
			btn:SetScript("OnClick", function(self) main.SetIcon(self.iconID, true) end)
			btn:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(IconName(self.iconID))
				GameTooltip:Show()
			end)
			btn:SetScript("OnLeave", GameTooltip_Hide)
		end
		btn.iconID = p.filtered[i]
		btn.tex:SetTexture(IconTexture(btn.iconID))
		btn.ring:SetShown(btn.iconID == state.icon)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)

	function p:Refresh()
		if not self.all then self.all = BuildIconList() end
		self.filtered = ns.FilterIcons(self.all, search:GetText(), self.classMask, self.itemMask)
		self.count:SetText(("%s icons"):format(BreakUpLargeNumbers(#self.filtered)))
		self.clear:SetShown(search:GetText() ~= "" or self.classMask ~= 0 or self.itemMask ~= 0)
		box:SetDataProvider(CreateIndexRangeDataProvider(#self.filtered))
	end

	function p:UpdateSelection()
		self.current:SetText(IconName(state.icon))
		box:ForEachFrame(function(f) f.ring:SetShown(f.iconID == state.icon) end)
	end

	p:SetScript("OnShow", p.Refresh)
	return p
end

------------------------------------------------------------------------------- line builder dialog
local LABEL_W = 130

local function CreateDialog(parent)
	local d = S.Modal(parent, 700, 600, "")
	local openModal = d.Open
	local vals = { condRow = {}, named = {} }
	d.vals = vals
	local function onChange() d:UpdatePreview() end
	local function set(k) return function(v) vals[k] = v onChange() end end
	local function get(k) return function() return vals[k] end end

	d.subtitle = S.Text(d, 12, C.muted)
	d.subtitle:SetPoint("LEFT", d.title, "RIGHT", 10, 0)

	local function rowLabel(parent, text)
		local l = S.Text(parent, 12, C.muted, text)
		l:SetWidth(LABEL_W - 10)
		l:SetWordWrap(true)
		return l
	end

	-- command row
	d.cmdRow = CreateFrame("Frame", nil, d)
	d.cmdRow:SetSize(660, 28)
	rowLabel(d.cmdRow, "Command"):SetPoint("LEFT")
	d.cmdDD = S.Dropdown(d.cmdRow, 300, function()
		local o = {}
		if not d.action then return o end -- dropdowns resolve options at creation, before any action is opened
		for _, s in ipairs(d.action.subs) do o[#o + 1] = { s[1], s[2] .. "   |cff8c96a8" .. s[1] .. "|r" } end
		return o
	end, get("sub"), function(v) vals.sub = v d:Layout() onChange() end)
	d.cmdDD:SetPoint("LEFT", LABEL_W, 0)

	-- per-action field blocks, built lazily
	d.fieldFrames = {}
	local function BuildFields(action)
		local f = CreateFrame("Frame", nil, d)
		f:SetWidth(660)
		f.refreshers = {}
		local y, checkRow, checkX = 0, nil, 0
		local function newRow(h)
			local row = CreateFrame("Frame", nil, f)
			row:SetSize(660, h)
			row:SetPoint("TOPLEFT", 0, y)
			y = y - h - 8
			return row
		end
		for _, field in ipairs(action.fields) do
			local key, kind, text, extra = field[1], field[2], field[3], field[4]
			if kind == "check" then
				if not checkRow then
					checkRow = newRow(22)
					rowLabel(checkRow, extra or ""):SetPoint("LEFT")
					checkX = LABEL_W
				end
				local c = S.Check(checkRow, text, get(key), set(key))
				c:SetPoint("LEFT", checkX, 0)
				checkX = checkX + c:GetWidth() + 16
				f.refreshers[#f.refreshers + 1] = function() c:Refresh() end
			else
				checkRow = nil
				local row = newRow(28)
				rowLabel(row, text):SetPoint("LEFT")
				if kind == "choice" or kind == "emote" then
					local dd = S.Dropdown(row, 240, kind == "emote" and EmoteOptions or extra, get(key), set(key), kind == "emote" and "Choose an emote" or nil)
					dd:SetPoint("LEFT", LABEL_W, 0)
					f.refreshers[#f.refreshers + 1] = function() dd:Refresh() end
				else
					local placeholder = (kind == "spell" and "Type a spell, or browse your spellbook")
						or (kind == "item" and "Type an item, or browse your bags")
						or (kind == "list" and "Browse to add, or type: A, B, C") or ""
					local box = S.Input(row, kind == "number" and 70 or 300, 28, placeholder, set(key))
					box:SetPoint("LEFT", LABEL_W, 0)
					if kind == "number" then box:SetNumeric(true) box.placeholder:SetText("0") end
					f.refreshers[#f.refreshers + 1] = function() box:SetValue(vals[key]) end
					local function put(name)
						if kind == "list" then
							local cur = box:GetText():gsub("[%s,]+$", "")
							name = cur == "" and name or (cur .. ", " .. name)
						end
						box:SetValue(name)
						vals[key] = name
						if kind == "spell" then vals.rank = nil end
						d:Layout()
						onChange()
					end
					if kind == "spell" or kind == "item" or kind == "list" then
						local browse = S.Button(row, "Browse", 76, 28, "default", function(self)
							MenuUtil.CreateContextMenu(self, function(_, root)
								if kind == "list" then
									AddSpellMenu(root:CreateButton("Spells"), put)
									AddItemMenu(root:CreateButton("Items"), put)
								elseif kind == "spell" then
									AddSpellMenu(root, put)
								else
									AddItemMenu(root, put)
								end
							end)
						end)
						browse:SetPoint("LEFT", box, "RIGHT", 6, 0)
						if kind == "spell" then
							box:HookScript("OnEditFocusLost", function() d:Layout() end)
							local rank = S.Dropdown(row, 140, function()
								local o = { { "", "Highest rank" } }
								for _, r in ipairs(d.ranks[vals[key] or ""] or {}) do o[#o + 1] = { r, r } end
								return o
							end, get("rank"), set("rank"))
							rank:SetPoint("LEFT", browse, "RIGHT", 6, 0)
							f.rankDD = rank
							f.refreshers[#f.refreshers + 1] = function() rank:Refresh() end
						end
					end
				end
			end
		end
		f:SetHeight(math.max(1, -y - 8))
		return f
	end

	-- target row
	d.targetRow = CreateFrame("Frame", nil, d)
	d.targetRow:SetSize(660, 28)
	rowLabel(d.targetRow, "Cast on"):SetPoint("LEFT")
	d.targetDD = S.Dropdown(d.targetRow, 240, B.TARGETS, get("target"), set("target"))
	d.targetDD:SetPoint("LEFT", LABEL_W, 0)
	d.fallbackDD = S.Dropdown(d.targetRow, 270, B.FALLBACKS, get("fallback"), set("fallback"))
	d.fallbackDD:SetPoint("LEFT", d.targetDD, "RIGHT", 6, 0)

	-- conditions: common ones always, the rest behind "More conditions"
	d.condHeader = CreateFrame("Frame", nil, d)
	d.condHeader:SetSize(660, 24)
	local ch = S.Text(d.condHeader, 12, C.muted, "Only when")
	ch:SetPoint("LEFT")
	d.condCount = S.Text(d.condHeader, 11, C.accent)
	d.condCount:SetPoint("LEFT", ch, "RIGHT", 8, 0)
	d.moreBtn = S.Button(d.condHeader, "", 150, 22, "ghost", function() d.showAll = not d.showAll d:Layout() end)
	d.moreBtn:SetPoint("RIGHT")

	d.condCells = {}
	local function cell(label, options, getter, setter, common)
		local c = CreateFrame("Frame", nil, d)
		c:SetSize(158, 46)
		local l = S.Text(c, 11, C.muted, label)
		l:SetPoint("TOPLEFT")
		c.dd = S.Dropdown(c, 154, options, getter, setter, "Any")
		c.dd:SetPoint("TOPLEFT", 0, -16)
		c.common = common
		d.condCells[#d.condCells + 1] = c
	end
	for i, row in ipairs(B.CONDITIONS) do
		local opts = { { "", "Any" } }
		for _, o in ipairs(row[2]) do opts[#opts + 1] = o end
		cell(row[1], opts, function() return vals.condRow[i] end, function(v) vals.condRow[i] = v onChange() end, row[3] == "common")
	end
	for _, nc in ipairs(B.NAMED_CONDITIONS) do
		local key, label, source = nc[1], nc[2], nc[3]
		local function opts()
			local o = { { "", "Any" } }
			for _, x in ipairs(NAMED_SOURCES[source](key .. ":")) do o[#o + 1] = x end
			return o
		end
		cell(label, opts, function() return vals.named[key] end, function(v) vals.named[key] = v onChange() end, false)
	end

	-- preview
	d.previewBox = S.Frame(d, C.surface)
	d.previewBox:SetSize(664, 64)
	local pl = S.Text(d.previewBox, 11, C.muted, "PREVIEW")
	pl:SetPoint("TOPLEFT", 10, -8)
	d.length = S.Text(d.previewBox, 11, C.muted)
	d.length:SetPoint("TOPRIGHT", -10, -8)
	d.preview = S.Text(d.previewBox, 13, { 0.62, 0.84, 1, 1 })
	d.preview:SetPoint("TOPLEFT", 10, -26)
	d.preview:SetPoint("RIGHT", -10, 0)
	d.preview:SetWordWrap(true)
	d.err = S.Text(d, 11, C.danger)
	d.err:SetPoint("TOPLEFT", d.previewBox, "BOTTOMLEFT", 2, -6)
	d.err:SetWidth(660)

	d.alt = S.Check(d, "Add as an alternative ( ; ) to my last line with this command",
		function() return d.altChecked end, function(v) d.altChecked = v onChange() end)
	d.alt:SetPoint("BOTTOMLEFT", 18, 20)
	d.insert = S.Button(d, "Insert line", 120, 30, "primary", function() d:Insert() end)
	d.insert:SetPoint("BOTTOMRIGHT", -18, 14)
	S.Button(d, CANCEL, 90, 30, "ghost", function() d:Close() end):SetPoint("RIGHT", d.insert, "LEFT", -6, 0)

	function d:Conds()
		local out = {}
		for i in ipairs(B.CONDITIONS) do
			local v = vals.condRow[i]
			if v and v ~= "" then out[#out + 1] = v end
		end
		for _, nc in ipairs(B.NAMED_CONDITIONS) do
			local v = vals.named[nc[1]]
			if v and v ~= "" then out[#out + 1] = v end
		end
		return out
	end

	function d:Result()
		vals.conds = self:Conds()
		local line, clause = B.BuildLine(self.action, vals)
		if not line then return nil, clause, "" end
		local body = editor.body:GetText()
		if self.altChecked and line:sub(1, 1) == "/" then
			local newBody = B.AppendToLast(body, B.CommandOf(line), clause)
			if not newBody then return nil, "There's no " .. B.CommandOf(line) .. " line yet to add an alternative to.", line end
			return newBody, nil, line
		end
		return B.InsertLine(body, line), nil, line
	end

	function d:UpdatePreview()
		local newBody, err, line = self:Result()
		self.preview:SetText(line or "")
		self.length:SetText("")
		if newBody then
			local n = #newBody
			self.length:SetText(("macro after insert: %d / %d"):format(n, B.MAX_CHARS))
			self.length:SetTextColor(unpack(n > B.MAX_CHARS and C.danger or C.muted))
			if n > B.MAX_CHARS then err = ("That's %d characters over the %d limit."):format(n - B.MAX_CHARS, B.MAX_CHARS) end
		end
		self.err:SetText(err or "")
		self.insert:SetEnabled(err == nil)
		local n = #vals.conds
		self.condCount:SetText(n > 0 and ("%d active"):format(n) or "")
	end

	function d:Insert()
		local newBody, err = self:Result()
		if err or #newBody > B.MAX_CHARS then return end
		editor.body:SetText(newBody)
		main.MarkDirty()
		self:Close()
	end

	-- Stack the visible sections top to bottom and size the card to fit.
	function d:Layout()
		local sub = B.FindSub(self.action, vals.sub)
		local noCond, noTarget = B.HasFlag(sub, "nocond"), B.HasFlag(sub, "notarget")
		local y = -52
		local function place(frame, h)
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", 20, y)
			frame:Show()
			y = y - h - 12
		end
		if #self.action.subs > 1 then place(self.cmdRow, 28) else self.cmdRow:Hide() end
		local fields = self.fieldFrames[self.action.key]
		if #self.action.fields > 0 then place(fields, fields:GetHeight()) else fields:Hide() end
		if fields.rankDD then fields.rankDD:SetShown(self.ranks[vals.spell or ""] ~= nil) end
		if noCond or noTarget then self.targetRow:Hide() else place(self.targetRow, 28) end

		for _, c in ipairs(self.condCells) do c:Hide() end
		if noCond then
			self.condHeader:Hide()
		else
			y = y - 4
			place(self.condHeader, 24)
			local shown = 0
			for _, c in ipairs(self.condCells) do
				if self.showAll or c.common then
					c:ClearAllPoints()
					c:SetPoint("TOPLEFT", 20 + (shown % 4) * 166, y - math.floor(shown / 4) * 50)
					c:Show()
					shown = shown + 1
				end
			end
			y = y - math.ceil(shown / 4) * 50 - 4
			local hidden = #self.condCells - shown
			self.moreBtn:SetText(self.showAll and "Fewer conditions" or ("More conditions (%d)"):format(hidden))
		end
		place(self.previewBox, 64)
		self:SetHeight(-y + 70)
	end

	function d:Open(action)
		self.action = action
		for k in pairs(vals) do vals[k] = nil end
		vals.condRow, vals.named, vals.conds = {}, {}, {}
		vals.sub = action.subs[1][1]
		self.altChecked = false
		self.showAll = false
		local _, ranks = ScanSpells()
		self.ranks = ranks
		for _, f in pairs(self.fieldFrames) do f:Hide() end
		if not self.fieldFrames[action.key] then self.fieldFrames[action.key] = BuildFields(action) end
		for _, r in ipairs(self.fieldFrames[action.key].refreshers) do r() end
		for _, c in ipairs(self.condCells) do c.dd:Refresh() end
		self.cmdDD:Refresh()
		self.targetDD:Refresh()
		self.fallbackDD:Refresh()
		self.alt:Refresh()
		self.title:SetText(action.label)
		self.subtitle:SetText(#action.subs == 1 and action.subs[1][1] or "")
		self:Layout()
		self:UpdatePreview()
		openModal(self)
	end
	return d
end

------------------------------------------------------------------------------- main window
local function CreateMain()
	local f = S.Window("MacroBuilderEnhancedFrame", 1060, 680, "Macro Builder")
	f.subtitle:SetText("Enhanced")

	tree = CreateTree(f)
	tree:SetPoint("TOPLEFT", 1, -43)
	tree:SetPoint("BOTTOMLEFT", 1, 1)
	tree:SetWidth(262)

	editor = CreateEditor(f)
	editor:SetPoint("TOPLEFT", tree, "TOPRIGHT", 22, -20)
	editor:SetPoint("BOTTOMLEFT", tree, "BOTTOMRIGHT", 22, 20)
	editor:SetWidth(432)

	iconPanel = CreateIconPanel(f)
	iconPanel:SetPoint("TOPLEFT", editor, "TOPRIGHT", 22, 20)
	iconPanel:SetPoint("BOTTOMRIGHT", -1, 1)

	dialog = CreateDialog(f)

	local notifyToken = 0
	function f.Notify(msg, color)
		notifyToken = notifyToken + 1
		local token = notifyToken
		tree.hint:SetText(msg)
		tree.hint:SetTextColor(unpack(color or C.text))
		C_Timer.After(4, function()
			if token == notifyToken then
				tree.hint:SetText(tree.defaultHint)
				tree.hint:SetTextColor(unpack(C.muted))
			end
		end)
	end

	function f.RefreshList()
		local macros = TabMacros()
		local names = {}
		for _, m in ipairs(macros) do names[m.name] = true end
		F.Prune(Store(), names)
		tree.box:SetDataProvider(CreateDataProvider(F.Rows(Store(), macros)), ScrollBoxConstants.RetainScrollPosition)
		local max = state.tab == "account" and MAX_ACCOUNT or MAX_CHAR
		tree.count:SetText(("%d of %d macros"):format(#macros, max))
		tree.seg:Refresh()
	end

	function f.MarkDirty()
		state.dirty = state.index ~= nil
		editor:UpdateCounter()
		editor:SetStatus()
	end

	function f.SetIcon(icon, user)
		state.icon = icon
		editor.icon:SetTexture(IconTexture(icon))
		iconPanel:UpdateSelection()
		if user then f.MarkDirty() end
	end

	function f.LoadMacro(index)
		local name, _, body
		if index then name, _, body = GetMacroInfo(index) end
		state.index = name and index or nil
		state.loadedName = name
		state.dirty = false
		if name then state.folder = Store().macros[name] end
		editor.name:SetValue(name)
		editor.body:SetText(body or "")
		f.SetIcon(state.index and (C_Macro.GetSelectedMacroIcon(index) or QUESTION_MARK) or QUESTION_MARK)
		editor:SetHasMacro(state.index ~= nil)
		editor:UpdateCounter()
		editor:SetStatus()
		tree.box:ForEachFrame(function(row)
			if row.data and row.data.kind == "macro" then
				row.selected = row.data.index == state.index
				row.bg:SetColorTexture(unpack(row.selected and C.accentSoft or C.hover))
				row.bg:SetShown(row.selected)
				row.accentBar:SetShown(row.selected)
				row.label:SetTextColor(unpack(row.selected and C.text or { 0.8, 0.83, 0.88, 1 }))
			end
		end)
	end

	function f.Save()
		if not state.index or not state.dirty or not CanEdit() then return end
		local name = editor.name:GetText():gsub('"', "")
		if name == "" then name = "Macro" end
		for _, m in ipairs(TabMacros()) do
			if m.name == name and m.index ~= state.index then
				f.Notify("Another macro has this name; they will share a folder.", C.warn)
			end
		end
		F.RenameMacro(Store(), state.loadedName, name)
		state.index = EditMacro(state.index, name, IconTexture(state.icon), editor.body:GetText())
		state.loadedName = name
		state.dirty = false
		editor:SetStatus()
		f.RefreshList()
	end

	function f.Select(index)
		f.Save()
		f.LoadMacro(index)
	end

	function f.SwitchTab(tab)
		f.Save()
		state.tab = tab
		state.folder = nil
		f.RefreshList()
		f.LoadMacro(TabMacros()[1] and TabMacros()[1].index)
	end

	function f.NewMacro()
		if not CanEdit() then return end
		f.Save()
		local numAccount, numChar = GetNumMacros()
		local isChar = state.tab == "char"
		if (isChar and numChar >= MAX_CHAR) or (not isChar and numAccount >= MAX_ACCOUNT) then
			f.Notify("This tab is full. Delete a macro or use the other tab.", C.warn)
			return
		end
		local name = UniqueName("New Macro")
		local index = CreateMacro(name, QUESTION_MARK, "", isChar)
		-- new macros land in the folder you're working in
		if state.folder and Store().folders[state.folder] then F.SetMacroFolder(Store(), name, state.folder) end
		f.RefreshList()
		f.LoadMacro(index)
		editor.name:SetFocus()
		editor.name:HighlightText()
	end

	function f.NewFolder(parent)
		S.Prompt(f, parent and "New subfolder" or "New folder", "Folder name", "", function(name)
			local id = F.Create(Store(), name, parent)
			if not id then return ("Folders can be nested at most %d levels deep."):format(F.MAX_DEPTH) end
			state.folder = id
			f.RefreshList()
		end)
	end

	function f.DeleteMacro(index, name)
		S.Confirm(f, "Delete macro?", ("\"%s\" will be deleted permanently and removed from your action bars."):format(name), "Delete macro", function()
			if not CanEdit() then return end
			if index == state.index then
				state.dirty = false
			else
				f.Save() -- may rename and re-sort, so look the target up again by name
				if GetMacroInfo(index) ~= name then index = GetMacroIndexByName(name) end
			end
			if not index or index == 0 then return end
			local keep = state.index ~= index and state.index
			DeleteMacro(index)
			f.RefreshList()
			if keep then
				f.LoadMacro(keep > index and keep - 1 or keep)
			else
				local first = TabMacros()[1]
				f.LoadMacro(first and first.index)
			end
		end)
	end

	f:RegisterEvent("UPDATE_MACROS")
	f:SetScript("OnEvent", function() if f:IsShown() then f.RefreshList() end end)
	f:HookScript("OnShow", function()
		f.RefreshList()
		local first = TabMacros()[1]
		f.LoadMacro(state.index or (first and first.index))
	end)
	f:HookScript("OnHide", function()
		f.Save()
		S.CloseModals()
	end)
	f.bar:HookScript("OnDragStop", function() ns.SaveWindowPos(f) end)
	ns.ApplyWindow(f)
	main = f -- only once fully built, so a build error can't leave a half-wired window behind
	ns.main = f
	return f
end

function ns.Open()
	if not main then CreateMain() end
	main:Show()
end

function ns.Toggle()
	if not main then CreateMain() end
	main:SetShown(not main:IsShown())
end

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	MacroBuilderEnhancedDB = MacroBuilderEnhancedDB or {}
	MacroBuilderEnhancedDB.account = F.Init(MacroBuilderEnhancedDB.account or {})
	MacroBuilderEnhancedCharDB = F.Init(MacroBuilderEnhancedCharDB or {})
end)

SLASH_MACROBUILDERENHANCED1 = "/mbe"
SLASH_MACROBUILDERENHANCED2 = "/macrobuilder"
SlashCmdList.MACROBUILDERENHANCED = function(msg)
	local command = (msg or ""):lower():match("^%s*(%S*)")
	if command == "options" or command == "config" then ns.OpenSettings() else ns.Toggle() end
end
