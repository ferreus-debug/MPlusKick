local _, ns = ...

local FLAT = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local A = ns.ACCENT
local QUESTION_ICON = 134400

local kickButton, focusButton, castAlert, toast
local pendingRebuild, pendingSettings = false, false
ns.focusEntry = nil

--------------------------------------------------------------------------
-- Shared widget helpers (also used by Options.lua)
--------------------------------------------------------------------------

function ns.Skin(frame, alpha, bg)
	frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
	local c = bg or 0.06
	frame:SetBackdropColor(c, c, c + 0.02, alpha or 0.92)
	frame:SetBackdropBorderColor(0, 0, 0, 1)
end

function ns.Text(parent, size, flags, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFont(FONT, size, flags or "")
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetJustifyH("LEFT")
	return fs
end

function ns.FlatButton(parent, label, width, height, onClick)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(width, height or 24)
	ns.Skin(b, 1, 0.13)
	b.text = ns.Text(b, 12)
	b.text:SetPoint("CENTER")
	b.text:SetText(label)
	b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(A[1], A[2], A[3], 1) end)
	b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0, 0, 0, 1) end)
	b:SetScript("OnMouseDown", function(self) self.text:SetPoint("CENTER", 1, -1) end)
	b:SetScript("OnMouseUp", function(self) self.text:SetPoint("CENTER") end)
	b:SetScript("OnClick", onClick)
	return b
end

function ns.CheckBox(parent, label, get, set)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(16, 16)
	ns.Skin(b, 1, 0.13)
	b.check = b:CreateTexture(nil, "ARTWORK")
	b.check:SetTexture(FLAT)
	b.check:SetVertexColor(A[1], A[2], A[3])
	b.check:SetPoint("TOPLEFT", 3, -3)
	b.check:SetPoint("BOTTOMRIGHT", -3, 3)
	b.label = ns.Text(b, 12)
	b.label:SetPoint("LEFT", b, "RIGHT", 8, 0)
	b.label:SetText(label)
	b:SetHitRectInsets(0, -(b.label:GetStringWidth() + 10), 0, 0)
	function b:Refresh() self.check:SetShown(get()) end
	b:SetScript("OnClick", function(self)
		set(not get())
		self:Refresh()
	end)
	b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(A[1], A[2], A[3], 1) end)
	b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0, 0, 0, 1) end)
	b:Refresh()
	return b
end

-- Re-anchor a frame by its top-left corner (saving it under db[key]) so
-- resizing grows right/down and the saved position survives size changes.
function ns.AnchorTopLeft(frame, key)
	local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local left, top = frame:GetLeft(), frame:GetTop()
	if not left then return end
	local y = top - UIParent:GetTop() / s
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left, y)
	ns.db[key] = { "TOPLEFT", left, y }
end

-- "Label [-] 3 [+]" control. Returns the label, the "+" button (for
-- anchoring the next control) and a refresh function.
function ns.Stepper(parent, label, get, set, min, max, onChange)
	local lbl = ns.Text(parent, 11)
	lbl:SetText(label)
	lbl:SetTextColor(0.7, 0.7, 0.75)
	local value = ns.Text(parent, 12)
	value:SetJustifyH("CENTER")
	value:SetWidth(22)
	local function step(delta)
		if InCombatLockdown() then return end
		set(math.max(min, math.min(max, get() + delta)))
		value:SetText(get())
		onChange()
	end
	local minus = ns.FlatButton(parent, "-", 18, 18, function() step(-1) end)
	local plus = ns.FlatButton(parent, "+", 18, 18, function() step(1) end)
	minus:SetPoint("LEFT", lbl, "RIGHT", 6, 0)
	value:SetPoint("LEFT", minus, "RIGHT", 2, 0)
	plus:SetPoint("LEFT", value, "RIGHT", 2, 0)
	return lbl, plus, function() value:SetText(get()) end
end

-- Corner grip. onStart() runs on mouse down and returns a state table;
-- onMove(state, dx, dy) runs while dragging (dx right, dy down, in the
-- frame's own units). Out of combat only, to keep secure frames safe.
function ns.CreateResizeGrip(frame, onStart, onMove)
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -1, 1)
	grip:SetFrameLevel(frame:GetFrameLevel() + 20)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:Hide()
	grip:SetScript("OnMouseDown", function(self)
		if InCombatLockdown() then return end
		local state = onStart()
		local scale = frame:GetEffectiveScale()
		local x0, y0 = GetCursorPosition()
		self:SetScript("OnUpdate", function()
			if InCombatLockdown() then return end
			local x, y = GetCursorPosition()
			onMove(state, (x - x0) / scale, (y0 - y) / scale)
		end)
	end)
	grip:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	return grip
end

-- Orange bar shown above a frame while frames are unlocked, ending in a
-- "Lock" button. Callers add their own controls to it.
function ns.CreateEditBar(frame, width)
	local bar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	bar:SetSize(width, 28)
	bar:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 4)
	ns.Skin(bar, 0.95)
	bar:SetBackdropBorderColor(A[1], A[2], A[3], 1)
	bar:Hide()
	local lock = ns.FlatButton(bar, "Lock", 50, 20, function()
		ns.db.locked = true
		ns.ApplySettings()
		if ns.RefreshOptions then ns.RefreshOptions() end
	end)
	lock:SetPoint("RIGHT", -4, 0)
	lock:SetBackdropBorderColor(A[1], A[2], A[3], 1)
	lock:SetScript("OnLeave", nil)
	return bar
end

-- Thin enemy health bar. Health is secret inside instances, but a
-- StatusBar may be fed secret values directly, so nothing is ever read.
local HEALTH_COLOR = { 0.78, 0.16, 0.16 }

