--[[
	ClassService (service)
	----------------------
	Each player keeps a chosen class PER FACTION (humanClass / infectedClass),
	mirrored to Player Attributes so the client class-select reflects them. The
	round's role decides which one applies; stats (walk speed, etc.) come from
	ClassConfig. Abilities are wired in a later increment.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local ClassConfig = require(Config:WaitForChild("ClassConfig"))
local RoundState = require(ReplicatedStorage:WaitForChild("Round"):WaitForChild("RoundState"))

local ClassService = {}

function ClassService:Initialize(services)
	self.data = services.DataService
	self.round = services.RoundService
	self.net = require(ReplicatedStorage:WaitForChild("Net"))
	self.humanClass = {} :: { [Player]: string }
	self.infectedClass = {} :: { [Player]: string }
end

function ClassService:Start()
	self.net.SelectClass.OnServerEvent:Connect(function(player, classId)
		self:SetClass(player, classId)
	end)
end

function ClassService:OnPlayerAdded(player: Player)
	self.humanClass[player] = ClassConfig.DEFAULT_HUMAN
	self.infectedClass[player] = ClassConfig.DEFAULT_INFECTED
	player:SetAttribute("HumanClass", ClassConfig.DEFAULT_HUMAN)
	player:SetAttribute("InfectedClass", ClassConfig.DEFAULT_INFECTED)
end

function ClassService:OnPlayerRemoving(player: Player)
	self.humanClass[player] = nil
	self.infectedClass[player] = nil
end

function ClassService:SetClass(player: Player, classId)
	if typeof(classId) ~= "string" then
		return
	end
	local def = ClassConfig.classes[classId]
	if not def then
		return -- unknown class id
	end
	-- No swapping class mid-match: allowed in the hub (not InMatch) or during Prep, but
	-- locked once the round is live (Action/Results). Gate on the PLAYER'S own match
	-- state so hub players can still repick while a different match runs elsewhere.
	if player:GetAttribute("InMatch") and self.round:GetPhase() ~= RoundState.Prep then
		self.net.Notify:FireClient(player, "You can't change class mid-match.")
		return
	end
	-- Locked classes must be bought in the shop first (server-authoritative gate).
	if (def.unlockCost or 0) > 0 and not self.data:IsUnlocked(player, classId) then
		self.net.Notify:FireClient(player, def.display .. " is LOCKED — unlock it in the Shop.")
		return
	end
	if def.faction == "Human" then
		self.humanClass[player] = classId
		player:SetAttribute("HumanClass", classId)
	else
		self.infectedClass[player] = classId
		player:SetAttribute("InfectedClass", classId)
	end
end

function ClassService:GetClassForRole(player: Player, role: string): string
	if role == GameConfig.ROLE_INFECTED then
		return self.infectedClass[player] or ClassConfig.DEFAULT_INFECTED
	end
	return self.humanClass[player] or ClassConfig.DEFAULT_HUMAN
end

function ClassService:GetWalkSpeed(player: Player, role: string): number
	local def = ClassConfig.classes[self:GetClassForRole(player, role)]
	return def and def.walkSpeed or GameConfig.SURVIVOR_WALKSPEED
end

-- Survivor infection-fill multiplier (HP-as-tankiness): tankier classes fill slower.
function ClassService:GetFillMult(player: Player): number
	local def = ClassConfig.classes[self:GetClassForRole(player, GameConfig.ROLE_SURVIVOR)]
	return (def and def.fillMult) or 1
end

-- The chosen class's Passive flags for a role (e.g. {AllyDecayMult=1.5}).
function ClassService:GetPassive(player: Player, role: string): { [string]: any }
	local def = ClassConfig.classes[self:GetClassForRole(player, role)]
	return (def and def.Passive) or {}
end

-- Infected stun-out threshold for the player's chosen infected class (tankiness).
function ClassService:GetInfectedHealth(player: Player): number
	local def = ClassConfig.classes[self:GetClassForRole(player, GameConfig.ROLE_INFECTED)]
	return (def and def.health) or 100
end

return ClassService
