local _, ns = ...

--------------------------------------------------------------------------
-- Party kick cooldowns: who has their interrupt ready.
--
-- Each member's interrupt comes from class + spec (specs via inspect, out
-- of combat). A kick is detected, most reliable first, by:
--   1. the spell itself on UNIT_SPELLCAST_SUCCEEDED (always readable for
--      you; for party members outside keys),
--   2. "interruptedBy" on an enemy's UNIT_SPELLCAST_INTERRUPTED,
--   3. timing: inside keys party spells are secret, but the cast event
--      still fires. A party member's (secret) cast in the same instant an
--      enemy cast got interrupted is almost certainly their kick. These
--      are marked estimated (~).
-- A party kick that misses (no cast to stop) can't be seen inside keys.
-- Base cooldowns may be shortened by talents; a member seen kicking again
-- sooner than expected has their cooldown learned down.
--------------------------------------------------------------------------

-- Base cooldowns (seconds) for every interrupt we know.
local COOLDOWN = {
	[6552] = 15,   -- Pummel
	[1766] = 15,   -- Kick
	[2139] = 24,   -- Counterspell
	[47528] = 15,  -- Mind Freeze
	[183752] = 15, -- Disrupt
	[147362] = 24, -- Counter Shot
	[187707] = 15, -- Muzzle
	[96231] = 15,  -- Rebuke
	[57994] = 12,  -- Wind Shear
	[116705] = 15, -- Spear Hand Strike
	[106839] = 15, -- Skull Bash
	[78675] = 60,  -- Solar Beam
	[15487] = 45,  -- Silence
	[351338] = 40, -- Quell
	[19647] = 24,  -- Spell Lock (Felhunter)
	[89766] = 30,  -- Axe Toss (Felguard)
	[132409] = 24, -- Spell Lock (Grimoire of Sacrifice)
}

local CLASS_KICK = {
	WARRIOR = 6552, ROGUE = 1766, MAGE = 2139, DEATHKNIGHT = 47528,
	DEMONHUNTER = 183752, HUNTER = 147362, PALADIN = 96231, SHAMAN = 57994,
	MONK = 116705, DRUID = 106839, EVOKER = 351338, WARLOCK = 19647,
	-- PRIEST: only Shadow has one (see SPEC_KICK)
}

-- Spec exceptions; false = that spec has no interrupt.
local SPEC_KICK = {
	[255] = 187707, -- Survival: Muzzle
	[102] = 78675,  -- Balance: Solar Beam
	[105] = false,  -- Restoration druid
	[258] = 15487,  -- Shadow: Silence
	[256] = false,  -- Discipline
	[257] = false,  -- Holy priest
	[266] = 89766,  -- Demonology: Axe Toss
}

local GROUP_UNITS = { "player", "party1", "party2", "party3", "party4" }
local CORRELATION_WINDOW = 0.3

local members = {}  -- [guid] = { unit, class, spec, spell, cd, learnedCd, usedAt, readyAt, estimated, lastCast }
local specs = {}    -- [guid] = specID (inspect results, kept for the session)
local inspecting, inspectTimer
local ticker
local lastInterrupt = 0

local function OwnerOf(unit)
	if unit == "pet" then return "player" end
	return (unit:gsub("^partypet", "party"))
end

local function KickFor(class, spec, unit)
	if spec and SPEC_KICK[spec] ~= nil then return SPEC_KICK[spec] or nil end
	if not spec and (class == "PRIEST" or class == "DRUID")
		and ns.Readable(UnitGroupRolesAssigned(unit)) == "HEALER" then
		return nil -- healer priest/resto druid until inspect says otherwise
	end
	return CLASS_KICK[class]
end

--------------------------------------------------------------------------
-- Roster + inspect queue
--------------------------------------------------------------------------

local InspectNext

function ns.CD_Roster()
	local present = {}
	for _, unit in ipairs(GROUP_UNITS) do
		local guid = ns.Readable(UnitExists(unit)) and ns.Readable(UnitGUID(unit))
		if guid then
			present[guid] = true
			local m = members[guid] or { usedAt = 0, readyAt = 0 }
			members[guid] = m
			m.unit = unit
			m.class = select(2, UnitClass(unit))
			if unit == "player" then
				local index = GetSpecialization and GetSpecialization()
				m.spec = index and GetSpecializationInfo(index) or m.spec
			else
				m.spec = specs[guid]
			end
			local spell = KickFor(m.class, m.spec, unit)
			if spell ~= m.baseSpell then
				m.baseSpell, m.spell, m.learnedCd = spell, spell, nil
			end
			m.cd = m.learnedCd or (m.spell and COOLDOWN[m.spell])
		end
	end
	for guid in pairs(members) do
		if not present[guid] then members[guid] = nil end
	end
	InspectNext()
	ns.UpdateKickFooter()
end

