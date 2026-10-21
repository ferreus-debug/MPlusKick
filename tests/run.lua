-- Minimal WoW API stub to load MPlusKick and exercise its main paths.
-- Run from the repository root:  lua tests/run.lua
-- Prints "ALL OK" on success; any failed check or addon error aborts.
local mockmt = {}
local function newmock() return setmetatable({}, mockmt) end
local NUMERIC = { GetStringWidth = 50, GetStringHeight = 12, GetFrameLevel = 1, GetEffectiveScale = 1, GetLeft = 40, GetTop = 700 }
mockmt.__index = function(t, k)
	-- Addon-defined fields are lowercase and simply unset until assigned;
	-- only WoW widget methods (CamelCase) are faked.
	if type(k) == "string" and k:sub(1, 1):match("%l") then return nil end
	local f = function(self, ...)
		if k == "GetText" then return "" end
		if k == "IsShown" then return true end
		if NUMERIC[k] then return NUMERIC[k] end
		if k == "GetPoint" then return "CENTER", nil, "CENTER", 0, 0 end
		if k == "GetScrollChild" then
			rawset(self, "_child", rawget(self, "_child") or newmock())
			return rawget(self, "_child")
		end
		return newmock()
	end
	rawset(t, k, f)
	return f
end
mockmt.__call = function() return newmock() end

handlers = {}
function CreateFrame(kind, name, parent, template)
	local f = newmock()
	local scripts, attrs = {}, {}
	rawset(f, "_scripts", scripts)
	rawset(f, "_attrs", attrs)
	rawset(f, "SetScript", function(self, ev, fn) scripts[ev] = fn end)
	rawset(f, "HookScript", function(self, ev, fn) scripts[ev] = fn end)
	rawset(f, "SetAlpha", function(self, a) rawset(self, "_lastAlpha", a) end)
	rawset(f, "SetAttribute", function(self, k, v) attrs[k] = v end)
	rawset(f, "GetAttribute", function(self, k) return attrs[k] end)
	if name then _G[name] = f end
	table.insert(handlers, f)
	return f
end

SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
function issecretvalue(v) return rawequal(v, SECRET) end
UIParent, GameTooltip, UISpecialFrames = newmock(), newmock(), {}
SOUNDKIT = setmetatable({}, { __index = function() return 1 end })
STANDARD_TEXT_FONT = "x"
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
NOW = 1
function GetTime() return NOW end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function tinsert(t, v) table.insert(t, v) end
function UnitClass(u) return "Warlock", "WARLOCK" end
function IsPlayerSpell() return true end
function InCombatLockdown() return false end
function GetBindingKey() return "V" end
function UnitExists(u) return u == "player" or u == "pet" or u == "party1" or u:match("^nameplate") ~= nil end
function UnitName(u) return ({ player = "Netheron", party1 = "Tankyboi", pet = "Thoodom" })[u] or "Mob" end
function UnitGUID(u) return "GUID-" .. u end
function UnitCanAttack(_, u) return u:match("^nameplate") ~= nil end
function UnitIsUnit() return false end
function UnitIsDead() return false end
function UnitHealth() return SECRET end
function UnitHealthMax() return SECRET end
casting = {}
function UnitCastingInfo(u) if casting[u] then return "Light Bolt Volley", nil, 123, 1000, 3000, false, 7, SECRET, 555 end end
function UnitChannelInfo() return nil end
function PlaySound() end
function GetCursorPosition() return 0, 0 end
function GetInstanceInfo() return "Murder Row", "party", 8, "Mythic Keystone", 5, 0, false, 2811 end
function CreateColor() return {} end
function GameTooltip_Hide() end
function HideUIPanel() end
INSTANCE = "party"
function GetSpecialization() return 1 end
function GetSpecializationInfo() return 265 end           -- Affliction
function UnitGroupRolesAssigned(u) return u == "party2" and "HEALER" or "DAMAGER" end
INSPECTED = {}
function CanInspect() return true end
function NotifyInspect(u) INSPECTED[#INSPECTED + 1] = u end
INSPECT_SPECS = { party1 = 71, party2 = 255 }
function GetInspectSpecialization(u) return INSPECT_SPECS[u] end
function ClearInspectPlayer() end
function IsInInstance() return INSTANCE ~= "none", INSTANCE end
MARKERS = { nameplate3 = 8 }
function GetRaidTargetIndex(u) return MARKERS[u] end
date = os.date
RANGE = {}
function Ambiguate(n) return (n:gsub("%-.*", "")) end
C_Timer = { After = function(_, fn) end, NewTimer = function() return newmock() end, NewTicker = function() return newmock() end }
C_NamePlate = { GetNamePlateForUnit = function() return newmock() end }
C_Spell = {
	GetSpellName = function(id) return ({ [1001] = "Light Bolt Volley", [1002] = "Frostbolt", [1003] = "Light Bolt", [119898] = "Command Demon" })[id] or "Kick" end,
	GetSpellTexture = function() return 136000 end,
	GetSpellCooldown = function() return { startTime = 0, duration = 0, isActive = false, isOnGCD = false } end,
	GetOverrideSpell = function() return 119910 end,
	IsSpellInRange = function(_, u) return RANGE[u] end,
}
SlashCmdList = {}
Settings = { RegisterCanvasLayoutCategory = function() return {} end, RegisterAddOnCategory = function() end }

-- Fake Blizzard damage meter. 12.1.5: sourceGUID may be hidden.
Enum = { DamageMeterSessionType = { Overall = 0 }, DamageMeterType = { Interrupts = 5 } }
METER = {}
METER_GUID = { Netheron = "GUID-player", Thoodom = "GUID-pet", Tankyboi = "GUID-party1" }
HIDE_GUIDS = false
C_ChallengeMode = {
	GetChallengeCompletionInfo = function() return { mapChallengeModeID = 999, level = 12, time = 1834000, onTime = true } end,
	GetMapUIInfo = function() return "Murder Row" end,
}
C_DamageMeter = {
	GetCombatSessionFromType = function()
		local srcs = {}
		for name, d in pairs(METER) do
			srcs[#srcs + 1] = {
				sourceGUID = HIDE_GUIDS and SECRET or METER_GUID[name],
				isLocalPlayer = METER_GUID[name] == "GUID-player",
				name = name .. "-Realm", classFilename = "WARLOCK", totalAmount = d.total,
			}
		end
		return { combatSources = srcs }
	end,
	GetCombatSessionSourceFromType = function(_, _, guid)
		if rawequal(guid, SECRET) then error("secret GUID from tainted code") end
		for name, g in pairs(METER_GUID) do
			if g == guid and METER[name] then
				local list = {}
				for _, sp in ipairs(METER[name].spells) do list[#list + 1] = { spellID = sp[1], totalAmount = sp[2], creatureName = sp[3] } end
				return { combatSpells = list }
			end
		end
	end,
}

-- Load the addon in TOC order.
local ns = {}
for _, file in ipairs({ "Data.lua", "Core.lua", "UI.lua", "Panel.lua", "Kicks.lua", "PartyCD.lua", "Options.lua" }) do
	assert(loadfile("MPlusKick/" .. file))("MPlusKick", ns)
end
local core = handlers[1]
local function ev(e, ...) core._scripts.OnEvent(core, e, ...) end

ev("ADDON_LOADED", "MPlusKick")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "UNIT_PET", "SPELL_UPDATE_COOLDOWN", "UPDATE_BINDINGS", "GROUP_ROSTER_UPDATE" }) do ev(e, "player") end

-- Casts, health, cooldown, panel.
casting.nameplate3 = true
ev("NAME_PLATE_UNIT_ADDED", "nameplate3")
ev("UNIT_SPELLCAST_START", "nameplate3")
ev("UNIT_HEALTH", "nameplate3")
casting.nameplate3 = nil
ev("UNIT_SPELLCAST_INTERRUPTED", "nameplate3", "cast-1", 1001, "GUID-pet")
assert(ns.KickRows()[1].landed == 1, "live interrupt credited to pet owner")

-- Meter sync with readable GUIDs.
METER = { Netheron = { total = 0, spells = {} }, Thoodom = { total = 0, spells = {} }, Tankyboi = { total = 0, spells = {} } }
SlashCmdList.MPLUSKICK("kicks reset")
METER.Thoodom = { total = 2, spells = { { 1001, 2, "Radiant Spellsower" } } }
METER.Tankyboi = { total = 1, spells = { { 1002, 1, "Random Trash" } } }
assert(ns.SyncKicksFromMeter(), "sync")
local function byName()
	local t = {}
	for _, e in ipairs(ns.KickRows()) do t[e.name] = e end
	return t
end
local b = byName()
assert(b.Netheron.landed == 2 and b.Tankyboi.landed == 1 and not b.Thoodom, "pet folded, readable GUIDs")

