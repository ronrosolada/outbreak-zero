--[[
	ResultsController (client controller)
	-------------------------------------
	Phase 8 — the end-of-round payoff screen: a big WIN/LOSE banner, the match
	COMMENDATIONS (MVP / Engineer / Guardian), and your own line of stats. Driven by
	the MatchResults remote; auto-hides after a few seconds as the hub returns.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Brand = require(ReplicatedStorage:WaitForChild("Brand"))

local ResultsController = {}

local SHOW_SECONDS = 7

local function corner(inst: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

function ResultsController:Init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Results"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 7
	gui.Enabled = false
	gui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(0.5, 0.6)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Brand.Color.Panel
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Parent = gui
	corner(panel, 16)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = panel

	local winner = Instance.new("TextLabel")
	winner.BackgroundTransparency = 1
	winner.Size = UDim2.fromScale(0.92, 0.18)
	winner.Position = UDim2.fromScale(0.5, 0.12)
	winner.AnchorPoint = Vector2.new(0.5, 0.5)
	winner.Font = Brand.Font.Display
	winner.TextScaled = true
	winner.Text = ""
	winner.Parent = panel

	local awardsTitle = Instance.new("TextLabel")
	awardsTitle.BackgroundTransparency = 1
	awardsTitle.Size = UDim2.fromScale(0.92, 0.08)
	awardsTitle.Position = UDim2.fromScale(0.5, 0.27)
	awardsTitle.AnchorPoint = Vector2.new(0.5, 0.5)
	awardsTitle.Font = Brand.Font.Body
	awardsTitle.TextScaled = true
	awardsTitle.TextColor3 = Brand.Color.TextDim
	awardsTitle.Text = "COMMENDATIONS"
	awardsTitle.Parent = panel

	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Size = UDim2.fromScale(0.86, 0.4)
	list.Position = UDim2.fromScale(0.5, 0.55)
	list.AnchorPoint = Vector2.new(0.5, 0.5)
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local myStats = Instance.new("TextLabel")
	myStats.BackgroundTransparency = 1
	myStats.Size = UDim2.fromScale(0.92, 0.1)
	myStats.Position = UDim2.fromScale(0.5, 0.92)
	myStats.AnchorPoint = Vector2.new(0.5, 0.5)
	myStats.Font = Brand.Font.Mono
	myStats.TextScaled = true
	myStats.TextColor3 = Brand.Color.TextLight
	myStats.Text = ""
	myStats.Parent = panel

	local function clearAwards()
		for _, child in list:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end
	end

	local token = 0
	Net.MatchResults.OnClientEvent:Connect(function(infectedWin, awards, mine)
		winner.Text = if infectedWin then "\u{2620} INFECTED WIN" else "\u{1F3C6} SURVIVORS WIN"
		winner.TextColor3 = if infectedWin then Brand.Color.InfectedPink else Brand.Color.HumanBlue
		stroke.Color = winner.TextColor3

		clearAwards()
		if typeof(awards) == "table" then
			for i, award in awards do
				local row = Instance.new("TextLabel")
				row.Size = UDim2.fromScale(1, 0.24)
				row.BackgroundColor3 = Brand.Color.BgDeep
				row.BackgroundTransparency = 0.25
				row.Font = Brand.Font.Display
				row.TextScaled = true
				row.TextColor3 = Brand.Color.HazardYellow
				row.Text = (award.title or "") .. "   " .. (award.name or "")
				row.LayoutOrder = i
				row.Parent = list
				corner(row, 8)
			end
		end

		local g = (mine and mine.generators) or 0
		local r = (mine and mine.rescues) or 0
		myStats.Text = string.format("You:  \u{26A1} %d generators   \u{1F91D} %d rescues", g, r)

		gui.Enabled = true
		token += 1
		local myToken = token
		task.delay(SHOW_SECONDS, function()
			if myToken == token then
				gui.Enabled = false
			end
		end)
	end)
end

return ResultsController
