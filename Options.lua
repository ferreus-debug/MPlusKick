local _, ns = ...

local A = ns.ACCENT
local FLAT = "Interface\\Buttons\\WHITE8X8"
local QUESTION_ICON = 134400
local MY_MOBS = 0 -- dungeon index used for the player's own list

local win
local selected = 1
local checks = {}
local dungeonButtons = {}
local rows = {}

local function SectionLabel(parent, text)
	local fs = ns.Text(parent, 10, "OUTLINE")
	fs:SetTextColor(0.55, 0.55, 0.6)
	fs:SetText(text)
	return fs
end

local function Divider(parent, x1, y, width)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetColorTexture(1, 1, 1, 0.06)
	t:SetPoint("TOPLEFT", x1, y)
	t:SetSize(width, 1)
	return t
end

local function MyMobsSorted()
	local list = {}
	for _, e in pairs(ns.db.mobs) do list[#list + 1] = { e.name, e.note or "", mine = true } end
	table.sort(list, function(a, b) return a[1] < b[1] end)
	return list
end

local function CountMine()
	local n = 0
	for _ in pairs(ns.db.mobs) do n = n + 1 end
	return n
end

--------------------------------------------------------------------------
-- Mob list rows
--------------------------------------------------------------------------

local ROW_H = 40

local function GetRow(i)
	if rows[i] then return rows[i] end
	local child = win.scroll:GetScrollChild()
	local r = CreateFrame("Frame", nil, child)
	r:SetHeight(ROW_H)
	r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	r:SetPoint("RIGHT", child, "RIGHT")
	r:EnableMouse(true)

	r.bg = r:CreateTexture(nil, "BACKGROUND")
	r.bg:SetAllPoints()
	r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)

	r.hl = r:CreateTexture(nil, "HIGHLIGHT")
	r.hl:SetAllPoints()
	r.hl:SetColorTexture(A[1], A[2], A[3], 0.08)

	r.name = ns.Text(r, 12)
	r.name:SetPoint("TOPLEFT", 8, -6)
	r.name:SetPoint("RIGHT", -28, 0)
	r.name:SetWordWrap(false)

	r.note = ns.Text(r, 11)
	r.note:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
	r.note:SetPoint("RIGHT", -8, 0)
	r.note:SetTextColor(0.62, 0.62, 0.66)
	r.note:SetWordWrap(false)

	r.remove = ns.FlatButton(r, "×", 18, 18, function(self)
		ns.RemoveMob(self:GetParent().mobName)
	end)
	r.remove:SetPoint("TOPRIGHT", -6, -6)

	r:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.mobName, 1, 1, 1)
		GameTooltip:AddLine(self.mobNote, A[1], A[2], A[3], true)
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", GameTooltip_Hide)

	rows[i] = r
	return r
end

