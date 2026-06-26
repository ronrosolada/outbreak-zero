--[[
	GamepassConfig
	--------------
	Phase 9 — FAIR, non-pay-to-win gamepasses. Perks are cosmetic only (an exclusive
	trail), never power. The `id` values are PLACEHOLDERS (0) until the game is
	published and real gamepass IDs exist on the Roblox creator dashboard; with id=0
	GamepassService no-ops cleanly, so this ships and tests safely now.
]]

local GamepassConfig = {}

GamepassConfig.passes = {
	{
		key = "VIP",
		id = 0, -- TODO: set to the real gamepass id after publishing the place
		name = "VIP",
		grantsTrail = "trail_gold", -- VIPs get this cosmetic trail for free (no gameplay power)
	},
}

return GamepassConfig
