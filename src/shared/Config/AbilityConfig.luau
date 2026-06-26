--[[
	AbilityConfig
	-------------
	Data-driven definitions for the 8 class signature abilities (from the design's
	class cards, 04_CLASSES.md). Server-validated cooldowns; effects implemented in
	AbilityService. Tweak freely — purely tuning values.

	Each playable class has exactly one signature ability (byClass maps class -> ability id).
	Patient Zero's Outbreak Pulse is fired by InfectionService at round start, not via the
	Q ability path, so it is not in byClass.
]]

local AbilityConfig = {}

AbilityConfig.abilities = {
	-- ===== Survivors =====
	FragGrenade = {
		class = "Assault",
		name = "Frag Grenade",
		desc = "Lob a grenade that stuns infected caught in the blast.",
		cooldown = 12,
		fuse = 1.5, -- seconds before it detonates
		throwSpeed = 64, -- studs/sec lob velocity
		blastRadius = 14, -- infected inside are stunned
		stunDuration = 3,
	},
	CleanseBeam = {
		class = "Medic",
		name = "Cleanse Beam",
		desc = "Drain infection from yourself and nearby allies.",
		cooldown = 8,
		radius = 18,
		cleanseAmount = 45, -- infection % removed from each ally in range
	},
	Barricade = {
		class = "Engineer",
		name = "Barricade Wall",
		desc = "Drop a destructible wall to seal a lane or shield a downed ally.",
		cooldown = 16,
		wallSize = { 12, 8, 2 }, -- X, Y, Z studs
		wallHealth = 200, -- damage to break (Bruiser Ground Slam shatters it)
		lifetime = 20, -- seconds before it dissolves
		offset = 7, -- studs in front of the engineer
	},
	MotionPing = {
		class = "Scout",
		name = "Motion Ping",
		desc = "Sonar pulse that outlines nearby infected through walls for the team.",
		cooldown = 10,
		range = 60,
		revealDuration = 6,
	},

	-- ===== Infected =====
	GroundSlam = {
		class = "Bruiser",
		name = "Ground Slam",
		desc = "Slam the ground for a burst of infection around you; breaks barricades.",
		cooldown = 14,
		radius = 12,
		infectBurst = 35, -- infection % added to each survivor in range
		stagger = 1.5,
		breaksBarricade = true,
	},
	CloakLunge = {
		class = "Stalker",
		name = "Cloak Lunge",
		desc = "Briefly turn translucent and surge forward to ambush.",
		cooldown = 10,
		duration = 4, -- seconds of cloak + speed
		speedBonus = 10, -- added to walk speed while active
		transparency = 0.7, -- character transparency while cloaked
	},
	GooSpit = {
		class = "Spitter",
		name = "Goo Spit",
		desc = "Lob goo that pools on the ground and infects survivors at range.",
		cooldown = 6,
		range = 40,
		throwSpeed = 64,
		fuse = 0.9, -- seconds airborne before it pools
		poolRadius = 8,
		poolLifetime = 6, -- seconds the infecting pool lasts
	},
	MutationNest = {
		class = "Controller",
		name = "Mutation Nest",
		desc = "Plant a nest that slows survivors and speeds infection nearby.",
		cooldown = 18,
		nestRadius = 16,
		nestHealth = 120, -- survivors can shoot it down
		lifetime = 30,
	},
}

AbilityConfig.byClass = {
	Assault = "FragGrenade",
	Medic = "CleanseBeam",
	Engineer = "Barricade",
	Scout = "MotionPing",
	Bruiser = "GroundSlam",
	Stalker = "CloakLunge",
	Spitter = "GooSpit",
	Controller = "MutationNest",
}

return AbilityConfig
