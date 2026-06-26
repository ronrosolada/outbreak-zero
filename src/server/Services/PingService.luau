--[[
	PingService (service)
	---------------------
	Phase 8 — a world-space PING so teammates can communicate without chat (key for
	a kids' game: readable, safe, no typing). A player marks a spot; the server
	validates + rate-limits and relays it to their FACTION only (survivors don't
	reveal pings to infected and vice-versa). Pure relay — the client draws the marker.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))

local PING_COOLDOWN = 1.25 -- seconds between pings per player
local MAX_RANGE = 600 -- studs from origin a ping may be (anti-garbage)

local PingService = {}

function PingService:Initialize(services)
	self.infection = services.InfectionService
	self.net = require(ReplicatedStorage:WaitForChild("Net"))
	self.lastPing = {} :: { [Player]: number }
end

function PingService:Start()
	self.net.Ping.OnServerEvent:Connect(function(player, position)
		self:_onPing(player, position)
	end)
end

function PingService:OnPlayerRemoving(player: Player)
	self.lastPing[player] = nil
end

function PingService:_onPing(player: Player, position: any)
	if typeof(position) ~= "Vector3" then
		return -- never trust the client's payload
	end
	-- Only in-match players ping, and only to their own faction.
	local role = self.infection:GetRole(player)
	if not role then
		return
	end
	local mag = position.Magnitude
	if mag ~= mag or mag > MAX_RANGE then -- rejects NaN in ANY component (mag is NaN) + out-of-range
		return
	end

	local now = os.clock()
	if self.lastPing[player] and now - self.lastPing[player] < PING_COOLDOWN then
		return
	end
	self.lastPing[player] = now

	local kind = if role == GameConfig.ROLE_INFECTED then "infected" else "survivor"
	for _, other in Players:GetPlayers() do
		if self.infection:GetRole(other) == role then
			self.net.Ping:FireClient(other, position, player.Name, kind)
		end
	end
end

return PingService
