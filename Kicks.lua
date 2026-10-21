local _, ns = ...

--------------------------------------------------------------------------
-- Interrupt tracker: who in the group interrupted what, per dungeon run.
--
-- The combat log is gone in Midnight, so this uses unit events:
--   * UNIT_SPELLCAST_INTERRUPTED on enemy units carries "interruptedBy"
--     (the interrupter's GUID, added in 12.0). Matched against the group's
--     GUIDs (pets count for their owner) this gives landed interrupts.
--   * UNIT_SPELLCAST_SUCCEEDED on group units with a known interrupt spell
--     ID gives kicks pressed (including ones that missed or were too late).
-- Either value may be secret inside a keystone. A secret interrupter still
-- counts, as "unattributed"; secret spell IDs are simply not counted.
--
-- After every pull the counts are replaced by Blizzard's own damage meter
-- (C_DamageMeter, Interrupts), the same data Details! shows: complete,
-- server-validated and readable once combat ends. The live events above only
-- fill the gap during a pull. The meter is shared with other addons, so it is
-- never reset here: a baseline is taken when a run starts and counts are
-- measured from it (carrying over if the meter itself gets reset).
-- The meter's per-source breakdown (combatSpells) lists the *interrupted*
-- enemy spells with the mob as creatureName (confirmed in game), and pets
-- appear as separate sources, so they are folded into their owner.
--
-- Each landed interrupt also records which spell it stopped (and on which
-- mob), flagged "important" when it's on the priority list. When the spell
-- is secret it can't be grouped or judged, but the raw secret is kept for
-- this session so its name can still be displayed.
--------------------------------------------------------------------------

-- Interrupt spells whose cast means "a kick was pressed". Warlocks are
-- counted through the pet's cast (Spell Lock / Axe Toss) rather than
-- Command Demon so one kick isn't counted twice.
local INTERRUPT_IDS = {
	[6552] = true,   -- Pummel
	[1766] = true,   -- Kick
	[2139] = true,   -- Counterspell
	[47528] = true,  -- Mind Freeze
	[183752] = true, -- Disrupt
	[147362] = true, -- Counter Shot
	[187707] = true, -- Muzzle
	[96231] = true,  -- Rebuke
	[57994] = true,  -- Wind Shear
	[116705] = true, -- Spear Hand Strike
	[106839] = true, -- Skull Bash
	[78675] = true,  -- Solar Beam
	[15487] = true,  -- Silence
	[351338] = true, -- Quell
	[19647] = true,  -- Spell Lock (Felhunter)
	[89766] = true,  -- Axe Toss (Felguard)
	[132409] = true, -- Spell Lock (Grimoire of Sacrifice)
}

local GROUP_UNITS = { "player", "party1", "party2", "party3", "party4" }

local roster = {}   -- [guid] = owner unit ("player"/"partyN"); pets map to owner
local seen = {}     -- castGUIDs already counted (one kick fires for several unit tokens)
local hidden = {}   -- [guid or "unattributed"] = newest-first secret interrupts (session only)
local HIDDEN_MAX = 30
local seenCount = 0
local lastAnonymous = 0

local function Stats()
	local s = ns.db.kickStats
	if not s then
		s = { players = {}, unknown = 0, total = 0 }
		ns.db.kickStats = s
	end
	if not s.unattributed then s.unattributed = { spells = {} } end
	if not s.petOwners then s.petOwners = {} end -- [pet guid] = owner guid, every pet seen this run
	if not s.nameToGuid then s.nameToGuid = {} end -- [short name] = guid, group members and pets seen this run
	return s
end

-- Important = on the priority list. With a readable mob name, only that
-- mob's listed spells count (your own /mk add mobs count for anything they
-- cast); otherwise any listed spell name counts.
local function BaseImportant(spellName, mobName)
	if mobName then
		local key = mobName:lower()
		local set = ns.MobSpells[key]
		if set then return set[spellName:lower()] == true end
		if ns.db.mobs[key] then return true end
	end
	return ns.ImportantSpells[spellName:lower()] == true
end

