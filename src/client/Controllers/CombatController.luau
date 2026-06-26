--[[
	CombatController (client controller)
	------------------------------------
	Wires the survivor's weapon Tools to the server and adds combat juice:
	  - on Tool.Activated, sends the weapon kind + camera aim direction to the server
	    (the server owns the raycast origin + does all validation)
	  - shows a crosshair while a ranged weapon is equipped
	  - flashes a hitmarker on a confirmed hit

	Aim is the camera look vector, which works on PC and mobile alike.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Brand = require(ReplicatedStorage:WaitForChild("Brand"))

local CombatController = {}

function CombatController:Init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "CombatHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	local crosshair = Instance.new("Frame")
	crosshair.Name = "Crosshair"
	crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshair.Position = UDim2.fromScale(0.5, 0.5)
	crosshair.Size = UDim2.fromOffset(6, 6)
	crosshair.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	crosshair.BackgroundTransparency = 0.2
	crosshair.BorderSizePixel = 0
	crosshair.Visible = false
	crosshair.Parent = gui
	local chCorner = Instance.new("UICorner")
	chCorner.CornerRadius = UDim.new(1, 0)
	chCorner.Parent = crosshair

	local hitmarker = Instance.new("TextLabel")
	hitmarker.Name = "Hitmarker"
	hitmarker.AnchorPoint = Vector2.new(0.5, 0.5)
	hitmarker.Position = UDim2.fromScale(0.5, 0.5)
	hitmarker.Size = UDim2.fromOffset(46, 46)
	hitmarker.BackgroundTransparency = 1
	hitmarker.Font = Brand.Font.Display
	hitmarker.Text = "\u{2715}"
	hitmarker.TextScaled = true
	hitmarker.TextColor3 = Brand.Color.HazardYellow
	hitmarker.TextTransparency = 1
	hitmarker.Parent = gui

	-- == Weapon input ==========================================================
	-- Weak keys so destroyed weapon Tools don't pile up as dead entries over a session.
	local hooked = setmetatable({}, { __mode = "k" })

	local function aimDirection(): Vector3
		local camera = Workspace.CurrentCamera
		return camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1)
	end

	local function hookTool(instance: Instance)
		if not instance:IsA("Tool") or hooked[instance] then
			return
		end
		local kind = instance:GetAttribute("WeaponKind")
		if not kind then
			return
		end
		hooked[instance] = true
		instance.Activated:Connect(function()
			Net.UseWeapon:FireServer(kind, aimDirection())
		end)
	end

	local function watch(container: Instance?)
		if not container then
			return
		end
		for _, child in container:GetChildren() do
			hookTool(child)
		end
		container.ChildAdded:Connect(hookTool)
	end

	-- Tools live in the Backpack and move into the Character when equipped.
	watch(player:WaitForChild("Backpack"))
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			watch(child)
		end
	end)
	if player.Character then
		watch(player.Character)
	end
	player.CharacterAdded:Connect(watch)

	-- == Crosshair (visible while a ranged weapon is equipped) =================
	RunService.RenderStepped:Connect(function()
		if player:GetAttribute("InMatch") ~= true then
			crosshair.Visible = false
			return -- no per-frame tool scan while in the hub
		end
		local char = player.Character
		local equipped = char and char:FindFirstChildOfClass("Tool")
		crosshair.Visible = equipped ~= nil and equipped:GetAttribute("WeaponKind") == "Ranged"
	end)

	-- == Hitmarker =============================================================
	Net.CombatFeedback.OnClientEvent:Connect(function(kind)
		if kind == "hit" then
			hitmarker.TextTransparency = 0
			TweenService:Create(hitmarker, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
		end
	end)
end

return CombatController
