local _, ns = ...

--------------------------------------------------------------------------
-- Casting panel: one tile per enemy nameplate, lit while that mob casts
-- something interruptible.
--
-- Midnight blocks addon buttons from acting on enemy nameplate units
-- (casting, focusing and targeting "nameplateN" all do nothing, and macro
-- conditions treat [@nameplateN] as non-existent), so tiles can't kick on
-- click. The kick comes from the player's key: [@mouseover] is resolved by
-- the game itself.
--
-- Hover-select: each tile is a secure *unit* button for its nameplate, like
-- a raid frame. Hovering a unit frame makes the game set "mouseover" to
-- that unit, so hovering a lit tile and pressing the kick key kicks that
-- mob without finding it on screen (confirmed in game inside a Midnight
-- key). Clicks do nothing.
--
-- Unlocked, the panel can be dragged, resized from the corner grip, and
-- its columns / tile count changed from the edit bar. The tiles are secure
-- frames, so layout changes wait until combat ends.
--------------------------------------------------------------------------

local A = ns.ACCENT
local FLAT = "Interface\\Buttons\\WHITE8X8"
local QUESTION_ICON = 134400

local MAX_TILES = 40
local GAP, PAD, HEADER = 4, 6, 22
local MIN_W, MAX_W, MIN_H, MAX_H = 70, 400, 22, 90

local panel, editBar, grip, footer
local tiles = {}

-- Interrupt tracker footer: title row + 5 players + "unattributed".
local FOOTER_ROWS, ROW_H, FOOTER_TITLE = 6, 14, 20
local FOOTER_H = FOOTER_TITLE + FOOTER_ROWS * ROW_H + 4
local CreateFooter
local pendingLayout, pendingApply = false, false

-- Lit tiles out of kick range fade to this alpha.
local OUT_OF_RANGE_ALPHA = 0.25

local function TileUnit(i) return "nameplate" .. i end

local function Settings()
	local db = ns.db
	return db.panelCols or 2, db.panelTiles or 20, db.panelTileW or 150, db.panelTileH or 40
end

local function CreateTile(i)
	local unit = TileUnit(i)
	local b = CreateFrame("Button", "MPlusKickTile" .. i, panel, "SecureUnitButtonTemplate")
	-- The "unit" attribute is what lets the game treat hovering this tile as
	-- hovering the mob. No click actions are set: clicks do nothing.
	b:SetAttribute("unit", unit)
	b:RegisterForClicks()
	b:EnableMouse(ns.db.hoverSelect)
	b.unit = unit

	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.12)

	-- Debug: report whether hovering this tile really selected its mob.
	b:HookScript("OnEnter", function(self)
		if not ns.db.debug then return end
		C_Timer.After(0.05, function()
			local exists = ns.Readable(UnitExists("mouseover"))
			local same = ns.Readable(UnitIsUnit("mouseover", self.unit))
			ns.Print(("tile %d hover: mouseover exists=%s, is %s=%s"):format(
				i, exists == nil and "secret" or tostring(exists), self.unit,
				same == nil and "secret" or tostring(same)))
		end)
	end)

	-- Idle layer: which mob sits on this nameplate (dim).
	local base = CreateFrame("Frame", nil, b, "BackdropTemplate")
	base:SetAllPoints()
	base:EnableMouse(false)
	ns.Skin(base, 0.8, 0.08)
	base.name = ns.Text(base, 11)
	base.name:SetPoint("LEFT", 8, 0)
	base.name:SetPoint("RIGHT", -6, 0)
	base.name:SetWordWrap(false)
	base.name:SetTextColor(0.55, 0.55, 0.6)
	base:SetAlpha(0)
	b.base = base

	-- Cast layer: cooldown gate > range gate > interruptible gate > visuals.
	local cdGate = CreateFrame("Frame", nil, b)
	cdGate:SetAllPoints()
	cdGate:EnableMouse(false)
	b.cdGate = cdGate

	local rangeGate = CreateFrame("Frame", nil, cdGate)
	rangeGate:SetAllPoints()
	rangeGate:EnableMouse(false)
	b.rangeGate = rangeGate

	local cast = CreateFrame("Frame", nil, rangeGate)
	cast:SetAllPoints()
	cast:EnableMouse(false)
	cast:Hide()
	b.cast = cast

	local inner = CreateFrame("Frame", nil, cast, "BackdropTemplate")
	inner:SetAllPoints()
	inner:EnableMouse(false)
	ns.Skin(inner, 0.96, 0.1)
	inner:SetBackdropBorderColor(A[1], A[2], A[3], 1)
	b.glow = ns.AccentBorder(inner, 2)
	b.glow:EnableMouse(false)

	local iconBorder = CreateFrame("Frame", nil, inner, "BackdropTemplate")
	iconBorder:SetPoint("LEFT", 5, 1)
	iconBorder:EnableMouse(false)
	ns.Skin(iconBorder, 1, 0)
	b.iconBorder = iconBorder
	b.icon = iconBorder:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	b.caster = ns.Text(inner, 11, "OUTLINE")
	b.caster:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 6, -1)
	b.caster:SetPoint("RIGHT", -5, 0)
	b.caster:SetWordWrap(false)

	b.spell = ns.Text(inner, 10)
	b.spell:SetPoint("TOPLEFT", b.caster, "BOTTOMLEFT", 0, -3)
	b.spell:SetPoint("RIGHT", -5, 0)
	b.spell:SetWordWrap(false)
	b.spell:SetTextColor(A[1], A[2], A[3])

	local bar = CreateFrame("StatusBar", nil, inner)
	bar:SetStatusBarTexture(FLAT)
	bar:SetStatusBarColor(A[1], A[2], A[3])
	bar:SetHeight(3)
	b.bar = bar

	-- Health: its own frame above the idle and cast layers so it shows in
	-- both states. The cast bar sits right on top of it (see Layout).
	b.hp = ns.CreateHealthStrip(b)
	b.hp:SetFrameLevel(b:GetFrameLevel() + 10)
	b.hp:SetPoint("BOTTOMLEFT", 1, 1)
	b.hp:SetPoint("BOTTOMRIGHT", -1, 1)
	b.hp:Hide()

	-- Raid marker, top-right, above every layer.
	local overlay = CreateFrame("Frame", nil, b)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(b:GetFrameLevel() + 11)
	overlay:EnableMouse(false)
	b.marker = overlay:CreateTexture(nil, "OVERLAY")
	b.marker:SetPoint("TOPRIGHT", -2, -2)
	b.marker:Hide()

	tiles[i] = b
	return b