-- Your own right-click choices (db.spellOverrides) win over the list.
local function IsImportant(spellName, mobName)
	local override = ns.db.spellOverrides[spellName:lower()]
	if override ~= nil then return override end
	return BaseImportant(spellName, mobName)
end
ns.IsImportantSpell = IsImportant

function ns.ToggleImportant(spellName, mobName)
	local key = spellName:lower()
	local want = not IsImportant(spellName, mobName)
	-- Store only real overrides; going back to the default clears it.
	if want == BaseImportant(spellName, mobName) then
		ns.db.spellOverrides[key] = nil
	else
		ns.db.spellOverrides[key] = want
	end
	ns.Print(("%s is %s important."):format(spellName, want and "now" or "no longer"))
	if ns.RefreshKickDetails then ns.RefreshKickDetails() end
end

local function Record(bucket, key, spellID, unit)
	local id = ns.Readable(spellID)
	local name = id and C_Spell.GetSpellName(id)
	if name then
		local mob = ns.Readable(UnitName(unit))
		bucket.spells = bucket.spells or {}
		local r = bucket.spells[id]
		if not r then
			r = { id = id, name = name, mob = mob, important = IsImportant(name, mob), count = 0 }
			bucket.spells[id] = r
		end
		r.count = r.count + 1
		r.mob = r.mob or mob
		return
	end
	-- Secret: keep the values themselves so they can still be shown.
	local list = hidden[key] or {}
	hidden[key] = list
	table.insert(list, 1, { spellID = spellID, mob = UnitName(unit) })
	if #list > HIDDEN_MAX then list[#list] = nil end
end

local function PetOf(unit)
	return unit == "player" and "pet" or unit:gsub("^party", "partypet")
end

local function OwnerOf(unit)
	if unit == "pet" then return "player" end
	return (unit:gsub("^partypet", "party"))
end

-- Stats entry for a group member, created on first sight. Returns nil when
-- the member can't be identified (secret GUID/name).
local function Entry(unit)
	local guid = ns.Readable(UnitGUID(unit))
	if not guid then return nil end
	local players = Stats().players
	local e = players[guid]
	if not e then
		local name = ns.Readable(UnitName(unit))
		if not name then return nil end
		e = { guid = guid, name = name, class = select(2, UnitClass(unit)), landed = 0, cast = 0, spells = {} }
		players[guid] = e
	end
	return e
end

-- Owner GUID of a pet seen this run (nil if not a known pet).
function ns.PetOwnerOf(guid)
	return Stats().petOwners[guid]
end

function ns.KicksRoster()
	wipe(roster)
	for _, unit in ipairs(GROUP_UNITS) do
		if ns.Readable(UnitExists(unit)) then
			local guid = ns.Readable(UnitGUID(unit))
			if guid then
				roster[guid] = unit
				Entry(unit)
				local name = ns.Readable(UnitName(unit))
				if name then Stats().nameToGuid[name] = guid end
			end
			local petGuid = ns.Readable(UnitGUID(PetOf(unit)))
			if petGuid then
				roster[petGuid] = unit
				-- Remembered for the whole run: the meter still lists a pet
				-- after it was dismissed or replaced by a new summon.
				if guid then Stats().petOwners[petGuid] = guid end
				local petName = ns.Readable(UnitName(PetOf(unit)))
				if petName then Stats().nameToGuid[petName] = petGuid end
			end
		end
	end
	if ns.UpdateKickFooter then ns.UpdateKickFooter() end
end

function ns.ResetKicks(instanceID)
	ns.db.kickStats = { players = {}, unknown = 0, total = 0, instance = instanceID, unattributed = { spells = {} } }
	wipe(seen)
	wipe(hidden)
	seenCount = 0
	ns.KicksRoster()
	-- Baseline for the damage meter; taken now if readable, else next sync.
	ns.db.kickStats.needBase = true
	ns.SyncKicksFromMeter()
end

-- New dungeon (or leaving one): start a fresh count. Re-entering the same
-- instance, e.g. after a wipe or /reload, keeps the numbers.
function ns.OnKicksEnterWorld()
	local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	if instanceType == "party" and Stats().instance ~= instanceID then
		ns.ResetKicks(instanceID)
	else
		ns.KicksRoster()
	end
