--[[
	EconomyService (service)
	------------------------
	Thin façade over DataService for coins. Coins now live in the persistent
	player profile, and DataService owns the leaderstats "Coins" board. This
	service just exposes the AddCoins call the rest of the game already uses, so
	existing callers (e.g. RoundService payouts) didn't have to change when
	Phase 7 added saving.
]]

local EconomyService = {}

function EconomyService:Initialize(services)
	self.data = services.DataService
end

-- Leaderstats are created by DataService when a profile loads. Kept as a no-op
-- so the existing Main.server call site stays valid.
function EconomyService:SetupPlayer(_player: Player) end

function EconomyService:AddCoins(player: Player, amount: number)
	self.data:AddCoins(player, amount)
end

return EconomyService
