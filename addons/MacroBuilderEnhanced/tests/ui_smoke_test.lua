-- Headless smoke test: loads the real addon files against a permissive fake WoW API, builds the window
-- and clicks through the main flows. Catches nil-index / wiring bugs, not visuals.
-- Run from the addon folder: luajit tests/ui_smoke_test.lua
local M -- "anything" object: every field/call/op yields itself, so unknown APIs don't crash
local mmeta = {}
mmeta.__index = function() return M end
mmeta.__call = function() return M end
mmeta.__concat = function(a, b) return tostring(a == M and "" or a) .. tostring(b == M and "" or b) end
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__unm" }) do mmeta[op] = function() return 0 end end
M = setmetatable({}, mmeta)

-- fake frames ---------------------------------------------------------------
local allFrames = {}
local Frame = {}
-- like WoW: unknown Capitalized keys are (no-op) widget methods, lowercase keys are plain nil fields
local fmeta = { __index = function(t, k) return Frame[k] or (k:match("^%u") and function() return M end) or nil end }
local function newFrame(kind, parent)
	local f = setmetatable({ _kind = kind, _scripts = {}, _shown = true, _text = "", _w = 100, _h = 28, _parent = parent }, fmeta)
	allFrames[#allFrames + 1] = f
	return f
end
function Frame:SetScript(n, fn) self._scripts[n] = fn end
function Frame:HookScript(n, fn)
	local old = self._scripts[n]
	self._scripts[n] = old and function(...) old(...) fn(...) end or fn
end
function Frame:GetScript(n) return self._scripts[n] end
function Frame:Fire(n, ...) if self._scripts[n] then return self._scripts[n](self, ...) end end
function Frame:Show() local was = self:IsVisible() self._shown = true if not was and self:IsVisible() then self:Fire("OnShow") end end
function Frame:Hide() local was = self:IsVisible() self._shown = false if was then self:Fire("OnHide") end end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self._shown end
function Frame:IsVisible() return self._shown and (not self._parent or self._parent == UIParent or self._parent:IsVisible()) end
function Frame:SetText(t) self._text = t if self._fs then self._fs._text = t end end
function Frame:SetFormattedText(fmt, ...) self._text = fmt:format(...) end
function Frame:GetText() return self._text end
function Frame:SetWidth(w) self._w = w end
function Frame:SetHeight(h) self._h = h end
function Frame:SetSize(w, h) self._w, self._h = w, h end
function Frame:GetWidth() return self._w end
function Frame:GetHeight() return self._h end
function Frame:GetStringWidth() return 50 end
function Frame:GetFrameLevel() return 1 end
function Frame:GetEffectiveScale() return 1 end
function Frame:IsMouseOver() return false end
function Frame:HasFocus() return false end
function Frame:IsEnabled() return self._enabled ~= false end
function Frame:SetEnabled(v) self._enabled = v and true or false end
function Frame:Enable() self._enabled = true end
function Frame:Disable() self._enabled = false end
function Frame:GetName() return self._name end
function Frame:CreateTexture() return newFrame("Texture", self) end
function Frame:CreateFontString() return newFrame("FontString", self) end
function Frame:SetFontString(fs) self._fs = fs end
function Frame:GetFontString() return self._fs or newFrame("FontString", self) end
function Frame:Click(button) self:Fire("OnClick", button or "LeftButton") end
-- DropdownButton
function Frame:SetupMenu(gen) self._gen = gen gen(self, M) end
function Frame:GenerateMenu() if self._gen then self._gen(self, M) end end
-- ScrollBox
function Frame:SetDataProvider(dp)
	self._rows = {}
	local view = self._view
	local n = dp.n or #dp.list
	for i = 1, n do
		local row = newFrame(view._type, self)
		view._init(row, dp.list and dp.list[i] or i)
		self._rows[i] = row
	end
end
function Frame:ForEachFrame(fn) for _, r in ipairs(self._rows or {}) do fn(r) end end

UIParent = newFrame("Frame")
function CreateFrame(kind, name, parent)
	local f = newFrame(kind, parent)
	f._name = name
	if name then _G[name] = f end
	if parent and parent ~= UIParent and not parent:IsVisible() then end
	return f
end
function CreateFont() return newFrame("Font") end

-- fake game API -------------------------------------------------------------
local macros = { { "Alpha", 134400, "/cast Frostbolt" }, { "Beta", 135846, "#showtooltip\n/cast Blink" } }
local charMacros = { { "Gamma", 134400, "" } }
local function macroAt(i)
	if i > 120 then return charMacros[i - 120] end
	return macros[i]
end
function GetNumMacros() return #macros, #charMacros end
function GetMacroInfo(i) local m = macroAt(i) if m then return m[1], m[2], m[3] end end
function GetMacroIndexByName(n) for i, m in ipairs(macros) do if m[1] == n then return i end end return 0 end
function CreateMacro(name, icon, body, perChar)
	local list = perChar and charMacros or macros
	list[#list + 1] = { name, icon, body or "" }
	return (perChar and 120 or 0) + #list
end
function EditMacro(i, name, icon, body)
	local m = macroAt(i)
	m[1], m[2], m[3] = name or m[1], icon or m[2], body or m[3]
	return i
end
function DeleteMacro(i) if i > 120 then table.remove(charMacros, i - 120) else table.remove(macros, i) end end
function PickupMacro(i) _cursor = i end
function GetCursorInfo() if _cursor then return "macro", _cursor end end
function ClearCursor() _cursor = nil end
function GetMacroIcons(t) t[#t + 1] = 135846 t[#t + 1] = 132337 end
function GetMacroItemIcons(t) t[#t + 1] = 135274 end
function GetLooseMacroIcons() end
function GetLooseMacroItemIcons() end
function InCombatLockdown() return false end
function GetLocale() return "enUS" end
function GetCursorPosition() return 0, 0 end
function GetInventoryItemID() return nil end
function UnitExists() return false end
function C_Timer_After() end
C_Timer = { After = function() end }
C_Macro = { GetSelectedMacroIcon = function(i) return macroAt(i) and macroAt(i)[2] end }
C_SpellBook = {
	GetNumSpellBookSkillLines = function() return 1 end,
	GetSpellBookSkillLineInfo = function() return { name = "Frost", itemIndexOffset = 0, numSpellBookItems = 2, shouldHide = false } end,
	GetSpellBookItemInfo = function(slot) return { name = "Frostbolt", itemType = 1, isPassive = false, subName = "Rank " .. slot, iconID = 135846, spellID = slot } end,
	HasPetSpells = function() return nil end,
}
C_Spell = { GetSpellSubtext = function() return "" end }
C_Item = {
	GetItemNameByID = function() return nil end,
	GetItemClassInfo = function(c) return "Class" .. c end,
	GetItemSubClassInfo = function(c, s) if s < 3 then return "Sub" .. c .. "_" .. s end end,
}
C_Container = { GetContainerNumSlots = function() return 0 end }
C_CreatureInfo = { GetClassInfo = function(id) return { className = "Class" .. id, classFile = "F" .. id } end }
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { WrapTextInColorCode = function(_, s) return s end } end })
Constants = { MacroConsts = { MAX_ACCOUNT_MACROS = 120, MAX_CHARACTER_MACROS = 30 } }
Enum = { SpellBookItemType = { Spell = 1 }, SpellBookSpellBank = { Player = 0, Pet = 1 } }
INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED, NUM_BAG_SLOTS = 1, 19, 4
UISpecialFrames, SlashCmdList = {}, {}
STANDARD_TEXT_FONT = "x"
ScrollBoxConstants = { RetainScrollPosition = true }
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
function tDeleteItem(t, v) for i = #t, 1, -1 do if t[i] == v then table.remove(t, i) end end end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function BreakUpLargeNumbers(n) return tostring(n) end
function GameTooltip_Hide() end
GameTooltip = M
function Mixin(t) return t end
BackdropTemplateMixin = {}
AnchorUtil = { CreateAnchor = function() return M end }
MenuUtil = { CreateContextMenu = function(owner, gen) gen(owner, M) end }
EventUtil = { ContinueOnAddOnLoaded = function(_, cb) cb() end }
Settings = setmetatable({ RegisterVerticalLayoutCategory = function() return M, M end }, mmeta)
local hooks = {}
function hooksecurefunc(t, name, fn) hooks[name] = fn end
function RunNextFrame(fn) fn() end
local hidden
function HideUIPanel(f) hidden = f if f.Hide then f:Hide() end end
MACROS = "Macros"
-- Esc menu: Options, Support, Macros | Log Out, each with a layoutIndex like MainMenuFrameMixin.
local function menuButton(text, i) return { layoutIndex = i, GetText = function() return text end } end
GameMenuFrame = { buttons = { menuButton("Options", 1), menuButton("Support", 2), menuButton("Macros", 3), menuButton("Log Out", 4) } }
function GameMenuFrame:AddButton(text, cb)
	local b = menuButton(text, #self.buttons + 1)
	b.Click = cb
	self.buttons[#self.buttons + 1] = b
	return b
end
function CreateIndexRangeDataProvider(n) return { n = n } end
function CreateDataProvider(t) return { list = t } end
function CreateScrollBoxListLinearView() local v = {} function v:SetElementExtent() end function v:SetElementInitializer(t, fn) self._type, self._init = t, fn end return v end
function CreateScrollBoxListGridView() local v = {} function v:SetElementSize() end function v:SetElementInitializer(t, fn) self._type, self._init = t, fn end return v end
ScrollUtil = { InitScrollBoxListWithScrollBar = function(box, _, view) box._view = view end, InitScrollFrameWithScrollBar = function() end }
function ScrollingEdit_OnTextChanged() end
function ScrollingEdit_OnCursorChanged() end
function ScrollingEdit_OnUpdate() end
-- any other global (CANCEL, SAVE, …) is a mock; our own globals (SavedVariables) start out nil like in game
setmetatable(_G, { __index = function(_, k) if not k:match("^MacroBuilderEnhanced") then return M end end })

-- load the addon as the TOC does ------------------------------------------
local ns = {}
for line in io.lines("MacroBuilderEnhanced.toc") do
	if not line:match("^#") and line:match("%S") then
		assert(loadfile((line:gsub("\\", "/"))))("MacroBuilderEnhanced", ns)
	end
end

local function find(pred)
	for _, f in ipairs(allFrames) do if pred(f) then return f end end
end
local function button(text)
	return assert(find(function(f) return f._kind == "Button" and f._fs and f._fs._text == text end), "no button " .. text)
end
local function step(name, fn)
	local ok, err = pcall(fn)
	if not ok then error(("[%s] %s"):format(name, err), 0) end
	print("ok  " .. name)
end

step("open window", function() SlashCmdList.MACROBUILDERENHANCED() end)
local main = MacroBuilderEnhancedFrame
step("macros listed", function()
	local tree = find(function(f) return f._rows and #f._rows > 0 and f._rows[1].data end)
	assert(tree and #tree._rows == 2, "expected 2 macro rows")
end)
step("new macro", function() button("+  New macro"):Click() assert(#macros == 3 and macros[3][1] == "New Macro") end)
step("new folder", function()
	button("+  Folder"):Click()
	local ok = button("OK")
	local input = find(function(f) return f._kind == "EditBox" and f._parent and f._parent._kind ~= nil and f._parent == ok._parent end)
	input._text = "PvP"
	ok:Click()
	assert(next(MacroBuilderEnhancedDB.account.folders), "folder not created")
end)
step("move macro into folder by drag", function()
	local tree = find(function(f) return f._rows and #f._rows > 0 and f._rows[1].data end)
	local folderRow, macroRow
	for _, r in ipairs(tree._rows) do
		if r.data.kind == "folder" then folderRow = r elseif r.data.name == "Alpha" then macroRow = r end
	end
	macroRow:Fire("OnDragStart")
	folderRow:Fire("OnReceiveDrag")
	assert(MacroBuilderEnhancedDB.account.macros.Alpha, "macro not filed")
end)
step("edit + save", function()
	local body = find(function(f) return f._kind == "EditBox" and f._scripts.OnCursorChanged end)
	body._text = "/cast Blink"
	body:Fire("OnTextChanged", true)
	button(SAVE):Click()
end)
for _, action in ipairs(ns.Builder.ACTIONS) do
	step("line form: " .. action.key, function()
		button(action.label):Click()
		button("Insert line"):Click()
	end)
end
step("icon filters", function()
	local search = find(function(f) return f._kind == "EditBox" and f._scripts.OnTextChanged and f.placeholder and f.placeholder._text:find("Search icons") end)
	search._text = "frost"
	search:Fire("OnTextChanged", true)
end)
step("character tab", function() main.SwitchTab("char") main.SwitchTab("account") end)
step("delete macro", function() main.DeleteMacro(1, "Alpha") button("Delete macro"):Click() end)
step("close + reopen", function() SlashCmdList.MACROBUILDERENHANCED() SlashCmdList.MACROBUILDERENHANCED() end)
step("esc menu button under Macros", function()
	main:Hide()
	hooks.InitButtons(GameMenuFrame)
	local order = {}
	for _, b in ipairs(GameMenuFrame.buttons) do order[b.layoutIndex] = b:GetText() end
	assert(table.concat(order, ",") == "Options,Support,Macros,Macro Builder,Log Out", table.concat(order, ","))
	GameMenuFrame.buttons[5].Click()
	assert(hidden == GameMenuFrame and main:IsShown())
end)
step("esc menu button can be turned off", function()
	MacroBuilderEnhancedDB.gameMenu = false
	local n = #GameMenuFrame.buttons
	hooks.InitButtons(GameMenuFrame)
	assert(#GameMenuFrame.buttons == n)
end)
step("window position saved and restored", function()
	assert(MacroBuilderEnhancedDB.scale == 1 and MacroBuilderEnhancedDB.replaceBlizzard == false)
	main.bar:Fire("OnDragStop")
	assert(MacroBuilderEnhancedDB.pos[1] ~= nil)
end)
print("ui_smoke_test: all passed")