-- 12.1.5: hidden GUIDs -> isLocalPlayer / names.
HIDE_GUIDS = true
METER.Thoodom = { total = 3, spells = { { 1001, 3, "Radiant Spellsower" } } }
METER.Netheron = { total = 1, spells = { { 1003, 1, "Kezkitt" } } }
METER.Tankyboi = { total = 2, spells = { { 1002, 2, "Random Trash" } } }
assert(ns.SyncKicksFromMeter(), "sync with hidden GUIDs")
b = byName()
print("12.1.5 sync:", b.Netheron.landed, b.Tankyboi.landed)
assert(b.Netheron.landed == 4 and b.Tankyboi.landed == 2 and not b.Thoodom, "hidden GUIDs resolved")
local _, _, list = ns.KickDetails("GUID-player")
assert(#list == 2 and list[1].name == "Light Bolt Volley" and list[1].count == 3, "breakdown with hidden GUIDs")

-- 1. Range fade: secret and readable results.
local tile = _G.MPlusKickTile3
local function recheck() NOW = NOW + 1; ev("UNIT_SPELLCAST_START", "nameplate3") end
casting.nameplate3 = true
RANGE.nameplate3 = false
recheck()
assert(tile.rangeGate._lastAlpha == 0.25, "out of range fades")
RANGE.nameplate3 = true; recheck()
assert(tile.rangeGate._lastAlpha == 1, "in range full")
RANGE.nameplate3 = SECRET; recheck()  -- secret -> SetAlphaFromBoolean (mock), no error
RANGE.nameplate3 = nil; recheck()
assert(tile.rangeGate._lastAlpha == 1, "no range info: no fade")

-- 2. Raid markers: readable, secret, none.
ev("RAID_TARGET_UPDATE")
MARKERS.nameplate3 = SECRET; ev("RAID_TARGET_UPDATE")
MARKERS.nameplate3 = nil; ev("RAID_TARGET_UPDATE")

-- 3. Toggle important.
local _, _, l1 = ns.KickDetails("GUID-player")
local fb; for _, r in ipairs(l1) do if r.name == "Frostbolt" then fb = r end end
-- Frostbolt belongs to Tankyboi in the meter data; use Netheron's Light Bolt (listed spell) instead
local lb; for _, r in ipairs(l1) do if r.name == "Light Bolt" then lb = r end end
assert(lb and lb.important, "Light Bolt important by default")
ns.ToggleImportant("Light Bolt", lb.mob)
_, _, l1 = ns.KickDetails("GUID-player")
for _, r in ipairs(l1) do if r.name == "Light Bolt" then lb = r end end
assert(lb.important == false and ns.db.spellOverrides["light bolt"] == false, "toggled off")
ns.ToggleImportant("Light Bolt", lb.mob)
assert(ns.db.spellOverrides["light bolt"] == nil, "back to default clears override")
SlashCmdList.MPLUSKICK("important Frostbolt")
assert(ns.db.spellOverrides["frostbolt"] == true, "slash toggle")
SlashCmdList.MPLUSKICK("important")

-- 4. Run recap on key completion.
local after = {}
C_Timer.After = function(_, fn) after[#after + 1] = fn end
ev("CHALLENGE_MODE_COMPLETED")
for _, fn in ipairs(after) do fn() end
assert(#ns.db.runs == 1, "run saved")
local run = ns.db.runs[1]
print("run:", run.dungeon, run.level, run.onTime, run.time, run.total, #run.players)
assert(run.dungeon == "Murder Row" and run.level == 12 and run.onTime == true, "completion info")
assert(run.players[1].name == "Netheron" and run.players[1].landed == 4, "players in recap")
for k = 1, 12 do ns.db.runs[#ns.db.runs + 1] = run end
ev("CHALLENGE_MODE_COMPLETED"); for _, fn in ipairs(after) do fn() end
assert(#ns.db.runs == 10, "capped at 10")
SlashCmdList.MPLUSKICK("runs"); SlashCmdList.MPLUSKICK("recap"); ns.ShowRuns(3)

-- 5. Panel only in dungeons.
local panelFrame = _G.MPlusKickPanel
rawset(panelFrame, "SetShown", function(self, v) rawset(self, "_shown", v) end)
INSTANCE = "none"; ev("PLAYER_ENTERING_WORLD")
assert(panelFrame._shown == false, "hidden outside dungeons")
SlashCmdList.MPLUSKICK("unlock")
assert(panelFrame._shown == true, "shown while unlocked")
SlashCmdList.MPLUSKICK("lock")
assert(panelFrame._shown == false, "hidden again after lock")
INSTANCE = "party"; ev("PLAYER_ENTERING_WORLD")
assert(panelFrame._shown == true, "shown in dungeon")
ns.db.panelDungeonOnly = false; INSTANCE = "none"; ns.ApplySettings()
assert(panelFrame._shown == true, "option off: shown everywhere")

-- 6. Party kick cooldowns.
CLASSES = { player = "WARLOCK", party1 = "WARRIOR", party2 = "HUNTER" }
UnitClass = function(u) return "x", CLASSES[OwnerTestUnit and OwnerTestUnit or u] or CLASSES[u] end
UnitExists = function(u) return u == "player" or u == "pet" or u == "party1" or u == "party2" or u:match("^nameplate") ~= nil end
UnitName = function(u) return ({ player = "Netheron", party1 = "Tankyboi", party2 = "Shooty", pet = "Thoodom" })[u] or "Mob" end
UnitGUID = function(u) return "GUID-" .. u end
C_Timer.NewTimer = function() return { Cancel = function() end } end
ev("GROUP_ROSTER_UPDATE")
local function status(g) local icon, rem, est, spell = ns.KickStatus(g); return spell, rem, est end
print("party1 kick:", status("GUID-party1"))
assert(select(1, status("GUID-player")) == 19647, "warlock: Spell Lock")
assert(select(1, status("GUID-party1")) == 6552, "warrior: Pummel")
-- party2 is a hunter, healer role is irrelevant for hunters; inspect says Survival
ev("INSPECT_READY", "GUID-" .. INSPECTED[1])
for k = 2, #INSPECTED do ev("INSPECT_READY", "GUID-" .. INSPECTED[k]) end
print("inspected:", table.concat(INSPECTED, ","), "party2 kick:", status("GUID-party2"))
assert(select(1, status("GUID-party2")) == 187707, "survival: Muzzle via inspect")

-- (1) readable party spell
NOW = 100
ev("UNIT_SPELLCAST_SUCCEEDED", "party1", "c", 6552)
local _, rem = status("GUID-party1")
assert(rem == 15, "Pummel 15s")
-- (3) secret spell + interrupt in the same instant -> estimated
NOW = 120
ev("UNIT_SPELLCAST_SUCCEEDED", "party2", "c", SECRET)
NOW = 120.1
ev("UNIT_SPELLCAST_INTERRUPTED", "nameplate4", SECRET, SECRET, SECRET)
local sp2, rem2, est2 = status("GUID-party2")
print("estimated:", sp2, rem2, est2)
assert(rem2 == 15 and est2 == true, "estimated Muzzle")
-- secret cast too long before the interrupt -> not credited
NOW = 200
ev("UNIT_SPELLCAST_SUCCEEDED", "party1", "c", SECRET)
NOW = 201
ev("UNIT_SPELLCAST_INTERRUPTED", "nameplate5", SECRET, SECRET, SECRET)
assert(select(2, status("GUID-party1")) == 0, "no false credit outside the window")
-- (2) interruptedBy readable, pet -> owner
NOW = 300
ev("UNIT_SPELLCAST_INTERRUPTED", "nameplate6", "c9", 1001, "GUID-pet")
-- player status uses the real cooldown (mock: not active -> ready)
assert(select(2, status("GUID-player")) == 0, "own: real cooldown wins")
-- learned shorter cooldown: Pummel seen again after 10s
NOW = 400; ev("UNIT_SPELLCAST_SUCCEEDED", "party1", "c", 6552)
NOW = 410; ev("UNIT_SPELLCAST_SUCCEEDED", "party1", "c", 6552)
assert(select(2, status("GUID-party1")) == 10, "learned 10s cooldown")
ns.UpdateKickFooter()

-- UI flows.
ns.ShowKickDetails("GUID-player")
ns.TestAlerts()
SlashCmdList.MPLUSKICK("unlock")
SlashCmdList.MPLUSKICK("lock")
SlashCmdList.MPLUSKICK("")
ns.RefreshOptions()
SlashCmdList.MPLUSKICK("debug")
SlashCmdList.MPLUSKICK("debug")
assert(#ns.loadErrors == 0, "no load/runtime errors: " .. table.concat(ns.loadErrors, " | "))
print("ALL OK")
