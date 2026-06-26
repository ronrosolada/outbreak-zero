--[[
	CombatConfig
	------------
	Weapon stats + infected health/stun tunables. Survivors fight back to create
	space and break the rescue standoff; the infected are never killed, only
	briefly STUNNED, preserving the asymmetry.
]]

local CombatConfig = {
	-- == Ranged weapon (hitscan) ==
	RANGED_NAME = "Pulse Rifle",
	RANGED_DAMAGE = 25,
	RANGED_RANGE = 220, -- studs
	RANGED_COOLDOWN = 0.45, -- seconds between shots

	-- == Melee weapon ==
	MELEE_NAME = "Stun Baton",
	MELEE_DAMAGE = 45,
	MELEE_RANGE = 9, -- studs (radius around the swinger)
	MELEE_COOLDOWN = 0.8,

	-- == Infected health + stun ==
	INFECTED_MAX_HEALTH = 100,
	STUN_SECONDS = 5, -- how long an infected is downed/frozen after HP hits 0
}

return CombatConfig
