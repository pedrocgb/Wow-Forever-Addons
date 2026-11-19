-- Saved settings, the Options > AddOns panel and the slash command.
local addonName, ns = ...

local DEFAULTS = {
	-- Swing bars, all of them
	anchored = true,   -- move the bars as one group, stacked
	spacing = 3,       -- gap between anchored bars
	pos = {},          -- the group's position when anchored
	locked = true,
	latency = true,    -- add world latency to the 0.5 s aim window
	dimRange = true,
	-- Summon Hawk
	hawkEnabled = true,
	hawkSize = 40,
	hawkSpacing = 4,
	hawkFontSize = 16,
	hawkColText = "ffeef0f5",
	hawkPos = {},
	hawkNpcs = {},    -- learned hawk NPC IDs besides the known one
	tamed = {},       -- npcID -> { { ability, rank } }: what a beast taught when tamed in game
	-- Ammo
	ammoEnabled = true,
	ammoShowBags = true,
	ammoWarnAt = 200,
	ammoAlert = true,
	ammoSound = "raid",
	ammoFontSize = 16,
	ammoPos = {},
	-- Pet training
	petGuideEnabled = true,
	petTooltip = true,        -- what tameable beasts teach, on their tooltips
	petGuidePos = {},
}

-- Per bar, saved as <bar key><Name>: rangedScale, mainColFill... Colours are "AARRGGBB".
local BAR_DEFAULTS = {
	Show = true,
	Visibility = "combat", -- always | combat | auto | combatAuto
	Style = "default", -- or "center": fills from both ends into the middle
	Scale = 1,
	Width = 260,
	Height = 20,
	FontSize = 11,
	ShowLabel = true,
	ShowTime = true,
	BgAlpha = 95,      -- percent
	Pos = {},          -- the bar's own position when not anchored
	ColIdle = "ff4d5466",
	ColBg = "ff191b22",
	ColText = "ffeef0f5",
	ColFlash = "ffffd140",
	Flash = false,     -- ranged: when still moving at the stop line; melee: on each swing
	Sound = "off",     -- key in ns.SOUNDS, or "off"
}
local BAR_OVERRIDES = {
	ranged = { Visibility = "combatAuto", ColFill = "ff59cc85", ColStill = "ffffb847", ColLate = "ffed5c5c", ColZone = "ffffb847",
		Flash = true, Sound = "tick", AlertEarly = 0 }, -- AlertEarly: ms before the stop line
	main = { ColFill = "ff4f8fff" },
	off = { ColFill = "ff9e7afa" },
}
for _, bar in ipairs(ns.BARS) do
	for name, value in pairs(BAR_DEFAULTS) do DEFAULTS[bar.key .. name] = value end
	for name, value in pairs(BAR_OVERRIDES[bar.key]) do DEFAULTS[bar.key .. name] = value end
end
ns.DEFAULTS = DEFAULTS

local category, layout
local settings = {} -- key -> Setting, for the reset button

function ns.Apply()
	for _, apply in ipairs(ns.modules) do apply() end
end

local function say(text)
	print("|cff4f8fffThe Ultimate Hunter Addon|r: " .. text)
end

local cat, lay -- the category being built; the helpers below add to it

local function setting(key, varType, name, onSet)
	local s = Settings.RegisterProxySetting(cat, "ULTIMATEHUNTER_" .. key:upper(), varType, name, DEFAULTS[key],
		function() return ns.db[key] end,
		function(value)
			ns.db[key] = value
			ns.Apply()
			if onSet then onSet(value) end
		end)
	settings[key] = s
	return s
end

local function header(name)
	lay:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
end

local function check(key, name, tooltip)
	Settings.CreateCheckbox(cat, setting(key, Settings.VarType.Boolean, name), tooltip)
end

local function slider(key, name, min, max, step, format, tooltip)
	local options = Settings.CreateSliderOptions(min, max, step)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return format:format(v) end)
	Settings.CreateSlider(cat, setting(key, Settings.VarType.Number, name), options, tooltip)
end

