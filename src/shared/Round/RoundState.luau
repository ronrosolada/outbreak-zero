--[[
	RoundState
	----------
	A player is either in the HUB (hanging out / queueing) or inside a MATCH,
	which runs through Prep -> Action -> Results before returning them to the hub.
	Shared by server & client so both speak the same language.
]]

local RoundState = {
	Hub = "Hub", -- not in a match: socializing / queueing in the hub
	Prep = "Prep", -- match started, roster in the arena, brief setup
	Action = "Action", -- infection is live
	Results = "Results", -- showing the winner before returning to the hub
}

return RoundState
