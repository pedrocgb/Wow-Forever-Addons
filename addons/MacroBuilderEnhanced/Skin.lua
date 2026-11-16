-- Flat, dark widget kit. Everything the addon draws goes through here so the look stays consistent.
local _, ns = ...
local S = {}
ns.Skin = S

local WHITE = "Interface\\Buttons\\WHITE8X8"
local ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"
local LATIN = { enUS = 1, enGB = 1, deDE = 1, frFR = 1, esES = 1, esMX = 1, itIT = 1, ptBR = 1 }
local FONT = LATIN[GetLocale()] and "Fonts\\ARIALN.TTF" or STANDARD_TEXT_FONT

S.C = {
	bg = { 0.071, 0.078, 0.098, 0.97 },
	surface = { 0.098, 0.106, 0.133, 1 },
	raised = { 0.129, 0.141, 0.176, 1 },
	hover = { 0.165, 0.18, 0.224, 1 },
	border = { 0.2, 0.216, 0.263, 1 },
	text = { 0.93, 0.94, 0.96, 1 },
	muted = { 0.55, 0.59, 0.66, 1 },
	accent = { 0.31, 0.56, 1, 1 },
	accentHover = { 0.43, 0.65, 1, 1 },
	accentSoft = { 0.31, 0.56, 1, 0.18 },
	danger = { 0.93, 0.36, 0.36, 1 },
	warn = { 1, 0.72, 0.28, 1 },
	success = { 0.35, 0.8, 0.52, 1 },
}
local C = S.C

local fonts = {}
function S.Font(size)
	local key = size
	if not fonts[key] then
		local f = CreateFont("MacroBuilderEnhancedFont" .. key)
		f:SetFont(FONT, size, "")
		f:SetShadowOffset(0, 0)
		f:SetTextColor(unpack(C.text))
		fonts[key] = f
	end
	return fonts[key]
end

function S.Backdrop(f, bg, border)
	if not f.SetBackdrop then Mixin(f, BackdropTemplateMixin) end
	f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	f:SetBackdropColor(unpack(bg))
	f:SetBackdropBorderColor(unpack(border or C.border))
end

function S.Frame(parent, bg, border, frameType)
	local f = CreateFrame(frameType or "Frame", nil, parent, "BackdropTemplate")
	if bg then S.Backdrop(f, bg, border) end
	return f
end

function S.Fill(parent, color, layer)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetColorTexture(unpack(color))
	return t
end

function S.Text(parent, size, color, text)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(S.Font(size or 12))
	fs:SetTextColor(unpack(color or C.text))
	fs:SetJustifyH("LEFT")
	if text then fs:SetText(text) end
	return fs
end

-- An "×" drawn with two rotated bars (no font glyph needed).
function S.CloseButton(parent, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(24, 24)
	local bars = {}
	for i, rot in ipairs({ math.pi / 4, -math.pi / 4 }) do
		local t = b:CreateTexture(nil, "ARTWORK")
		t:SetColorTexture(1, 1, 1, 1)
		t:SetSize(12, 1.5)
		t:SetPoint("CENTER")
		t:SetRotation(rot)
		t:SetVertexColor(unpack(C.muted))
		bars[i] = t
	end
	local bg = S.Fill(b, C.hover)
	bg:SetAllPoints()
	bg:Hide()
	b:SetScript("OnEnter", function() bg:Show() for _, t in ipairs(bars) do t:SetVertexColor(unpack(C.text)) end end)
	b:SetScript("OnLeave", function() bg:Hide() for _, t in ipairs(bars) do t:SetVertexColor(unpack(C.muted)) end end)
	b:SetScript("OnClick", onClick)
	return b
end

local BUTTON_STYLES = {
	default = { C.raised, C.hover, C.border, C.text },
	primary = { C.accent, C.accentHover, C.accent, { 1, 1, 1, 1 } },
	ghost = { { 0, 0, 0, 0 }, C.hover, { 0, 0, 0, 0 }, C.muted },
	danger = { { 0, 0, 0, 0 }, { 0.93, 0.36, 0.36, 0.15 }, { 0, 0, 0, 0 }, C.danger },
}

-- kind: default | primary | ghost | danger. icon: optional texture shown left of the label.
function S.Button(parent, text, w, h, kind, onClick, icon)
	local st = BUTTON_STYLES[kind or "default"]
	local b = S.Frame(parent, st[1], st[3], "Button")
	b:SetSize(w, h or 26)
	local label = S.Text(b, 12, st[4], text)
	b:SetFontString(label)
	if icon then
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize((h or 26) - 10, (h or 26) - 10)
		b.icon:SetPoint("LEFT", 6, 0)
		b.icon:SetTexture(icon)
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		label:ClearAllPoints()
		label:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
		label:SetPoint("RIGHT", -4, 0)
	else
		label:SetPoint("CENTER")
		label:SetJustifyH("CENTER")
	end
	b:SetScript("OnEnter", function(self) if self:IsEnabled() then self:SetBackdropColor(unpack(st[2])) end end)
	b:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(st[1])) end)
	b:SetScript("OnDisable", function(self) self:SetAlpha(0.4) end)
	b:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
	b:SetScript("OnClick", onClick)
	return b