end

--------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------

local function Layout()
	if InCombatLockdown() then
		pendingLayout = true
		return
	end
	pendingLayout = false

	local cols, count, tw, th = Settings()
	cols = math.min(cols, count)
	local rows = math.ceil(count / cols)
	local tilesBottom = HEADER + rows * (th + GAP) - GAP
	-- The footer's space is reserved here (out of combat) so filling it in
	-- during a pull never has to resize a frame that holds secure tiles.
	local footerH = ns.db.kickLog and (FOOTER_H + 4) or 0
	panel:SetSize(PAD * 2 + cols * tw + (cols - 1) * GAP, tilesBottom + PAD + footerH)
	footer:ClearAllPoints()
	footer:SetPoint("TOPLEFT", PAD, -(tilesBottom + 6))
	footer:SetPoint("TOPRIGHT", -PAD, -(tilesBottom + 6))
	footer:SetHeight(FOOTER_H)
	footer:SetShown(ns.db.kickLog)

	local iconSize = math.max(12, math.min(th - 10, 48))
	for i, tile in ipairs(tiles) do
		if i <= count then
			local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
			tile:SetSize(tw, th)
			tile:ClearAllPoints()
			tile:SetPoint("TOPLEFT", PAD + col * (tw + GAP), -(HEADER + row * (th + GAP)))
			tile.iconBorder:SetSize(iconSize, iconSize)
			local markerSize = math.max(10, math.min(20, math.floor(th * 0.4)))
			tile.marker:SetSize(markerSize, markerSize)
			-- Short tiles: drop the spell line so the caster name stays readable.
			tile.spell:SetShown(th >= 34)
			local hpH = math.max(3, math.min(8, math.floor(th * 0.1)))
			tile.hp:SetHeight(hpH)
			tile.bar:ClearAllPoints()
			tile.bar:SetPoint("BOTTOMLEFT", 1, 1 + hpH + 1)
			tile.bar:SetPoint("BOTTOMRIGHT", -1, 1 + hpH + 1)
			tile:Show()
		else
			tile:Hide()
		end
	end
	if editBar then editBar:Refresh() end
end

--------------------------------------------------------------------------
-- Edit mode: edit bar + resize grip, shown while frames are unlocked
--------------------------------------------------------------------------

local function CreateEditControls()
	editBar = ns.CreateEditBar(panel, 330)
	local colsLbl, colsEnd, colsRefresh = ns.Stepper(editBar, "Columns",
		function() return ns.db.panelCols or 2 end,
		function(v) ns.db.panelCols = v end, 1, 8, Layout)
	colsLbl:SetPoint("LEFT", 8, 0)
	local tilesLbl, _, tilesRefresh = ns.Stepper(editBar, "Tiles",
		function() return ns.db.panelTiles or 20 end,
		function(v) ns.db.panelTiles = v end, 1, MAX_TILES, Layout)
	tilesLbl:SetPoint("LEFT", colsEnd, "RIGHT", 12, 0)
	function editBar:Refresh()
		colsRefresh()
		tilesRefresh()
	end

	-- Dragging the grip changes the tile size; the panel size follows.
	grip = ns.CreateResizeGrip(panel, function()
		ns.AnchorTopLeft(panel, "panelPos")
		local cols, count, tw, th = Settings()
		cols = math.min(cols, count)
		return { tw = tw, th = th, cols = cols, rows = math.ceil(count / cols) }
	end, function(st, dx, dy)
		ns.db.panelTileW = math.floor(math.max(MIN_W, math.min(MAX_W, st.tw + dx / st.cols)))
		ns.db.panelTileH = math.floor(math.max(MIN_H, math.min(MAX_H, st.th + dy / st.rows)))
		Layout()
	end)
