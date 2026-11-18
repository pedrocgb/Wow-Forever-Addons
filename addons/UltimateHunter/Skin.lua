-- Flat, dark widget kit (from MacroBuilderEnhanced/Skin.lua, hunter-green accent).
-- Everything the addon's windows draw goes through here so the look stays consistent.
local _, ns = ...
local S = {}
ns.Skin = S

local WHITE = "Interface\\Buttons\\WHITE8X8"
local ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
S.QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
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
	accent = { 0.67, 0.83, 0.45, 1 },
	accentHover = { 0.76, 0.9, 0.56, 1 },
	accentSoft = { 0.67, 0.83, 0.45, 0.16 },
	info = { 0.45, 0.67, 1, 1 },
	silver = { 0.8, 0.82, 0.87, 1 },
	danger = { 0.93, 0.36, 0.36, 1 },
	warn = { 1, 0.72, 0.28, 1 },
	success = { 0.35, 0.8, 0.52, 1 },
}
local C = S.C

-- "|cffrrggbb" for inline colouring.
function S.Hex(c)
	return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

local fonts = {}
function S.Font(size)
	if not fonts[size] then
		local f = CreateFont("UltimateHunterFont" .. size)
		f:SetFont(FONT, size, "")
		f:SetShadowOffset(0, 0)
		f:SetTextColor(unpack(C.text))
		fonts[size] = f
	end
	return fonts[size]
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

-- Single-line text that truncates instead of overflowing.
function S.Line(parent, size, color, width)
	local fs = S.Text(parent, size, color)
	fs:SetWordWrap(false)
	fs:SetMaxLines(1)
	if width then fs:SetWidth(width) end
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
	primary = { C.accent, C.accentHover, C.accent, { 0.07, 0.08, 0.1, 1 } },
	ghost = { { 0, 0, 0, 0 }, C.hover, { 0, 0, 0, 0 }, C.muted },
}

-- kind: default | primary | ghost.
function S.Button(parent, text, w, h, kind, onClick)
	local st = BUTTON_STYLES[kind or "default"]
	local b = S.Frame(parent, st[1], st[3], "Button")
	b:SetSize(w, h or 26)
	local label = S.Text(b, 12, st[4], text)
	b:SetFontString(label)
	label:SetPoint("CENTER")
	label:SetJustifyH("CENTER")
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

-- Options: list of { value, label }, or a function returning one.
-- "" is the "nothing chosen" value and shows the placeholder in muted text.
function S.Dropdown(parent, w, options, get, set, placeholder)
	local d = CreateFrame("DropdownButton", nil, parent, "BackdropTemplate")
	S.Backdrop(d, C.raised)
	d:SetSize(w, 26)
	d.text = S.Line(d, 12)
	d.text:SetPoint("LEFT", 8, 0)
	d.text:SetPoint("RIGHT", -22, 0)
	local a = d:CreateTexture(nil, "ARTWORK")
	a:SetTexture(ARROW)
	a:SetSize(12, 12)
	a:SetRotation(-math.pi / 2)
	a:SetVertexColor(unpack(C.muted))
	a:SetPoint("RIGHT", -8, 0)
	d:SetMenuAnchor(AnchorUtil.CreateAnchor("TOPLEFT", d, "BOTTOMLEFT", 0, -2))
	d:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(C.accent)) end)
	d:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(C.border)) end)
	local function resolve() return type(options) == "function" and options() or options end
	function d:Refresh()
		local v, label = get() or "", nil
		for _, o in ipairs(resolve()) do if o[1] == v then label = o[2] end end
		d.text:SetText(label or (v == "" and (placeholder or "Any")) or v)
		d.text:SetTextColor(unpack(v == "" and C.muted or C.text))
	end
	d:SetupMenu(function(_, root)
		root:SetScrollMode(420)
		for _, o in ipairs(resolve()) do
			root:CreateRadio(o[2], function() return (get() or "") == o[1] end, function() set(o[1]) d:Refresh() end)
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

-- Scroll frame with a minimal bar on its right; content goes in sf.child (set its width).
function S.ScrollArea(parent)
	local sf = CreateFrame("ScrollFrame", nil, parent)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(1, 1)
	sf:SetScrollChild(child)
	local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 6, 0)
	bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 6, 0)
	ScrollUtil.InitScrollFrameWithScrollBar(sf, bar)
	sf.child = child
	return sf