function ns.CreateHealthStrip(parent)
	local hp = CreateFrame("StatusBar", nil, parent)
	hp:SetStatusBarTexture(FLAT)
	hp:SetStatusBarColor(HEALTH_COLOR[1], HEALTH_COLOR[2], HEALTH_COLOR[3])
	hp:SetMinMaxValues(0, 1)
	hp:SetValue(1)
	hp:EnableMouse(false)
	hp.bg = hp:CreateTexture(nil, "BACKGROUND")
	hp.bg:SetAllPoints()
	hp.bg:SetColorTexture(0.12, 0.02, 0.02, 0.85)
	return hp
end

function ns.SetHealth(hp, unit)
	local ok = pcall(function()
		hp:SetMinMaxValues(0, UnitHealthMax(unit))
		hp:SetValue(UnitHealth(unit))
	end)
	hp:SetShown(ok)
end

-- Raid target icon for a unit (skull, cross, ...). The index can be secret;
-- the icon path is then built from it without reading it, and textures
-- accept secret paths.
local MARKER_PATH = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"

function ns.SetRaidMarker(tex, unit)
	if ns.Readable(UnitExists(unit)) == false then tex:Hide() return end
	local idx = GetRaidTargetIndex(unit)
	if idx == nil then tex:Hide() return end
	local readable = ns.Readable(idx)
	if readable then
		if readable < 1 or readable > 8 then tex:Hide() return end
		tex:SetTexture(MARKER_PATH .. readable)
		tex:Show()
		return
	end
	local ok = pcall(function() tex:SetTexture(MARKER_PATH .. idx) end)
	tex:SetShown(ok)
end

local function PulseAnim(target, from, to, dur)
	local g = target:CreateAnimationGroup()
	g:SetLooping("BOUNCE")
	local a = g:CreateAnimation("Alpha")
	a:SetFromAlpha(from)
	a:SetToAlpha(to)
	a:SetDuration(dur)
	a:SetSmoothing("IN_OUT")
	return g
end

local function AccentBorder(parent, size)
	local glow = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	glow:SetPoint("TOPLEFT", -size, size)
	glow:SetPoint("BOTTOMRIGHT", size, -size)
	glow:SetBackdrop({ edgeFile = FLAT, edgeSize = size })
	glow:SetBackdropBorderColor(A[1], A[2], A[3], 1)
	glow:SetAlpha(0)
	glow.pulse = PulseAnim(glow, 1, 0.25, 0.35)
	return glow
end

--------------------------------------------------------------------------
-- Kick button (secure; macro is static, the game resolves the target)
--------------------------------------------------------------------------

local function CreateKickButton()
	kickButton = CreateFrame("Button", "MPlusKickButton", UIParent, "SecureActionButtonTemplate, BackdropTemplate")
	kickButton:SetSize(56, 56)
	kickButton:RegisterForClicks("AnyUp", "AnyDown")
	kickButton:SetAttribute("type", "macro")
	ns.Skin(kickButton, 1)
	ns.RestorePos(kickButton, "buttonPos", "CENTER", 0, -180)
	ns.MakeDraggable(kickButton, "buttonPos")

	kickButton.icon = kickButton:CreateTexture(nil, "ARTWORK")
	kickButton.icon:SetPoint("TOPLEFT", 2, -2)
	kickButton.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	kickButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local hl = kickButton:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(kickButton.icon)
	hl:SetColorTexture(1, 1, 1, 0.12)

	kickButton.cd = CreateFrame("Cooldown", nil, kickButton, "CooldownFrameTemplate")
	kickButton.cd:SetAllPoints(kickButton.icon)
	kickButton.cd:SetDrawEdge(false)
	kickButton.cd:SetSwipeColor(0, 0, 0, 0.75)

	kickButton.cdGate = CreateFrame("Frame", nil, kickButton)
	kickButton.cdGate:SetAllPoints()
	kickButton.glowGate = CreateFrame("Frame", nil, kickButton.cdGate)
	kickButton.glowGate:SetAllPoints()
	kickButton.glow = AccentBorder(kickButton.glowGate, 3)

	kickButton.hotkey = ns.Text(kickButton, 11, "OUTLINE")
	kickButton.hotkey:SetPoint("TOPRIGHT", -3, -4)
	kickButton.hotkey:SetJustifyH("RIGHT")

	kickButton.focusName = ns.Text(kickButton, 12, "OUTLINE")
	kickButton.focusName:SetPoint("TOP", kickButton, "BOTTOM", 0, -5)
	kickButton.focusName:SetJustifyH("CENTER")

	kickButton.focusNote = ns.Text(kickButton, 10, "OUTLINE")
	kickButton.focusNote:SetPoint("TOP", kickButton.focusName, "BOTTOM", 0, -2)
	kickButton.focusNote:SetJustifyH("CENTER")
	kickButton.focusNote:SetTextColor(0.75, 0.75, 0.75)
	kickButton.focusNote:SetWidth(200)
	kickButton.focusNote:SetWordWrap(false)

	kickButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("MPlusKick", A[1], A[2], A[3])
		GameTooltip:AddLine("Click: interrupt focus > mouseover > target", 1, 1, 1)
		GameTooltip:AddLine("Shift-click: set focus (mouseover > target)", 1, 1, 1)
		GameTooltip:AddLine("Shift-drag: move   ·   /mk: options", 0.6, 0.6, 0.6)
		GameTooltip:AddLine("Created by Netheron", 0.45, 0.45, 0.5)
		GameTooltip:Show()
	end)
	kickButton:SetScript("OnLeave", GameTooltip_Hide)

	focusButton = CreateFrame("Button", "MPlusKickFocusButton", UIParent, "SecureActionButtonTemplate")
	focusButton:RegisterForClicks("AnyUp", "AnyDown")
	focusButton:SetAttribute("type", "macro")
	focusButton:SetAttribute("macrotext", "/focus [@mouseover,exists,harm,nodead][]")