end

-- Single-line input with placeholder and an accent border while focused.
function S.Input(parent, w, h, placeholder, onChange)
	local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
	S.Backdrop(e, C.raised)
	e:SetSize(w, h or 26)
	e:SetFontObject(S.Font(12))
	e:SetTextInsets(8, 8, 0, 0)
	e:SetAutoFocus(false)
	local ph = S.Text(e, 12, C.muted, placeholder)
	ph:SetPoint("LEFT", 8, 0)
	ph:SetPoint("RIGHT", -8, 0)
	local function update() ph:SetShown(e:GetText() == "" and not e:HasFocus()) end
	e:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(unpack(C.accent)) update() end)
	e:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(C.border)) update() end)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	e:SetScript("OnEnterPressed", e.ClearFocus)
	e:SetScript("OnTextChanged", function(self, user)
		update()
		if user and onChange then onChange(self:GetText()) end
	end)
	e.placeholder = ph
	function e:SetValue(v) self:SetText(v or "") update() end
	return e
end

local function arrow(parent)
	local a = parent:CreateTexture(nil, "ARTWORK")
	a:SetTexture(ARROW)
	a:SetSize(12, 12)
	a:SetRotation(-math.pi / 2)
	a:SetVertexColor(unpack(C.muted))
	return a
end

-- Options: list of { value, label } or { label = "Group", children = {...} } (submenu). May be a function.
local function findLabel(list, value)
	for _, o in ipairs(list) do
		if o.children then
			local l = findLabel(o.children, value)
			if l then return l end
		elseif o[1] == value then
			return o[2]
		end
	end
end

local function baseDropdown(parent, w)
	local d = CreateFrame("DropdownButton", nil, parent, "BackdropTemplate")
	S.Backdrop(d, C.raised)
	d:SetSize(w, 26)
	d.text = S.Text(d, 12)
	d.text:SetPoint("LEFT", 8, 0)
	d.text:SetPoint("RIGHT", -22, 0)
	d.text:SetWordWrap(false)
	local a = arrow(d)
	a:SetPoint("RIGHT", -8, 0)
	d:SetMenuAnchor(AnchorUtil.CreateAnchor("TOPLEFT", d, "BOTTOMLEFT", 0, -2))
	d:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(C.accent)) end)
	d:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(C.border)) end)
	return d
end

-- Single choice. "" is the "nothing chosen" value and shows the placeholder in muted text.
function S.Dropdown(parent, w, options, get, set, placeholder)
	local d = baseDropdown(parent, w)
	local function resolve() return type(options) == "function" and options() or options end
	function d:Refresh()
		local v = get() or ""
		local label = (v == d.lastValue and d.lastLabel) or findLabel(resolve(), v)
		d.text:SetText(label or (v == "" and (placeholder or "Any")) or v)
		d.text:SetTextColor(unpack(v == "" and C.muted or C.text))
	end
	local function add(root, list)
		for _, o in ipairs(list) do
			if o.children then
				local sub = root:CreateButton(o.label)
				sub:SetScrollMode(420)
				add(sub, o.children)
			else
				root:CreateRadio(o[2], function() return (get() or "") == o[1] end, function()
					d.lastValue, d.lastLabel = o[1], o[2]
					set(o[1])
					d:Refresh()
				end)
			end
		end
	end
	d:SetupMenu(function(_, root)
		root:SetScrollMode(420)
		add(root, resolve())
	end)
	d:Refresh()
	return d
end

