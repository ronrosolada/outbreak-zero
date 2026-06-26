--[[
	ContractsService (service) — Increment 4a
	-----------------------------------------
	Thin coordinator for daily contracts. DataService owns the persistent state (progress,
	claimed, daily reset); this service is the network face + the entry point gameplay
	services call to advance progress:
	  - ObjectiveService -> AddProgress(player, "gens", 1)
	  - InfectionService -> AddProgress(rescuer, "rescues", 1)
	  - RoundService     -> AddProgress(winner, "wins", 1)
	Pushes a fresh snapshot to the client whenever progress changes or a claim resolves.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ContractsService = {}

function ContractsService:Initialize(services)
	self.data = services.DataService
	self.net = require(ReplicatedStorage:WaitForChild("Net"))
	self._lastClaim = {} :: { [Player]: { [string]: number } } -- per-(player,contract) claim debounce
end

function ContractsService:Start()
	self.net.RequestContracts.OnServerEvent:Connect(function(player)
		self:_send(player)
	end)
	self.net.ClaimContract.OnServerEvent:Connect(function(player, id)
		if typeof(id) ~= "string" then
			return
		end
		-- Debounce per (player, contract) so spamming ONE contract is throttled but the
		-- player can still claim two different completed contracts back-to-back.
		local now = os.clock()
		local cd = self._lastClaim[player]
		if not cd then
			cd = {}
			self._lastClaim[player] = cd
		end
		if cd[id] and now - cd[id] < 0.4 then
			return
		end
		cd[id] = now
		if self.data:ClaimContract(player, id) then
			self.net.Notify:FireClient(player, "\u{2713} Contract complete — reward claimed!")
		end
		self:_send(player)
	end)
end

function ContractsService:OnPlayerRemoving(player: Player)
	self._lastClaim[player] = nil
end

-- Push the player's current contracts (no-op until their profile has loaded).
function ContractsService:_send(player: Player)
	local contracts = self.data:GetContracts(player)
	if contracts then
		self.net.ContractsState:FireClient(player, contracts)
	end
end

-- Gameplay hook: advance a contract and refresh the client if it actually moved.
function ContractsService:AddProgress(player: Player, id: string, amount: number)
	if self.data:AddContractProgress(player, id, amount) then
		self:_send(player)
	end
end

return ContractsService
