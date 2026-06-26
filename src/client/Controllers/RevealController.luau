--[[
	RevealController (client controller)
	------------------------------------
	Renders the two "see-through-walls" reveals the server pushes:
	  - RevealInfected  (Scout Motion Ping)      -> outline infected for the survivor team.
	  - RevealSurvivors (Patient Zero Outbreak Pulse) -> outline survivors for PZ.
	Each reveal is a temporary AlwaysOnTop Highlight on the target characters that
	auto-clears after the server-sent duration. Re-revealing a target refreshes it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Brand = require(ReplicatedStorage:WaitForChild("Brand"))

local RevealController = {}

local active = {} :: { [Player]: { hl: Highlight, token: number } }
local counter = 0

local function clear(target: Player)
	local entry = active[target]
	if entry then
		if entry.hl.Parent then
			entry.hl:Destroy()
		end
		active[target] = nil
	end
end

local function reveal(target: Player, color: Color3, duration: number)
	if target == Players.LocalPlayer then
		return -- no point outlining yourself
	end
	local char = target.Character
	if not char then
		return
	end
	clear(target) -- replace any existing outline (refresh duration)

	local hl = Instance.new("Highlight")
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- visible through walls
	hl.FillColor = color
	hl.OutlineColor = color
	hl.FillTransparency = 0.6
	hl.OutlineTransparency = 0
	hl.Parent = char

	counter += 1
	local token = counter
	active[target] = { hl = hl, token = token }
	task.delay(duration, function()
		local entry = active[target]
		if entry and entry.token == token then
			clear(target)
		end
	end)
end

local function revealList(list, color: Color3, duration: number)
	if typeof(list) ~= "table" then
		return
	end
	for _, target in list do
		if typeof(target) == "Instance" and target:IsA("Player") then
			reveal(target, color, duration)
		end
	end
end

function RevealController:Init()
	Net.RevealInfected.OnClientEvent:Connect(function(list, duration)
		revealList(list, Brand.Color.InfectedPink, duration or 6)
	end)
	Net.RevealSurvivors.OnClientEvent:Connect(function(list, duration)
		revealList(list, Brand.Color.HumanBlue, duration or 5)
	end)
	Players.PlayerRemoving:Connect(clear)
end

return RevealController