end

--------------------------------------------------------------------------
-- Interrupt tracker footer
--------------------------------------------------------------------------

local function ClassColor(class)
	local c = class and (C_ClassColor and C_ClassColor.GetClassColor(class) or RAID_CLASS_COLORS[class])
	if c then return c.r, c.g, c.b end
	return 0.8, 0.8, 0.8
end

function CreateFooter()
	footer = CreateFrame("Frame", nil, panel)

	local line = footer:CreateTexture(nil, "ARTWORK")
	line:SetPoint("TOPLEFT", 0, 0)
	line:SetPoint("TOPRIGHT", 0, 0)
	line:SetHeight(1)
	line:SetColorTexture(1, 1, 1, 0.08)

	local title = ns.Text(footer, 10, "OUTLINE")
	title:SetPoint("TOPLEFT", 2, -6)
	title:SetText("INTERRUPTS")
	title:SetTextColor(A[1], A[2], A[3])

	footer.total = ns.Text(footer, 10)
	footer.total:SetPoint("LEFT", title, "RIGHT", 8, 0)
	footer.total:SetTextColor(0.5, 0.5, 0.55)

	-- Plain (non-secure) buttons: fine to click any time, even in combat.
	local reset = ns.FlatButton(footer, "reset", 38, 14, function() ns.ResetKicks(ns.db.kickStats and ns.db.kickStats.instance) end)
	reset:SetPoint("TOPRIGHT", 0, -3)
	reset.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 9, "")
	local runs = ns.FlatButton(footer, "runs", 34, 14, function() ns.ShowRuns() end)
	runs:SetPoint("RIGHT", reset, "LEFT", -4, 0)
	runs.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 9, "")

	footer.rows = {}
	for i = 1, FOOTER_ROWS do
		local row = CreateFrame("Button", nil, footer)
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", 0, -(FOOTER_TITLE + (i - 1) * ROW_H))
		row:SetPoint("TOPRIGHT", 0, -(FOOTER_TITLE + (i - 1) * ROW_H))

		local hl = row:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.08)
		row.selected = row:CreateTexture(nil, "BACKGROUND")
		row.selected:SetAllPoints()
		row.selected:SetColorTexture(A[1], A[2], A[3], 0.18)
		row.selected:Hide()

		-- Kick cooldown: interrupt icon + "ready" / seconds left.
		row.cdIcon = row:CreateTexture(nil, "ARTWORK")
		row.cdIcon:SetSize(12, 12)
		row.cdIcon:SetPoint("LEFT", 2, 0)
		row.cdIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.cdText = ns.Text(row, 10)
		row.cdText:SetPoint("RIGHT", -46, 0)
		row.cdText:SetJustifyH("RIGHT")

		row.name = ns.Text(row, 11)
		row.name:SetPoint("LEFT", 18, 0)
		row.name:SetPoint("RIGHT", row.cdText, "LEFT", -4, 0)
		row.name:SetWordWrap(false)
		row.count = ns.Text(row, 11)
		row.count:SetPoint("RIGHT", -2, 0)
		row.count:SetJustifyH("RIGHT")

		row:SetScript("OnClick", function(self) ns.ShowKickDetails(self.key) end)
		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local _, remaining, estimated, spell = ns.KickStatus(self.key)
			if spell then
				GameTooltip:AddLine(C_Spell.GetSpellName(spell) or "Interrupt", A[1], A[2], A[3])
				GameTooltip:AddLine(remaining > 0 and ("Ready in %ds%s"):format(math.ceil(remaining), estimated and " (estimated)" or "") or "Ready", 1, 1, 1)
			end
			GameTooltip:AddLine("Click: see which spells they interrupted", 1, 1, 1)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		row:Hide()
		footer.rows[i] = row
	end
end

--------------------------------------------------------------------------
-- Interrupt details: which spells one player interrupted
--------------------------------------------------------------------------

local details
local DETAIL_ROWS, DETAIL_ROW_H, DETAIL_TOP = 14, 18, 74