end

local COMMAND_DEMON = 119898

-- Some interrupts are "command" spells that turn into a pet ability:
-- Command Demon becomes Spell Lock (Felhunter) or Axe Toss (Felguard).
-- The macro keeps casting the base spell (the game redirects it), but the
-- icon and cooldown have to follow whatever it currently turns into.
function ns.ActiveKickSpell()
	local id = kickButton.spellID
	if not id then return nil end
	local override = C_Spell.GetOverrideSpell and ns.Readable(C_Spell.GetOverrideSpell(id))
	if override and override ~= 0 then return override end
	return id
end

-- True when the kick can't be used at all right now, e.g. a warlock whose
-- current demon has no interrupt (Imp, Voidwalker) or no demon out.
function ns.KickUnavailable()
	return kickButton.spellID == COMMAND_DEMON and ns.ActiveKickSpell() == COMMAND_DEMON
end

function ns.UpdateKickIcon()
	local id = ns.ActiveKickSpell()
	kickButton.icon:SetTexture(id and C_Spell.GetSpellTexture(id) or QUESTION_ICON)
	kickButton.icon:SetDesaturated(ns.KickUnavailable())
end

function ns.RebuildMacro()
	if InCombatLockdown() then
		pendingRebuild = true
		return
	end
	pendingRebuild = false

	local id = ns.FindInterrupt()
	local name = id and C_Spell.GetSpellName(id)
	kickButton.spellID = name and id or nil
	if not name then
		kickButton:SetAttribute("macrotext", "")
		kickButton.icon:SetTexture(QUESTION_ICON)
	else
		ns.UpdateKickIcon()
		kickButton:SetAttribute("macrotext", table.concat({
			"/focus [mod:shift,@mouseover,exists,harm,nodead][mod:shift]",
			"/stopmacro [mod:shift]",
			"/cast [@focus,harm,nodead][@mouseover,harm,nodead][] " .. name,
		}, "\n"))
	end
	if ns.RefreshOptions then ns.RefreshOptions() end
end

function ns.UpdateCooldown()
	local id = ns.ActiveKickSpell()
	if not id then return end
	local info = C_Spell.GetSpellCooldown(id)
	if not info then return end
	-- Cooldown frames accept secret values directly, so no need to inspect them.
	pcall(kickButton.cd.SetCooldown, kickButton.cd, info.startTime, info.duration)
end

local function ShortKey(key)
	if not key then return "" end
	key = key:gsub("SHIFT%-", "S"):gsub("CTRL%-", "C"):gsub("ALT%-", "A")
	key = key:gsub("MOUSEWHEELUP", "WU"):gsub("MOUSEWHEELDOWN", "WD"):gsub("BUTTON", "M")
	return key
end

function ns.UpdateBindingText()
	kickButton.hotkey:SetText(ShortKey(GetBindingKey(ns.KICK_BINDING)))
	if ns.RefreshPanelHint then ns.RefreshPanelHint() end
	if ns.RefreshOptions then ns.RefreshOptions() end
end

function ns.UpdateFocusLabel()
	local exists = UnitExists("focus")
	if ns.Readable(exists) == false then
		kickButton.focusName:SetText("No focus")
		kickButton.focusName:SetTextColor(0.5, 0.5, 0.5)
		kickButton.focusNote:SetText("Shift-click a mob to focus it")
		return
	end
	kickButton.focusName:SetText("")
	pcall(kickButton.focusName.SetText, kickButton.focusName, UnitName("focus"))
	if ns.focusEntry then
		kickButton.focusName:SetTextColor(A[1], A[2], A[3])
		kickButton.focusNote:SetText(ns.focusEntry.note or "")
	else
		kickButton.focusName:SetTextColor(1, 1, 1)
		kickButton.focusNote:SetText("")
	end
end

--------------------------------------------------------------------------
-- Cast alert cards
--
-- Whether a cast can be interrupted is a secret value inside instances, so
-- the addon can't filter on it. Instead every caster gets its own card and
-- the game itself sets the card's alpha from the secret flag
-- (SetAlphaFromBoolean): uninterruptible casts are simply invisible.
-- Each card is a "gate" frame (alpha from the flag) holding an "inner"
-- frame that carries the visuals and animations, so the two never fight.
--------------------------------------------------------------------------

local MAX_CARDS = 6
local CARD_W, CARD_H = 340, 72
local MIN_CW, MAX_CW, MIN_CH, MAX_CH = 180, 700, 34, 140
local cards = {}

-- Show a frame only if the cast is interruptible, without reading the flag.
local function GateOnInterruptible(frame, notInterruptible)
	if issecretvalue and issecretvalue(notInterruptible) then
		if frame.SetAlphaFromBoolean and pcall(frame.SetAlphaFromBoolean, frame, notInterruptible, 0, 1) then
			return
		end
		frame:SetAlpha(1) -- API missing: better to over-alert than hide kicks
		return
	end
	frame:SetAlpha(notInterruptible and 0 or 1)
end