-- Closes the settings so the simulated alert is visible, then fires it.
local function testButton(tooltip, fire)
	lay:AddInitializer(CreateSettingsButtonInitializer("Test", "Test warning", function()
		SettingsPanel:Close(true) -- true: don't fall back to the Esc menu
		fire()
	end, tooltip, false))
end

local function color(key, name, tooltip)
	Settings.CreateColorSwatch(cat, setting(key, Settings.VarType.String, name), tooltip)
end

-- choices: { value, label, value, label... }
local function dropdown(key, name, choices, tooltip, onSet)
	local function options()
		local container = Settings.CreateControlTextContainer()
		for i = 1, #choices, 2 do container:Add(choices[i], choices[i + 1]) end
		return container:GetData()
	end
	Settings.CreateDropdown(cat, setting(key, Settings.VarType.String, name, onSet), options, tooltip)
end

local SOUND_CHOICES = { "off", "Off", "tick", "Tick", "alarm", "Alarm clock", "raid", "Raid warning" }
local VISIBILITY_CHOICES = { "always", "Always", "combat", "In combat", "auto", "While Auto Shot is on",
	"combatAuto", "In combat or while Auto Shot is on" }
local STYLE_CHOICES = { "default", "Default (fills left to right)", "center", "Center (fills from both ends to the middle)" }

local refreshMatrix -- set by the colour matrix page

local function resetAll()
	for key, value in pairs(DEFAULTS) do
		if settings[key] then
			settings[key]:SetValue(value) -- also refreshes the controls
		elseif key ~= "hawkNpcs" and key ~= "tamed" then
			ns.db[key] = type(value) == "table" and {} or value
		end
	end
	ns.Apply()
	if refreshMatrix then refreshMatrix() end
	say("settings reset.")
end

local function barPage(bar)
	local k = bar.key
	local label = bar.label:lower()
	cat, lay = Settings.RegisterVerticalLayoutSubcategory(category, bar.label .. " bar")
	header("Appearance")
	check(k .. "Show", "Show the bar", bar.ranged
		and "Auto Shot timer. The amber zone at the end is the 0.5 s you must stand still; be stopped by the white line."
		or k == "off" and "Shown only while dual wielding." or "Melee swing timer.")
	dropdown(k .. "Visibility", "Visibility", VISIBILITY_CHOICES,
		"When the bar shows. Unlocking the frames shows every bar so you can move it.")
	dropdown(k .. "Style", "Bar style", STYLE_CHOICES, bar.ranged
		and "Center: the fill comes from both ends and meets in the middle; the stand-still zone sits in the middle." or nil)
	slider(k .. "Scale", "Scale", 0.6, 2, 0.05, "x%.2f")
	slider(k .. "Width", "Width", 120, 600, 10, "%d px")
	slider(k .. "Height", "Height", 10, 48, 1, "%d px")
	slider(k .. "FontSize", "Font size", 8, 20, 1, "%d")
	check(k .. "ShowLabel", "Show bar name", "\"" .. bar.label .. "\" on the left of the bar.")
	check(k .. "ShowTime", "Show time left", "Seconds left in the swing on the right of the bar.")
	slider(k .. "BgAlpha", "Background opacity", 0, 100, 5, "%d%%")
	header("Alerts")
	if bar.ranged then
		check(k .. "Flash", "Flash at the stop line", "Flash when you are still moving at the stop line.")
		dropdown(k .. "Sound", "Stop sound", SOUND_CHOICES, "Sound when you are still moving at the stop line.", ns.PlaySound)
		slider(k .. "AlertEarly", "Alert early", 0, 400, 10, "%d ms",
			"Fire the alert this much before the stop line, to give you time to react.")
		testButton("Close the settings and fire the stop-line alert (flash and sound as set above).",
			function() ns.TestSwingAlert(k) end)
	else
		check(k .. "Flash", "Flash on each swing", "Flash the " .. label .. " bar each time it swings.")
		dropdown(k .. "Sound", "Sound on each swing", SOUND_CHOICES, "Sound each time the " .. label .. " swings.", ns.PlaySound)
		testButton("Close the settings and fire the swing alert (flash and sound as set above).",
			function() ns.TestSwingAlert(k) end)
	end
	header("Colours")
	lay:AddInitializer(CreateSettingsButtonInitializer("Bar colours", "Open colour table", function()
		Settings.OpenToCategory(ns.matrixCategory:GetID())
	end, "All three bars' colours side by side.", false))
