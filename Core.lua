local ADDON, ns = ...

BINDING_HEADER_MPLUSKICK = "MPlusKick"
_G["BINDING_NAME_CLICK MPlusKickButton:LeftButton"] = "Interrupt (focus > mouseover > target)"
_G["BINDING_NAME_CLICK MPlusKickFocusButton:LeftButton"] = "Set focus (mouseover > target)"

ns.KICK_BINDING = "CLICK MPlusKickButton:LeftButton"
ns.FOCUS_BINDING = "CLICK MPlusKickFocusButton:LeftButton"

-- Interrupt candidates per class, in priority order. The first one the player
-- knows is used. Warlock uses Command Demon so it follows whatever pet is out.
local INTERRUPTS = {
	WARRIOR     = { 6552 },            -- Pummel
	ROGUE       = { 1766 },            -- Kick
	MAGE        = { 2139 },            -- Counterspell
	DEATHKNIGHT = { 47528 },           -- Mind Freeze
	DEMONHUNTER = { 183752 },          -- Disrupt
	HUNTER      = { 147362, 187707 },  -- Counter Shot, Muzzle
	PALADIN     = { 96231 },           -- Rebuke
	SHAMAN      = { 57994 },           -- Wind Shear
	MONK        = { 116705 },          -- Spear Hand Strike
	DRUID       = { 106839, 78675 },   -- Skull Bash, Solar Beam
	PRIEST      = { 15487 },           -- Silence
	EVOKER      = { 351338 },          -- Quell
	WARLOCK     = { 119898 },          -- Command Demon (Spell Lock / Axe Toss)
}

local DEFAULTS = {
	mobs = {},        -- [lowername] = { name = "Mob", note = "..." }
	sound = true,
	toasts = true,
	alertAll = true,     -- alert on any hostile cast, not just focus
	plateMarkers = true, -- "KICK" tag above casting nameplates
	hideOnCD = true,     -- hide cast alerts while your kick is on cooldown
	panel = true,        -- casting panel (one tile per nameplate)
	hoverSelect = true,  -- hovering a panel tile selects its mob as mouseover
	kickLog = true,      -- interrupt tracker in the panel footer
	rangeFade = true,    -- fade lit tiles that are out of kick range
	panelDungeonOnly = true, -- only show the casting panel inside dungeons
	spellOverrides = {}, -- [lowercase spell] = true/false: your right-click "important" choices
	runs = {},           -- last 10 run recaps, newest first
	centerCards = true,  -- center-screen cast alert cards
	showButton = true,
	locked = true,
	scale = 1,
	buttonPos = nil,  -- { point, x, y }
	alertPos = nil,
	toastPos = nil,
}

ns.ACCENT = { 1, 0.45, 0.15 }

-- Secret values (Midnight) cannot be compared or used as table keys.
-- Return nil for anything the addon is not allowed to inspect.
function ns.Readable(v)
	if v == nil then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

-- True if a value is present. Secrets count as present (a secret cast name
-- still means "something is being cast"), and are never compared directly.
function ns.Present(v)
	if issecretvalue and issecretvalue(v) then return true end
	return v ~= nil
end

function ns.Print(msg)
	print("|cffff7326MPlusKick|r: " .. msg)
end

local function KnowsSpell(id)
	if IsPlayerSpell and IsPlayerSpell(id) then return true end
	if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id) then return true end
	if IsSpellKnown and IsSpellKnown(id) then return true end
	return false
end

function ns.FindInterrupt()
	local _, class = UnitClass("player")
	local list = INTERRUPTS[class]
	if not list then return nil end
	for _, id in ipairs(list) do
		if KnowsSpell(id) then return id end
	end
	-- Warlock pet commands don't always report as known; fall back anyway.
	if class == "WARLOCK" then return list[1] end
	return nil
end

--------------------------------------------------------------------------
-- Priority list
--------------------------------------------------------------------------

function ns.LookupMob(name)
	name = ns.Readable(name)
	if not name then return nil end
	local key = name:lower()
	return ns.db.mobs[key] or ns.KnownMobsLower[key]
end