end

function ns.OnKeystoneStart()
	local instanceID = select(8, GetInstanceInfo())
	ns.ResetKicks(instanceID)
end

-- One interrupt fires UNIT_SPELLCAST_INTERRUPTED for every token that
-- points at the mob (target, focus, nameplateN): count it once.
local function AlreadyCounted(castGUID)
	local key = ns.Readable(castGUID)
	if key then
		if seen[key] then return true end
		seen[key] = true
		seenCount = seenCount + 1
		if seenCount > 500 then wipe(seen); seenCount = 0 end
		return false
	end
	-- Secret cast GUID: treat events in the same instant as one interrupt.
	local now = GetTime()
	if now - lastAnonymous < 0.05 then return true end
	lastAnonymous = now
	return false
end

local function Show(v)
	if issecretvalue and issecretvalue(v) then return "secret" end
	return tostring(v)
end

-- Debug: every interrupt event, before any filtering, and why it would be
-- dropped or who it would be credited to.
local function TraceInterrupt(unit, castGUID, spellID, interruptedBy)
	local by = ns.Readable(interruptedBy)
	local owner = by and roster[by]
	local id = ns.Readable(spellID)
	ns.Print(("INTERRUPTED %s: spell=%s by=%s -> %s | tracked=%s hostile=%s castGUID=%s"):format(
		unit, id and (C_Spell.GetSpellName(id) or id) or Show(spellID), Show(interruptedBy),
		owner and ("group " .. owner) or (by and "not in group" or "nobody"),
		tostring(ns.IsTrackedUnit(unit) or unit:match("^boss%d$") ~= nil),
		Show(UnitCanAttack("player", unit)), Show(castGUID)))
end

function ns.KicksDebugRoster()
	local n = 0
	for guid, unit in pairs(roster) do
		n = n + 1
		ns.Print(("  roster: %s = %s"):format(unit, guid))
	end
	if n == 0 then ns.Print("  roster is empty") end
end

function ns.OnInterrupted(unit, castGUID, spellID, interruptedBy)
	if not ns.db.kickLog then return end
	if ns.db.debug then TraceInterrupt(unit, castGUID, spellID, interruptedBy) end
	if not (ns.IsTrackedUnit(unit) or unit:match("^boss%d$")) then return end
	if ns.Readable(UnitCanAttack("player", unit)) == false then return end

	local secretBy = issecretvalue and issecretvalue(interruptedBy)
	local by = ns.Readable(interruptedBy)
	-- No interrupter at all: the cast was cancelled some other way.
	if not secretBy and (by == nil or by == "") then return end
	if AlreadyCounted(castGUID) then return end

	local stats = Stats()
	stats.fromMeter = false
	stats.total = stats.total + 1
	local owner = by and roster[by]
	local e = owner and Entry(owner)
	if e then
		e.landed = e.landed + 1
		Record(e, e.guid, spellID, unit)
	else
		stats.unknown = stats.unknown + 1
		Record(stats.unattributed, "unattributed", spellID, unit)
	end

	if ns.db.debug then
		ns.Print(("interrupt on %s: by=%s -> %s"):format(unit,
			secretBy and "secret" or tostring(by), e and e.name or "unattributed"))
	end
	ns.UpdateKickFooter()
	if ns.RefreshKickDetails then ns.RefreshKickDetails() end
end

function ns.OnSpellSucceeded(unit, castGUID, spellID)
	if not ns.db.kickLog then return end
	if not (unit == "player" or unit == "pet" or unit:match("^party%d$") or unit:match("^partypet%d$")) then return end
	local id = ns.Readable(spellID)
	if not id or not INTERRUPT_IDS[id] then return end
	local e = Entry(OwnerOf(unit))
	if ns.db.debug then
		ns.Print(("kick pressed: %s by %s (%s)"):format(C_Spell.GetSpellName(id) or id, unit, Show(UnitGUID(unit))))
	end
	if not e then return end
	e.cast = e.cast + 1
	ns.UpdateKickFooter()
end