end

local function hexOf(r, g, b)
	local function byte(v) return math.floor(v * 255 + 0.5) end
	return ("ff%02x%02x%02x"):format(byte(r), byte(g), byte(b))
end

-- Colour matrix: one row per colour role, one column per bar. Canvas page, own swatches.
local function matrixPage()
	local f = CreateFrame("Frame")
	local title = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Swing bar colours")
	local hint = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	hint:SetText("Click a swatch to change it. Ranged-only colours have no melee swatch.")
	local COL_X, COL_W, ROW_Y, ROW_H = 200, 110, -80, 32
	local swatches = {}
	for j, bar in ipairs(ns.BARS) do
		local head = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		head:SetPoint("TOP", f, "TOPLEFT", COL_X + (j - 1) * COL_W, ROW_Y + 26)
		head:SetText(bar.label)
	end
	for i, role in ipairs(ns.COLOR_ROLES) do
		local y = ROW_Y - (i - 1) * ROW_H
		local name = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		name:SetPoint("LEFT", f, "TOPLEFT", 24, y)
		name:SetText(role[2])
		for j, bar in ipairs(ns.BARS) do
			local key = bar.key .. "Col" .. role[1]
			if DEFAULTS[key] then
				local b = CreateFrame("Button", nil, f, "BackdropTemplate")
				b:SetSize(36, 22)
				b:SetPoint("CENTER", f, "TOPLEFT", COL_X + (j - 1) * COL_W, y)
				b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
				b:SetBackdropBorderColor(0.2, 0.216, 0.263, 1)
				b.key = key
				local function set(hex)
					ns.db[key] = hex
					b:SetBackdropColor(ns.Hex(hex))
					ns.Apply()
				end
				b:SetScript("OnClick", function()
					local r, g, bl = ns.Hex(ns.db[key])
					ColorPickerFrame:SetupColorPickerAndShow({
						r = r, g = g, b = bl, swatch = b,
						swatchFunc = function() set(hexOf(ColorPickerFrame:GetColorRGB())) end,
						cancelFunc = function() set(hexOf(ColorPickerFrame:GetPreviousValues())) end,
					})
				end)
				b:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText(bar.label .. ": " .. role[2])
					GameTooltip:Show()
				end)
				b:SetScript("OnLeave", GameTooltip_Hide)
				swatches[#swatches + 1] = b
			end
		end
	end
	refreshMatrix = function()
		for _, b in ipairs(swatches) do b:SetBackdropColor(ns.Hex(ns.db[b.key])) end
	end
	f:SetScript("OnShow", refreshMatrix)
	f.OnRefresh = refreshMatrix
	ns.matrixCategory = Settings.RegisterCanvasLayoutSubcategory(category, f, "Swing bar colours")
end

local function createSettings()
	category, layout = Settings.RegisterVerticalLayoutCategory("The Ultimate Hunter Addon")
	cat, lay = category, layout

	header("Swing Timer")
	check("locked", "Lock frames", "Uncheck to drag the swing bars, hawk icons and ammo counter around.")
	check("anchored", "Anchor bars together",
		"On: the bars stack and move as one group. Off: drag each bar anywhere on its own.")
	slider("spacing", "Spacing", 0, 20, 1, "%d px", "Gap between anchored bars.")
	check("latency", "Include latency",
		"Widen the stand-still zone by your world latency, since the stop has to reach the server.")
	check("dimRange", "Dim when out of range", "Fade a bar while your target is out of range for that attack.")

	header("Summon Hawk")
	check("hawkEnabled", "Track hawks",
		"An icon per active hawk (18 s), right to left. A new hawk replaces the oldest; a hawk that dies is removed. " ..
		"For exact death tracking, turn on friendly guardian nameplates in the game options.")
	slider("hawkSize", "Icon size", 20, 80, 2, "%d px")
	slider("hawkSpacing", "Icon spacing", 0, 20, 1, "%d px")
	slider("hawkFontSize", "Timer font size", 8, 32, 1, "%d")
	color("hawkColText", "Timer text")

	header("Ammo")
	check("ammoEnabled", "Show ammo counter", "Your equipped ammo, counted across all your bags.")
	check("ammoShowBags", "Show quiver / bags split",
		"How much of it is in your quiver or ammo pouch (haste bonus) and how much in normal bags (amber).")
	slider("ammoWarnAt", "Low ammo at", 0, 1000, 50, "%d",
		"The count turns red at or below this. 200 is one stack.")
	check("ammoAlert", "Low ammo warning", "Show \"Almost out of ammo\" like a raid warning, once each time you drop that low.")
	dropdown("ammoSound", "Low ammo sound", SOUND_CHOICES, "Sound with the low ammo warning.", ns.PlaySound)
	testButton("Close the settings and show the low ammo warning.", function() ns.AmmoWarn(ns.db.ammoWarnAt) end)
	slider("ammoFontSize", "Font size", 8, 32, 1, "%d")

	header("Pet Training")
	check("petTooltip", "Show what tameable beasts teach on tooltips",
		"On a tameable beast's tooltip: the abilities and ranks you learn by taming it.")
	lay:AddInitializer(CreateSettingsButtonInitializer("Pet guide", "Open pet guide", function()
		SettingsPanel:Close(true)
		ns.TogglePetGuide()
	end, "How pet training works, your pet's abilities and where to tame each rank. Also /uh pets.", false))

	layout:AddInitializer(CreateSettingsButtonInitializer("Reset", "Reset to defaults", resetAll,
		"Put every setting and position back to default.", true))
	Settings.RegisterAddOnCategory(category)

	for _, bar in ipairs(ns.BARS) do barPage(bar) end
	matrixPage()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
	if name ~= addonName then return end
	self:UnregisterEvent("ADDON_LOADED")
	UltimateHunterDB = UltimateHunterDB or {} -- SavedVariables exist only from here on
	local db = UltimateHunterDB
	for key, value in pairs(DEFAULTS) do
		if db[key] == nil then db[key] = type(value) == "table" and {} or value end
	end
	for key in pairs(db) do
		if DEFAULTS[key] == nil then db[key] = nil end -- settings from older versions
	end
	ns.db = db
	createSettings()
	ns.Apply()
end)

