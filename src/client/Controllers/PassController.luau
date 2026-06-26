--[[
	PassController (client controller) — Increment 4d
	-------------------------------------------------
	The Outbreak Pass screen: a button opens a panel showing the seasonal tier track with
	a FREE and a PREMIUM reward per tier, claim buttons, the current tier + XP progress,
	and an "Unlock Premium" (gems) button. Reads Net.PassState; claims via
	Net.ClaimPassReward / Net.UnlockPassPremium. Server is authoritative. Hub-only.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Brand = require(ReplicatedStorage:WaitForChild("Brand"))

local PassController = {}

local function corner(inst: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local function rewardText(r: any): string
	if not r then
		return "-"
	end
	if r.kind == "credits" then
		return "\u{25C8} " .. r.amount
	elseif r.kind == "gems" then
		return "\u{25C6} " .. r.amount
	elseif r.kind == "trail" then
		return "\u{2728} Trail"
	end
	return "-"
end

function PassController:Init()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "OutbreakPass"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	local openBtn = Instance.new("TextButton")
	openBtn.Name = "Open"
	openBtn.Position = UDim2.fromOffset(16, 106)
	openBtn.Size = UDim2.fromOffset(150, 40)
	openBtn.BackgroundColor3 = Brand.Color.Panel
	openBtn.Font = Brand.Font.Display
	openBtn.TextScaled = true
	openBtn.TextColor3 = Brand.Color.SafeGreen
	openBtn.Text = "\u{2B50} PASS"
	openBtn.Parent = gui
	corner(openBtn, 10)
	local openStroke = Instance.new("UIStroke")
	openStroke.Color = Brand.Color.SafeGreen
	openStroke.Thickness = 1.5
	openStroke.Transparency = 0.4
	openStroke.Parent = openBtn

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(520, 480)
	panel.BackgroundColor3 = Brand.Color.BgDeep
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 18)
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Brand.Color.SafeGreen
	panelStroke.Thickness = 2
	panelStroke.Transparency = 0.3
	panelStroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(16, 12)
	title.Size = UDim2.new(1, -120, 0, 30)
	title.Font = Brand.Font.Display
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Brand.Color.TextLight
	title.Text = "OUTBREAK PASS"
	title.Parent = panel

	local progressLabel = Instance.new("TextLabel")
	progressLabel.BackgroundTransparency = 1
	progressLabel.Position = UDim2.fromOffset(16, 44)
	progressLabel.Size = UDim2.new(1, -32, 0, 20)
	progressLabel.Font = Brand.Font.Body
	progressLabel.TextScaled = true
	progressLabel.TextXAlignment = Enum.TextXAlignment.Left
	progressLabel.TextColor3 = Brand.Color.TextDim
	progressLabel.Text = "Tier 0"
	progressLabel.Parent = panel

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.fromOffset(36, 36)
	close.BackgroundColor3 = Brand.Color.Panel
	close.Font = Brand.Font.Display
	close.TextScaled = true
	close.TextColor3 = Brand.Color.TextLight
	close.Text = "\u{2715}"
	close.Parent = panel
	corner(close, 10)

	local unlockBtn = Instance.new("TextButton")
	unlockBtn.AnchorPoint = Vector2.new(1, 0)
	unlockBtn.Position = UDim2.new(1, -56, 0, 14)
	unlockBtn.Size = UDim2.fromOffset(150, 32)
	unlockBtn.BackgroundColor3 = Brand.Color.SafeGreen
	unlockBtn.Font = Brand.Font.Display
	unlockBtn.TextScaled = true
	unlockBtn.TextColor3 = Brand.Color.BgDeep
	unlockBtn.Text = "UNLOCK PREMIUM"
	unlockBtn.Parent = panel
	corner(unlockBtn, 8)
	unlockBtn.Activated:Connect(function()
		Net.UnlockPassPremium:FireServer()
	end)

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(16, 74)
	list.Size = UDim2.new(1, -32, 1, -86)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list

	-- One claim button cell (free or premium track) for a tier row.
	local function claimCell(parent: Frame, x: number, label: string)
		local cell = Instance.new("TextButton")
		cell.Position = UDim2.fromScale(x, 0.5)
		cell.AnchorPoint = Vector2.new(0, 0.5)
		cell.Size = UDim2.new(0.42, -8, 0.78, 0)
		cell.Font = Brand.Font.Body
		cell.TextScaled = true
		cell.AutoButtonColor = false
		cell.Parent = parent
		corner(cell, 8)
		local tag = Instance.new("TextLabel")
		tag.BackgroundTransparency = 1
		tag.Size = UDim2.new(1, -8, 0.45, 0)
		tag.Position = UDim2.fromScale(0.5, 0.02)
		tag.AnchorPoint = Vector2.new(0.5, 0)
		tag.Font = Brand.Font.Body
		tag.TextScaled = true
		tag.TextColor3 = Brand.Color.TextDim
		tag.Text = label
		tag.Parent = cell
		return cell, tag
	end

	-- Rebuild the whole track from a PassState snapshot.
	local function render(state)
		if typeof(state) ~= "table" then
			return
		end
		progressLabel.Text = string.format("Tier %d / %d   \u{00B7}   %d XP", state.tier, state.tierCount, state.xp)
		unlockBtn.Visible = not state.premium
		if state.premium then
			-- show an "active" pill instead of the unlock button
			title.Text = "OUTBREAK PASS \u{2605}"
		else
			unlockBtn.Text = "UNLOCK \u{25C6} " .. (state.premiumCost or "?")
		end

		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		local PassConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("PassConfig"))
		for tier, def in PassConfig.tiers do
			local reached = tier <= state.tier
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 56)
			row.BackgroundColor3 = if reached then Brand.Color.Panel else Brand.Color.BgDeep
			row.BackgroundTransparency = if reached then 0 else 0.4
			row.LayoutOrder = tier
			row.Parent = list
			corner(row, 10)

			local num = Instance.new("TextLabel")
			num.BackgroundTransparency = 1
			num.Position = UDim2.fromScale(0.005, 0)
			num.Size = UDim2.fromScale(0.12, 1)
			num.Font = Brand.Font.Display
			num.TextScaled = true
			num.TextColor3 = if reached then Brand.Color.SafeGreen else Brand.Color.TextDim
			num.Text = tostring(tier)
			num.Parent = row

			-- Free cell.
			local freeClaimed = state.claimedFree[tostring(tier)] == true
			local freeCell, freeTag = claimCell(row, 0.14, "FREE  " .. rewardText(def.free))
			if freeClaimed then
				freeCell.BackgroundColor3 = Brand.Color.BgDeep
				freeCell.Text = ""
				freeTag.Text = "\u{2713} " .. rewardText(def.free)
				freeTag.TextColor3 = Brand.Color.SafeGreen
			elseif reached then
				freeCell.BackgroundColor3 = Brand.Color.SafeGreen
				freeCell.Text = ""
				freeTag.Text = "CLAIM  " .. rewardText(def.free)
				freeTag.TextColor3 = Brand.Color.BgDeep
				freeCell.Activated:Connect(function()
					Net.ClaimPassReward:FireServer(tier, false)
				end)
			else
				freeCell.BackgroundColor3 = Brand.Color.BgDeep
				freeCell.Text = ""
			end

			-- Premium cell.
			local premClaimed = state.claimedPremium[tostring(tier)] == true
			local premCell, premTag = claimCell(row, 0.57, "PREMIUM  " .. rewardText(def.premium))
			if not state.premium then
				premCell.BackgroundColor3 = Brand.Color.BgDeep
				premCell.Text = ""
				premTag.Text = "\u{1F512} " .. rewardText(def.premium)
				premTag.TextColor3 = Brand.Color.TextDim
			elseif premClaimed then
				premCell.BackgroundColor3 = Brand.Color.BgDeep
				premCell.Text = ""
				premTag.Text = "\u{2713} " .. rewardText(def.premium)
				premTag.TextColor3 = Brand.Color.SafeGreen
			elseif reached then
				premCell.BackgroundColor3 = Brand.Color.HazardYellow
				premCell.Text = ""
				premTag.Text = "CLAIM  " .. rewardText(def.premium)
				premTag.TextColor3 = Brand.Color.BgDeep
				premCell.Activated:Connect(function()
					Net.ClaimPassReward:FireServer(tier, true)
				end)
			else
				premCell.BackgroundColor3 = Brand.Color.BgDeep
				premCell.Text = ""
			end
		end
	end

	local function updateVisibility()
		local inMatch = player:GetAttribute("InMatch") == true
		openBtn.Visible = not inMatch
		if inMatch then
			panel.Visible = false
		end
	end

	openBtn.Activated:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			Net.RequestPass:FireServer()
		end
	end)
	close.Activated:Connect(function()
		panel.Visible = false
	end)
	Net.PassState.OnClientEvent:Connect(render)
	player:GetAttributeChangedSignal("InMatch"):Connect(updateVisibility)

	updateVisibility()
	Net.RequestPass:FireServer()
end

return PassController