local function CreateCard(i)
	local card = CreateFrame("Frame", nil, castAlert)
	if i == 1 then
		card:SetPoint("TOP", castAlert, "TOP", 0, 0)
	else
		card:SetPoint("TOP", cards[i - 1], "BOTTOM", 0, -6)
	end
	card:Hide()

	local inner = CreateFrame("Frame", nil, card, "BackdropTemplate")
	inner:SetAllPoints()
	ns.Skin(inner, 0.94)
	card.inner = inner

	card.glow = AccentBorder(inner, 2)

	local stripe = inner:CreateTexture(nil, "ARTWORK")
	stripe:SetColorTexture(A[1], A[2], A[3], 1)
	stripe:SetPoint("TOPLEFT", 1, -1)
	stripe:SetPoint("BOTTOMLEFT", 1, 1)
	stripe:SetWidth(3)

	local iconBorder = CreateFrame("Frame", nil, inner, "BackdropTemplate")
	iconBorder:SetPoint("LEFT", 12, 2)
	card.iconBorder = iconBorder
	card.marker = inner:CreateTexture(nil, "OVERLAY")
	card.marker:SetSize(16, 16)
	card.marker:SetPoint("CENTER", iconBorder, "TOPLEFT", 2, -2)
	card.marker:Hide()
	ns.Skin(iconBorder, 1, 0)
	card.icon = iconBorder:CreateTexture(nil, "ARTWORK")
	card.icon:SetPoint("TOPLEFT", 1, -1)
	card.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	card.title = ns.Text(inner, 18, "OUTLINE")
	card.title:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 10, -1)
	card.title:SetTextColor(A[1], A[2], A[3])

	card.hotkey = ns.Text(inner, 12, "OUTLINE")
	card.hotkey:SetPoint("TOPRIGHT", -10, -9)
	card.hotkey:SetJustifyH("RIGHT")
	card.hotkey:SetTextColor(0.8, 0.8, 0.8)

	card.spell = ns.Text(inner, 13)
	card.spell:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
	card.spell:SetPoint("RIGHT", -10, 0)
	card.spell:SetWordWrap(false)

	card.note = ns.Text(inner, 11)
	card.note:SetPoint("TOPLEFT", card.spell, "BOTTOMLEFT", 0, -2)
	card.note:SetPoint("RIGHT", -10, 0)
	card.note:SetTextColor(0.7, 0.7, 0.7)
	card.note:SetWordWrap(false)

	card.hp = ns.CreateHealthStrip(inner)
	card.hp:SetPoint("BOTTOMLEFT", 4, 1)
	card.hp:SetPoint("BOTTOMRIGHT", -1, 1)

	local bar = CreateFrame("StatusBar", nil, inner)
	bar:SetStatusBarTexture(FLAT)
	bar:SetStatusBarColor(A[1], A[2], A[3])
	bar:SetPoint("BOTTOMLEFT", card.hp, "TOPLEFT", 0, 1)
	bar:SetPoint("BOTTOMRIGHT", card.hp, "TOPRIGHT", 0, 1)
	bar:SetHeight(4)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	bar.bg:SetColorTexture(0, 0, 0, 0.6)
	card.bar = bar

	-- Pop in: slight zoom + fade.
	local pop = inner:CreateAnimationGroup()
	local sc = pop:CreateAnimation("Scale")
	sc:SetScaleFrom(1.12, 1.12)
	sc:SetScaleTo(1, 1)
	sc:SetDuration(0.15)
	sc:SetSmoothing("OUT")
	local fa = pop:CreateAnimation("Alpha")
	fa:SetFromAlpha(0)
	fa:SetToAlpha(1)
	fa:SetDuration(0.12)
	card.pop = pop

	cards[i] = card
	return card
end

local function CardSettings()
	local db = ns.db
	return db.alertW or CARD_W, db.alertH or CARD_H, db.alertCards or 4
end

-- Size every card and scale its contents with the card height.
local function LayoutCards()
	local w, h = CardSettings()
	castAlert:SetSize(w, h)
	local function clamp(v, lo, hi) return math.floor(math.max(lo, math.min(hi, v))) end
	for _, card in ipairs(cards) do
		card:SetSize(w, h)
		local icon = clamp(h - 22, 16, 96)
		card.iconBorder:SetSize(icon, icon)
		card.title:SetFont(FONT, clamp(h * 0.25, 10, 30), "OUTLINE")
		card.spell:SetFont(FONT, clamp(h * 0.18, 9, 22), "")
		card.note:SetFont(FONT, clamp(h * 0.15, 8, 18), "")
		card.hotkey:SetFont(FONT, clamp(h * 0.17, 8, 18), "OUTLINE")
		card.bar:SetHeight(clamp(h * 0.055, 3, 8))
		card.hp:SetHeight(clamp(h * 0.06, 3, 8))
		-- Short cards drop the lower lines so the title stays readable.
		card.note:SetShown(h >= 58)
		card.spell:SetShown(h >= 44)
	end
end

local function CreateCastAlert()
	-- Invisible anchor that holds the card stack; this is what gets dragged.
	castAlert = CreateFrame("Frame", "MPlusKickCastAlert", UIParent, "BackdropTemplate")
	castAlert:SetFrameStrata("HIGH")
	castAlert:SetClampedToScreen(true)
	ns.RestorePos(castAlert, "alertPos", "CENTER", 0, 160)
	ns.MakeDraggable(castAlert, "alertPos")
	castAlert:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		ns.AnchorTopLeft(self, "alertPos")
	end)
	castAlert:Hide()
	for i = 1, MAX_CARDS do CreateCard(i) end

	-- Edit mode: corner grip resizes the cards, bar sets how many stack.
	castAlert.grip = ns.CreateResizeGrip(castAlert, function()
		ns.AnchorTopLeft(castAlert, "alertPos")
		local w, h = CardSettings()
		return { w = w, h = h }
	end, function(state, dx, dy)
		ns.db.alertW = math.floor(math.max(MIN_CW, math.min(MAX_CW, state.w + dx)))
		ns.db.alertH = math.floor(math.max(MIN_CH, math.min(MAX_CH, state.h + dy)))
		LayoutCards()
	end)

	castAlert.editBar = ns.CreateEditBar(castAlert, 190)
	local lbl, _, refresh = ns.Stepper(castAlert.editBar, "Cards",
		function() return ns.db.alertCards or 4 end,
		function(v) ns.db.alertCards = v end, 1, MAX_CARDS,
		function() if ns.RefreshCardPreview then ns.RefreshCardPreview() end end)
	lbl:SetPoint("LEFT", 8, 0)
	castAlert.editBar.Refresh = refresh

	LayoutCards()