local function RefreshList()
	local list, title
	if selected == MY_MOBS then
		list, title = MyMobsSorted(), "MY MOBS"
	else
		local d = ns.Dungeons[selected]
		list, title = d.mobs, d.name:upper()
	end
	win.listTitle:SetText(title)

	for i, mob in ipairs(list) do
		local r = GetRow(i)
		r.mobName, r.mobNote = mob[1], mob[2]
		r.name:SetText(mob[1])
		local override = ns.db.mobs[mob[1]:lower()]
		if override and not mob.mine then
			r.name:SetText(mob[1] .. "  |cff888888(overridden)|r")
		end
		r.note:SetText(mob[2])
		if mob[2]:find("^Boss") then
			r.name:SetTextColor(A[1], A[2], A[3])
		else
			r.name:SetTextColor(1, 1, 1)
		end
		r.remove:SetShown(mob.mine == true)
		r:Show()
	end
	for i = #list + 1, #rows do rows[i]:Hide() end
	win.scroll:GetScrollChild():SetHeight(math.max(1, #list * ROW_H))

	win.empty:SetShown(#list == 0)
end

--------------------------------------------------------------------------
-- Refresh everything that depends on state
--------------------------------------------------------------------------

function ns.RefreshOptions()
	if not win or not win:IsShown() then return end

	local id = ns.GetKickSpell()
	if id then
		win.kickIcon:SetTexture(C_Spell.GetSpellTexture(id))
		win.kickName:SetText(C_Spell.GetSpellName(id))
	else
		win.kickIcon:SetTexture(QUESTION_ICON)
		win.kickName:SetText("No interrupt found")
	end

	local kick, focus = GetBindingKey(ns.KICK_BINDING), GetBindingKey(ns.FOCUS_BINDING)
	win.kickKey:SetText("Kick key:  " .. (kick and ("|cffffffff" .. kick .. "|r") or "|cffff5555not bound|r"))
	win.focusKey:SetText("Focus key: " .. (focus and ("|cffffffff" .. focus .. "|r") or "|cff888888not bound|r"))
	win.bindHint:SetShown(not kick)

	for _, c in ipairs(checks) do c:Refresh() end
	win.scaleValue:SetText(("%d%%"):format(math.floor(ns.db.scale * 100 + 0.5)))

	for i, b in ipairs(dungeonButtons) do
		local idx = b.index
		local on = idx == selected
		b.stripe:SetShown(on)
		b:SetBackdropColor(on and 0.16 or 0.1, on and 0.16 or 0.1, on and 0.18 or 0.12, 1)
		b.label:SetTextColor(on and 1 or 0.8, on and 1 or 0.8, on and 1 or 0.8)
		b.count:SetText(idx == MY_MOBS and CountMine() or #ns.Dungeons[idx].mobs)
	end

	RefreshList()
end

--------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------

local function BuildLeftColumn()
	local x = 18

	local lbl = SectionLabel(win, "YOUR INTERRUPT")
	lbl:SetPoint("TOPLEFT", x, -62)

	local iconBorder = CreateFrame("Frame", nil, win, "BackdropTemplate")
	iconBorder:SetSize(42, 42)
	iconBorder:SetPoint("TOPLEFT", x, -80)
	ns.Skin(iconBorder, 1, 0)
	win.kickIcon = iconBorder:CreateTexture(nil, "ARTWORK")
	win.kickIcon:SetPoint("TOPLEFT", 1, -1)
	win.kickIcon:SetPoint("BOTTOMRIGHT", -1, 1)
	win.kickIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	win.kickName = ns.Text(win, 14)
	win.kickName:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 10, -2)

	win.kickKey = ns.Text(win, 11)
	win.kickKey:SetPoint("TOPLEFT", win.kickName, "BOTTOMLEFT", 0, -4)
	win.kickKey:SetTextColor(0.7, 0.7, 0.7)

	win.focusKey = ns.Text(win, 11)
	win.focusKey:SetPoint("TOPLEFT", win.kickKey, "BOTTOMLEFT", 0, -2)
	win.focusKey:SetTextColor(0.7, 0.7, 0.7)

	win.bindHint = ns.Text(win, 10)
	win.bindHint:SetPoint("TOPLEFT", x, -130)
	win.bindHint:SetWidth(212)
	win.bindHint:SetTextColor(1, 0.4, 0.4)
	win.bindHint:SetText("Bind it: Esc > Options > Keybindings > AddOns > MPlusKick")

	Divider(win, x, -154, 212)

	local opt = SectionLabel(win, "OPTIONS")
	opt:SetPoint("TOPLEFT", x, -168)

	local defs = {
		{ "Casting panel (shows who is casting)", "panel", true },
		{ "Panel only in dungeons", "panelDungeonOnly", true },
		{ "Fade lit tiles out of kick range", "rangeFade" },
		{ "Hover a panel tile to select its mob", "hoverSelect", true },
		{ "Interrupt tracker (panel footer)", "kickLog", true },
		{ "Center cast alerts", "centerCards" },
		{ "Alert on all enemy casts", "alertAll" },
		{ "KICK tag on casting nameplates", "plateMarkers" },
		{ "Hide casts while kick is on cooldown", "hideOnCD", "cd" },
		{ "Alert sound", "sound" },
		{ "Priority mob toasts", "toasts" },
		{ "Show kick button", "showButton", true },
		{ "Unlock frames (drag to move)", "locked", true, true },
	}
	for i, d in ipairs(defs) do
		local key, applies, inverted = d[2], d[3], d[4]
		local c = ns.CheckBox(win, d[1],
			function() if inverted then return not ns.db[key] end return ns.db[key] end,
			function(v)
				if inverted then v = not v end
				ns.db[key] = v
				if applies == "cd" then ns.UpdateKickReady()
				elseif applies then ns.ApplySettings() end
			end)
		c:SetPoint("TOPLEFT", x, -186 - (i - 1) * 24)
		checks[#checks + 1] = c
	end

	local scaleLbl = ns.Text(win, 12)
	scaleLbl:SetPoint("TOPLEFT", x, -506)
	scaleLbl:SetText("Button scale")

	local function Step(delta)
		ns.db.scale = math.min(2, math.max(0.5, ns.db.scale + delta))
		ns.ApplySettings()
		ns.RefreshOptions()
	end
	local plus = ns.FlatButton(win, "+", 22, 20, function() Step(0.1) end)
	plus:SetPoint("TOPLEFT", x + 190, -502)
	win.scaleValue = ns.Text(win, 12)
	win.scaleValue:SetPoint("RIGHT", plus, "LEFT", -8, 0)
	win.scaleValue:SetJustifyH("RIGHT")
	local minus = ns.FlatButton(win, "-", 22, 20, function() Step(-0.1) end)
	minus:SetPoint("RIGHT", plus, "LEFT", -46, 0)

	Divider(win, x, -536, 212)

	local tools = SectionLabel(win, "TOOLS")
	tools:SetPoint("TOPLEFT", x, -550)

	local test = ns.FlatButton(win, "Test alerts", 212, 26, function() ns.TestAlerts() end)
	test:SetPoint("TOPLEFT", x, -568)
	local reset = ns.FlatButton(win, "Reset positions", 212, 26, function() ns.ResetPositions() end)
	reset:SetPoint("TOPLEFT", x, -600)

	local help = ns.Text(win, 10)
	help:SetPoint("TOPLEFT", x, -638)
	help:SetWidth(212)
	help:SetTextColor(0.5, 0.5, 0.55)
	help:SetText("Pre-pull: shift-click the priority mob to focus it. In combat: press the kick key when the KICK FOCUS alert fires.")
end

local function BuildDungeonColumn()
	local x = 254
	local lbl = SectionLabel(win, "DUNGEONS")
	lbl:SetPoint("TOPLEFT", x, -62)

	local order = {}
	for i = 1, #ns.Dungeons do order[#order + 1] = i end
	order[#order + 1] = MY_MOBS

	for i, idx in ipairs(order) do
		local b = CreateFrame("Button", nil, win, "BackdropTemplate")
		b:SetSize(176, 30)
		local y = -80 - (i - 1) * 33
		if idx == MY_MOBS then y = y - 10 end
		b:SetPoint("TOPLEFT", x, y)
		ns.Skin(b, 1, 0.1)
		b.index = idx

		b.stripe = b:CreateTexture(nil, "ARTWORK")
		b.stripe:SetColorTexture(A[1], A[2], A[3], 1)
		b.stripe:SetPoint("TOPLEFT", 1, -1)
		b.stripe:SetPoint("BOTTOMLEFT", 1, 1)
		b.stripe:SetWidth(3)

		b.label = ns.Text(b, 12)
		b.label:SetPoint("LEFT", 12, 0)
		b.label:SetText(idx == MY_MOBS and "My mobs" or ns.Dungeons[idx].name)

		b.count = ns.Text(b, 11)
		b.count:SetPoint("RIGHT", -10, 0)
		b.count:SetJustifyH("RIGHT")
		b.count:SetTextColor(0.5, 0.5, 0.55)

		b:SetScript("OnClick", function(self)
			selected = self.index
			win.scroll:SetVerticalScroll(0)
			ns.RefreshOptions()
		end)
		b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(A[1], A[2], A[3], 1) end)
		b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0, 0, 0, 1) end)
		dungeonButtons[#dungeonButtons + 1] = b
	end
end

local function BuildListColumn()
	local x, width = 448, 296

	win.listTitle = SectionLabel(win, "")
	win.listTitle:SetPoint("TOPLEFT", x, -62)

	local box = CreateFrame("Frame", nil, win, "BackdropTemplate")
	box:SetPoint("TOPLEFT", x, -80)
	box:SetSize(width, 560)
	ns.Skin(box, 1, 0.04)

	local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
	if not ok then scroll = CreateFrame("ScrollFrame", nil, box, "ScrollFrameTemplate") end
	scroll:SetPoint("TOPLEFT", 1, -1)
	scroll:SetPoint("BOTTOMRIGHT", -24, 1)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(width - 26, 1)
	scroll:SetScrollChild(child)
	win.scroll = scroll

	win.empty = ns.Text(box, 12)
	win.empty:SetPoint("CENTER", -10, 0)
	win.empty:SetWidth(230)
	win.empty:SetJustifyH("CENTER")
	win.empty:SetTextColor(0.5, 0.5, 0.55)
	win.empty:SetText("No mobs yet.\nTarget a mob, type a note below and press Add target.")

	local note = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
	note:SetSize(width - 104, 22)
	note:SetPoint("TOPLEFT", x + 6, -650)
	note:SetAutoFocus(false)
	note:SetMaxLetters(80)
	note:SetScript("OnEscapePressed", note.ClearFocus)
	note.placeholder = ns.Text(note, 11)
	note.placeholder:SetPoint("LEFT", 2, 0)
	note.placeholder:SetTextColor(0.45, 0.45, 0.5)
	note.placeholder:SetText("Note, e.g. Kick: Light Bolt")
	note:SetScript("OnTextChanged", function(self) self.placeholder:SetShown(self:GetText() == "") end)

	local add = ns.FlatButton(win, "Add target", 92, 24, function()
		if ns.AddTarget(note:GetText()) then
			note:SetText("")
			note:ClearFocus()
			selected = MY_MOBS
			ns.RefreshOptions()
		end
	end)
	add:SetPoint("LEFT", note, "RIGHT", 6, 0)
	note:SetScript("OnEnterPressed", function() add:Click() end)
end

function ns.CreateOptions()
	win = CreateFrame("Frame", "MPlusKickOptions", UIParent, "BackdropTemplate")
	win:SetSize(762, 690)
	win:SetPoint("CENTER")
	win:SetFrameStrata("DIALOG")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:SetMovable(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", win.StopMovingOrSizing)
	ns.Skin(win, 0.97)
	win:Hide()
	tinsert(UISpecialFrames, "MPlusKickOptions") -- close with Escape

	local header = win:CreateTexture(nil, "ARTWORK")
	header:SetPoint("TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", -1, -1)
	header:SetHeight(44)
	header:SetColorTexture(1, 1, 1, 0.03)

	local line = win:CreateTexture(nil, "ARTWORK")
	line:SetPoint("TOPLEFT", 1, -45)
	line:SetPoint("TOPRIGHT", -1, -45)
	line:SetHeight(2)
	line:SetTexture(FLAT)
	line:SetGradient("HORIZONTAL", CreateColor(A[1], A[2], A[3], 1), CreateColor(A[1], A[2], A[3], 0))

	local title = ns.Text(win, 18, "OUTLINE")
	title:SetPoint("TOPLEFT", 18, -13)
	title:SetText("MPlus|cffff7326Kick|r")

	local sub = ns.Text(win, 11)
	sub:SetPoint("LEFT", title, "RIGHT", 12, -1)
	sub:SetTextColor(0.55, 0.55, 0.6)
	sub:SetText("Mythic+ interrupt helper  ·  Midnight Season 2")

	local credit = ns.Text(win, 11)
	credit:SetPoint("RIGHT", win, "TOPRIGHT", -46, -22)
	credit:SetJustifyH("RIGHT")
	credit:SetTextColor(0.55, 0.55, 0.6)
	credit:SetText("Created by |cffff7326Netheron|r")

	local close = ns.FlatButton(win, "×", 24, 24, function() win:Hide() end)
	close:SetPoint("TOPRIGHT", -10, -10)
	close.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 16, "")

	BuildLeftColumn()
	BuildDungeonColumn()
	BuildListColumn()

	win:SetScript("OnShow", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
		ns.RefreshOptions()
	end)
	win:SetScript("OnHide", function() PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE) end)

	-- Blizzard Settings > AddOns entry that opens the window.
	pcall(function()
		local panel = CreateFrame("Frame")
		local t = ns.Text(panel, 16)
		t:SetPoint("TOPLEFT", 16, -16)
		t:SetText("MPlus|cffff7326Kick|r")
		local b = ns.FlatButton(panel, "Open MPlusKick", 160, 26, function()
			if SettingsPanel then HideUIPanel(SettingsPanel) end
			win:Show()
		end)
		b:SetPoint("TOPLEFT", 16, -48)
		local by = ns.Text(panel, 12)
		by:SetPoint("TOPLEFT", 16, -84)
		by:SetTextColor(0.7, 0.7, 0.7)
		by:SetText("Created by |cffff7326Netheron|r")
		local category = Settings.RegisterCanvasLayoutCategory(panel, "MPlusKick")
		Settings.RegisterAddOnCategory(category)
	end)
end

function ns.ToggleOptions()
	win:SetShown(not win:IsShown())
end

-- Addon compartment (the addon list button on the minimap).
function MPlusKick_OnCompartmentClick()
	ns.ToggleOptions()
end
