-- Options > AddOns page, the Esc menu button and taking over the Blizzard macro window.
local addonName, ns = ...

local DEFAULTS = {
	gameMenu = true,         -- "Macro Builder" button under Macros in the Esc menu
	replaceBlizzard = false, -- anything that opens the Blizzard macro window opens ours instead
	scale = 1,
	pos = {},                -- window position, saved when dragged
}

local category

-- Window scale and position; also used by UI.lua right after the window is built.
function ns.ApplyWindow(f)
	local db = MacroBuilderEnhancedDB
	f:SetScale(db.scale)
	f:ClearAllPoints()
	local pos = db.pos
	if pos[1] then
		f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		f:SetPoint("CENTER")
	end
end

function ns.SaveWindowPos(f)
	local point, _, relativePoint, x, y = f:GetPoint()
	MacroBuilderEnhancedDB.pos = { point, relativePoint, x, y }
end

-- Esc menu: our button right under Blizzard's "Macros". The menu rebuilds its buttons on every open.
local function addGameMenuButton(menu)
	if not MacroBuilderEnhancedDB.gameMenu or not menu.buttons then return end
	local macros
	for _, b in ipairs(menu.buttons) do
		if b:GetText() == MACROS then macros = b end
	end
	if not macros then return end -- macros disabled by the game rules
	local at = macros.layoutIndex + 1
	for _, b in ipairs(menu.buttons) do
		if b.layoutIndex >= at then b.layoutIndex = b.layoutIndex + 1 end
	end
	local sectionSpacing = menu.sectionSpacing
	menu.sectionSpacing = nil -- AddButton would otherwise pad ours like a new section
	local button = menu:AddButton("Macro Builder", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
		HideUIPanel(menu)
		ns.Open()
	end)
	menu.sectionSpacing = sectionSpacing
	button.layoutIndex = at
	button.topPadding = nil
end

-- Blizzard's macro window: let it open, then swap it for ours. Covers Esc > Macros, /macro and keybinds.
local function takeOverMacroFrame()
	MacroFrame:HookScript("OnShow", function(self)
		if not MacroBuilderEnhancedDB.replaceBlizzard then return end
		RunNextFrame(function() HideUIPanel(self) end) -- not mid-ShowUIPanel
		ns.Open()
	end)
end

local function createSettings()
	local layout
	category, layout = Settings.RegisterVerticalLayoutCategory("Macro Builder Enhanced")
	local function setting(key, varType, name)
		return Settings.RegisterProxySetting(category, "MACROBUILDERENHANCED_" .. key:upper(), varType, name, DEFAULTS[key],
			function() return MacroBuilderEnhancedDB[key] end,
			function(value)
				MacroBuilderEnhancedDB[key] = value
				if ns.main then ns.ApplyWindow(ns.main) end
			end)
	end
	local function button(name, text, click, tooltip)
		layout:AddInitializer(CreateSettingsButtonInitializer(name, text, click, tooltip, true))
	end

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Opening"))
	button("Macro Builder", "Open", function() ns.Open() end, "Open the Macro Builder window. Same as /mbe.")
	Settings.CreateCheckbox(category, setting("gameMenu", Settings.VarType.Boolean, "Show in the game menu"),
		"Add a Macro Builder button under Macros in the Esc menu.")
	Settings.CreateCheckbox(category, setting("replaceBlizzard", Settings.VarType.Boolean, "Replace the Blizzard macro window"),
		"Esc > Macros, /macro and the macro keybind open Macro Builder instead of the Blizzard window.")

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Window"))
	local options = Settings.CreateSliderOptions(0.7, 1.5, 0.05)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return ("x%.2f"):format(v) end)
	Settings.CreateSlider(category, setting("scale", Settings.VarType.Number, "Scale"), options)
	button("Position", "Reset position", function()
		MacroBuilderEnhancedDB.pos = {}
		if ns.main then ns.ApplyWindow(ns.main) end
	end, "Put the window back in the middle of the screen.")

	Settings.RegisterAddOnCategory(category)
end

function ns.OpenSettings()
	if InCombatLockdown() then
		print("|cff4f8fffMacro Builder Enhanced|r: the settings panel can't open in combat.")
	else
		Settings.OpenToCategory(category:GetID())
	end
end

EventUtil.ContinueOnAddOnLoaded(addonName, function()
	local db = MacroBuilderEnhancedDB -- created by UI.lua's loader, which runs first
	for key, value in pairs(DEFAULTS) do
		if db[key] == nil then db[key] = type(value) == "table" and {} or value end
	end
	createSettings()
	hooksecurefunc(GameMenuFrame, "InitButtons", addGameMenuButton)
	EventUtil.ContinueOnAddOnLoaded("Blizzard_MacroUI", takeOverMacroFrame)
end)
