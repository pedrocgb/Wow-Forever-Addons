-- Swing bars: Ranged (with the Auto Shot "stand still" window), Main Hand and Off Hand.
-- Driven by Forever's native PLAYER_SWING (the combat log is gone for addons in 12.x).
-- swingDuration already includes haste; UNIT_ATTACK_SPEED only rescales a swing in progress.
local _, ns = ...

local SWING = Enum.PlayerSwingType
local WHITE = "Interface\\Buttons\\WHITE8X8"
local LATIN = { enUS = 1, enGB = 1, deDE = 1, frFR = 1, esES = 1, esMX = 1, itIT = 1, ptBR = 1 }
local FONT = LATIN[GetLocale()] and "Fonts\\ARIALN.TTF" or STANDARD_TEXT_FONT
local BORDER = { 0.2, 0.216, 0.263, 1 } -- Macro Builder Enhanced border
local ZONE_ALPHA, OUT_OF_RANGE_ALPHA = 0.22, 0.35
local MAX_ACTION_SLOT = 180

-- Phase -> colour role, and its word on the bar.
local PHASE = {
	go = { "Fill", "MOVE" },
	still = { "Still", "STAND STILL" },
	late = { "Late", "STOP! SHOT DELAYED" },
	held = { "Late", "STOP TO SHOOT" },
	ready = { "Still", "AIMING" },
}
-- Colour roles; the ranged-only ones are absent from the melee bars' settings.
ns.COLOR_ROLES = {
	{ "Fill", "Fill / Move" }, { "Still", "Stand still" }, { "Late", "Moving too late" },
	{ "Zone", "Stand-still zone" }, { "Idle", "Idle" }, { "Bg", "Background" }, { "Text", "Text" },
	{ "Flash", "Flash" },
}
ns.SOUNDS = {
	tick = SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON,
	alarm = SOUNDKIT.ALARM_CLOCK_WARNING_3,
	raid = SOUNDKIT.RAID_WARNING,
}

-- Each bar's settings are saved as key .. Setting (rangedScale, mainColFill...).
local ROWS = {
	{ key = "ranged", type = SWING.Ranged, label = "Ranged", ranged = true },
	{ key = "main", type = SWING.MainHand, label = "Main Hand" },
	{ key = "off", type = SWING.OffHand, label = "Off Hand" },
}
ns.BARS = ROWS

local moving, autoOn, inCombat = false, false, false
local has = { [SWING.MainHand] = true } -- which slots have a weapon that swings
local rows, byType = {}, {}
local holder = CreateFrame("Frame", "UltimateHunterSwing", UIParent) -- events, OnUpdate, show/hide all bars
holder:SetAllPoints()