local function CreateDetails()
	details = CreateFrame("Frame", "MPlusKickDetails", UIParent, "BackdropTemplate")
	details:SetWidth(310)
	details:SetFrameStrata("MEDIUM")
	details:SetClampedToScreen(true)
	details:EnableMouse(true)
	ns.Skin(details, 0.95)
	details:Hide()

	local stripe = details:CreateTexture(nil, "ARTWORK")
	stripe:SetColorTexture(A[1], A[2], A[3], 1)
	stripe:SetPoint("TOPLEFT", 1, -1)
	stripe:SetPoint("TOPRIGHT", -1, -1)
	stripe:SetHeight(2)

	details.title = ns.Text(details, 14, "OUTLINE")
	details.title:SetPoint("TOPLEFT", 10, -10)
	details.sub = ns.Text(details, 10)
	details.sub:SetPoint("TOPLEFT", details.title, "BOTTOMLEFT", 0, -3)
	details.sub:SetTextColor(0.55, 0.55, 0.6)

	local close = ns.FlatButton(details, "×", 20, 20, function() details:Hide() end)
	close:SetPoint("TOPRIGHT", -6, -6)

	details.filter = ns.CheckBox(details, "Important only",
		function() return ns.db.detailImportantOnly end,
		function(v) ns.db.detailImportantOnly = v; ns.RefreshKickDetails() end)
	details.filter:SetPoint("TOPLEFT", 10, -48)

	details.rows = {}
	for i = 1, DETAIL_ROWS do
		local row = CreateFrame("Button", nil, details)
		row:RegisterForClicks("RightButtonUp")
		row:SetHeight(DETAIL_ROW_H)
		local hl = row:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.06)
		row:SetScript("OnClick", function(self)
			if self.spellName then ns.ToggleImportant(self.spellName, self.mob) end
		end)
		row:SetScript("OnEnter", function(self)
			if not self.spellName then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self.spellName, 1, 1, 1)
			GameTooltip:AddLine(self.important and "Right-click: mark as NOT important" or "Right-click: mark as important", A[1], A[2], A[3])
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		row:SetPoint("TOPLEFT", 8, -(DETAIL_TOP + (i - 1) * DETAIL_ROW_H))
		row:SetPoint("TOPRIGHT", -8, -(DETAIL_TOP + (i - 1) * DETAIL_ROW_H))
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(15, 15)
		row.icon:SetPoint("LEFT", 0, 0)
		row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.spell = ns.Text(row, 11)
		row.spell:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
		row.spell:SetPoint("RIGHT", -36, 0)
		row.spell:SetWordWrap(false)
		row.count = ns.Text(row, 11)
		row.count:SetPoint("RIGHT", 0, 0)
		row.count:SetJustifyH("RIGHT")
		details.rows[i] = row
	end

	details.note = ns.Text(details, 10)
	details.note:SetPoint("BOTTOMLEFT", 10, 9)
	details.note:SetPoint("RIGHT", -10, 0)
	details.note:SetWordWrap(true)
	details.note:SetJustifyV("BOTTOM")
	details.note:SetTextColor(0.55, 0.55, 0.6)
end

local function SetRow(row, icon, text, count, r)
	row.spellName, row.mob, row.important = r and r.name, r and r.mob, r and r.important
	row.icon:SetTexture(icon or QUESTION_ICON)
	row.spell:SetText(text)
	row.spell:SetTextColor(1, 1, 1)
	row.count:SetText(count)
	row:Show()
end

