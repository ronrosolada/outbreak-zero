--[[
	AbilityConfig
	-------------
	Data-driven definitions for the 4 MVP class signature abilities (from the
	design's class cards). Server-validated cooldowns; effects implemented in
	AbilityService. Tweak freely — purely tuning values.

	Each class has exactly one signature ability (byClass maps class -> ability id).
]]

local AbilityConfig = {}

AbilityConfig.abilities = {
	FragGrenade = {
		class = "Assault",
		name = "Frag Grenade",
		desc = "Lob a grenade that stuns infected caught in the blast.",
		cooldown = 10,
		fuse = 1.4, -- seconds before it detonates
		throwSpeed = 64, -- studs/sec lob velocity
		blastRadius = 14, -- infected inside are stunned
	},
	CleanseBeam = {
		class = "Medic",
		name = "Cleanse Beam",
		desc = "Drain infection from yourself and nearby allies.",
		cooldown = 8,
		radius = 16,
		cleanseAmount = 45, -- infection % removed from each ally in range
	},
	GroundSlam = {
		class = "Bruiser",
		name = "Ground Slam",
		desc = "Slam the ground for a burst of infection around you.",
		cooldown = 9,
		radius = 14,
		infectBurst = 35, -- infection % added to each survivor in range
	},
	CloakLunge = {
		class = "Stalker",
		name = "Cloak Lunge",
		desc = "Briefly turn translucent and surge forward to ambush.",
		cooldown = 8,
		duration = 3, -- seconds of cloak + speed
		speedBonus = 10, -- added to walk speed while active
		transparency = 0.7, -- character transparency while cloaked
	},
}

AbilityConfig.byClass = {
	Assault = "FragGrenade",
	Medic = "CleanseBeam",
	Bruiser = "GroundSlam",
	Stalker = "CloakLunge",
}

return AbilityConfig
