--[[
	ClassConfig
	-----------
	Outbreak Zero class definitions — 4 Survivors + 4 Infected + Patient Zero, from the
	design handoff (04_CLASSES.md + 05_CHARACTER_COSTUMES.md). Each player keeps a chosen
	class PER FACTION (the class-select has a faction toggle); the round's assigned role
	decides which one applies.

	Fields:
	  faction      "Human" | "Infected"
	  display      name shown in UI
	  blurb        one-line description (class-select / cards)
	  ability      { name, desc } — tuning lives in AbilityConfig (byClass maps class -> id)
	  walkSpeed    real in-game speed (design values)
	  stats        { hp, spd, pwr } 0-1 bars for the class-select cards
	  fillMult     (survivors only) infection-fill multiplier — design HP as TANKINESS, not
	               a kill HP bar: tankier classes fill slower (Assault 0.83x), fragile faster
	               (Scout 1.11x). Stun-not-kill / downed-via-meter is unchanged.
	  health       (infected only) stun-out threshold — survivor weapon damage to drop them
	               to a stun (Bruiser 350 tank, Stalker 180 squishy). Recover at full health.
	  Passive      class passive flags consumed by the services
	  Colors       costume BodyColors/accent hex (see CostumeService)
	  unlockCost   coins to unlock (0 = free starter); gating kept per owner decision
]]

local ClassConfig = {}

ClassConfig.DEFAULT_HUMAN = "Assault"
ClassConfig.DEFAULT_INFECTED = "Bruiser"

