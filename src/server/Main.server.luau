--[[
	Main  (server bootstrap)
	------------------------
	Starts the service registry. Each module under Services/ may expose
	:Initialize(services) and :Start(). We require all, Initialize all (in
	dependency order), then Start all. (Modern 2026 alternative to Knit.)
]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create the RemoteEvents before any client asks for them.
require(ReplicatedStorage:WaitForChild("Net"))

local servicesFolder = ServerScriptService:WaitForChild("Services")

-- Dependency order: depended-upon services first; HubService (drives matches) last.
local SERVICE_ORDER = {
	"DataService", -- persistence first: profiles must be loadable before anything pays out
	"MapService",
	"TeamManager",
	"EconomyService",
	"ProgressionService",
	"StatsService",
	"ClassService",
	"CostumeService",
	"CombatService",
	"InfectionService",
	"AbilityService",
	"ObjectiveService",
	"RoundService",
	"HubService",
	"PingService",
	"StoreService",
	"GamepassService",
}

local services = {}
for _, name in SERVICE_ORDER do
	services[name] = require(servicesFolder:WaitForChild(name))
end
for _, name in SERVICE_ORDER do
	local service = services[name]
	if service.Initialize then
		service:Initialize(services)
	end
end

-- Phase 5 cross-ref: InfectionService's tick drives ObjectiveService, but Objective
-- is constructed after Infection in dependency order, so wire the back-ref now that
-- both are initialized. (ObjectiveService grabs InfectionService directly in Initialize.)
services.InfectionService.objectives = services.ObjectiveService

for _, name in SERVICE_ORDER do
	local service = services[name]
	if service.Start then
		service:Start()
	end
end

-- Per-player wiring (centralized so order is explicit).
local function onPlayerAdded(player: Player)
	services.DataService:OnPlayerAdded(player) -- load persistent data first (creates leaderstats)
	services.EconomyService:SetupPlayer(player)
	services.ClassService:OnPlayerAdded(player)
	services.InfectionService:OnPlayerAdded(player)
	services.RoundService:OnPlayerAdded(player)
	services.HubService:OnPlayerAdded(player)
	services.StoreService:OnPlayerAdded(player)
	services.GamepassService:OnPlayerAdded(player)
end

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	services.InfectionService:OnPlayerRemoving(player)
	services.RoundService:OnPlayerRemoving(player)
	services.HubService:OnPlayerRemoving(player)
	services.CombatService:OnPlayerRemoving(player)
	services.AbilityService:OnPlayerRemoving(player)
	services.PingService:OnPlayerRemoving(player)
	services.StoreService:OnPlayerRemoving(player)
	services.StatsService:OnPlayerRemoving(player)
	services.ProgressionService:OnPlayerRemoving(player)
	services.ClassService:OnPlayerRemoving(player)
	services.DataService:OnPlayerRemoving(player) -- save last, after other services finish writing
end)

print("[OutbreakZero] Server started — hub + matchmaking running.")