-- Multi choice with checkboxes. summary() returns the button text.
function S.MultiDropdown(parent, w, options, isSelected, toggle, clear, summary)
	local d = baseDropdown(parent, w)
	function d:Refresh()
		local text, active = summary()
		d.text:SetText(text)
		d.text:SetTextColor(unpack(active and C.text or C.muted))
		d:SetBackdropColor(unpack(active and C.accentSoft or C.raised))
	end
	d:SetupMenu(function(_, root)
		root:SetScrollMode(420)
		root:CreateButton("Clear selection", function() clear() d:Refresh() end)
		root:CreateDivider()
		for _, o in ipairs(options) do
			root:CreateCheckbox(o[2], function() return isSelected(o[1]) end, function() toggle(o[1]) d:Refresh() end)
		end
	end)
	d:Refresh()
	return d
end

function S.Check(parent, text, get, set)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(20)
	local box = S.Frame(b, C.raised)
	box:SetSize(16, 16)
	box:SetPoint("LEFT")
	local mark = S.Fill(box, C.accent, "ARTWORK")
	mark:SetPoint("TOPLEFT", 3, -3)
	mark:SetPoint("BOTTOMRIGHT", -3, 3)
	local label = S.Text(b, 12, C.text, text)
	label:SetPoint("LEFT", box, "RIGHT", 8, 0)
	b:SetWidth(label:GetStringWidth() + 26)
	function b:Refresh() mark:SetShown(get() and true or false) end
	b:SetScript("OnClick", function(self) set(not get()) self:Refresh() end)
	b:SetScript("OnEnter", function() box:SetBackdropBorderColor(unpack(C.accent)) end)
	b:SetScript("OnLeave", function() box:SetBackdropBorderColor(unpack(C.border)) end)
	b:Refresh()
	return b
end

-- Segmented control: items = { {value, label} }.
function S.Segmented(parent, w, items, get, set)
	local f = S.Frame(parent, C.surface)
	f:SetSize(w, 28)
	local bw = (w - 4) / #items
	local buttons = {}
	function f:Refresh()
		for _, b in ipairs(buttons) do
			local on = get() == b.value
			b:SetBackdropColor(unpack(on and C.raised or { 0, 0, 0, 0 }))
			b:SetBackdropBorderColor(unpack(on and C.border or { 0, 0, 0, 0 }))
			b:GetFontString():SetTextColor(unpack(on and C.text or C.muted))
		end
	end
	for i, it in ipairs(items) do
		local b = S.Frame(f, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, "Button")
		b:SetSize(bw, 24)
		b:SetPoint("LEFT", 2 + (i - 1) * bw, 0)
		local fs = S.Text(b, 12, C.text, it[2])
		fs:SetJustifyH("CENTER")
		b:SetFontString(fs)
		b.value = it[1]
		b:SetScript("OnClick", function() set(it[1]) f:Refresh() end)
		buttons[i] = b
	end
	f.buttons = buttons
	f:Refresh()
	return f
end

function S.Scroll(box, parent)
	local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
	bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
	return bar
end