ClassConfig.classes = {
	-- ============================ SURVIVORS (cool blue) ============================
	Assault = {
		faction = "Human",
		display = "Assault",
		blurb = "Front-line pressure — grenades + a harder-hitting stun baton.",
		ability = { name = "Frag Grenade", desc = "Lob a grenade that stuns infected caught in the blast." },
		walkSpeed = 16,
		stats = { hp = 0.8, spd = 0.5, pwr = 0.75 },
		fillMult = 0.83, -- HP 120
		Passive = { BatonStunMult = 1.2 },
		Colors = { Head = "E6B58A", Torso = "22386B", Arms = "2A4374", Legs = "1C2C52", Visor = "2EE0FF" },
		unlockCost = 0, -- starter
	},
	Medic = {
		faction = "Human",
		display = "Medic",
		blurb = "Support — purge infection from allies and revive faster.",
		ability = { name = "Cleanse Beam", desc = "Drain infection from yourself and nearby allies." },
		walkSpeed = 16,
		stats = { hp = 0.6, spd = 0.5, pwr = 0.4 },
		fillMult = 1.0, -- HP 100
		Passive = { AllyDecayMult = 1.5, ReviveSpeed = 1.5 },
		Colors = { Head = "E6B58A", Torso = "EEF2F8", Arms = "DBE3F0", Legs = "B9C6DC", Accent = "2BE88B" },
		unlockCost = 250,
	},
	Engineer = {
		faction = "Human",
		display = "Engineer",
		blurb = "Control — drop walls to seal lanes; objectives charge faster.",
		ability = { name = "Barricade Wall", desc = "Drop a destructible wall to seal a lane or shield an ally." },
		walkSpeed = 15,
		stats = { hp = 0.7, spd = 0.4, pwr = 0.55 },
		fillMult = 0.91, -- HP 110
		Passive = { ObjectiveChargeMult = 1.25 },
		Colors = { Head = "E6B58A", Torso = "3A4A66", Gloves = "FF8A3D", Legs = "2A3650", Accent = "FFD02E" },
		unlockCost = 300,
	},
	Scout = {
		faction = "Human",
		display = "Scout",
		blurb = "Recon — sonar-ping infected through walls; fastest survivor.",
		ability = { name = "Motion Ping", desc = "Sonar pulse that outlines nearby infected for the team." },
		walkSpeed = 20,
		stats = { hp = 0.4, spd = 0.95, pwr = 0.4 },
		fillMult = 1.11, -- HP 90
		Passive = { SeeDownedThroughWalls = true },
		Colors = { Head = "E6B58A", Torso = "1D6FA8", Arms = "1D6FA8", Legs = "16344D", Visor = "2EE0FF" },
		unlockCost = 350,
	},

	-- ============================ INFECTED (hot pink / toxic green) ============================
	Bruiser = {
		faction = "Infected",
		display = "Bruiser",
		blurb = "Tank — huge stun threshold; smashes barricades.",
		ability = { name = "Ground Slam", desc = "Slam the ground for knockback + stagger; breaks barricades." },
		walkSpeed = 14,
		stats = { hp = 0.95, spd = 0.3, pwr = 0.8 },
		health = 350, -- tank: soaks a lot of fire before stunning
		Passive = {},
		Colors = {
			Head = "8A1F57",
			Torso = "6E1746",
			Arms = "8A1F57",
			Legs = "4A0F2E",
			Growth = "FF2E93",
			Eye = "B6FF2E",
		},
		unlockCost = 0, -- starter
	},
	Stalker = {
		faction = "Infected",
		display = "Stalker",
		blurb = "Assassin — cloak and pounce to isolate a straggler.",
		ability = { name = "Cloak Lunge", desc = "Briefly turn invisible and surge forward to ambush." },
		walkSpeed = 18,
		stats = { hp = 0.5, spd = 0.85, pwr = 0.6 },
		health = 180, -- squishy assassin
		Passive = {},
		Colors = {
			Head = "3A1A55",
			Torso = "3A1A55",
			Arms = "5A2A7D",
			Legs = "2A1240",
			Claws = "FF79BD",
			Eye = "FF79BD",
		},
		unlockCost = 300,
	},
	Spitter = {
		faction = "Infected",
		display = "Spitter",
		blurb = "Ranged — lob goo that leaves an infecting pool.",
		ability = { name = "Goo Spit", desc = "Lob goo that pools on the ground and infects survivors at range." },
		walkSpeed = 15,
		stats = { hp = 0.45, spd = 0.5, pwr = 0.65 },
		health = 160, -- fragile ranged
		Passive = {},
		Colors = { Head = "8A2566", Torso = "7A1F5A", Arms = "8A2566", Legs = "5A134A", Sac = "B6FF2E", Eye = "B6FF2E" },
		unlockCost = 350,
	},
	Controller = {
		faction = "Infected",
		display = "Controller",
		blurb = "Zone — plant nests that slow survivors and speed infection.",
		ability = { name = "Mutation Nest", desc = "Plant a nest that slows survivors and speeds infection nearby." },
		walkSpeed = 14,
		stats = { hp = 0.6, spd = 0.3, pwr = 0.55 },
		health = 200, -- zone-control bruiser-lite
		Passive = {},
		Colors = {
			Head = "6E3A94",
			Torso = "5A2A7D",
			Arms = "5A2A7D",
			Legs = "4A1D6B",
			Pods = "FF2E93",
			Eye = "B6FF2E",
		},
		unlockCost = 400,
	},
}

-- Display order per faction, for the class-select UI.
ClassConfig.humanOrder = { "Assault", "Medic", "Engineer", "Scout" }
ClassConfig.infectedOrder = { "Bruiser", "Stalker", "Spitter", "Controller" }

-- ============================ PATIENT ZERO ============================
-- The first Infected each round — buffed early so a single hunter can pressure the lobby,
-- then normalizes to the chosen infected class after BuffDuration. (Not selectable.)
ClassConfig.PatientZero = {
	display = "Patient Zero",
	Health = 220, -- stun-out threshold while buffed
	WalkSpeed = 17,
	InfectRangeMult = 1.25, -- +25% infection contact range while buffed
	BuffDuration = 60, -- seconds before normalizing
	RevealDuration = 5, -- Outbreak Pulse: reveal all survivors at spawn
	Colors = { HumanHalf = "3A4F73", MutantHalf = "FF2E93", Core = "FFD02E", Eye = "B6FF2E" },
}

return ClassConfig
