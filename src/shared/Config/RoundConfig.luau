--[[
	RoundConfig
	-----------
	Match pacing & sizing. A match runs for a ROSTER of players pulled from the
	hub queue (see HubService); these values shape one match.
]]

local RoundConfig = {
	MIN_PLAYERS = 2, -- queue must reach this many before the start countdown begins
	MAX_PLAYERS = 12, -- roster cap; once the queue hits this, the match pops immediately
	QUEUE_COUNTDOWN_SECONDS = 15, -- once MIN_PLAYERS are queued, wait this long for more before starting
	PATIENT_ZERO_RATIO = 5, -- 1 starting-infected per N players in the roster (min 1)

	-- Phase durations (seconds)
	PREP_SECONDS = 10, -- setup time in the arena before infection begins
	ACTION_SECONDS = 360, -- 6 min (tune toward Roblox snappiness during playtests)
	RESULTS_SECONDS = 8, -- winner screen before returning to the hub
}

return RoundConfig