end

------------------------------------------------------------------------------- small widgets
-- Filled circle (colour texture under a round mask). Recolour with SetVertexColor.
function S.Circle(parent, size, color, layer)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetColorTexture(1, 1, 1, 1)
	t:SetSize(size, size)
	local m = parent:CreateMaskTexture()
	m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	m:SetAllPoints(t)
	t:AddMaskTexture(m)
	t:SetVertexColor(unpack(color))
	return t
end

-- Numbered accent circle.
function S.Badge(parent, n, size)
	size = size or 20
	local dot = S.Circle(parent, size, C.accent)
	local fs = S.Text(parent, 11, C.bg, tostring(n))
	fs:SetJustifyH("CENTER")
	fs:SetPoint("CENTER", dot, "CENTER", 0, 0)
	return dot
end

-- Tinted pill. pill:Set(text, color, onClick); pill.w is its width after Set.
function S.Pill(parent)
	local p = S.Frame(parent, C.raised, C.border, "Button")
	p:SetHeight(18)
	p.text = S.Line(p, 11)
	p.text:SetPoint("CENTER")
	local function tint(self, a)
		local c = self.color
		self:SetBackdropColor(c[1], c[2], c[3], 0.14)
		self:SetBackdropBorderColor(c[1], c[2], c[3], a)
	end
	function p:Set(text, color, onClick)
		self.color, self.onClick = color or C.muted, onClick
		self.text:SetText(text)
		self.text:SetTextColor(unpack(self.color))
		self.w = math.floor(self.text:GetStringWidth() + 14.5)
		self:SetWidth(self.w)
		self:EnableMouse(onClick ~= nil)
		tint(self, 0.35)
	end
	p:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
	p:SetScript("OnEnter", function(self) tint(self, 1) end)
	p:SetScript("OnLeave", function(self) tint(self, 0.35) end)
	p:Set("")
	return p
end

-- Thin progress bar: bar:Set(cur, max, color).
function S.ProgressBar(parent, h)
	local f = S.Frame(parent, C.bg)
	f:SetHeight(h or 8)
	local sb = CreateFrame("StatusBar", nil, f)
	sb:SetPoint("TOPLEFT", 1, -1)
	sb:SetPoint("BOTTOMRIGHT", -1, 1)
	sb:SetStatusBarTexture(WHITE)
	function f:Set(cur, max, color)
		sb:SetMinMaxValues(0, (max and max > 0) and max or 1)
		sb:SetValue(cur or 0)
		sb:SetStatusBarColor(unpack(color or C.accent))
	end
	f:Set(0, 1)
	return f
end

-- Square icon with a 1px border: tile:SetIcon(texture).
function S.IconTile(parent, size)
	local f = S.Frame(parent, C.bg)
	f:SetSize(size, size)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetPoint("TOPLEFT", 1, -1)
	f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	function f:SetIcon(tex) self.icon:SetTexture(tex or S.QUESTION) end
	return f
end

-- Raised surface. Clickable cards (a Button) highlight on hover while card.onClick is set.
function S.Card(parent, clickable)
	local f = S.Frame(parent, C.raised, C.border, clickable and "Button" or nil)
	if clickable then
		f:SetScript("OnEnter", function(self)
			if not self.onClick then return end
			self:SetBackdropColor(unpack(C.hover))
			self:SetBackdropBorderColor(unpack(C.accent))
		end)
		f:SetScript("OnLeave", function(self)
			self:SetBackdropColor(unpack(C.raised))
			self:SetBackdropBorderColor(unpack(C.border))
		end)
		f:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
	end
	return f
