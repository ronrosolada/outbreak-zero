--[[
	PassConfig
	----------
	The "Outbreak Pass" — a seasonal reward track (design shop/social-hub). Earn pass XP
	by playing; each tier has a FREE reward everyone gets + a PREMIUM reward unlocked by
	buying the pass with gems. Cosmetic + currency rewards only (no power = fair F2P).

	SEASON_ID stamps the player's saved track; bumping it starts a fresh season (progress
	+ claims + premium ownership reset). Rewards: {kind="credits"|"gems"|"trail", amount/id}.
]]

local PassConfig = {}

PassConfig.SEASON_ID = "S1"
PassConfig.XP_PER_TIER = 200 -- pass XP per tier (pass XP == account match XP)
PassConfig.PREMIUM_COST = 150 -- gems to unlock the premium track

PassConfig.tiers = {
	{ free = { kind = "credits", amount = 50 }, premium = { kind = "gems", amount = 10 } },
	{ free = { kind = "credits", amount = 60 }, premium = { kind = "credits", amount = 200 } },
	{ free = { kind = "gems", amount = 3 }, premium = { kind = "gems", amount = 15 } },
	{ free = { kind = "credits", amount = 80 }, premium = { kind = "trail", id = "trail_prism" } },
	{ free = { kind = "credits", amount = 100 }, premium = { kind = "credits", amount = 300 } },
	{ free = { kind = "gems", amount = 5 }, premium = { kind = "gems", amount = 20 } },
	{ free = { kind = "credits", amount = 120 }, premium = { kind = "credits", amount = 350 } },
	{ free = { kind = "credits", amount = 140 }, premium = { kind = "trail", id = "trail_void" } },
	{ free = { kind = "gems", amount = 8 }, premium = { kind = "gems", amount = 30 } },
	{ free = { kind = "credits", amount = 200 }, premium = { kind = "credits", amount = 500 } },
}

return PassConfig