function ns.AddTarget(note)
	local name = ns.Readable(UnitName("target"))
	if not name or not UnitExists("target") then
		ns.Print("Target a mob first (names can't be read in combat inside instances).")
		return false
	end
	if note == "" then note = nil end
	ns.db.mobs[name:lower()] = { name = name, note = note }
	ns.Print(("Added %s%s"):format(name, note and (" — " .. note) or ""))
	if ns.RefreshOptions then ns.RefreshOptions() end
	return true
end

function ns.RemoveMob(name)
	ns.db.mobs[name:lower()] = nil
	if ns.RefreshOptions then ns.RefreshOptions() end
end

--------------------------------------------------------------------------
-- Frame positions
--------------------------------------------------------------------------

function ns.SavePos(frame, key)
	local point, _, _, x, y = frame:GetPoint()
	ns.db[key] = { point, x, y }
end

function ns.RestorePos(frame, key, defPoint, defX, defY)
	frame:ClearAllPoints()
	local p = ns.db[key]
	if p then
		frame:SetPoint(p[1], UIParent, p[1], p[2], p[3])
	else
		frame:SetPoint(defPoint, UIParent, defPoint, defX, defY)
	end
end

function ns.MakeDraggable(frame, key)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if InCombatLockdown() then return end
		if IsShiftKeyDown() or not ns.db.locked then self:StartMoving() end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		ns.SavePos(self, key)
	end)
end

--------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------

-- Problems hit while loading, shown by /mk debug.
ns.loadErrors = {}