SLASH_ULTIMATEHUNTER1 = "/uh"
SLASH_ULTIMATEHUNTER2 = "/ultimatehunter"
SlashCmdList.ULTIMATEHUNTER = function(msg)
	local command = msg:lower():match("^%s*(%S*)")
	if command == "lock" or command == "unlock" then
		settings.locked:SetValue(command == "lock")
		say(ns.db.locked and "frames locked." or "frames unlocked, drag them where you like.")
	elseif command == "reset" then
		ns.db.pos, ns.db.hawkPos, ns.db.ammoPos, ns.db.petGuidePos = {}, {}, {}, {}
		for _, bar in ipairs(ns.BARS) do ns.db[bar.key .. "Pos"] = {} end
		ns.Apply()
		say("positions reset.")
	elseif command == "pets" then
		ns.TogglePetGuide()
	elseif command == "debug" then
		ns.debug = not ns.debug
		say("hawk debug " .. (ns.debug and "on: casts, landings, sightings and deaths print to chat." or "off."))
	elseif command == "" then
		if InCombatLockdown() then
			say("the settings panel can't open in combat.")
		else
			Settings.OpenToCategory(category:GetID())
		end
	else
		say("/uh (settings) | /uh lock | /uh unlock | /uh reset | /uh pets (pet training guide) | /uh debug")
	end
end
