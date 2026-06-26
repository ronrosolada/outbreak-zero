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

-- Each trail: { id, name, price, color, currency }. currency defaults to "coins";
-- premium trails cost "gems" (the ◆ currency). Trails are readability-safe (they don't
-- recolor the body) so any color is fine — that's why cosmetics here are trails, not
-- body skins (full body recolors would break the blue=survivor / pink=infected rule).
CosmeticConfig.trails = {
	{ id = "none", name = "No Trail", price = 0, color = nil },
	{ id = "trail_blue", name = "Azure Streak", price = 150, color = Brand.Color.HumanBlue },
	{ id = "trail_pink", name = "Hot Trail", price = 150, color = Brand.Color.InfectedPink },
	{ id = "trail_green", name = "Toxic Wake", price = 250, color = Brand.Color.SafeGreen },
	{ id = "trail_gold", name = "Gold Rush", price = 500, color = Brand.Color.HazardYellow },
	-- Premium (gems):
	{ id = "trail_prism", name = "Prism", price = 40, currency = "gems", color = Color3.fromRGB(180, 120, 255) },
	{ id = "trail_void", name = "Void Wisp", price = 70, currency = "gems", color = Color3.fromRGB(120, 120, 150) },
}

-- Fast id -> def lookup.
CosmeticConfig.byId = {}
for _, t in CosmeticConfig.trails do
	CosmeticConfig.byId[t.id] = t
end

return CosmeticConfig