function InspectNext()
	if inspecting or InCombatLockdown() or not NotifyInspect then return end
	for guid, m in pairs(members) do
		if m.unit ~= "player" and not specs[guid] and CanInspect and CanInspect(m.unit) then
			inspecting = guid
			NotifyInspect(m.unit)
			-- Give up on this one after a few seconds and move on.
			inspectTimer = C_Timer.NewTimer(4, function()
				inspecting = nil
				specs[guid] = specs[guid] or 0
				InspectNext()
			end)
			return
		end
	end
end

function ns.CD_OnInspect(guid)
	if guid ~= inspecting then return end
	if inspectTimer then inspectTimer:Cancel() end
	local m = members[guid]
	local spec = m and GetInspectSpecialization and GetInspectSpecialization(m.unit)
	specs[guid] = (spec and spec > 0) and spec or 0
	if ClearInspectPlayer then ClearInspectPlayer() end
	inspecting = nil
	ns.CD_Roster()
end

function ns.CD_OnLeaveCombat()
	InspectNext()
end

--------------------------------------------------------------------------
-- Detection
--------------------------------------------------------------------------

local function Tick()
	local now, any = GetTime(), false
	for _, m in pairs(members) do
		if (m.readyAt or 0) > now then any = true break end
	end
	ns.UpdateKickFooter()
	if not any and ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local function StartCD(guid, spellID, how)
	local m = members[guid]
	if not m then return end
	local now = GetTime()
	if now - (m.usedAt or 0) < 1 then return end -- same kick seen twice

	-- The kick they actually used beats the class/spec guess.
	if spellID and COOLDOWN[spellID] and spellID ~= m.spell then
		m.spell, m.learnedCd = spellID, nil
	end
	-- Seen kicking again while we thought it was still cooling down: their
	-- cooldown is shorter (talents). Only learned from confident sightings.
	if how ~= "estimated" and not m.estimated and m.readyAt > now and now - m.usedAt >= 5 then
		m.learnedCd = math.floor(now - m.usedAt)
	end
	m.cd = m.learnedCd or (m.spell and COOLDOWN[m.spell]) or 15
	m.usedAt, m.readyAt, m.estimated = now, now + m.cd, how == "estimated"

	if ns.db.debug then
		ns.Print(("kick cd: %s %s %ds (%s)"):format(
			ns.Readable(UnitName(m.unit)) or m.unit, m.spell and C_Spell.GetSpellName(m.spell) or "?", m.cd, how))
	end
	if not ticker then ticker = C_Timer.NewTicker(0.25, Tick) end
	ns.UpdateKickFooter()
end

function ns.CD_OnSucceeded(unit, castGUID, spellID)
	if not (unit == "player" or unit == "pet" or unit:match("^party%d$") or unit:match("^partypet%d$")) then return end
	local guid = ns.Readable(UnitGUID(OwnerOf(unit)))
	local m = guid and members[guid]
	if not m then return end
	local id = ns.Readable(spellID)
	if id then
		if COOLDOWN[id] then StartCD(guid, id, "seen") end
		return
	end
	-- Secret spell: remember when, in case an enemy cast gets interrupted now.
	m.lastCast = GetTime()
end

function ns.CD_OnInterrupted(unit, castGUID, spellID, interruptedBy)
	if not (ns.IsTrackedUnit(unit) or unit:match("^boss%d$")) then return end
	if ns.Readable(UnitCanAttack("player", unit)) == false then return end
	local now = GetTime()
	if now - lastInterrupt < 0.05 then return end -- same interrupt, other unit token
	lastInterrupt = now

	local by = ns.Readable(interruptedBy)
	if by then
		local owner = (ns.PetOwnerOf and ns.PetOwnerOf(by)) or by
		if members[owner] then StartCD(owner, nil, "interruptedBy") end
		return
	end

	-- Interrupter hidden: whoever cast something in the same instant.
	local best, bestGap
	for guid, m in pairs(members) do
		if m.spell and m.lastCast and now - m.usedAt > 1 then
			local gap = now - m.lastCast
			if gap >= 0 and gap <= CORRELATION_WINDOW and (not bestGap or gap < bestGap) then
				best, bestGap = guid, gap
			end
		end
	end
	if best then StartCD(best, nil, "estimated") end
end

--------------------------------------------------------------------------
-- Status for the footer
--------------------------------------------------------------------------

-- icon, secondsLeft (0 = ready), estimated, spellID; nil if the member has
-- no interrupt (or isn't known).
function ns.KickStatus(guid)
	local m = members[guid]
	if not m or not m.spell then return nil end
	local remaining = math.max(0, (m.readyAt or 0) - GetTime())
	-- Your own: the game's real cooldown, when it's readable.
	if m.unit == "player" then
		local id = ns.GetKickSpell()
		local info = id and C_Spell.GetSpellCooldown(id)
		if info and ns.Readable(info.isOnGCD) ~= true then
			local active = ns.Readable(info.isActive)
			local start, duration = ns.Readable(info.startTime), ns.Readable(info.duration)
			if active == false then
				remaining = 0
			elseif active and start and duration then
				remaining = math.max(0, start + duration - GetTime())
			end
		end
	end
	return C_Spell.GetSpellTexture(m.spell), remaining, m.estimated and remaining > 0, m.spell
end