end

-- 14px title with an 11px muted helper line under it (title.help). About 32px tall.
function S.SectionTitle(parent, title, help)
	local t = S.Text(parent, 14, C.text, title)
	t.help = S.Text(parent, 11, C.muted, help)
	t.help:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -5)
	return t
end

-- Sidebar/list entry: icon tile + label; item:SetSelected(on). Label set with item:SetText.
function S.NavItem(parent, h, iconSize, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(h)
	b.fill = S.Fill(b, C.hover)
	b.fill:SetAllPoints()
	b.fill:Hide()
	b.bar = S.Fill(b, C.accent, "ARTWORK")
	b.bar:SetPoint("TOPLEFT")
	b.bar:SetPoint("BOTTOMLEFT")
	b.bar:SetWidth(2)
	b.bar:Hide()
	b.tile = S.IconTile(b, iconSize)
	b.tile:SetPoint("LEFT", 12, 0)
	b.label = S.Line(b, 13)
	b:SetFontString(b.label)
	b.label:ClearAllPoints()
	b.label:SetPoint("LEFT", b.tile, "RIGHT", 10, 0)
	b.label:SetPoint("RIGHT", -8, 0)
	function b:SetSelected(on)
		self.selected = on
		self.fill:SetColorTexture(unpack(on and C.accentSoft or C.hover))
		self.fill:SetShown(on)
		self.bar:SetShown(on)
		self.label:SetTextColor(unpack(on and C.accent or C.text))
	end
	b:SetScript("OnEnter", function(self) if not self.selected then self.fill:Show() end end)
	b:SetScript("OnLeave", function(self) if not self.selected then self.fill:Hide() end end)
	b:SetScript("OnClick", onClick)
	b:SetSelected(false)
	return b
end

-- Centered empty state: big muted icon, title, wrapped hint. empty:Set(icon, title, hint).
function S.Empty(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(380, 150)
	f.tile = S.IconTile(f, 56)
	f.tile:SetPoint("TOP")
	f.tile:SetAlpha(0.6)
	f.tile.icon:SetDesaturated(true)
	f.title = S.Text(f, 14, C.text)
	f.title:SetPoint("TOP", f.tile, "BOTTOM", 0, -14)
	f.hint = S.Text(f, 12, C.muted)
	f.hint:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
	f.hint:SetWidth(380)
	f.hint:SetJustifyH("CENTER")
	f.hint:SetWordWrap(true)
	function f:Set(icon, title, hint)
		self.tile:SetIcon(icon)
		self.title:SetText(title)
		self.hint:SetText(hint or "")
		self:Show()
	end
	return f
end

------------------------------------------------------------------------------- windows
-- ESC handling: one hidden frame sits in UISpecialFrames. When the game hides it on ESC we close
-- the topmost window and re-arm it while any window stays open.
local escStack = {}
local catcher = CreateFrame("Frame", "UltimateHunterEscCatcher", UIParent)
catcher:Hide()
tinsert(UISpecialFrames, catcher:GetName())
catcher:SetScript("OnHide", function(self)
	local top = escStack[#escStack]
	if top then top:Hide() end
	if #escStack > 0 then self:Show() end
end)

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
	f.subtitle = S.Text(bar, 11, C.muted)
	f.subtitle:SetPoint("LEFT", f.title, "RIGHT", 10, -1)
	local close = S.CloseButton(bar, function() f:Hide() end)
	close:SetPoint("RIGHT", -10, 0)
	f.bar = bar

	f:HookScript("OnShow", function()
		tDeleteItem(escStack, f)
		escStack[#escStack + 1] = f
		catcher:Show()
	end)
	f:HookScript("OnHide", function()
		tDeleteItem(escStack, f)
		if #escStack == 0 then catcher:Hide() end
	end)
	return f
end