function ns.RefreshKickDetails()
	if not details or not details:IsShown() then return end
	local name, class, list, hiddenList = ns.KickDetails(details.key)
	if not name then details:Hide() return end

	details.title:SetText(name)
	details.title:SetTextColor(ClassColor(class))
	details.filter:Refresh()

	local importantOnly = ns.db.detailImportantOnly
	local shown, important, total = 0, 0, 0
	for _, r in ipairs(list) do
		total = total + r.count
		if r.important then important = important + r.count end
	end
	details.sub:SetText(("%d interrupts · %d on important spells"):format(total + #hiddenList, important))

	local i = 0
	for _, r in ipairs(list) do
		if not importantOnly or r.important then
			shown = shown + 1
			if i < DETAIL_ROWS then
				i = i + 1
				local mob = r.mob and ("  |cff808080" .. r.mob .. "|r") or ""
				local label = r.important and ("|cffff7326" .. r.name .. "|r") or r.name
				SetRow(details.rows[i], C_Spell.GetSpellTexture(r.id), label .. mob, "x" .. r.count, r)
			end
		end
	end
	-- Secret entries: the game hid the spell, so it can't be grouped or
	-- judged important. Shown as-is (widgets can display secrets).
	for _, h in ipairs(hiddenList) do
		if i >= DETAIL_ROWS then break end
		i = i + 1
		local row = details.rows[i]
		row.spellName, row.mob, row.important = nil, nil, nil
		row.icon:SetTexture(QUESTION_ICON)
		pcall(function() row.icon:SetTexture(C_Spell.GetSpellTexture(h.spellID)) end)
		row.spell:SetText("|cff808080(hidden spell)|r")
		pcall(function() row.spell:SetText(C_Spell.GetSpellName(h.spellID)) end)
		row.spell:SetTextColor(0.6, 0.6, 0.65)
		row.count:SetText("|cff808080?|r")
		row:Show()
	end
	for j = i + 1, DETAIL_ROWS do details.rows[j]:Hide() end

	local notes = {}
	if i == 0 then notes[#notes + 1] = importantOnly and "No important spells interrupted yet." or "No interrupts recorded yet." end
	if shown + #hiddenList > DETAIL_ROWS then notes[#notes + 1] = ("+%d more"):format(shown + #hiddenList - DETAIL_ROWS) end
	if #hiddenList > 0 then notes[#notes + 1] = "grey ? = spell hidden by the game during the key" end
	notes[#notes + 1] = "|cffff7326orange|r = priority spell (right-click to change)"
	notes[#notes + 1] = ns.IsKickDataFromMeter() and "source: damage meter" or "live (meter syncs after combat)"
	details.note:SetText(table.concat(notes, "   "))

	details:SetHeight(DETAIL_TOP + math.max(i, 1) * DETAIL_ROW_H + 18 + details.note:GetStringHeight())
end

-- Click a footer row: open that player's details (click again to close).
function ns.ShowKickDetails(key)
	if not details then CreateDetails() end
	if details:IsShown() and details.key == key then
		details:Hide()
	else
		details.key = key
		if not InCombatLockdown() then ns.SyncKicksFromMeter() end
		details:ClearAllPoints()
		details:SetPoint("TOPLEFT", panel, "TOPRIGHT", 6, 0)
		details:Show()
		ns.RefreshKickDetails()
	end
	ns.UpdateKickFooter()
end

-- landed / pressed, e.g. "7 / 9": 7 kicks landed out of 9 pressed. The
-- pressed count is only shown when the game revealed it.
function ns.UpdateKickFooter()
	if not footer or not footer:IsShown() then return end
	local players, unknown, total = ns.KickRows()
	footer.total:SetText(total > 0 and ("total " .. total) or "none yet")
	local openKey = details and details:IsShown() and details.key
	local i = 0
	local function fill(key, name, r, g, b, count)
		i = i + 1
		local row = footer.rows[i]
		row.key = key
		row.name:SetText(name)
		row.name:SetTextColor(r, g, b)
		row.count:SetText(count)
		row.selected:SetShown(openKey == key)
		local icon, remaining, estimated = ns.KickStatus(key)
		if icon then
			row.cdIcon:SetTexture(icon)
			row.cdIcon:SetDesaturated(remaining > 0)
			row.cdIcon:Show()
			if remaining > 0 then
				row.cdText:SetText(("|cff9a9aa3%s%ds|r"):format(estimated and "~" or "", math.ceil(remaining)))
			else
				row.cdText:SetText("|cff55dd55ready|r")
			end
		else
			row.cdIcon:Hide()
			row.cdText:SetText("")
		end
		row:Show()
	end
	for _, e in ipairs(players) do
		if i >= FOOTER_ROWS - 1 then break end
		local r, g, b = ClassColor(e.class)
		fill(e.guid, e.name, r, g, b,
			e.cast > 0 and ("%d |cff808080/ %d|r"):format(e.landed, e.cast) or tostring(e.landed))
	end
	if unknown > 0 then fill("unattributed", "Unattributed", 0.55, 0.55, 0.6, tostring(unknown)) end
	for j = i + 1, FOOTER_ROWS do footer.rows[j]:Hide() end
end

function ns.CreatePanel()
	panel = CreateFrame("Frame", "MPlusKickPanel", UIParent, "BackdropTemplate")
	panel:SetFrameStrata("MEDIUM")
	panel:SetClampedToScreen(true)
	panel:EnableMouse(false) -- only while unlocked, for dragging
	ns.Skin(panel, 0.35, 0)
	ns.RestorePos(panel, "panelPos", "LEFT", 40, 40)
	ns.MakeDraggable(panel, "panelPos")
	panel:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		ns.AnchorTopLeft(self, "panelPos")
	end)

	local title = ns.Text(panel, 10, "OUTLINE")
	title:SetPoint("TOPLEFT", PAD + 2, -6)
	title:SetText("CASTERS")
	title:SetTextColor(A[1], A[2], A[3])
	local hint = ns.Text(panel, 10)
	hint:SetPoint("LEFT", title, "RIGHT", 8, 0)
	hint:SetPoint("RIGHT", -PAD, 0)
	hint:SetWordWrap(false)
	hint:SetTextColor(0.5, 0.5, 0.55)
	panel.hint = hint

	for i = 1, MAX_TILES do CreateTile(i) end
	CreateFooter()
	CreateEditControls()
	ns.RefreshPanelHint()
	Layout()
	ns.UpdateKickFooter()
end

-- "lit = hover it + [V]": how to kick what the panel shows.
function ns.RefreshPanelHint()
	if not panel or panel.preview then return end
	local key = "[" .. (GetBindingKey(ns.KICK_BINDING) or "kick key") .. "]"
	panel.hint:SetText(ns.db.hoverSelect and ("lit: hover tile or mob + " .. key) or ("lit: hover that mob + " .. key))
end

--------------------------------------------------------------------------
-- Live cast display
--------------------------------------------------------------------------

local function RefreshIdle(tile)
	local unit = tile.unit
	if ns.Readable(UnitExists(unit)) == false or ns.Readable(UnitCanAttack("player", unit)) == false then
		tile.base:SetAlpha(0)
		tile.base.name:SetText("")
		tile.hp:Hide()
		tile.marker:Hide()
		return
	end
	tile.base:SetAlpha(1)
	tile.base.name:SetText("")
	pcall(tile.base.name.SetText, tile.base.name, UnitName(unit))
	ns.SetHealth(tile.hp, unit)
	ns.SetRaidMarker(tile.marker, unit)
end

function ns.PanelMarkers()
	if not panel or panel.preview then return end
	for _, tile in ipairs(tiles) do
		if tile.hp:IsShown() then ns.SetRaidMarker(tile.marker, tile.unit) end
	end
end

--------------------------------------------------------------------------
-- Range fade: lit tiles you can't reach with your kick fade out. The
-- range result may be secret; the game then sets the alpha itself.
--------------------------------------------------------------------------

local rangeTicker

local function UpdateRange()
	local spell = ns.GetKickSpell()
	local any = false
	for _, tile in ipairs(tiles) do
		if tile.castT then
			any = true
			local inRange = ns.db.rangeFade and spell and C_Spell.IsSpellInRange(spell, tile.unit)
			if issecretvalue and issecretvalue(inRange) then
				if not pcall(tile.rangeGate.SetAlphaFromBoolean, tile.rangeGate, inRange, 1, OUT_OF_RANGE_ALPHA) then
					tile.rangeGate:SetAlpha(1)
				end
			else
				-- nil = no range info (e.g. no target rules): don't fade.
				tile.rangeGate:SetAlpha(inRange == false and OUT_OF_RANGE_ALPHA or 1)
			end
		else
			tile.rangeGate:SetAlpha(1)
		end
	end
	if not any and rangeTicker then
		rangeTicker:Cancel()
		rangeTicker = nil
	end
end

local function WatchRange()
	UpdateRange()
	if not rangeTicker then rangeTicker = C_Timer.NewTicker(0.2, UpdateRange) end
end

-- UNIT_HEALTH / UNIT_MAXHEALTH for a nameplate: update its tile.
function ns.PanelHealth(unit)
	if not panel or panel.preview then return end
	local i = tonumber(unit:match("^nameplate(%d+)$") or "")
	local tile = i and tiles[i]
	if tile and tile.hp:IsShown() then ns.SetHealth(tile.hp, unit) end
end

local function ClearTile(tile)
	tile.castT = nil
	tile.bar:SetScript("OnUpdate", nil)
	tile.glow.pulse:Stop()
	tile.cast:Hide()
end

local function RenderTile(tile, info)
	local unit = tile.unit
	local infoFn = info.channel and UnitChannelInfo or UnitCastingInfo
	local name, _, texture = infoFn(unit)

	-- All of these may be secret inside instances; widgets display them as-is.
	tile.spell:SetText("")
	if ns.Present(name) then pcall(tile.spell.SetText, tile.spell, name) end
	tile.caster:SetText("")
	pcall(tile.caster.SetText, tile.caster, UnitName(unit))
	tile.icon:SetTexture(QUESTION_ICON)
	if ns.Present(texture) then pcall(tile.icon.SetTexture, tile.icon, texture) end

	ns.StartCastBar(tile.bar, unit, info.channel)
	ns.GateOnInterruptible(tile.cast, info.ni)
	tile.castT = info.t
	tile.cast:Show()
	tile.glow.pulse:Play()
	WatchRange()
end

-- Re-sync every tile with the shared cast tracker (ns.active).
function ns.UpdatePanel()
	if not panel or panel.preview then return end
	for _, tile in ipairs(tiles) do
		local info = ns.active[tile.unit]
		if info then
			if tile.castT ~= info.t then RenderTile(tile, info) end
		elseif tile.castT then
			ClearTile(tile)
		end
		RefreshIdle(tile)
	end
end

function ns.PanelDebugSummary()
	if not panel then return end
	local lit = 0
	for _, tile in ipairs(tiles) do if tile.castT then lit = lit + 1 end end
	ns.Print(("panel shown=%s tiles=%d lit=%d"):format(tostring(panel:IsShown()), ns.db.panelTiles or 20, lit))
end

function ns.PanelUnitChanged(unit)
	local i = tonumber(unit:match("^nameplate(%d+)$") or "")
	if i and tiles[i] then RefreshIdle(tiles[i]) end
end

function ns.PanelReadiness(alpha)
	if not panel or panel.preview then return end
	for _, tile in ipairs(tiles) do tile.cdGate:SetAlpha(alpha) end
end

local function InDungeon()
	local _, instanceType = IsInInstance()
	return instanceType == "party"
end

-- Show/hide and mouse are protected on secure frames: out of combat only.
function ns.ApplyPanelSettings()
	if not panel then return end
	if InCombatLockdown() then
		pendingApply = true
		return
	end
	pendingApply = false
	-- While unlocked it always shows, so it can be placed from anywhere.
	panel:SetShown(ns.db.panel and (panel.preview or not ns.db.panelDungeonOnly or InDungeon()))
	for _, tile in ipairs(tiles) do tile:EnableMouse(ns.db.hoverSelect) end
	ns.RefreshPanelHint()
	Layout()
	ns.UpdateKickFooter()
end

function ns.OnPanelLeaveCombat()
	if pendingApply then ns.ApplyPanelSettings() end
	if pendingLayout then Layout() end
end

--------------------------------------------------------------------------
-- Preview (frames unlocked) and /mk test
--------------------------------------------------------------------------

local SAMPLE_NAMES = { "Radiant Spellsower", "Leafy Grovecrawler", "Thorny Saptor", "Lightfeather Petalwing" }

local function ShowSample(on, editing)
	panel.preview = on
	for i, tile in ipairs(tiles) do
		ClearTile(tile)
		tile.cdGate:SetAlpha(1)
		-- While editing, show every tile so the grid's extent is visible.
		local visible = on and (editing or i <= #SAMPLE_NAMES)
		tile.base:SetAlpha(visible and 1 or 0)
		tile.hp:SetMinMaxValues(0, 1)
		tile.hp:SetValue(1 - (i % 5) * 0.18)
		tile.hp:SetShown(visible)
		tile.base.name:SetText(visible and (SAMPLE_NAMES[i] or ("Nameplate " .. i)) or "")
	end
	if on then
		local tile = tiles[1]
		tile.caster:SetText("Radiant Spellsower")
		tile.spell:SetText("Light Bolt Volley")
		tile.icon:SetTexture(QUESTION_ICON)
		tile.bar:SetMinMaxValues(0, 1)
		tile.bar:SetValue(0.6)
		tile.bar:Show()
		tile.cast:SetAlpha(1)
		tile.cast:Show()
		tile.glow.pulse:Play()
		tile.rangeGate:SetAlpha(1)
		tile.marker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
		tile.marker:Show()
	else
		for _, tile in ipairs(tiles) do tile.marker:Hide() end
	end
end

function ns.PanelPreview(on)
	if not panel then return end
	editBar:SetShown(on)
	grip:SetShown(on)
	panel:EnableMouse(on)
	if on then panel.hint:SetText("drag to move  ·  corner to resize") end
	ShowSample(on, on)
	ns.ApplyPanelSettings()
	if not on then
		ns.RefreshPanelHint()
		ns.UpdatePanel()
	end
end

function ns.PanelTest()
	if not panel or panel.preview or not panel:IsShown() then return end
	ShowSample(true, false)
	C_Timer.After(2.5, function()
		if panel.preview and ns.db.locked then
			ShowSample(false)
			ns.UpdatePanel()
		end
	end)
end

--------------------------------------------------------------------------
-- Run recap & history
--------------------------------------------------------------------------

local runsWin
local RUN_LIST_ROWS, RECAP_ROWS = 11, 5

local function FormatTime(sec)
	if not sec or sec <= 0 then return "" end
	return ("%d:%02d"):format(math.floor(sec / 60), math.floor(sec % 60))
end

local function RunLabel(run)
	local level = run.level and run.level > 0 and ("+" .. run.level .. " ") or ""
	return level .. (run.dungeon or "?")
end

local function CreateRuns()
	runsWin = CreateFrame("Frame", "MPlusKickRuns", UIParent, "BackdropTemplate")
	runsWin:SetSize(600, 300)
	runsWin:SetPoint("CENTER", 0, 80)
	runsWin:SetFrameStrata("DIALOG")
	runsWin:SetClampedToScreen(true)
	runsWin:EnableMouse(true)
	runsWin:SetMovable(true)
	runsWin:RegisterForDrag("LeftButton")
	runsWin:SetScript("OnDragStart", runsWin.StartMoving)
	runsWin:SetScript("OnDragStop", runsWin.StopMovingOrSizing)
	ns.Skin(runsWin, 0.97)
	runsWin:Hide()
	tinsert(UISpecialFrames, "MPlusKickRuns")

	local stripe = runsWin:CreateTexture(nil, "ARTWORK")
	stripe:SetColorTexture(A[1], A[2], A[3], 1)
	stripe:SetPoint("TOPLEFT", 1, -1)
	stripe:SetPoint("TOPRIGHT", -1, -1)
	stripe:SetHeight(2)

	local title = ns.Text(runsWin, 14, "OUTLINE")
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText("Interrupt runs")
	local close = ns.FlatButton(runsWin, "×", 20, 20, function() runsWin:Hide() end)
	close:SetPoint("TOPRIGHT", -6, -6)

	-- Left: run list (current run first, then saved runs).
	runsWin.list = {}
	for i = 1, RUN_LIST_ROWS do
		local row = CreateFrame("Button", nil, runsWin)
		row:SetSize(190, 22)
		row:SetPoint("TOPLEFT", 10, -36 - (i - 1) * 23)
		local hl = row:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.07)
		row.sel = row:CreateTexture(nil, "BACKGROUND")
		row.sel:SetAllPoints()
		row.sel:SetColorTexture(A[1], A[2], A[3], 0.18)
		row.label = ns.Text(row, 11)
		row.label:SetPoint("TOPLEFT", 6, -2)
		row.label:SetPoint("RIGHT", -4, 0)
		row.label:SetWordWrap(false)
		row.sub = ns.Text(row, 9)
		row.sub:SetPoint("BOTTOMLEFT", 6, 1)
		row.sub:SetTextColor(0.5, 0.5, 0.55)
		row:SetScript("OnClick", function(self) ns.ShowRuns(self.index) end)
		runsWin.list[i] = row
	end

	local divider = runsWin:CreateTexture(nil, "ARTWORK")
	divider:SetColorTexture(1, 1, 1, 0.08)
	divider:SetPoint("TOPLEFT", 208, -34)
	divider:SetSize(1, 250)

	-- Right: recap of the selected run.
	runsWin.head = ns.Text(runsWin, 13, "OUTLINE")
	runsWin.head:SetPoint("TOPLEFT", 222, -36)
	runsWin.head:SetPoint("RIGHT", -12, 0)
	runsWin.head:SetWordWrap(false)
	runsWin.headSub = ns.Text(runsWin, 10)
	runsWin.headSub:SetPoint("TOPLEFT", runsWin.head, "BOTTOMLEFT", 0, -3)
	runsWin.headSub:SetTextColor(0.6, 0.6, 0.65)

	local cols = { { "Player", 0, "LEFT" }, { "Landed", 150, "RIGHT" }, { "Pressed", 210, "RIGHT" },
		{ "Missed", 270, "RIGHT" }, { "Important", 350, "RIGHT" } }
	local function Cell(parent, x, justify, size)
		local fs = ns.Text(parent, size or 11)
		if justify == "RIGHT" then
			fs:SetPoint("TOPRIGHT", parent, "TOPLEFT", x, 0)
			fs:SetJustifyH("RIGHT")
		else
			fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, 0)
			fs:SetWidth(140)
			fs:SetWordWrap(false)
		end
		return fs
	end
	local header = CreateFrame("Frame", nil, runsWin)
	header:SetPoint("TOPLEFT", 222, -82)
	header:SetSize(360, 16)
	for _, c in ipairs(cols) do
		local fs = Cell(header, c[2], c[3], 10)
		fs:SetText(c[1])
		fs:SetTextColor(0.55, 0.55, 0.6)
	end
	runsWin.rows = {}
	for i = 1, RECAP_ROWS + 1 do
		local row = CreateFrame("Frame", nil, runsWin)
		row:SetPoint("TOPLEFT", 222, -102 - (i - 1) * 20)
		row:SetSize(360, 18)
		row.cells = {}
		for c, col in ipairs(cols) do row.cells[c] = Cell(row, col[2], col[3]) end
		runsWin.rows[i] = row
	end
	runsWin.foot = ns.Text(runsWin, 10)
	runsWin.foot:SetPoint("BOTTOMLEFT", 222, 12)
	runsWin.foot:SetPoint("RIGHT", -12, 0)
	runsWin.foot:SetTextColor(0.5, 0.5, 0.55)
	runsWin.foot:SetText("Missed = pressed but didn't land (late, wrong target or no cast). Important = kicks on priority spells.")
end

-- index: 0 = current run, 1..n = saved runs (newest first). nil = default.
function ns.ShowRuns(index)
	if not runsWin then CreateRuns() end
	if not InCombatLockdown() then ns.SyncKicksFromMeter() end
	local entries = {}
	local current = ns.BuildRunRecord()
	if current.total > 0 then entries[#entries + 1] = { run = current, index = 0, live = true } end
	for i, run in ipairs(ns.db.runs) do entries[#entries + 1] = { run = run, index = i } end

	if index == nil then index = entries[1] and entries[1].index or 0 end
	local selected
	for i, row in ipairs(runsWin.list) do
		local e = entries[i]
		if e then
			row.index = e.index
			row.label:SetText(e.live and ("|cffff7326Current:|r " .. RunLabel(e.run)) or RunLabel(e.run))
			local status = e.run.onTime == true and "|cff55dd55timed|r" or (e.run.onTime == false and "|cffdd5555over time|r" or "")
			row.sub:SetText((e.run.date or "") .. "  " .. status)
			row.sel:SetShown(e.index == index)
			if e.index == index then selected = e.run end
			row:Show()
		else
			row:Hide()
		end
	end

	for _, row in ipairs(runsWin.rows) do
		for _, cell in ipairs(row.cells) do cell:SetText("") end
	end
	if not selected then
		runsWin.head:SetText("No runs yet")
		runsWin.headSub:SetText("A recap is saved when a key ends.")
	else
		runsWin.head:SetText(RunLabel(selected))
		local parts = {}
		if selected.onTime ~= nil then parts[#parts + 1] = selected.onTime and "timed" or "over time" end
		if selected.time and selected.time > 0 then parts[#parts + 1] = FormatTime(selected.time) end
		parts[#parts + 1] = selected.total .. " interrupts"
		runsWin.headSub:SetText(table.concat(parts, "  ·  "))
		for i, pl in ipairs(selected.players) do
			if i > RECAP_ROWS then break end
			local cells = runsWin.rows[i].cells
			cells[1]:SetText(pl.name)
			cells[1]:SetTextColor(ClassColor(pl.class))
			cells[2]:SetText(pl.landed)
			cells[3]:SetText(pl.cast > 0 and pl.cast or "|cff808080-|r")
			cells[4]:SetText(pl.missed and (pl.missed > 0 and ("|cffdd7755" .. pl.missed .. "|r") or "0") or "|cff808080-|r")
			cells[5]:SetText(pl.important > 0 and ("|cffff7326" .. pl.important .. "|r") or "0")
		end
	end
	runsWin:Show()
end
