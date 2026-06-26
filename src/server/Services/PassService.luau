--[[
	PassService (service) — Increment 4d
	------------------------------------
	Network face for the Outbreak Pass. DataService owns the persistent track (xp, tier
	claims, premium ownership, season reset); this service handles the remotes and is the
	entry point ProgressionService calls to add pass XP after a match. Pushes a fresh
	Net.PassState on any change.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PassService = {}

function PassService:Initialize(services)
	self.data = services.DataService
	self.net = require(ReplicatedStorage:WaitForChild("Net"))
	self._last = {} :: { [Player]: { [string]: number } } -- per-(player, action-key) debounce
end

-- Debounce per (player, key) so distinct actions (e.g. two different tier claims) aren't
-- dropped by a single global per-player throttle — mirrors ContractsService.
function PassService:_throttled(player: Player, key: string): boolean
	local now = os.clock()
	local m = self._last[player]
	if not m then
		m = {}
		self._last[player] = m
	end
	if m[key] and now - m[key] < 0.3 then
		return true
	end
	m[key] = now
	return false
end

function PassService:Start()
	self.net.RequestPass.OnServerEvent:Connect(function(player)
		if self:_throttled(player, "request") then
			return -- read-only, but throttle to avoid GetPass/FireClient spam
		end
		self:_send(player)
	end)
	self.net.ClaimPassReward.OnServerEvent:Connect(function(player, tier, isPremium)
		if type(tier) ~= "number" then
			return
		end
		-- Key per (tier, track) so a freshly-leveled player can claim several cells back-to-back.
		if self:_throttled(player, tostring(tier) .. (if isPremium == true then "P" else "F")) then
			return
		end
		if self.data:ClaimPassReward(player, tier, isPremium == true) then
			self.net.Notify:FireClient(player, "\u{2728} Pass reward claimed!")
		end
		self:_send(player)
	end)
	self.net.UnlockPassPremium.OnServerEvent:Connect(function(player)
		if self:_throttled(player, "unlock") then
			return
		end
		if self.data:UnlockPassPremium(player) then
			self.net.Notify:FireClient(player, "\u{2B50} Outbreak Pass unlocked — premium rewards are yours!")
		else
			self.net.Notify:FireClient(player, "Not enough gems for the Outbreak Pass.")
		end
		self:_send(player)
	end)
end

function PassService:OnPlayerRemoving(player: Player)
	self._last[player] = nil
end

-- Push the player's current pass (no-op until the profile loads).
function PassService:_send(player: Player)
	local pass = self.data:GetPass(player)
	if pass then
		self.net.PassState:FireClient(player, pass)
	end
end

-- Gameplay hook (ProgressionService after a match): add pass XP + refresh the client.
function PassService:AddXp(player: Player, amount: number)
	self.data:AddPassXp(player, amount)
	self:_send(player)
end

return PassService
