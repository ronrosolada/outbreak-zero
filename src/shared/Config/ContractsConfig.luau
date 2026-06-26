--[[
	ContractsConfig
	---------------
	Daily contracts (design social-hub widget, 02_UI_SCREENS): a small rotating set of
	goals that reset each day and pay credits — a cheap, strong retention hook ("log in,
	knock out your dailies"). Progress is tracked server-side in the player's profile and
	resets at UTC midnight. Tweak freely — pure tuning.

	Each contract: { id, desc, target, reward } where reward is in credits (coins).
]]

local ContractsConfig = {}

ContractsConfig.daily = {
	{ id = "gens", desc = "Power 5 generators", target = 5, reward = 60 },
	{ id = "rescues", desc = "Rescue 3 teammates", target = 3, reward = 50 },
	{ id = "wins", desc = "Win 2 matches", target = 2, reward = 80 },
}

return ContractsConfig
