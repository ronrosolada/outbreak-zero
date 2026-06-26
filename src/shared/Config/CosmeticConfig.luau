--[[
	CosmeticConfig
	--------------
	Phase 9 — purely-cosmetic TRAILS bought with coins (no gameplay power; fair F2P).
	Trails are readability-safe (they don't recolor the body, so role colors stay
	clear). "none" is the free default everyone owns. More cosmetic types (titles,
	auras) and a season pass are deferred to a later increment.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Brand = require(ReplicatedStorage:WaitForChild("Brand"))

local CosmeticConfig = {}

CosmeticConfig.DEFAULT_TRAIL = "none"

CosmeticConfig.trails = {
	{ id = "none", name = "No Trail", price = 0, color = nil },
	{ id = "trail_blue", name = "Azure Streak", price = 150, color = Brand.Color.HumanBlue },
	{ id = "trail_pink", name = "Hot Trail", price = 150, color = Brand.Color.InfectedPink },
	{ id = "trail_green", name = "Toxic Wake", price = 250, color = Brand.Color.SafeGreen },
	{ id = "trail_gold", name = "Gold Rush", price = 500, color = Brand.Color.HazardYellow },
}

-- Fast id -> def lookup.
CosmeticConfig.byId = {}
for _, t in CosmeticConfig.trails do
	CosmeticConfig.byId[t.id] = t
end

return CosmeticConfig
