--[[
	OnboardingController (client controller)
	----------------------------------------
	Phase 8 — a "How to Play" card shown on first join (so a 7-year-old gets it in
	5 seconds) plus a persistent "?" button to reopen it anytime. Brand-styled,
	zero text walls — short lines with color cues.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Brand = require(ReplicatedStorage:WaitForChild("Brand"))

local OnboardingController = {}

local STEPS = {
	{ icon = "\u{1F7E1}", text = "Power the 3 GENERATORS — stand on each and hold." },
	{ icon = "\u{2728}", text = "Every generator CLEANSES your team (heals infection!)." },
	{ icon = "\u{1F7E2}", text = "All 3 on? Get to the GREEN pad together to ESCAPE and win." },
	{ icon = "\u{1F9EC}", text = "Stay away from the Infected — they fill your meter. At 100% you go DOWN." },
	{ icon = "\u{1F91D}", text = "Revive downed friends. Press V to PING the team." },
}

local function corner(inst: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

function OnboardingController:Init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Onboarding"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.Parent = playerGui

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Brand.Color.BgDeep
	backdrop.BackgroundTransparency = 0.3
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.Parent = gui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(0.56, 0.66)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Brand.Color.Panel
	panel.BorderSizePixel = 0
	panel.Parent = backdrop
	corner(panel, 16)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Brand.Color.HumanBlue
	stroke.Thickness = 1.5
	stroke.Transparency = 0.4
	stroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(0.9, 0.12)
	title.Position = UDim2.fromScale(0.05, 0.04)
	title.Font = Brand.Font.Display
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Brand.Color.TextLight
	title.Text = "HOW TO PLAY"
	title.Parent = panel

	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Size = UDim2.fromScale(0.9, 0.6)
	list.Position = UDim2.fromScale(0.05, 0.18)
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	for i, step in STEPS do
		local row = Instance.new("TextLabel")
		row.Size = UDim2.fromScale(1, 0.17)
		row.BackgroundColor3 = Brand.Color.BgDeep
		row.BackgroundTransparency = 0.3
		row.Font = Brand.Font.Body
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = Brand.Color.TextLight
		row.Text = "  " .. step.icon .. "  " .. step.text
		row.LayoutOrder = i
		row.Parent = list
		corner(row, 8)
	end

	local gotIt = Instance.new("TextButton")
	gotIt.Size = UDim2.fromScale(0.5, 0.1)
	gotIt.Position = UDim2.fromScale(0.5, 0.93)
	gotIt.AnchorPoint = Vector2.new(0.5, 0.5)
	gotIt.Font = Brand.Font.Display
	gotIt.TextScaled = true
	gotIt.Text = "GOT IT!"
	gotIt.TextColor3 = Brand.Color.TextLight
	gotIt.BackgroundColor3 = Brand.Color.SafeGreen
	gotIt.Parent = panel
	corner(gotIt, 10)

	-- Persistent "?" reopen button.
	local helpButton = Instance.new("TextButton")
	helpButton.Name = "Help"
	helpButton.Size = UDim2.fromOffset(44, 44)
	helpButton.Position = UDim2.fromScale(0.97, 0.5)
	helpButton.AnchorPoint = Vector2.new(1, 0.5)
	helpButton.Font = Brand.Font.Display
	helpButton.TextScaled = true
	helpButton.Text = "?"
	helpButton.TextColor3 = Brand.Color.TextLight
	helpButton.BackgroundColor3 = Brand.Color.HumanBlue
	helpButton.Parent = gui
	corner(helpButton, 22)

	local function setOpen(open: boolean)
		backdrop.Visible = open
		helpButton.Visible = not open
	end

	gotIt.Activated:Connect(function()
		setOpen(false)
	end)
	helpButton.Activated:Connect(function()
		setOpen(true)
	end)

	setOpen(true) -- show once on join
end

return OnboardingController
