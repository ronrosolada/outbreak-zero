--[[
	TeamManager (service)
	---------------------
	Creates the Survivors / Infected teams and assigns players. Teams give free
	colored name-tags and leaderboard grouping.
]]

local Teams = game:GetService("Teams")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))
local Brand = require(ReplicatedStorage:WaitForChild("Brand"))

local TeamManager = {}

local function makeTeam(name: string, color: Color3): Team
	local existing = Teams:FindFirstChild(name)
	if existing and existing:IsA("Team") then
		return existing
	end
	local team = Instance.new("Team")
	team.Name = name
	team.TeamColor = BrickColor.new(color) -- snaps to the nearest BrickColor
	team.AutoAssignable = false -- we assign teams ourselves each round
	team.Parent = Teams
	return team
end

function TeamManager:Initialize()
	self.survivorTeam = makeTeam(GameConfig.SURVIVOR_TEAM_NAME, Brand.Color.HumanBlue)
	self.infectedTeam = makeTeam(GameConfig.INFECTED_TEAM_NAME, Brand.Color.InfectedPink)
end

function TeamManager:ToSurvivor(player: Player)
	player.Neutral = false
	player.Team = self.survivorTeam
end

function TeamManager:ToInfected(player: Player)
	player.Neutral = false
	player.Team = self.infectedTeam
end

function TeamManager:ToLobby(player: Player)
	player.Team = nil
	player.Neutral = true
end

return TeamManager
