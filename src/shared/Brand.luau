--[[
	Brand — Outbreak Zero design tokens
	------------------------------------
	Single source of truth for colors + fonts, taken from the Claude Design
	"Outbreak Zero" handoff (Direction A — "Outbreak Arcade"). Every UI surface
	references these so the whole game matches the brand.

	Conventions: BLUE = humans/allies · PINK = infected/threat ·
	YELLOW = warnings/hazards/pings · GREEN = health/safe/cleanse/rescue.
	Chunky rounded panels, neon glow on active elements, big mobile touch targets.
]]

local Brand = {
	Color = {
		HumanBlue = Color3.fromRGB(46, 168, 255), -- #2EA8FF survivors / allies
		InfectedPink = Color3.fromRGB(255, 46, 147), -- #FF2E93 infected / threat
		HazardYellow = Color3.fromRGB(255, 208, 46), -- #FFD02E warnings / pings / hazards
		SafeGreen = Color3.fromRGB(43, 232, 139), -- #2BE88B health / safe / cleanse / rescue
		BgDeep = Color3.fromRGB(20, 18, 43), -- #14122B background
		Panel = Color3.fromRGB(34, 29, 68), -- #221D44 panels
		TextLight = Color3.fromRGB(244, 241, 255),
		TextDim = Color3.fromRGB(170, 160, 200),
	},

	-- Roblox-native font mapping for the handoff's type system:
	--   Lilita One (display)  -> FredokaOne  (chunky rounded arcade display)
	--   Nunito (UI/body)      -> Nunito
	--   Space Mono (stats)    -> RobotoMono
	Font = {
		Display = Enum.Font.FredokaOne,
		Body = Enum.Font.Nunito,
		Mono = Enum.Font.RobotoMono,
	},
}

return Brand