local function Guard(label, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		ns.loadErrors[#ns.loadErrors + 1] = label .. ": " .. tostring(err)
	end
	return ok
end

function ns.DebugReport()
	ns.Print(("version %s, interface %s"):format(
		C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?",
		tostring(GetBuildInfo and select(4, GetBuildInfo()) or "?")))
	if #ns.loadErrors == 0 then
		ns.Print("Loaded without errors.")
	else
		for _, e in ipairs(ns.loadErrors) do ns.Print("|cffff5555LOAD ERROR|r " .. e) end
	end
	if ns.KicksDebugRoster then
		ns.Print("Interrupt tracker group (kicks by these GUIDs are credited):")
		ns.KicksDebugRoster()
	end
	if ns.PanelDebugSummary then
		local ok, err = pcall(ns.PanelDebugSummary)
		if not ok then ns.Print("|cffff5555panel check failed|r " .. tostring(err)) end
	else
		ns.Print("Casting panel was not created.")
	end
end

local function SlashHandler(msg)
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	if not ns.db then
		ns.Print("Not loaded yet. Errors so far:")
		for _, e in ipairs(ns.loadErrors) do ns.Print(e) end
		return
	end
	-- /mk debug must work even if the rest of the addon failed to load.
	if cmd == "debug" then
		ns.db.debug = not ns.db.debug
		ns.Print("Debug " .. (ns.db.debug and "on." or "off."))
		if ns.db.debug then ns.DebugReport() end
		return
	end
	local ok, err = pcall(function()

	if cmd == "" or cmd == "config" or cmd == "options" then
		ns.ToggleOptions()
	elseif cmd == "add" then
		ns.AddTarget(rest)
	elseif cmd == "remove" then
		local name = rest ~= "" and rest or ns.Readable(UnitName("target"))
		if not name then ns.Print("Usage: /mk remove <name> (or target the mob)") return end
		ns.RemoveMob(name)
		ns.Print("Removed " .. name)
	elseif cmd == "unlock" or cmd == "lock" then
		if InCombatLockdown() then ns.Print("Can't edit frames in combat.") return end
		ns.db.locked = cmd == "lock"
		ns.ApplySettings()
		if ns.RefreshOptions then ns.RefreshOptions() end
		ns.Print(cmd == "lock" and "Frames locked." or "Frames unlocked: drag to move, drag the panel's corner to resize.")
	elseif cmd == "kicks" then
		if rest:lower() == "reset" then
			ns.ResetKicks(ns.db.kickStats and ns.db.kickStats.instance)
			ns.Print("Interrupt counts reset.")
		else
			ns.SyncKicksFromMeter()
			local players, unknown, total = ns.KickRows()
			ns.Print(("Interrupts this run: %d"):format(total))
			for _, e in ipairs(players) do ns.Print(("  %s: %d landed, %d pressed"):format(e.name, e.landed, e.cast)) end
			if unknown > 0 then ns.Print(("  unattributed: %d"):format(unknown)) end
		end
	elseif cmd == "runs" or cmd == "recap" then
		ns.ShowRuns(cmd == "recap" and 0 or nil)
	elseif cmd == "important" then
		if rest ~= "" then
			ns.ToggleImportant(rest, nil)
		else
			local any = false
			for spell, v in pairs(ns.db.spellOverrides) do
				any = true
				ns.Print(("  %s: %s"):format(spell, v and "important" or "not important"))
			end
			if not any then ns.Print("No custom important spells. Right-click a spell in the interrupt details, or /mk important <spell name>.") end
		end
	elseif cmd == "test" then
		ns.TestAlerts()
	elseif cmd == "reset" then
		ns.ResetPositions()
	else
		ns.Print("/mk — open the options window")
		ns.Print("/mk add <note> — add your target to the priority list")
		ns.Print("/mk remove [name] — remove a mob")
		ns.Print("/mk unlock | lock — move and resize frames")
		ns.Print("/mk kicks [reset] — interrupt counts this run")
		ns.Print("/mk runs | recap — run history / current run recap")
		ns.Print("/mk important [spell] — list or toggle your important spells")
		ns.Print("/mk test — preview the alerts")
		ns.Print("/mk reset — reset frame positions")
		ns.Print("/mk debug — show load errors and panel status")
	end
	end)
	if not ok then ns.Print("|cffff5555error|r " .. tostring(err)) end
end

-- Register the slash command immediately, before anything can fail.
SLASH_MPLUSKICK1 = "/mk"
SLASH_MPLUSKICK2 = "/mpluskick"
SlashCmdList.MPLUSKICK = SlashHandler

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------

local CAST_START = {
	UNIT_SPELLCAST_START = false,
	UNIT_SPELLCAST_CHANNEL_START = true, -- value = is channel
	UNIT_SPELLCAST_EMPOWER_START = true,
}
local CAST_END = {
	UNIT_SPELLCAST_STOP = true,
	UNIT_SPELLCAST_CHANNEL_STOP = true,
	UNIT_SPELLCAST_EMPOWER_STOP = true,
	UNIT_SPELLCAST_INTERRUPTED = true,
	UNIT_SPELLCAST_FAILED = true,
}

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
local function OnEvent(self, event, arg1, ...)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then return end
		MPlusKickDB = MPlusKickDB or {}
		ns.db = MPlusKickDB
		for k, v in pairs(DEFAULTS) do
			if ns.db[k] == nil then ns.db[k] = type(v) == "table" and {} or v end
		end
		ns.KnownMobsLower = {}
		for name, note in pairs(ns.KnownMobs) do
			ns.KnownMobsLower[name:lower()] = { name = name, note = note }
		end

		Guard("CreateUI", ns.CreateUI)
		Guard("CreateOptions", ns.CreateOptions)

		self:UnregisterEvent("ADDON_LOADED")
		-- One registration per call: an event missing from this client version
		-- is recorded instead of stopping every registration after it.
		local events = {
			"PLAYER_LOGIN", "PLAYER_SPECIALIZATION_CHANGED", "SPELLS_CHANGED",
			"PLAYER_REGEN_ENABLED", "PLAYER_FOCUS_CHANGED", "PLAYER_TARGET_CHANGED",
			"UPDATE_MOUSEOVER_UNIT", "SPELL_UPDATE_COOLDOWN", "UPDATE_BINDINGS",
			"NAME_PLATE_UNIT_REMOVED", "NAME_PLATE_UNIT_ADDED",
			"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
			"UNIT_SPELLCAST_SUCCEEDED", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD",
			"CHALLENGE_MODE_START", "UNIT_PET",
			"DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_RESET",
			"UNIT_HEALTH", "UNIT_MAXHEALTH",
			"RAID_TARGET_UPDATE", "CHALLENGE_MODE_COMPLETED", "INSPECT_READY",
		}
		-- Not unit-filtered: casts from target and enemy nameplates count too.
		for e in pairs(CAST_START) do events[#events + 1] = e end
		for e in pairs(CAST_END) do events[#events + 1] = e end
		for _, e in ipairs(events) do Guard("event " .. e, self.RegisterEvent, self, e) end

		if #ns.loadErrors > 0 then
			ns.Print("|cffff5555loaded with errors|r — type /mk debug for details.")
		end
	elseif event == "UNIT_PET" and arg1 ~= "player" then
		ns.KicksRoster() -- a party member's pet changed
	elseif event == "PLAYER_LOGIN" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "SPELLS_CHANGED" or event == "UNIT_PET" then
		-- Macro text can only change out of combat; the icon, cooldown and
		-- readiness follow a pet swap immediately.
		ns.RebuildMacro()
		ns.UpdateKickIcon()
		ns.UpdateCooldown()
		ns.UpdateKickReady()
		if event == "UNIT_PET" then ns.KicksRoster() end
		ns.CD_Roster() -- spec or pet changed: maybe a different interrupt
		if ns.RefreshOptions then ns.RefreshOptions() end
	elseif event == "PLAYER_REGEN_ENABLED" then
		ns.OnLeaveCombat()
		ns.OnKicksLeaveCombat()
		ns.OnKicksLeaveCombatRuns()
		ns.CD_OnLeaveCombat()
	elseif event == "RAID_TARGET_UPDATE" then
		ns.PanelMarkers()
		ns.CardsMarkers()
	elseif event == "CHALLENGE_MODE_COMPLETED" then
		ns.OnKeystoneComplete()
	elseif event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" or event == "DAMAGE_METER_RESET" then
		-- Readable inside the meter's own events; the sync notices resets.
		ns.SyncKicksFromMeter()
	elseif event == "SPELL_UPDATE_COOLDOWN" then
		ns.UpdateCooldown()
		ns.UpdateKickReady()
	elseif event == "UPDATE_BINDINGS" then
		ns.UpdateBindingText()
	elseif event == "PLAYER_FOCUS_CHANGED" then
		ns.OnFocusChanged()
	elseif event == "PLAYER_TARGET_CHANGED" then
		ns.OnUnitChanged("target")
		ns.CheckPriorityMob("target")
	elseif event == "NAME_PLATE_UNIT_REMOVED" then
		ns.OnCastEnd(arg1)
		ns.PanelUnitChanged(arg1)
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		ns.PanelUnitChanged(arg1)
		ns.OnUnitChanged(arg1)
	elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
		ns.OnInterruptibleChanged(arg1, event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		ns.CheckPriorityMob("mouseover")
	elseif CAST_START[event] ~= nil then
		ns.OnCastStart(arg1)
	elseif CAST_END[event] then
		if event == "UNIT_SPELLCAST_INTERRUPTED" then
			ns.OnInterrupted(arg1, ...)
			ns.CD_OnInterrupted(arg1, ...)
		end
		ns.OnCastEnd(arg1)
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		ns.OnSpellSucceeded(arg1, ...)
		ns.CD_OnSucceeded(arg1, ...)
	elseif event == "INSPECT_READY" then
		ns.CD_OnInspect(arg1)
	elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
		if ns.IsTrackedUnit(arg1) then
			ns.PanelHealth(arg1)
			ns.CardsHealth(arg1)
		end
	elseif event == "GROUP_ROSTER_UPDATE" then
		ns.KicksRoster()
		ns.CD_Roster()
	elseif event == "PLAYER_ENTERING_WORLD" then
		ns.OnKicksEnterWorld()
		ns.CD_Roster()
		ns.ApplyPanelSettings() -- dungeon-only visibility
	elseif event == "CHALLENGE_MODE_START" then
		ns.OnKeystoneStart()
	end
end

-- Runtime errors are recorded (once per event) for /mk debug instead of
-- spamming error popups mid-pull.
local reported = {}
f:SetScript("OnEvent", function(self, event, ...)
	local ok, err = pcall(OnEvent, self, event, ...)
	if not ok and not reported[event] then
		reported[event] = true
		ns.loadErrors[#ns.loadErrors + 1] = "runtime " .. event .. ": " .. tostring(err)
		ns.Print("|cffff5555error|r in " .. event .. " — type /mk debug for details.")
	end
end)
