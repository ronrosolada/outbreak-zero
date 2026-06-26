--[[
	PingController (client controller)
	----------------------------------
	Phase 8 — press V (or tap the on-screen PING button on mobile) to mark the spot
	under your cursor; the server relays it to your faction and every teammate sees a
	floating world marker for a few seconds. Chat-free team comms (safe + readable).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Brand = require(ReplicatedStorage:WaitForChild("Brand"))

local PingController = {}

local PING_LIFETIME = 5 -- seconds a ping marker lingers

function PingController:Init()
	local player = Players.LocalPlayer
	local cam = Workspace.CurrentCamera

	local function targetUnderCursor(): Vector3?
		local loc = UserInputService:GetMouseLocation()
		local ray = cam:ViewportPointToRay(loc.X, loc.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = if player.Character then { player.Character } else {}
		local result = Workspace:Raycast(ray.Origin, ray.Direction * 600, params)
		return result and result.Position or nil
	end

	ContextActionService:BindAction("OutbreakPing", function(_, state)
		if state == Enum.UserInputState.Begin then
			local pos = targetUnderCursor()
			if pos then
				Net.Ping:FireServer(pos)
			end
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.V)
	ContextActionService:SetTitle("OutbreakPing", "PING")

	Net.Ping.OnClientEvent:Connect(function(position, name, kind)
		if typeof(position) ~= "Vector3" then
			return
		end
		local color = if kind == "infected" then Brand.Color.InfectedPink else Brand.Color.HumanBlue

		local marker = Instance.new("Part")
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanQuery = false
		marker.Shape = Enum.PartType.Ball
		marker.Size = Vector3.new(2, 2, 2)
		marker.Material = Enum.Material.Neon
		marker.Color = color
		marker.Transparency = 0.2
		marker.Position = position + Vector3.new(0, 2, 0)
		marker.Parent = Workspace

		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(160, 44)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 1000
		billboard.Parent = marker
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Brand.Font.Display
		label.TextScaled = true
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.3
		label.Text = "\u{1F4CD} " .. (name or "Ping")
		label.Parent = billboard

		Debris:AddItem(marker, PING_LIFETIME)
	end)
end

return PingController