end

-- Drive the cast bar without ever reading the (secret) timings ourselves.
-- Prefer the 12.x duration-object API; fall back to feeding raw values into
-- the StatusBar, which accepts secrets. If neither works, hide the bar.
local function StartCastBar(bar, unit, channel)
	bar:SetScript("OnUpdate", nil)
	local ok = false

	local durationFn = channel and UnitChannelDuration or UnitCastingDuration
	if durationFn and bar.SetTimerDuration then
		local dir = Enum and Enum.StatusBarTimerDirection
		dir = dir and (channel and dir.RemainingTime or dir.ElapsedTime)
		ok = pcall(function() bar:SetTimerDuration(durationFn(unit), nil, dir) end)
	end
	if not ok then
		local infoFn = channel and UnitChannelInfo or UnitCastingInfo
		local _, _, _, startMS, endMS = infoFn(unit)
		ok = pcall(bar.SetMinMaxValues, bar, startMS, endMS)
		if ok then
			bar:SetScript("OnUpdate", function(self)
				pcall(self.SetValue, self, GetTime() * 1000)
			end)
		end
	end
	bar:SetShown(ok)
end

--------------------------------------------------------------------------
-- Tracking every hostile caster (focus, target and enemy nameplates).
-- Unit tokens are plain strings, never secret, so they are safe to track.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- Kick readiness. SpellCooldownInfo.isActive / isOnGCD are never secret in
-- Midnight, so the addon may branch on them even in combat.
--------------------------------------------------------------------------

local kickOnCD = false
local cdTicker

-- All nameplate "KICK" tags live under one root so they hide together.
local markerRoot = CreateFrame("Frame", nil, UIParent)
markerRoot:SetAllPoints()

local function KickOnCooldown()
	local id = ns.ActiveKickSpell()
	if not id or not ns.db.hideOnCD then return false end
	if ns.KickUnavailable() then return true end
	local info = C_Spell.GetSpellCooldown(id)
	if not info then return false end
	-- The global cooldown alone doesn't count: the kick is only ~1s away.
	return ns.Readable(info.isActive) == true and ns.Readable(info.isOnGCD) ~= true
end

local function ApplyReadiness()
	local alpha = kickOnCD and 0 or 1
	-- Preview/test cards stay visible so frames can still be placed.
	if not castAlert.preview then castAlert:SetAlpha(alpha) end
	markerRoot:SetAlpha(alpha)
	kickButton.cdGate:SetAlpha(alpha)
	if ns.PanelReadiness then ns.PanelReadiness(alpha) end
end

local active = {}   -- [unit] = { channel = bool, t = GetTime(), ni = notInterruptible (maybe secret) }
local markers = {}  -- [unit] = nameplate marker frame
local lastSound = 0

-- Shared with Panel.lua.
ns.active = active
ns.PulseAnim = PulseAnim
ns.AccentBorder = AccentBorder
ns.GateOnInterruptible = GateOnInterruptible
ns.StartCastBar = StartCastBar

function ns.IsTrackedUnit(unit)
	return unit == "focus" or unit == "target" or (unit ~= nil and unit:match("^nameplate%d+$") ~= nil)
end

-- Returns isCasting, isChannel, notInterruptible (the latter may be secret).
local function CastState(unit)
	local name, _, _, _, _, _, _, ni = UnitCastingInfo(unit)
	if ns.Present(name) then return true, false, ni end
	local cname, _, _, _, _, _, cni = UnitChannelInfo(unit)
	if ns.Present(cname) then return true, true, cni end
	return false
end

local function CreateMarker()
	local m = CreateFrame("Frame", nil, markerRoot)
	m:SetSize(46, 18)
	m:SetFrameStrata("HIGH")
	m:EnableMouse(false)
	local inner = CreateFrame("Frame", nil, m, "BackdropTemplate")
	inner:SetAllPoints()
	ns.Skin(inner, 0.9, 0)
	inner:SetBackdropBorderColor(A[1], A[2], A[3], 1)
	m.text = ns.Text(inner, 11, "OUTLINE")
	m.text:SetPoint("CENTER", 0, 0)
	m.text:SetJustifyH("CENTER")
	m.text:SetText("KICK")
	m.text:SetTextColor(A[1], A[2], A[3])
	m.pulse = PulseAnim(inner, 1, 0.4, 0.3)
	m:Hide()
	return m
end

local function HideMarker(unit)
	local m = markers[unit]
	if m then
		m.pulse:Stop()
		m:ClearAllPoints()
		m:Hide()
	end
end

-- Put a pulsing "KICK" tag above the caster's nameplate. Enemy nameplates
-- may be off-limits to addons inside instances; if so this silently does
-- nothing and the center alert still works.
local function ShowMarker(unit)
	if not ns.db.plateMarkers or not ns.db.alertAll or not unit:match("^nameplate") then return end
	local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then return end
	local m = markers[unit] or CreateMarker()
	markers[unit] = m
	m:ClearAllPoints()
	if not pcall(m.SetPoint, m, "BOTTOM", plate, "TOP", 0, 2) then
		m:Hide()
		return
	end
	GateOnInterruptible(m, active[unit].ni)
	m:Show()
	m.pulse:Play()
