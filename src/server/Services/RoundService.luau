--[[
	RoundService (service)
	----------------------
	Runs ONE match for a given ROSTER of players (handed in by HubService when a
	queue fills), then returns them to the hub:

		Prep -> Action -> Results -> (back to hub)

	HubService owns the "when does a match start" loop; RoundService owns "how a
	match plays out". Match state is sent only to the roster; the rest of the
	server keeps living in the hub.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local RoundConfig = require(Config:WaitForChild("RoundConfig"))
local RoundState = require(ReplicatedStorage:WaitForChild("Round"):WaitForChild("RoundState"))

local RoundService = {}

function RoundService:Initialize(services)
	self.map = services.MapService
	self.teams = services.TeamManager
	self.economy = services.EconomyService
	self.infection = services.InfectionService
	self.progression = services.ProgressionService
	self.objectives = services.ObjectiveService
	self.stats = services.StatsService
	self.data = services.DataService
	self.net = require(ReplicatedStorage:WaitForChild("Net"))
	self.phase = RoundState.Hub
	self._arenaCounter = 0
	self.spawnConns = {} :: { [Player]: RBXScriptConnection }
end

-- == Player placement (respawns) =============================================

function RoundService:_placePlayer(player: Player)
	if player:GetAttribute("InMatch") and (self.phase == RoundState.Prep or self.phase == RoundState.Action) then
		self._arenaCounter += 1 -- spread respawners across spawn points
		self.map:SendToArena(player, self._arenaCounter)
	else
		self.map:SendToHub(player)
	end
end

function RoundService:OnPlayerAdded(player: Player)
	player:SetAttribute("InMatch", false)
	-- Placement (MapService) waits for the HumanoidRootPart itself.
	local conn = player.CharacterAdded:Connect(function()
		self:_placePlayer(player)
	end)
	self.spawnConns[player] = conn
	if player.Character then
		self:_placePlayer(player)
	end
end

function RoundService:OnPlayerRemoving(player: Player)
	local conn = self.spawnConns[player]
	if conn then
		conn:Disconnect()
		self.spawnConns[player] = nil
	end
end

-- Current match phase (Hub / Prep / Action / Results). Used by ClassService to gate
-- class changes to hub + Prep only.
function RoundService:GetPhase(): string
	return self.phase
end

-- == Match helpers ===========================================================

function RoundService:_broadcast(roster: { Player }, phase: string, timeLeft: number)
	local survivors = self.infection:GetSurvivorCount()
	local infected = self.infection:GetInfectedCount()
	for _, player in roster do
		if player.Parent then
			self.net.RoundStateChanged:FireClient(player, phase, timeLeft, survivors, infected)
		end
	end
end

function RoundService:_placeRoster(roster: { Player }, toArena: boolean)
	local index = 0
	for _, player in roster do
		index += 1
		if player.Parent then
			if toArena then
				self.map:SendToArena(player, index)
			else
				self.map:SendToHub(player)
			end
		end
	end
end

function RoundService:_payout(roster: { Player }, infectedWin: boolean)
	for _, player in roster do
		if player.Parent then
			-- Make sure a slow DataStore load has finished, so coins/XP/stats actually
			-- land instead of silently no-opping on a not-yet-loaded profile (C3). Returns
			-- promptly if the load already failed (read-only session).
			self.data:WaitForProfile(player)
			local role = self.infection:GetRole(player)
			self.economy:AddCoins(player, GameConfig.REWARD_PARTICIPATION)
			if infectedWin and role == GameConfig.ROLE_INFECTED then
				self.economy:AddCoins(player, GameConfig.REWARD_INFECTED_WIN)
			elseif not infectedWin and role == GameConfig.ROLE_SURVIVOR then
				self.economy:AddCoins(player, GameConfig.REWARD_SURVIVE_WIN)
			end
			-- Persistent progression: XP for finishing + a bonus for winning.
			self.progression:AwardMatchResult(player, role, infectedWin)
		end
	end
end

-- == Run one match ===========================================================

-- Prep + Action. Returns the match result: "survivor" | "infected" | "aborted".
-- Wrapped by RunMatch in a pcall so a mid-match error can't strand players.
function RoundService:_runMatch(roster: { Player }): (string, string)
	-- Pick a fresh arena for this match (random rotation), THEN drop the roster in.
	self.map:LoadRandomMap()
	self.stats:StartMatch(roster)
	-- Prep: drop the roster into the arena for a brief setup window.
	self.phase = RoundState.Prep
	self:_placeRoster(roster, true)
	for t = RoundConfig.PREP_SECONDS, 1, -1 do
		self:_broadcast(roster, RoundState.Prep, t)
		task.wait(1)
	end

	-- Action: assign roles, arm the objectives, run the round.
	self.phase = RoundState.Action
	self.infection:StartRound(roster)
	self.objectives:StartObjectives(roster)
	self:_broadcast(roster, RoundState.Action, RoundConfig.ACTION_SECONDS)
	for t = RoundConfig.ACTION_SECONDS, 1, -1 do
		self:_broadcast(roster, RoundState.Action, t)
		if self.objectives:IsExtractionComplete() then
			return "survivor", "The survivors escaped through extraction!"
		end
		local survivors = self.infection:GetSurvivorCount()
		local infected = self.infection:GetInfectedCount()
		if infected <= 0 then
			return "survivor", "The infected fled — survivors win!"
		end
		if survivors <= 0 then
			-- Survivors gone: a real infected win ONLY if someone was actually tagged.
			-- If everyone just LEFT with zero conversions, it's a no-contest abort.
			if self.infection:GetConversions() > 0 then
				return "infected", "Everyone got infected!"
			end
			return "aborted", "Match ended — no result."
		end
		task.wait(1)
	end
	-- Final boundary: extraction may have completed during the last second's wait.
	if self.objectives:IsExtractionComplete() then
		return "survivor", "The survivors escaped through extraction!"
	end
	return "infected", "Time ran out — the infected win!" -- the clock favors the infected
end

-- Blocks until the match is over. Cleanup ALWAYS runs, even if _runMatch errors.
function RoundService:RunMatch(roster: { Player })
	for _, player in roster do
		player:SetAttribute("InMatch", true)
	end

	local ok, result, reason = pcall(function()
		return self:_runMatch(roster)
	end)
	if not ok then
		warn("[RoundService] match error: " .. tostring(result))
		result, reason = "aborted", "Match ended — no result."
	end

	if result == "aborted" then
		-- No real contest (everyone left / mid-match error): clean up, no payout, neutral notice.
		self.infection:EndRound(roster)
		self.objectives:EndObjectives()
		for _, player in roster do
			if player.Parent then
				self.net.Notify:FireClient(player, reason)
			end
		end
	else
		local infectedWin = result == "infected"
		-- Resolve: pay out + read commendations (both read roles) BEFORE clearing them.
		self:_payout(roster, infectedWin)
		local awards, perPlayer = self.stats:BuildResults(roster)
		self.infection:EndRound(roster)
		self.objectives:EndObjectives()

		-- Results: announce the WHY + the results/commendations panel.
		for _, player in roster do
			if player.Parent then
				self.net.Notify:FireClient(player, reason)
				local mine = perPlayer[player] or { generators = 0, rescues = 0, survived = false }
				self.net.MatchResults:FireClient(player, infectedWin, awards, mine, reason)
			end
		end
	end

	self.phase = RoundState.Results
	self:_placeRoster(roster, false)
	for t = RoundConfig.RESULTS_SECONDS, 1, -1 do
		self:_broadcast(roster, RoundState.Results, t)
		task.wait(1)
	end

	-- Back to the hub.
	self.phase = RoundState.Hub
	for _, player in roster do
		player:SetAttribute("InMatch", false)
		if player.Parent then
			self.net.RoundStateChanged:FireClient(player, RoundState.Hub, 0, 0, 0)
		end
	end
end

return RoundService
