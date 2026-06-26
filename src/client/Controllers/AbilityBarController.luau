--[[
	AbilityBarController (client controller) — Phase 4
	--------------------------------------------------
	Shows your current class's signature ability as a button (tap, or press Q) and
	a client-predicted cooldown. On activate it sends UseAbility with the camera
	aim direction; the server validates + runs it authoritatively. The shown ability
	follows your role's class (Survivor -> HumanClass, Infected -> InfectedClass).

	(Registered in ClientMain during the shared-file pass — dormant until then.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ContextActionService = game:GetService("ContextActionService")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Brand = require(ReplicatedStorage:WaitForChild("Brand"))
local Config = ReplicatedStorage:WaitForChild("Config")
local AbilityConfig = require(Config:WaitForChild("AbilityConfig"))
local RoundState = require(ReplicatedStorage:WaitForChild("Round"):WaitForChild("RoundState"))

local AbilityBarController = {}

function AbilityBarController:Init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "AbilityHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui

	local button = Instance.new("TextButton")
	button.Name = "Ability"
	button.Size = UDim2.fromScale(0.1, 0.1)
	button.SizeConstraint = Enum.SizeConstraint.RelativeYY
	button.Position = UDim2.fromScale(0.88, 0.74)
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.BackgroundColor3 = Brand.Color.Panel
	button.BackgroundTransparency = 0.15
	button.AutoButtonColor = false
	button.Text = ""
	button.Visible = false
	button.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = Brand.Color.HazardYellow
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = button

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.fromScale(0.9, 0.4)
	nameLabel.Position = UDim2.fromScale(0.05, 0.18)
	nameLabel.Font = Brand.Font.Display
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Brand.Color.TextLight
	nameLabel.Text = "ABILITY"
	nameLabel.Parent = button

	local keyHint = Instance.new("TextLabel")
	keyHint.BackgroundTransparency = 1
	keyHint.Size = UDim2.fromScale(0.9, 0.28)
	keyHint.Position = UDim2.fromScale(0.05, 0.62)
	keyHint.Font = Brand.Font.Mono
	keyHint.TextScaled = true
	keyHint.TextColor3 = Brand.Color.TextDim
	keyHint.Text = "Q"
	keyHint.Parent = button

	local cooldownLabel = Instance.new("TextLabel")
	cooldownLabel.BackgroundTransparency = 1
	cooldownLabel.Size = UDim2.fromScale(1, 1)
	cooldownLabel.Font = Brand.Font.Display
	cooldownLabel.TextScaled = true
	cooldownLabel.TextColor3 = Brand.Color.TextLight
	cooldownLabel.Text = ""
	cooldownLabel.Visible = false
	cooldownLabel.Parent = button

	local state = { role = nil :: string?, phase = nil :: string?, cooldownUntil = 0, def = nil :: any }

	local function currentDef()
		if not state.role then
			return nil
		end
		local classId = player:GetAttribute(state.role == "Survivor" and "HumanClass" or "InfectedClass")
		local abilityId = classId and AbilityConfig.byClass[classId]
		return abilityId and AbilityConfig.abilities[abilityId] or nil
	end

	local function refresh()
		state.def = currentDef()
		if state.def then
			nameLabel.Text = string.upper(state.def.name)
		end
		-- recompute here too, so a RoleAssigned arriving AFTER the Action broadcast still reveals the button
		button.Visible = state.phase == RoundState.Action and state.def ~= nil
	end

	local function activate()
		local def = state.def
		if not def or os.clock() < state.cooldownUntil then
			return
		end
		state.cooldownUntil = os.clock() + def.cooldown -- client prediction; server is authoritative
		local camera = Workspace.CurrentCamera
		Net.UseAbility:FireServer(camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1))
	end

	button.Activated:Connect(activate)
	ContextActionService:BindAction("OZ_Ability", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			activate()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.Q)

	RunService.RenderStepped:Connect(function()
		if not button.Visible then
			return -- no per-frame property churn while hidden
		end
		local remaining = state.cooldownUntil - os.clock()
		if remaining > 0 then
			cooldownLabel.Visible = true
			cooldownLabel.Text = string.format("%.1f", remaining)
			button.BackgroundTransparency = 0.6
		else
			cooldownLabel.Visible = false
			button.BackgroundTransparency = 0.15
		end
	end)

	Net.RoleAssigned.OnClientEvent:Connect(function(role)
		state.role = role
		state.cooldownUntil = 0 -- a fresh ability on a role change starts ready
		refresh()
	end)
	player:GetAttributeChangedSignal("HumanClass"):Connect(refresh)
	player:GetAttributeChangedSignal("InfectedClass"):Connect(refresh)
	Net.RoundStateChanged.OnClientEvent:Connect(function(phase)
		state.phase = phase
		if phase ~= RoundState.Action then
			state.cooldownUntil = 0
		end
		refresh()
	end)

	refresh()
end

return AbilityBarController