end

local function SameMob(a, b)
	return ns.Readable(UnitIsUnit(a, b)) == true
end

-- Focus first (you chose it), then target, then newest nameplate casts.
-- A nameplate that is also the focus/target is folded into that card.
local function OrderedCasters()
	for unit in pairs(active) do
		if not CastState(unit) then
			active[unit] = nil
			HideMarker(unit)
		end
	end
	local list = {}
	if active.focus then list[#list + 1] = "focus" end
	if not ns.db.alertAll then return list end
	if active.target and not (active.focus and SameMob("target", "focus")) then
		list[#list + 1] = "target"
	end
	local plates = {}
	for unit in pairs(active) do
		if unit ~= "focus" and unit ~= "target"
			and not (active.focus and SameMob(unit, "focus"))
			and not (active.target and SameMob(unit, "target")) then
			plates[#plates + 1] = unit
		end
	end
	table.sort(plates, function(a, b) return active[a].t > active[b].t end)
	for _, unit in ipairs(plates) do list[#list + 1] = unit end
	return list
end

local function RenderCard(card, unit)
	local info = active[unit]
	local infoFn = info.channel and UnitChannelInfo or UnitCastingInfo
	local name, _, texture = infoFn(unit)

	card.title:SetText(unit == "focus" and "KICK FOCUS" or "INTERRUPT")

	-- Spell name/icon and caster name are secret in instances. Widgets may
	-- display secrets, so pass them straight through without inspecting them.
	card.spell:SetText("")
	if ns.Present(name) then pcall(card.spell.SetText, card.spell, name) end
	card.icon:SetTexture(kickButton.icon:GetTexture() or QUESTION_ICON)
	if ns.Present(texture) then pcall(card.icon.SetTexture, card.icon, texture) end

	local entry = unit == "focus" and ns.focusEntry or ns.LookupMob(UnitName(unit))
	card.note:SetText("")
	if entry then
		card.note:SetText(entry.name .. " — " .. (entry.note or ""))
	else
		pcall(card.note.SetText, card.note, UnitName(unit))
	end

	-- Tell the player how the kick key will reach this caster.
	local key = GetBindingKey(ns.KICK_BINDING) or "kick"
	if unit == "focus" or unit == "target" then
		card.hotkey:SetText("[" .. key .. "]")
	else
		card.hotkey:SetText("hover + [" .. key .. "]")
	end

	StartCastBar(card.bar, unit, info.channel)
	ns.SetHealth(card.hp, unit)
	ns.SetRaidMarker(card.marker, unit)
	GateOnInterruptible(card, info.ni)
	card.unit, card.castT = unit, info.t
	card:Show()
	card.pop:Play()
	card.glow.pulse:Play()
end

local function ClearCard(card)
	card.unit, card.castT = nil, nil
	card.bar:SetScript("OnUpdate", nil)
	card.glow.pulse:Stop()
	card:Hide()
end

function ns.CardsMarkers()
	for _, card in ipairs(cards) do
		if card.unit then ns.SetRaidMarker(card.marker, card.unit) end
	end
end

function ns.CardsHealth(unit)
	for _, card in ipairs(cards) do
		if card.unit == unit then ns.SetHealth(card.hp, unit) end
	end
end

function ns.HideCastAlert()
	if castAlert.preview then return end
	for _, card in ipairs(cards) do ClearCard(card) end
	kickButton.glow.pulse:Stop()
	kickButton.glow:SetAlpha(0)
	castAlert:Hide()
end

local function Layout()
	local list = OrderedCasters()
	if ns.UpdatePanel then ns.UpdatePanel() end
	if castAlert.preview then return end
	if #list == 0 then
		ns.HideCastAlert()
		return
	end
	castAlert:SetShown(ns.db.centerCards)
	for i, card in ipairs(cards) do
		local unit = ns.db.centerCards and i <= (ns.db.alertCards or 4) and list[i]
		if not unit then
			if card.unit then ClearCard(card) end
		elseif card.unit ~= unit or card.castT ~= active[unit].t then
			RenderCard(card, unit)
		end
	end
	-- The kick button glows along with the top card (and is hidden with it
	-- when that cast can't be interrupted).
	GateOnInterruptible(kickButton.glowGate, active[list[1]].ni)
	kickButton.glow.pulse:Play()
end

function ns.OnCastStart(unit, channel)
	if not ns.IsTrackedUnit(unit) then return end
	-- Skip friendly casters; if hostility is unreadable, assume hostile.
	if ns.Readable(UnitCanAttack("player", unit)) == false then return end

	local casting, isChannel, ni = CastState(unit)
	if not casting then return end
	if ns.Readable(ni) == true then
		-- Known to be uninterruptible (outside instances this is readable).
		ns.OnCastEnd(unit)
		return
	end

	active[unit] = { channel = isChannel, t = GetTime(), ni = ni }
	ShowMarker(unit)
	Layout()

	-- One sound per burst so a big pull doesn't turn into noise. Inside
	-- instances the addon can't tell kickable casts apart, so it still plays.
	local wanted = unit == "focus" or ns.db.alertAll or ns.db.panel
	if wanted and ns.db.sound and not kickOnCD and GetTime() - lastSound > 0.8 then
		lastSound = GetTime()
		PlaySound(SOUNDKIT.RAID_WARNING, "Master")
	end
end

-- Called on SPELL_UPDATE_COOLDOWN; while the kick is cooling down a light
-- ticker watches for it coming back, since no event reliably fires then.
function ns.UpdateKickReady()
	local onCD = KickOnCooldown()
	if onCD and not cdTicker then
		cdTicker = C_Timer.NewTicker(0.1, ns.UpdateKickReady)
	elseif not onCD and cdTicker then
		cdTicker:Cancel()
		cdTicker = nil
	end
	if onCD == kickOnCD then return end
	kickOnCD = onCD
	ApplyReadiness()
	-- Kick is back while casts are still going: re-alert.
	if not onCD and next(active) and ns.db.sound then
		lastSound = GetTime()
		PlaySound(SOUNDKIT.RAID_WARNING, "Master")
	end
end

function ns.OnCastEnd(unit)
	if not active[unit] then return end
	active[unit] = nil
	HideMarker(unit)
	Layout()
end

-- UNIT_SPELLCAST_(NOT_)INTERRUPTIBLE: the event name itself says which way
-- the cast flipped (e.g. a shield went up or came down mid-cast).
function ns.OnInterruptibleChanged(unit, notInterruptible)
	if not ns.IsTrackedUnit(unit) then return end
	if notInterruptible then
		ns.OnCastEnd(unit)
	elseif not active[unit] then
		ns.OnCastStart(unit)
	end
end

-- A unit token now points at a different mob (focus/target changed or a
-- nameplate was recycled): drop the old cast and pick up any new one.
function ns.OnUnitChanged(unit)
	ns.OnCastEnd(unit)
	if ns.Readable(UnitExists(unit)) ~= false then ns.OnCastStart(unit) end
end

--------------------------------------------------------------------------
-- Priority mob toast
--------------------------------------------------------------------------

local function CreateToast()
	toast = CreateFrame("Frame", "MPlusKickToast", UIParent, "BackdropTemplate")
	toast:SetSize(380, 46)
	toast:SetFrameStrata("HIGH")
	ns.Skin(toast, 0.94)
	ns.RestorePos(toast, "toastPos", "TOP", 0, -140)
	ns.MakeDraggable(toast, "toastPos")
	toast:Hide()

	local stripe = toast:CreateTexture(nil, "ARTWORK")
	stripe:SetColorTexture(A[1], A[2], A[3], 1)
	stripe:SetPoint("TOPLEFT", 1, -1)
	stripe:SetPoint("BOTTOMLEFT", 1, 1)
	stripe:SetWidth(3)

	toast.tag = ns.Text(toast, 10, "OUTLINE")
	toast.tag:SetPoint("TOPLEFT", 14, -8)
	toast.tag:SetText("PRIORITY")
	toast.tag:SetTextColor(A[1], A[2], A[3])

	toast.name = ns.Text(toast, 13, "OUTLINE")
	toast.name:SetPoint("LEFT", toast.tag, "RIGHT", 8, 0)
	toast.name:SetPoint("RIGHT", -10, 0)
	toast.name:SetWordWrap(false)

	toast.note = ns.Text(toast, 11)
	toast.note:SetPoint("BOTTOMLEFT", 14, 8)
	toast.note:SetPoint("RIGHT", -10, 0)
	toast.note:SetTextColor(0.8, 0.8, 0.8)
	toast.note:SetWordWrap(false)

	local show = toast:CreateAnimationGroup()
	local sc = show:CreateAnimation("Scale")
	sc:SetScaleFrom(1, 0.4)
	sc:SetScaleTo(1, 1)
	sc:SetDuration(0.18)
	sc:SetSmoothing("OUT")
	local a = show:CreateAnimation("Alpha")
	a:SetFromAlpha(0)
	a:SetToAlpha(1)
	a:SetDuration(0.18)
	toast.showAnim = show

	local hide = toast:CreateAnimationGroup()
	local h = hide:CreateAnimation("Alpha")
	h:SetFromAlpha(1)
	h:SetToAlpha(0)
	h:SetDuration(0.4)
	h:SetStartDelay(3.5)
	hide:SetScript("OnFinished", function() if not toast.preview then toast:Hide() end end)
	toast.hideAnim = hide
end

local function ShowToast(entry)
	toast.name:SetText(entry.name)
	toast.note:SetText((entry.note or "") .. "   |cff888888· shift-click the kick button to focus|r")
	toast.hideAnim:Stop()
	toast:Show()
	toast.showAnim:Play()
	toast.hideAnim:Play()
end

function ns.CheckPriorityMob(unit)
	if not ns.db.toasts or toast.preview then return end
	if ns.Readable(UnitExists(unit)) == false then return end
	if ns.Readable(UnitCanAttack("player", unit)) == false then return end
	local entry = ns.LookupMob(UnitName(unit))
	if not entry then return end
	if ns.Readable(UnitIsUnit(unit, "focus")) then return end -- already on it
	ShowToast(entry)
end

--------------------------------------------------------------------------
-- Focus / settings / preview
--------------------------------------------------------------------------

function ns.OnFocusChanged()
	-- Names are readable out of combat, so the note is cached when you focus
	-- a mob pre-pull and stays available once the pull starts.
	ns.focusEntry = ns.LookupMob(UnitName("focus"))
	ns.UpdateFocusLabel()
	ns.OnUnitChanged("focus")
end

function ns.ApplySettings()
	if InCombatLockdown() then
		pendingSettings = true
		return
	end
	pendingSettings = false
	kickButton:SetScale(ns.db.scale)
	kickButton:SetShown(ns.db.showButton)
	ns.ApplyPanelSettings()
	ns.SetPreview(not ns.db.locked)
end

function ns.OnLeaveCombat()
	if pendingRebuild then ns.RebuildMacro() end
	if pendingSettings then ns.ApplySettings() end
	ns.OnPanelLeaveCombat()
end

-- Preview mode: show the alert and toast with sample text so they can be
-- dragged into place. Mouse is only enabled while previewing so the frames
-- never eat clicks in the middle of the screen during a pull.
local PREVIEW_SAMPLES = {
	{ "INTERRUPT", "Light Bolt Volley", "Drag to move · corner to resize" },
	{ "INTERRUPT", "Disorienting Screech", "Lightfeather Petalwing" },
	{ "INTERRUPT", "Seed Shot", "Leafy Grovecrawler" },
	{ "INTERRUPT", "Lightspore Shot", "Lasher" },
	{ "INTERRUPT", "Earth Bolt", "Earthwhisper Tender" },
	{ "INTERRUPT", "Arc Lightning", "Stormbound Mystic" },
}

-- Fill the configured number of cards with sample casts while editing.
function ns.RefreshCardPreview()
	if not castAlert.preview then return end
	local n = ns.db.alertCards or 4
	for i, card in ipairs(cards) do
		ClearCard(card)
		if i <= n then
			local sample = PREVIEW_SAMPLES[i]
			card.title:SetText(sample[1])
			card.spell:SetText(sample[2])
			card.note:SetText(sample[3])
			card.hotkey:SetText("")
			card.icon:SetTexture(kickButton.icon:GetTexture() or QUESTION_ICON)
			card.bar:SetMinMaxValues(0, 1)
			card.bar:SetValue(0.6 - i * 0.08)
			card.hp:SetMinMaxValues(0, 1)
			card.hp:SetValue(0.9 - i * 0.12)
			card.hp:Show()
			card.bar:Show()
			card:SetAlpha(1)
			card:Show()
		end
	end
	castAlert.editBar.Refresh()
end

-- Preview mode: show the alert and toast with sample text so they can be
-- moved and resized. Mouse is only enabled while previewing so the frames
-- never eat clicks in the middle of the screen during a pull.
function ns.SetPreview(on)
	ns.PanelPreview(on)
	castAlert.preview, toast.preview = on, on
	castAlert:EnableMouse(on)
	toast:EnableMouse(on)
	castAlert.grip:SetShown(on)
	castAlert.editBar:SetShown(on)
	castAlert:SetAlpha(on and 1 or (kickOnCD and 0 or 1))
	if on then
		castAlert:Show()
		ns.RefreshCardPreview()
		toast.name:SetText("Radiant Spellsower")
		toast.note:SetText("Drag me · priority mob toast")
		toast.hideAnim:Stop()
		toast:SetAlpha(1)
		toast:Show()
	else
		for _, card in ipairs(cards) do ClearCard(card) end
		castAlert:Hide()
		toast:Hide()
		Layout()
	end
end

function ns.TestAlerts()
	if castAlert.preview then return end
	local key = GetBindingKey(ns.KICK_BINDING) or "kick"
	local samples = {
		{ "INTERRUPT", "Light Bolt Volley", "Radiant Spellsower — Kick EVERY cast: Light Bolt Volley", "hover + [" .. key .. "]" },
		{ "INTERRUPT", "Disorienting Screech", "Lightfeather Petalwing — Kick EVERY cast", "[" .. key .. "]" },
	}
	local start = GetTime()
	castAlert:SetAlpha(1)
	castAlert:Show()
	for i, sample in ipairs(samples) do
		local card = cards[i]
		card.title:SetText(sample[1])
		card.spell:SetText(sample[2])
		card.note:SetText(sample[3])
		card.hotkey:SetText(sample[4])
		card.icon:SetTexture(kickButton.icon:GetTexture() or QUESTION_ICON)
		card.hp:SetMinMaxValues(0, 1)
		card.hp:SetValue(0.75 - i * 0.3)
		card.hp:Show()
		card.bar:SetMinMaxValues(0, 2.5)
		card.bar:SetScript("OnUpdate", function(self)
			local t = GetTime() - start
			self:SetValue(t)
			if t >= 2.5 then
				ns.HideCastAlert()
				ApplyReadiness()
			end
		end)
		card.bar:Show()
		card:SetAlpha(1)
		card:Show()
		card.pop:Play()
		card.glow.pulse:Play()
	end
	kickButton.glowGate:SetAlpha(1)
	kickButton.glow.pulse:Play()
	if ns.db.sound then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
	ShowToast({ name = "Radiant Spellsower", note = "Kick EVERY cast: Light Bolt Volley" })
	ns.PanelTest()
end

function ns.ResetPositions()
	if InCombatLockdown() then ns.Print("Can't move frames in combat.") return end
	ns.db.buttonPos, ns.db.alertPos, ns.db.toastPos, ns.db.panelPos = nil, nil, nil, nil
	ns.db.alertW, ns.db.alertH = nil, nil
	LayoutCards()
	ns.RestorePos(MPlusKickPanel, "panelPos", "LEFT", 40, 40)
	ns.RestorePos(kickButton, "buttonPos", "CENTER", 0, -180)
	ns.RestorePos(castAlert, "alertPos", "CENTER", 0, 160)
	ns.RestorePos(toast, "toastPos", "TOP", 0, -140)
	ns.Print("Positions reset.")
end

function ns.GetKickSpell()
	return ns.ActiveKickSpell()
end

function ns.CreateUI()
	CreateKickButton()
	CreateCastAlert()
	CreateToast()
	ns.CreatePanel()
	ns.UpdateBindingText()
	ns.UpdateFocusLabel()
	ns.ApplySettings()
end
