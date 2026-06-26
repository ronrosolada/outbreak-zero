--[[
	GameConfig
	----------
	Gameplay tunables shared by server & client. One place to balance the game.
	(Match pacing lives separately in RoundConfig.)
]]

local GameConfig = {
	-- == Movement (studs/second). Infected are faster so rounds resolve. ==
	SURVIVOR_WALKSPEED = 16, -- Roblox default
	INFECTED_WALKSPEED = 20,
	PATIENT_ZERO_WALKSPEED = 22, -- the original infected is a touch faster
	JUMP_POWER = 50,

	-- == Coin rewards (stub payouts until Phase 7 persistence) ==
	REWARD_RESCUE = 30, -- to a survivor who revives a downed ally (rewards teamwork)
	REWARD_SURVIVE_WIN = 100,
	REWARD_INFECTED_WIN = 75,
	REWARD_PARTICIPATION = 10,

	-- == Teams (colors come from Brand: survivors = Human Blue, infected = Infected Pink) ==
	SURVIVOR_TEAM_NAME = "Survivors",
	INFECTED_TEAM_NAME = "Infected",

	-- == Role identifiers ==
	ROLE_SURVIVOR = "Survivor",
	ROLE_INFECTED = "Infected",
}

return GameConfig
