--[[
	StatsService (service)
	----------------------
	Phase 8 — per-match performance tracking that feeds the end-of-round results +
	COMMENDATIONS screen (a big retention hook: everyone leaves a match with a
	highlight). Other services call :Add when something noteworthy happens; at match
	end RoundService calls :BuildResults to compute the awards. Stats are per-match
	only (reset every StartMatch) — persistent lifetime stats live in DataService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))

local StatsService = {}

function StatsService:Initialize(services)
	self.infection = services.InfectionService
	self.stats = {} :: { [Player]: { generators: number, rescues: number } }
end

-- Reset counters for a fresh match roster.
function StatsService:StartMatch(roster: { Player })
	self.stats = {}
	for _, player in roster do
		self.stats[player] = { generators = 0, rescues = 0 }
	end
end

-- Release a departed player's entry immediately (otherwise held until next StartMatch).
function StatsService:OnPlayerRemoving(player: Player)
	self.stats[player] = nil
end

function StatsService:Add(player: Player, key: string, amount: number)
	local s = self.stats[player]
	if s and s[key] ~= nil then
		s[key] += amount
	end
end

-- Compute commendations + per-player stats for the results screen. MUST be called
-- while roles are still assigned (before InfectionService:EndRound), so "survived"
-- can be read. Returns (awards, perPlayer).
function StatsService:BuildResults(roster: { Player }): ({ { title: string, name: string } }, { [Player]: any })
	local awards = {}
	local perPlayer = {}

	local bestGen, genName = 0, nil
	local bestRes, resName = 0, nil
	local bestScore, mvpName = 0, nil

	for _, player in roster do
		local s = self.stats[player] or { generators = 0, rescues = 0 }
		local survived = self.infection:GetRole(player) == GameConfig.ROLE_SURVIVOR
		perPlayer[player] = { generators = s.generators, rescues = s.rescues, survived = survived }

		if s.generators > bestGen then
			bestGen, genName = s.generators, player.Name
		end
		if s.rescues > bestRes then
			bestRes, resName = s.rescues, player.Name
		end
		local score = s.generators * 10 + s.rescues * 15 + (if survived then 20 else 0)
		if score > bestScore then
			bestScore, mvpName = score, player.Name
		end
	end

	if mvpName then
		table.insert(awards, { title = "\u{2B50} MVP", name = mvpName })
	end
	if genName then
		table.insert(awards, { title = "\u{26A1} Engineer", name = genName })
	end
	if resName then
		table.insert(awards, { title = "\u{1F91D} Guardian", name = resName })
	end

	return awards, perPlayer
end

return StatsService
