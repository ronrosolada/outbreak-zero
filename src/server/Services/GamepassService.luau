--[[
	GamepassService (service)
	-------------------------
	Phase 9 — FAIR gamepasses. Perks are cosmetic only (a free exclusive trail),
	never gameplay power. Grants on join (if owned) and live on purchase. With the
	placeholder id=0 in GamepassConfig it no-ops cleanly, so it ships safely before
	the place is published; set the real ids later and it just works.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Config")
local GamepassConfig = require(Config:WaitForChild("GamepassConfig"))

local GamepassService = {}

function GamepassService:Initialize(services)
	self.data = services.DataService
end

function GamepassService:_grant(player: Player, pass: any)
	-- Cosmetic only — a free trail for owners. No gameplay power.
	if pass.grantsTrail then
		self.data:Unlock(player, pass.grantsTrail)
	end
end

function GamepassService:_check(player: Player, pass: any)
	if not pass.id or pass.id <= 0 then
		return -- placeholder id: nothing to verify until the place is published
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
	end)
	if ok and owns then
		self:_grant(player, pass)
	end
end

function GamepassService:Start()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
		if not purchased then
			return
		end
		for _, pass in GamepassConfig.passes do
			if pass.id == gamePassId then
				self:_grant(player, pass)
			end
		end
	end)
end

function GamepassService:OnPlayerAdded(player: Player)
	task.spawn(function()
		self.data:WaitForProfile(player) -- grant into the LOADED profile, never a placeholder
		for _, pass in GamepassConfig.passes do
			self:_check(player, pass)
		end
	end)
end

return GamepassService