------------------------------------------------------------------------------- windows & modals
-- ESC handling: one hidden frame sits in UISpecialFrames. When the game hides it on ESC we close
-- the topmost thing (an open modal first, otherwise the window) and re-arm it if the window stays open.
local escStack = {}
local catcher = CreateFrame("Frame", "MacroBuilderEnhancedEscCatcher", UIParent)
catcher:Hide()
tinsert(UISpecialFrames, catcher:GetName())
catcher:SetScript("OnHide", function(self)
	local top = escStack[#escStack]
	if top then top:Hide() end
	if #escStack > 0 then self:Show() end
end)
local function pushEsc(frame)
	tDeleteItem(escStack, frame)
	escStack[#escStack + 1] = frame
	catcher:Show()
end
local function popEsc(frame)
	tDeleteItem(escStack, frame)
	if #escStack == 0 then catcher:Hide() end
end

function S.Window(name, w, h, title)
	local f = S.Frame(UIParent, C.bg)
	f:SetSize(w, h)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:Hide()
	_G[name] = f

	local bar = CreateFrame("Frame", nil, f)
	bar:SetPoint("TOPLEFT", 1, -1)
	bar:SetPoint("TOPRIGHT", -1, -1)
	bar:SetHeight(42)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function() f:StartMoving() end)
	bar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
	local line = S.Fill(bar, C.border, "ARTWORK")
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	line:SetHeight(1)
	local dot = S.Fill(bar, C.accent, "ARTWORK")
	dot:SetSize(4, 18)
	dot:SetPoint("LEFT", 14, 0)
	f.title = S.Text(bar, 15, C.text, title)
	f.title:SetPoint("LEFT", dot, "RIGHT", 10, 0)
	f.subtitle = S.Text(bar, 12, C.muted)
	f.subtitle:SetPoint("LEFT", f.title, "RIGHT", 10, 0)
	local close = S.CloseButton(bar, function() f:Hide() end)
	close:SetPoint("RIGHT", -10, 0)
	f.bar = bar

	f:HookScript("OnShow", function() pushEsc(f) end)
	f:HookScript("OnHide", function() popEsc(f) end)
	return f
end

S.modals = {}
function S.CloseModals()
	for _, m in ipairs(S.modals) do m:Close() end
end

-- Dims `parent` and shows a centered card on top of it. Returns the card; card.overlay is the dim layer.
function S.Modal(parent, w, h, title)
	local overlay = CreateFrame("Frame", nil, parent)
	overlay:SetAllPoints(parent)
	overlay:SetFrameLevel(parent:GetFrameLevel() + 50)
	overlay:EnableMouse(true)
	overlay:Hide()
	local dim = S.Fill(overlay, { 0, 0, 0, 0.6 })
	dim:SetAllPoints()

	local card = S.Frame(overlay, C.bg, C.border)
	card:SetSize(w, h)
	card:SetPoint("CENTER")
	card:EnableMouse(true)
	card.title = S.Text(card, 15, C.text, title)
	card.title:SetPoint("TOPLEFT", 18, -16)
	local close = S.CloseButton(card, function() overlay:Hide() end)
	close:SetPoint("TOPRIGHT", -10, -10)
	card.overlay = overlay
	S.modals[#S.modals + 1] = card
	function card:Open() overlay:Show() end
	function card:Close() overlay:Hide() end
	overlay:SetScript("OnShow", function() pushEsc(overlay) end)
	overlay:SetScript("OnHide", function() popEsc(overlay) if card.OnClose then card:OnClose() end end)
	return card
end

-- Small text prompt (rename, new folder). onAccept(text) returns an error string to keep it open.
local prompt
function S.Prompt(parent, title, label, default, onAccept)
	if not prompt or prompt.parent ~= parent then
		prompt = S.Modal(parent, 360, 150, "")
		prompt.parent = parent
		prompt.label = S.Text(prompt, 12, C.muted)
		prompt.label:SetPoint("TOPLEFT", 18, -46)
		prompt.input = S.Input(prompt, 324, 28)
		prompt.input:SetPoint("TOPLEFT", 18, -66)
		prompt.err = S.Text(prompt, 11, C.danger)
		prompt.err:SetPoint("TOPLEFT", prompt.input, "BOTTOMLEFT", 0, -4)
		local ok = S.Button(prompt, "OK", 90, 28, "primary", function() prompt:Accept() end)
		ok:SetPoint("BOTTOMRIGHT", -18, 14)
		S.Button(prompt, CANCEL, 80, 28, "ghost", function() prompt:Close() end):SetPoint("RIGHT", ok, "LEFT", -6, 0)
		prompt.input:SetScript("OnEnterPressed", function() prompt:Accept() end)
		function prompt:Accept()
			local text = strtrim(self.input:GetText())
			if text == "" then return end
			local err = self.onAccept(text)
			if err then self.err:SetText(err) else self:Close() end
		end
	end
	prompt.title:SetText(title)
	prompt.label:SetText(label)
	prompt.err:SetText("")
	prompt.onAccept = onAccept
	prompt.input:SetText(default or "")
	prompt:Open()
	prompt.input:SetFocus()
	prompt.input:HighlightText()
end

local confirm
function S.Confirm(parent, title, text, buttonText, onAccept)
	if not confirm or confirm.parent ~= parent then
		confirm = S.Modal(parent, 380, 140, "")
		confirm.parent = parent
		confirm.text = S.Text(confirm, 12, C.muted)
		confirm.text:SetPoint("TOPLEFT", 18, -46)
		confirm.text:SetWidth(344)
		confirm.text:SetWordWrap(true)
		confirm.ok = S.Button(confirm, "", 100, 28, "default", function() confirm:Close() confirm.onAccept() end)
		confirm.ok:SetPoint("BOTTOMRIGHT", -18, 14)
		confirm.ok:GetFontString():SetTextColor(unpack(C.danger))
		S.Button(confirm, CANCEL, 80, 28, "ghost", function() confirm:Close() end):SetPoint("RIGHT", confirm.ok, "LEFT", -6, 0)
	end
	confirm.title:SetText(title)
	confirm.text:SetText(text)
	confirm.ok:SetText(buttonText)
	confirm.onAccept = onAccept
	confirm:Open()
end