-- Secret values can't be compared, so they count as "unknown".
local function plain(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local function rawSpeed(t)
	local mh, oh, rg = UnitAttackSpeed("player")
	if t == SWING.Ranged then return rg elseif t == SWING.OffHand then return oh end
	return mh
end

local function lead()
	local l = ns.AIM
	if ns.db.latency then l = l + (select(4, GetNetStats()) or 0) / 1000 end -- the stop must reach the server
	return l
end

local function playSound(key)
	local kit = ns.SOUNDS[key]
	if kit then PlaySound(kit, "Master") end
end
ns.PlaySound = playSound

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function newRow(def)
	local row = CreateFrame("Frame", nil, holder, "BackdropTemplate")
	row.def = def
	row:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	row:SetBackdropBorderColor(unpack(BORDER))

	-- Default style: bar fills the row from the left. Center style: bar is the left half, bar2 the
	-- right half filling right to left, so the fill meets in the middle.
	local function statusBar()
		local b = CreateFrame("StatusBar", nil, row)
		b:SetStatusBarTexture(WHITE)
		b:SetMinMaxValues(0, 1)
		return b
	end
	row.bar = statusBar()
	row.bar2 = statusBar()
	row.bar2:SetReverseFill(true)

	local top = CreateFrame("Frame", nil, row) -- everything drawn over the fill
	top:SetPoint("TOPLEFT", 1, -1)
	top:SetPoint("BOTTOMRIGHT", -1, 1)
	top:SetFrameLevel(row.bar:GetFrameLevel() + 1)
	row.top = top
	row.texts = {}
	local function text(justify)
		local fs = top:CreateFontString(nil, "OVERLAY")
		fs:SetFont(FONT, 11, "")
		fs:SetShadowOffset(1, -1)
		fs:SetShadowColor(0, 0, 0, 0.9)
		fs:SetJustifyH(justify)
		row.texts[#row.texts + 1] = fs
		return fs
	end

	if def.ranged then
		-- The last AIM + latency of the swing: be standing still by the white line.
		-- (centred in the Center style, with a line on each side).
		row.zone = top:CreateTexture(nil, "BACKGROUND")
		local function mark()
			local m = top:CreateTexture(nil, "BORDER")
			m:SetWidth(2)
			m:SetColorTexture(1, 1, 1, 0.9)
			return m
		end
		row.mark = mark()
		row.mark:SetPoint("TOPRIGHT", row.zone, "TOPLEFT")
		row.mark:SetPoint("BOTTOMRIGHT", row.zone, "BOTTOMLEFT")
		row.mark2 = mark()
		row.mark2:SetPoint("TOPLEFT", row.zone, "TOPRIGHT")
		row.mark2:SetPoint("BOTTOMLEFT", row.zone, "BOTTOMRIGHT")
		row.state = text("CENTER")
		row.state:SetPoint("CENTER")
	end

	local function spark()
		local t = top:CreateTexture(nil, "ARTWORK")
		t:SetWidth(2)
		t:SetColorTexture(1, 1, 1, 0.9)
		return t
	end
	row.spark, row.spark2 = spark(), spark()
	row.label = text("LEFT")
	row.label:SetPoint("LEFT", 6, 0)
	row.label:SetText(def.label)
	row.time = text("RIGHT")
	row.time:SetPoint("RIGHT", -6, 0)

	-- Two quick pulses under the text.
	row.flash = top:CreateTexture(nil, "OVERLAY", nil, -1)
	row.flash:SetAllPoints()
	row.flash:SetAlpha(0)
	local anim = row.flash:CreateAnimationGroup()
	for i = 0, 3 do
		local a = anim:CreateAnimation("Alpha")
		local up = i % 2 == 0
		a:SetFromAlpha(up and 0 or 0.8)
		a:SetToAlpha(up and 0.8 or 0)
		a:SetDuration(up and 0.06 or 0.2)
		a:SetOrder(i + 1)
	end
	row.flashAnim = anim
	return row
end

for i, def in ipairs(ROWS) do
	rows[i] = newRow(def)
	byType[def.type] = rows[i]
end

local function flash(row)
	row.flashAnim:Stop()
	row.flashAnim:Play()
end

local function paint(row, now, l)
	local db, k, c = ns.db, row.def.key, row.col
	local start, dur = row.start, row.dur
	local left = start and start + dur - now or 0
	local p = start and ns.Progress(now, start, dur) or 1
	local full = row.top:GetWidth()
	local half = row.center and full / 2 or full
	row.bar:SetValue(p)
	row.bar2:SetValue(p)
	row.spark:SetShown(left > 0)
	row.spark:SetPoint("CENTER", row.top, "LEFT", half * p, 0)
	row.spark2:SetShown(row.center and left > 0)
	row.spark2:SetPoint("CENTER", row.top, "RIGHT", -half * p, 0)
	row.time:SetText(left > 0 and ("%.1f"):format(left) or "")
	local color = left > 0 and c.Fill or c.Idle

	if row.zone then
		local d = dur or plain(rawSpeed(SWING.Ranged))
		row.zone:SetWidth(math.max(1, full * (d and d > 0 and math.min(1, l / d) or 0)))
		local phase = start and autoOn and ns.RangedPhase(now, start, dur, l, moving)
		local look = phase and PHASE[phase]
		color = look and c[look[1]] or c.Idle
		row.state:SetText(look and look[2] or "")
		row.state:SetTextColor(unpack(look and c[look[1]] or c.Text))
		-- Once per swing, only when useful: still moving at (or "early" before) the stop line.
		if start and autoOn and moving and not row.alerted
			and now >= ns.StopAt(start, dur, l) - db[k .. "AlertEarly"] / 1000 then
			row.alerted = true
			if db[k .. "Flash"] then flash(row) end
			playSound(db[k .. "Sound"])
		end
	end
	row.bar:SetStatusBarColor(unpack(color))
	row.bar2:SetStatusBarColor(unpack(color))
end

holder:SetScript("OnUpdate", function()
	local now, l = GetTime(), lead()
	for _, row in ipairs(rows) do
		if row:IsShown() then paint(row, now, l) end
	end
end)

---------------------------------------------------------------------------
-- Range
---------------------------------------------------------------------------

local function setOutOfRange(row, out)
	row:SetAlpha(out and OUT_OF_RANGE_ALPHA or 1)
end

-- Re-arm the checks and re-read them (target changes, settings changes).
local function updateRange()
	for _, row in ipairs(rows) do
		local t = row.def.type
		local want = ns.db.dimRange and row:IsShown()
		C_SwingTimer.EnableRangeCheck(t, want and true or false)
		-- nil means "no check possible" and must not read as out of range.
		setOutOfRange(row, want and plain(C_SwingTimer.IsTargetWithinSwingRange(t)) == false)
	end
end

---------------------------------------------------------------------------
-- Layout and visibility
---------------------------------------------------------------------------

-- Per bar: always | combat | auto (Auto Shot on) | combatAuto. Unlocked shows everything to drag.
local function wanted(mode)
	if not ns.db.locked or mode == "always" then return true end
	if mode == "combat" then return inCombat end
	if mode == "auto" then return autoOn end
	return inCombat or autoOn
end

local function firstShown()
	for _, row in ipairs(rows) do
		if row:IsShown() then return row end
	end
end

local function place(row, pos, x, y)
	row:ClearAllPoints()
	if pos[1] then
		row:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		row:SetPoint("CENTER", UIParent, "CENTER", x, y)
	end
end

local function apply()
	local db = ns.db
	local prev
	for i, row in ipairs(rows) do
		local k = row.def.key
		local function get(name) return db[k .. name] end
		local c = {}
		for _, role in ipairs(ns.COLOR_ROLES) do
			local hex = get("Col" .. role[1])
			if hex then c[role[1]] = { ns.Hex(hex) } end
		end
		row.col = c
		local height = get("Height")
		row:SetScale(get("Scale"))
		row:SetSize(get("Width"), height)
		row:SetBackdropColor(c.Bg[1], c.Bg[2], c.Bg[3], get("BgAlpha") / 100)
		row.spark:SetHeight(height - 2)
		row.spark2:SetHeight(height - 2)
		for _, fs in ipairs(row.texts) do
			fs:SetFont(FONT, get("FontSize"), "")
			fs:SetTextColor(unpack(c.Text))
		end
		row.label:SetShown(get("ShowLabel"))
		row.time:SetShown(get("ShowTime"))
		row.flash:SetColorTexture(unpack(c.Flash))

		row.center = get("Style") == "center"
		row.bar:ClearAllPoints()
		row.bar:SetPoint("TOPLEFT", 1, -1)
		if row.center then
			row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOM", 0, 1)
			row.bar2:SetPoint("TOPLEFT", row, "TOP", 0, -1)
			row.bar2:SetPoint("BOTTOMRIGHT", -1, 1)
		else
			row.bar:SetPoint("BOTTOMRIGHT", -1, 1)
		end
		row.bar2:SetShown(row.center)
		if row.zone then
			row.zone:SetColorTexture(c.Zone[1], c.Zone[2], c.Zone[3], ZONE_ALPHA)
			row.zone:ClearAllPoints()
			local side = row.center and "" or "RIGHT"
			row.zone:SetPoint("TOP" .. side)
			row.zone:SetPoint("BOTTOM" .. side)
			row.mark2:SetShown(row.center)
		end

		local on = get("Show") and (has[row.def.type] or not db.locked) and wanted(get("Visibility"))
		row:SetShown(on and true or false)
		row:EnableMouse(not db.locked) -- locked bars never eat clicks
		if not db.anchored then
			place(row, get("Pos"), 0, -220 - (i - 1) * 30)
		elseif on then
			if prev then
				row:ClearAllPoints()
				row:SetPoint("TOP", prev, "BOTTOM", 0, -db.spacing)
			else
				place(row, db.pos, 0, -220)
			end
			prev = row
		end
	end
	updateRange()
end
local updateVisibility = apply -- visibility can change which bar tops an anchored stack

-- Anchored: dragging any bar moves the group (by its top bar). Free: each bar moves alone.
for _, row in ipairs(rows) do
	row:SetMovable(true)
	row:SetClampedToScreen(true)
	row:RegisterForDrag("LeftButton")
	row:SetScript("OnDragStart", function(self)
		local target = ns.db.anchored and firstShown() or self
		holder.dragging = target
		target:StartMoving()
	end)
	row:SetScript("OnDragStop", function()
		local target = holder.dragging
		if not target then return end
		holder.dragging = nil
		target:StopMovingOrSizing()
		local point, _, relativePoint, x, y = target:GetPoint()
		local pos = { point, relativePoint, x, y }
		if ns.db.anchored then ns.db.pos = pos else ns.db[target.def.key .. "Pos"] = pos end
	end)
end
ns.modules[#ns.modules + 1] = apply

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function refreshWeapons()
	local changed
	for _, row in ipairs(rows) do
		local t = row.def.type
		local v = rawSpeed(t)
		if t ~= SWING.MainHand and not (issecretvalue and issecretvalue(v)) then -- secret: keep what we knew
			local swings = (v or 0) > 0
			changed = changed or has[t] ~= swings
			has[t] = swings
		end
	end
	if changed then apply() end
end

-- After a /reload mid-fight the START_AUTOREPEAT_SPELL edge is gone: look for a repeating action.
local function seedAutoRepeat()
	autoOn = false
	for slot = 1, MAX_ACTION_SLOT do
		if plain(C_ActionBar.IsAutoRepeatAction(slot)) then
			autoOn = true
			return
		end
	end
end

local events = {
	PLAYER_SWING = function(dur, t)
		dur, t = plain(dur), plain(t)
		local row = t and byType[t]
		if not (row and dur) then return end
		row.start, row.dur, row.speed, row.alerted = GetTime(), dur, plain(rawSpeed(t)), nil
		if not has[t] then
			has[t] = true -- a swing proves the slot swings, even if its speed read was secret
			apply()
		end
		if not row.def.ranged and row:IsShown() then
			local k = row.def.key
			if ns.db[k .. "Flash"] then flash(row) end
			playSound(ns.db[k .. "Sound"])
		end
	end,
	UNIT_ATTACK_SPEED = function(unit)
		if unit ~= "player" then return end
		local now = GetTime()
		for _, row in ipairs(rows) do
			local new = plain(rawSpeed(row.def.type))
			if row.speed and new and new ~= row.speed and row.start and now < row.start + row.dur then
				row.start, row.dur = ns.Rescale(now, row.start, row.dur, row.dur * new / row.speed)
			end
			row.speed = new or row.speed
		end
	end,
	PLAYER_SWING_RANGE_UPDATE = function(t, inRange, checks)
		t, inRange, checks = plain(t), plain(inRange), plain(checks)
		local row = t and byType[t]
		if row and ns.db.dimRange then setOutOfRange(row, checks == true and inRange == false) end
	end,
	PLAYER_TARGET_CHANGED = updateRange,
	UNIT_INVENTORY_CHANGED = function(unit) if unit == "player" then refreshWeapons() end end,
	WEAPON_SLOT_CHANGED = refreshWeapons,
	PLAYER_ENTERING_WORLD = function()
		moving = IsPlayerMoving() and true or false
		inCombat = InCombatLockdown()
		seedAutoRepeat()
		refreshWeapons()
		updateVisibility()
		updateRange()
	end,
	PLAYER_STARTED_MOVING = function() moving = true end,
	PLAYER_STOPPED_MOVING = function() moving = false end,
	START_AUTOREPEAT_SPELL = function() autoOn = true updateVisibility() end,
	STOP_AUTOREPEAT_SPELL = function() autoOn = false updateVisibility() end,
	PLAYER_REGEN_DISABLED = function() inCombat = true updateVisibility() end,
	PLAYER_REGEN_ENABLED = function() inCombat = false updateVisibility() end,
	PLAYER_DEAD = function()
		for _, row in ipairs(rows) do row.start = nil end
		autoOn = false
		updateVisibility()
	end,
}
events.UNIT_RANGEDDAMAGE = events.UNIT_ATTACK_SPEED -- ranged haste (Rapid Fire, Quick Shots) reports here

for event in pairs(events) do holder:RegisterEvent(event) end
holder:SetScript("OnEvent", function(_, event, ...)
	if ns.db then events[event](...) end -- nothing to draw before SavedVariables load
end)
