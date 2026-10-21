local _, ns = ...

-- Known priority mobs, keyed by NPC name exactly as it appears in game.
-- The value is a short note shown when you mouse over / target the mob.
--
-- Matching is by mob NAME, not by spell: in Midnight, enemy cast info
-- (spell name / spell ID) is a secret value inside instances, so an addon
-- cannot see WHICH spell is being cast. Instead you focus the mobs that
-- carry dangerous casts, and the addon alerts on ANY focus cast.
--
-- You can also add mobs in game: target one and type  /mk add <note>
-- (those are saved per account and merged with this table).
--
-- Source: bispath.gg Season 2 dungeon guides (must-interrupt tables),
-- researched early in Season 2 (Patch 12.1). Names may need tweaks if the
-- in-game NPC name differs; use /mk add to override.
ns.Dungeons = {
	{
		name = "Altar of Fangs",
		mobs = {
			{ "Primal Serpent", "Kick: Piercing Hiss", spells = { "Piercing Hiss" } },
			{ "Twinfang Harrower", "Kick: Paralyzing Shots", spells = { "Paralyzing Shots" } },
			{ "Ravenous Descendant", "Kick: Ravenous Claws (never pull two)", spells = { "Ravenous Claws" } },
			{ "High Evolutionist", "Kick: Envenom", spells = { "Envenom" } },
			{ "The Writhing Coil", "Boss: kick all 3 Toxic Atrophy casts (rotate 2-3 kickers)", spells = { "Toxic Atrophy" } },
		},
	},
	{
		name = "Murder Row",
		mobs = {
			{ "Seductive Sayaad", "Kick/CC: Seduction (charms a party member)", spells = { "Seduction" } },
			{ "Felonious Mage", "Kick: Fel Missiles", spells = { "Fel Missiles" } },
			{ "Influential Reviewer", "Kick: Scathing Review (tavern star rating)", spells = { "Scathing Review" } },
			{ "Wrathguard Flayer", "Kick or soothe: Fel Rage", spells = { "Fel Rage" } },
			{ "Kystia Manaheart", "Boss: kick/CC Mirror Image copies as they spawn", spells = { "Mirror Image" } },
			{ "Wild Imp", "Kick/CC/AoE: Felfire Burst (Lithiel fight)", spells = { "Felfire Burst" } },
			{ "Lithiel Cinderfury", "Boss: Chaos Bolt, keep a fixed kick rotation", spells = { "Chaos Bolt" } },
		},
	},
	{
		name = "Den of Nalorakk",
		mobs = {
			{ "Earthwhisper Tender", "Kick: Healing Breeze (top), then Earth Bolt", spells = { "Healing Breeze", "Earth Bolt" } },
			{ "Keen-Eyed Striker", "Kick: Scavenge (steals offerings)", spells = { "Scavenge" } },
			{ "Frigid Mauler", "Kick EVERY cast: Frigid Roar", spells = { "Frigid Roar" } },
			{ "Stormbound Mystic", "Kick EVERY cast: Arc Lightning, then Lightning Bolt", spells = { "Arc Lightning", "Lightning Bolt" } },
			{ "Loa Speaker Nanea", "Kick rotation: Lightning Bolt", spells = { "Lightning Bolt" } },
			{ "Fractured Shivercore", "Kick: Winter's Shroud (Sentinel of Winter adds)", spells = { "Winter's Shroud" } },
		},
	},
	{
		name = "The Blinding Vale",
		mobs = {
			{ "Radiant Spellsower", "Kick EVERY cast: Light Bolt Volley (#1 in dungeon), spare kicks on Light Bolt", spells = { "Light Bolt Volley", "Light Bolt" } },
			{ "Lightfeather Petalwing", "Kick EVERY cast: Disorienting Screech", spells = { "Disorienting Screech" } },
			{ "Leafy Grovecrawler", "Spare kick: Seed Shot", spells = { "Seed Shot" } },
			{ "Kezkitt", "Boss: kick rotation on Light Bolt", spells = { "Light Bolt" } },
			{ "Lightwarden Ruia", "Boss P1: kick rotation on Warden's Wrath", spells = { "Warden's Wrath" } },
			-- Ziekket's summoned Lashers (Lightspore Shot): exact NPC name unconfirmed,
			-- add in game with /mk add Kick: Lightspore Shot
		},
	},
	{
		name = "Voidscar Arena",
		mobs = {
			{ "Kilivore Screamer", "Kick EVERY cast: Mad Shriek / Mass Shriek (AoE fear)", spells = { "Mad Shriek", "Mass Shriek" } },
			{ "Dominated Brawler", "Kick EVERY cast: Demoralizing Shout", spells = { "Demoralizing Shout" } },
			{ "Voidtouched Magi", "Kick on CD: Shadowbolt Volley", spells = { "Shadowbolt Volley" } },
			{ "Enthralled Shaman", "Kick: Lava Bolt (kill Magma Totem)", spells = { "Lava Bolt" } },
			{ "Angry Krolusk", "Kick: Violent Sand", spells = { "Violent Sand" } },
		},
	},
	{
		name = "Ruby Life Pools",
		mobs = {
			{ "Flashfrost Chillweaver", "Kick: Ice Shield (top) and Icebolt", spells = { "Ice Shield", "Icebolt" } },
			{ "Flashfrost Earthshaper", "Kick/stun: Tectonic Slam", spells = { "Tectonic Slam" } },
			{ "Blazebound Destroyer", "Kick: Fiery Blast (top priority section 2)", spells = { "Fiery Blast" } },
			{ "Tempest Channeler", "Kick: Thunder Blast", spells = { "Thunder Blast" } },
			{ "Ruinous Stormbringer", "Kick rotation: Storm Bolt", spells = { "Storm Bolt" } },
			{ "Melidrussa Chillworn", "Boss: Frigid Shard is kickable in S2", spells = { "Frigid Shard" } },
			{ "Blazebound Firestorm", "Swap + kick: Roaring Blaze", spells = { "Roaring Blaze" } },
		},
	},
	{
		name = "Kings' Rest",
		mobs = {
			{ "Risen Hexer", "Kick: Hex Volley (top), then Shadowfrost Bolt", spells = { "Hex Volley", "Shadowfrost Bolt" } },
			{ "Seneschal M'bara", "Kick: Unholy Mending (purge if it lands)", spells = { "Unholy Mending" } },
			{ "King Timalji", "Kick: Bind Soul", spells = { "Bind Soul" } },
			{ "Queen Wasi", "Kick: Bind Soul", spells = { "Bind Soul" } },
			{ "Half-Finished Mummy", "Kick EVERY cast: Wretched Discharge", spells = { "Wretched Discharge" } },
			{ "Phantom Hex Priest", "Kick: Hex and Spectral Bolt", spells = { "Hex", "Spectral Bolt" } },
			{ "Zanazal the Wise", "Boss: MUST kick Poison Nova (near wipe)", spells = { "Poison Nova" } },
			{ "Dazar, the First King", "Boss P1: kick every Deathly Roar", spells = { "Deathly Roar" } },
		},
	},
	{
		name = "Temple of Sethraliss",
		mobs = {
			{ "Shrouded Fang", "Kick: Poisoned Cheap Shot (top, stealthed)", spells = { "Poisoned Cheap Shot" } },
			{ "Storm Adept", "Kick: Lightning Bolt", spells = { "Lightning Bolt" } },
			{ "Sandswept Hunter", "Kick/stun: Arrow Barrage", spells = { "Arrow Barrage" } },
			{ "Faithless Subjugator", "Kick: Addle Mind (top priority)", spells = { "Addle Mind" } },
			{ "Imbued Stormcaller", "Kick: Lightning Bolt", spells = { "Lightning Bolt" } },
			{ "Temple Disruptor", "Kick/CC NOW: Essence Disruption (eye event)", spells = { "Essence Disruption" } },
			{ "Toxic Viper", "Kick: Poison Spit (Merektha adds)", spells = { "Poison Spit" } },
			{ "Twisted Hexxer", "Kick: Flame Shock (final boss waves)", spells = { "Flame Shock" } },
		},
	},
}

-- Lookups built from the dungeon list above:
--   KnownMobs[name] = note
--   MobSpells[lowercase mob name][lowercase spell name] = true
--   ImportantSpells[lowercase spell name] = true (any listed mob's spell)
ns.KnownMobs, ns.MobSpells, ns.ImportantSpells = {}, {}, {}
for _, dungeon in ipairs(ns.Dungeons) do
	for _, mob in ipairs(dungeon.mobs) do
		ns.KnownMobs[mob[1]] = mob[2]
		local set = {}
		for _, spell in ipairs(mob.spells or {}) do
			set[spell:lower()] = true
			ns.ImportantSpells[spell:lower()] = true
		end
		ns.MobSpells[mob[1]:lower()] = set
	end
end