-- Rows for the panel footer: best kicker first.
function ns.KickRows()
	local stats = Stats()
	local rows = {}
	for guid, e in pairs(stats.players) do
		-- Entries saved by older versions lack these.
		e.guid = e.guid or guid
		e.spells = e.spells or {}
		rows[#rows + 1] = e
	end
	table.sort(rows, function(a, b)
		if a.landed ~= b.landed then return a.landed > b.landed end
		return a.name < b.name
	end)
	return rows, stats.unknown, stats.total
end

-- What one player (guid) or "unattributed" interrupted: readable records
-- sorted important-first then by count, plus the secret (hidden) ones.
function ns.KickDetails(key)
	local stats = Stats()
	local bucket, name, class
	if key == "unattributed" then
		bucket, name = stats.unattributed, "Unattributed"
	else
		bucket = stats.players[key]
		if not bucket then return nil end
		name, class = bucket.name, bucket.class
	end
	local list = {}
	for _, r in pairs(bucket.spells or {}) do
		-- Re-judged every time so right-click changes apply to past kicks.
		r.important = IsImportant(r.name, r.mob)
		list[#list + 1] = r
	end
	table.sort(list, function(a, b)
		if a.important ~= b.important then return a.important end
		if a.count ~= b.count then return a.count > b.count end
		return a.name < b.name
	end)
	return name, class, list, hidden[key] or {}
end

--------------------------------------------------------------------------
-- Blizzard damage meter sync
--------------------------------------------------------------------------

local function MeterEnums()
	local DM = C_DamageMeter
	local st, mt = Enum and Enum.DamageMeterSessionType, Enum and Enum.DamageMeterType
	if not (DM and DM.GetCombatSessionFromType and st and mt and mt.Interrupts) then return nil end
	return DM, st.Overall, mt.Interrupts
end

-- Overall interrupts per group member: { [guid] = { name, class, total,
-- spells = { ["spellID:creature"] = { id, creature, count } } } }.
-- Returns nil plus a reason when the meter isn't readable (e.g. in combat).
local function ReadMeter()
	local DM, overall, interrupts = MeterEnums()
	if not DM then return nil, "no damage meter API" end
	local ok, session = pcall(DM.GetCombatSessionFromType, overall, interrupts)
	if not ok then return nil, "error: " .. tostring(session) end
	if not session or (issecretvalue and issecretvalue(session)) then return nil, "hidden" end
	local sources = session.combatSources
	if not sources or (issecretvalue and issecretvalue(sources)) then return nil, "hidden" end

	local out = {}
	local stats = Stats()
	for _, src in ipairs(sources) do
		local total = ns.Readable(src.totalAmount)
		if not total then return nil, "hidden (in combat)" end
		local name = ns.Readable(src.name)
		name = name and (Ambiguate and Ambiguate(name, "short") or name)

		-- Since 12.1.5 sourceGUID is secret when the unit's identity is.
		-- Fall back to the never-secret isLocalPlayer flag, then to names
		-- of group members and pets seen this run.
		local guid = ns.Readable(src.sourceGUID)
		if not guid and ns.Readable(src.isLocalPlayer) == true then guid = ns.Readable(UnitGUID("player")) end
		if not guid and name then guid = stats.nameToGuid[name] end

		if not guid then
			if ns.db.debug then ns.Print("damage meter: skipped a source with hidden identity (" .. tostring(name) .. ")") end
		else
			local existing = stats.players[guid]
			local p = {
				name = name or (existing and existing.name) or "?",
				class = ns.Readable(src.classFilename),
				total = total,
				spells = {},
			}
			-- The C side can resolve its own (possibly secret) GUID; use the
			-- resolved one only if that fails.
			local ok2, detail = pcall(DM.GetCombatSessionSourceFromType, overall, interrupts, src.sourceGUID)
			if not ok2 or not detail then
				ok2, detail = pcall(DM.GetCombatSessionSourceFromType, overall, interrupts, guid)
			end
			local list = ok2 and detail and not (issecretvalue and issecretvalue(detail)) and detail.combatSpells
			if list and not (issecretvalue and issecretvalue(list)) then
				for _, sp in ipairs(list) do
					local id, amount = ns.Readable(sp.spellID), ns.Readable(sp.totalAmount)
					local creature = ns.Readable(sp.creatureName)
					if creature == "" then creature = nil end
					if id and amount then
						local key = id .. ":" .. (creature or "")
						local cur = p.spells[key] or { id = id, creature = creature, count = 0 }
						cur.count = cur.count + amount
						p.spells[key] = cur
					end
				end
			end
			out[guid] = p
		end
	end

	-- The meter lists pets as their own sources: fold them into the owner.
	local owners = Stats().petOwners
	local pets = {}
	for guid in pairs(out) do
		if owners[guid] and owners[guid] ~= guid then pets[#pets + 1] = guid end
	end
	for _, petGuid in ipairs(pets) do
		local p, ownerGuid = out[petGuid], owners[petGuid]
		local o = out[ownerGuid]
		if not o then
			local e = Stats().players[ownerGuid]
			o = { name = e and e.name or p.name, class = e and e.class, total = 0, spells = {} }
			out[ownerGuid] = o
		end
		o.total = o.total + p.total
		for key, sp in pairs(p.spells) do
			local cur = o.spells[key] or { id = sp.id, creature = sp.creature, count = 0 }
			cur.count = cur.count + sp.count
			o.spells[key] = cur
		end
		out[petGuid] = nil
	end
	return out
end

local function Snapshot(meter)
	local snap = {}
	for guid, p in pairs(meter) do
		local spells = {}
		for key, sp in pairs(p.spells) do spells[key] = sp.count end
		snap[guid] = { total = p.total, spells = spells }
	end
	return snap
end

-- Pull the authoritative numbers from the damage meter. Safe to call any
-- time; does nothing while the data is hidden.
function ns.SyncKicksFromMeter()
	if not ns.db or not ns.db.kickLog then return false end
	local meter, why = ReadMeter()
	local stats = Stats()
	if not meter then
		if ns.db.debug then ns.Print("damage meter: not readable (" .. tostring(why) .. ")") end
		return false
	end

	stats.dmCarry = stats.dmCarry or {}
	for petGuid, ownerGuid in pairs(stats.petOwners) do
		for _, tbl in ipairs({ stats.dmBase or {}, stats.dmCarry }) do
			local from = tbl[petGuid]
			if from then
				local to = tbl[ownerGuid] or { total = 0, spells = {} }
				to.total = to.total + from.total
				for key, n in pairs(from.spells) do to.spells[key] = (to.spells[key] or 0) + n end
				tbl[ownerGuid] = to
				tbl[petGuid] = nil
			end
		end
		stats.players[petGuid] = nil
	end
	if stats.needBase or not stats.dmBase then
		stats.dmBase = Snapshot(meter)
		stats.dmCarry = {}
		stats.needBase = nil
	end
	local base, carry = stats.dmBase, stats.dmCarry

	-- The meter went backwards (someone reset it): keep what was counted so
	-- far as carry and measure from zero again.
	for guid, b in pairs(base) do
		local p = meter[guid]
		if not p or p.total < b.total then
			for g, e in pairs(stats.players) do
				if e.fromMeter then
					local spells = {}
					for key, r in pairs(e.meterSpells or {}) do spells[key] = r end
					carry[g] = { total = e.landed, spells = spells }
				end
			end
			stats.dmBase = {}
			base = stats.dmBase
			break
		end
	end

	local total = 0
	local seenGuids = {}
	for guid, p in pairs(meter) do
		seenGuids[guid] = true
		local b = base[guid] or { total = 0, spells = {} }
		local c = carry[guid] or { total = 0, spells = {} }
		local e = stats.players[guid]
		if not e then
			e = { guid = guid, name = p.name, class = p.class, landed = 0, cast = 0, spells = {} }
			stats.players[guid] = e
		end
		e.class = e.class or p.class
		e.landed = c.total + (p.total - b.total)
		e.fromMeter = true

		-- Per spell (and mob): carry + (now - baseline).
		local counts = {}
		for key, n in pairs(c.spells) do counts[key] = n end
		for key, sp in pairs(p.spells) do
			counts[key] = (counts[key] or 0) + sp.count - (b.spells[key] or 0)
		end
		e.meterSpells = counts
		e.spells = {}
		for key, n in pairs(counts) do
			if n > 0 then
				local id, creature = key:match("^(%d+):(.*)$")
				id = tonumber(id)
				if creature == "" then creature = nil end
				local name = C_Spell.GetSpellName(id) or ("Spell " .. id)
				e.spells[key] = { id = id, name = name, mob = creature, important = IsImportant(name, creature), count = n }
			end
		end
		total = total + e.landed
	end
	-- Group members the meter has no interrupts for.
	for guid, e in pairs(stats.players) do
		if not seenGuids[guid] then
			local c = carry[guid]
			e.landed = c and c.total or 0
			e.fromMeter = true
			total = total + e.landed
		end
	end

	stats.total = total
	stats.unknown = 0
	stats.unattributed = { spells = {} }
	stats.fromMeter = true
	wipe(hidden)

	if ns.db.debug then
		ns.Print("damage meter synced:")
		for guid, p in pairs(meter) do
			local parts = {}
			for _, sp in pairs(p.spells) do
				parts[#parts + 1] = ("%s x%d%s"):format(C_Spell.GetSpellName(sp.id) or sp.id, sp.count,
					sp.creature and (" (" .. sp.creature .. ")") or "")
			end
			ns.Print(("  %s: meter total %d -> %s"):format(p.name, p.total, table.concat(parts, ", ")))
		end
	end
	ns.UpdateKickFooter()
	if ns.RefreshKickDetails then ns.RefreshKickDetails() end
	return true
end

-- End of a pull: the meter becomes readable again.
function ns.OnKicksLeaveCombat()
	C_Timer.After(0.5, ns.SyncKicksFromMeter)
end

function ns.IsKickDataFromMeter()
	return Stats().fromMeter == true
end

--------------------------------------------------------------------------
-- Run records (recap when a key ends, last 10 kept)
--------------------------------------------------------------------------

local MAX_RUNS = 10
local pendingRun = false

-- Snapshot of the current run in the shape the runs window shows.
function ns.BuildRunRecord()
	local stats = Stats()
	local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	local run = {
		date = date("%d %b %H:%M"),
		dungeon = (GetInstanceInfo()),
		total = stats.total or 0,
		players = {},
	}
	for _, e in pairs(stats.players) do
		local important = 0
		for _, r in pairs(e.spells or {}) do
			if IsImportant(r.name, r.mob) then important = important + r.count end
		end
		run.players[#run.players + 1] = {
			name = e.name, class = e.class, landed = e.landed, cast = e.cast,
			missed = e.cast > 0 and math.max(0, e.cast - e.landed) or nil,
			important = important,
		}
	end
	table.sort(run.players, function(a, b) return a.landed > b.landed end)

	local ok, info = pcall(C_ChallengeMode and C_ChallengeMode.GetChallengeCompletionInfo)
	if ok and type(info) == "table" and ns.Readable(info.level) and info.level > 0 then
		run.level, run.time, run.onTime = info.level, (info.time or 0) / 1000, info.onTime
		local okName, name = pcall(C_ChallengeMode.GetMapUIInfo, info.mapChallengeModeID)
		if okName and name then run.dungeon = name end
	end
	return run
end

local function FinishRun()
	if not pendingRun then return end
	if InCombatLockdown() then return end -- retried when combat ends
	ns.SyncKicksFromMeter()
	pendingRun = false
	local run = ns.BuildRunRecord()
	if run.total == 0 and #run.players == 0 then return end
	table.insert(ns.db.runs, 1, run)
	while #ns.db.runs > MAX_RUNS do table.remove(ns.db.runs) end
	ns.ShowRuns(1)
end

function ns.OnKeystoneComplete()
	pendingRun = true
	-- The meter settles a moment after the final kill.
	C_Timer.After(2, FinishRun)
end

function ns.OnKicksLeaveCombatRuns()
	if pendingRun then C_Timer.After(1, FinishRun) end
end
