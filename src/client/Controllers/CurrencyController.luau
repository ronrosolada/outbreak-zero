--[[
	CurrencyController (client controller) — Increment 4b
	-----------------------------------------------------
	The design's dual-currency header: ◈ credits (earned) + ◆ gems (premium). Reads the
	mirrored player Attributes "Coins" and "Gems" (DataService is authoritative) and
	updates with no polling. Sits top-left; always visible.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Brand = require(ReplicatedStorage:WaitForChild("Brand"))

local CurrencyController = {}

local function pill(icon: string, color: Color3, order: number): (Frame, TextLabel)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(110, 34)
	frame.BackgroundColor3 = Brand.Color.Panel
	frame.BackgroundTransparency = 0.1
	frame.LayoutOrder = order
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 1.5
	stroke.Transparency = 0.35
	stroke.Parent = frame
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -12, 1, 0)
	label.Position = UDim2.fromOffset(6, 0)
	label.Font = Brand.Font.Display
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = color
	label.Text = icon .. " 0"
	label.Parent = frame
	return frame, label
end

function CurrencyController:Init()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "Currency"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	local row = Instance.new("Frame")
	row.Position = UDim2.fromOffset(16, 64) -- below the CONTRACTS button
	row.Size = UDim2.fromOffset(232, 34)
	row.BackgroundTransparency = 1
	row.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.Parent = row

	local creditsFrame, creditsLabel = pill("\u{25C8}", Brand.Color.HazardYellow, 1)
	creditsFrame.Parent = row
	local gemsFrame, gemsLabel = pill("\u{25C6}", Brand.Color.HumanBlue, 2)
	gemsFrame.Parent = row

	local function update()
		creditsLabel.Text = "\u{25C8} " .. tostring(player:GetAttribute("Coins") or 0)
		gemsLabel.Text = "\u{25C6} " .. tostring(player:GetAttribute("Gems") or 0)
	end
	player:GetAttributeChangedSignal("Coins"):Connect(update)
	player:GetAttributeChangedSignal("Gems"):Connect(update)
	update()
end

return CurrencyController
