--[[
	KillFeedController (client controller) — Increment 3
	----------------------------------------------------
	A top-right feed of match events (infect / rescue / stun / generator / outbreak),
	in faction colors with chunky icons — the readable "what just happened" stream from
	the design HUD (02_UI_SCREENS). Server fires Net.KillFeed(kind, nameA, nameB) for the
	whole roster; lines stack newest-on-top, cap at MAX_LINES, and fade after LIFETIME.

	Only renders while the local player is in a match (the feed is match flavor, not hub).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Brand = require(ReplicatedStorage:WaitForChild("Brand"))

local KillFeedController = {}

local MAX_LINES = 5
local LIFETIME = 5 -- seconds a line stays before fading

-- kind -> (color, text). a/b are player names (or counts for "generator").
local function describe(kind: string, a: string?, b: string?): (Color3, string)
	if kind == "infect" then
		return Brand.Color.InfectedPink, "\u{2623} " .. (a or "Someone") .. " was infected"
	elseif kind == "rescue" then
		return Brand.Color.SafeGreen, "\u{271A} " .. (a or "Someone") .. " revived " .. (b or "an ally")
	elseif kind == "stun" then
		return Brand.Color.HazardYellow, "\u{2726} " .. (a or "Someone") .. " stunned an infected"
	elseif kind == "generator" then
		return Brand.Color.HazardYellow, "\u{26A1} Generator " .. (a or "?") .. "/" .. (b or "?") .. " powered"
	elseif kind == "outbreak" then
		return Brand.Color.InfectedPink, "\u{2623} OUTBREAK — Patient Zero is loose!"
	end
	return Brand.Color.TextLight, tostring(kind)
end

function KillFeedController:Init()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "KillFeed"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")

	local list = Instance.new("Frame")
	list.Name = "Feed"
	list.AnchorPoint = Vector2.new(1, 0)
	list.Position = UDim2.new(1, -16, 0, 92) -- top-right, below the top bar
	list.Size = UDim2.fromOffset(320, 200)
	list.BackgroundTransparency = 1
	list.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list

	local seq = 0 -- newer lines get a smaller LayoutOrder so they sort to the top

	local function addLine(kind: string, a: string?, b: string?)
		if not player:GetAttribute("InMatch") then
			return -- match feed only
		end
		local color, text = describe(kind, a, b)

		seq -= 1
		local row = Instance.new("Frame")
		row.Size = UDim2.fromOffset(320, 30)
		row.BackgroundColor3 = Brand.Color.Panel
		row.BackgroundTransparency = 0.25
		row.BorderSizePixel = 0
		row.LayoutOrder = seq
		row.Parent = list
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = row
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = 1.5
		stroke.Transparency = 0.2
		stroke.Parent = row

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -16, 1, 0)
		label.Position = UDim2.fromOffset(8, 0)
		label.BackgroundTransparency = 1
		label.Font = Brand.Font.Body
		label.TextSize = 16
		label.TextXAlignment = Enum.TextXAlignment.Right
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.5
		label.Text = text
		label.Parent = row

		-- Trim to the newest MAX_LINES (remove the oldest = largest LayoutOrder).
		local rows = {}
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				table.insert(rows, child)
			end
		end
		if #rows > MAX_LINES then
			table.sort(rows, function(x, y)
				return x.LayoutOrder > y.LayoutOrder
			end)
			for i = 1, #rows - MAX_LINES do
				rows[i]:Destroy()
			end
		end

		task.delay(LIFETIME, function()
			if row.Parent then
				TweenService:Create(row, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
				TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
				TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 })
					:Play()
				task.delay(0.45, function()
					if row.Parent then
						row:Destroy()
					end
				end)
			end
		end)
	end

	Net.KillFeed.OnClientEvent:Connect(addLine)
end

return KillFeedController
