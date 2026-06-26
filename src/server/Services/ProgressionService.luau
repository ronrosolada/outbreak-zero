--[[
	ProgressionService (service)
	----------------------------
	Turns gameplay into progression: awards XP at the end of a match (called by
	RoundService alongside the coin payout) and runs the daily-login reward. All
	persistence goes through DataService; this service only decides the numbers.

	Server-authoritative: the client can only ASK to claim a daily reward — the
	server checks the timer and grants it. Never trust the client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local ProgressionConfig = require(Config:WaitForChild("ProgressionConfig"))

local ProgressionService = {}

function ProgressionService:Initialize(services)
	self.data = services.DataService
	self.net = require(ReplicatedStorage:WaitForChild("Net"))
	self._claiming = {} :: { [Player]: boolean } -- in-flight daily claims (anti double-grant)
	self._lastReq = {} :: { [Player]: number } -- per-player RequestDailyState debounce
end

function ProgressionService:OnPlayerRemoving(player: Player)
	self._claiming[player] = nil
	self._lastReq[player] = nil
end

function ProgressionService:Start()
	-- Claims must run against the LOADED profile, never the load-window placeholder —
	-- otherwise a client firing on join could farm "Day 1" and clobber the real save.
	self.net.ClaimDailyReward.OnServerEvent:Connect(function(player)
		task.spawn(function()
			if self.data:WaitForProfile(player) then
				self:_claimDaily(player)
			end
		end)
	end)
	-- Client asks for its daily state once its HUD is ready (mirrors RequestHubState).
	self.net.RequestDailyState.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if self._lastReq[player] and now - self._lastReq[player] < 0.5 then
			return -- light per-player debounce against request spam
		end
		self._lastReq[player] = now
		task.spawn(function()
			if self.data:WaitForProfile(player) then
				self:_sendDailyState(player)
			end
		end)
	end)
end

-- == Match XP ================================================================

-- Called from RoundService:_payout for each roster player, next to the coin
-- award. `infectedWin` is the match result; we work out if THIS player won.
function ProgressionService:AwardMatchResult(player: Player, role: string, infectedWin: boolean)
	local won = (infectedWin and role == GameConfig.ROLE_INFECTED)
		or (not infectedWin and role == GameConfig.ROLE_SURVIVOR)

	local xp = ProgressionConfig.XP_PARTICIPATION + (if won then ProgressionConfig.XP_WIN else 0)
	self.data:AddXp(player, xp)

	local profile = self.data:GetProfile(player)
	if profile then
		profile.stats.rounds += 1
		if won then
			if role == GameConfig.ROLE_INFECTED then
				profile.stats.infectedWins += 1
			else
				profile.stats.survivorWins += 1
			end
		end
	end
end

-- == Daily reward ============================================================

-- Returns: canClaim, dayIfClaimedNow, coinAmount, secondsUntilClaimable
function ProgressionService:_dailyState(profile): (boolean, number, number, number)
	local daily = profile.daily
	local now = os.time()
	local cooldown = ProgressionConfig.DAILY_COOLDOWN_HOURS * 3600
	local grace = ProgressionConfig.DAILY_STREAK_GRACE_HOURS * 3600
	local elapsed = now - daily.lastClaim

	local firstEver = daily.lastClaim == 0
	local canClaim = firstEver or elapsed >= cooldown

	-- The streak/day they'd be on if they claimed right now.
	local day
	if firstEver or elapsed > grace then
		day = 1 -- never claimed, or waited too long -> streak resets
	else
		day = daily.streak + 1
	end

	local rewards = ProgressionConfig.DAILY_REWARDS
	local amount = rewards[math.min(day, #rewards)]
	local secondsLeft = if canClaim then 0 else math.max(0, cooldown - elapsed)
	return canClaim, day, amount, secondsLeft
end

function ProgressionService:_sendDailyState(player: Player)
	local profile = self.data:GetProfile(player)
	if not profile then
		return
	end
	local canClaim, day, amount, secondsLeft = self:_dailyState(profile)
	self.net.DailyRewardState:FireClient(player, canClaim, day, amount, secondsLeft)
end

function ProgressionService:_claimDaily(player: Player)
	local profile = self.data:GetProfile(player)
	if not profile then
		return
	end
	-- In-flight guard: makes "no double-claim" explicit instead of silently depending
	-- on this function staying yield-free before the lastClaim write. Set BEFORE the
	-- canClaim check (the check->write below has no yield) and hold it across SaveNow
	-- (which DOES yield) so a spammed ClaimDailyReward can never grant twice.
	if self._claiming[player] then
		return
	end
	self._claiming[player] = true

	local canClaim, day, amount = self:_dailyState(profile)
	if canClaim then
		profile.daily.streak = day
		profile.daily.lastClaim = os.time()
		self.data:AddCoins(player, amount)
		self.data:SaveNow(player) -- persist immediately so the reward can't be re-claimed
		self.net.Notify:FireClient(player, ("Daily reward: +%d coins  (Day %d)"):format(amount, day))
	end

	self._claiming[player] = nil
	self:_sendDailyState(player) -- always resync the client (claimed, or it was out of sync)
end

return ProgressionService
