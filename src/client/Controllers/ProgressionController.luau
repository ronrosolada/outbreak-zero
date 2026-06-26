--[[
	ProgressionController (client controller)
	-----------------------------------------
	Display only — the server owns all the numbers. Shows:
	  - a bottom-left Level + XP bar + coins readout (driven by Player Attributes
	    the server mirrors: Level / Xp / XpForNext / Coins)
	  - a "LEVEL UP!" toast when your Level attribute ticks up
	  - the daily-login reward popup (claim button -> asks the server to grant it)

	Colors/fonts come from the shared Brand module, like every other UI surface.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Brand = require(ReplicatedStorage:WaitForChild("Brand"))

local ProgressionController = {}

-- chunky rounded corner + optional neon edge glow (same look as RoundHud)
local function style(frame: GuiObject, radius: number, glow: Color3?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = frame
	if glow then
		local stroke = Instance.new("UIStroke")
		stroke.Color = glow
		stroke.Thickness = 1.5
		stroke.Transparency = 0.35
		stroke.Parent = frame
	end
end

function ProgressionController:Init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "ProgressionHud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	-- == Bottom-left Level / XP / coins panel =================================
	local panel = Instance.new("Frame")
	panel.Name = "ProgressPanel"
	panel.Size = UDim2.fromScale(0.24, 0.1)
	panel.Position = UDim2.fromScale(0.012, 0.985)
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.BackgroundColor3 = Brand.Color.Panel
	panel.BackgroundTransparency = 0.1
	panel.ZIndex = 3
	panel.Parent = gui
	style(panel, 12, Brand.Color.HumanBlue)

	local coinsLabel = Instance.new("TextLabel")
	coinsLabel.Name = "Coins"
	coinsLabel.BackgroundTransparency = 1
	coinsLabel.Size = UDim2.fromScale(0.96, 0.4)
	coinsLabel.Position = UDim2.fromScale(0.03, 0.06)
	coinsLabel.TextXAlignment = Enum.TextXAlignment.Left
	coinsLabel.Font = Brand.Font.Display
	coinsLabel.TextScaled = true
	coinsLabel.TextColor3 = Brand.Color.HazardYellow
	coinsLabel.Text = "0 coins"
	coinsLabel.ZIndex = 3
	coinsLabel.Parent = panel

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "Level"
	levelLabel.BackgroundTransparency = 1
	levelLabel.Size = UDim2.fromScale(0.28, 0.4)
	levelLabel.Position = UDim2.fromScale(0.03, 0.52)
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.Font = Brand.Font.Display
	levelLabel.TextScaled = true
	levelLabel.TextColor3 = Brand.Color.TextLight
	levelLabel.Text = "Lv 1"
	levelLabel.ZIndex = 3
	levelLabel.Parent = panel

	local xpBarBg = Instance.new("Frame")
	xpBarBg.Name = "XpBar"
	xpBarBg.Size = UDim2.fromScale(0.62, 0.3)
	xpBarBg.Position = UDim2.fromScale(0.34, 0.57)
	xpBarBg.BackgroundColor3 = Brand.Color.BgDeep
	xpBarBg.BorderSizePixel = 0
	xpBarBg.ZIndex = 3
	xpBarBg.Parent = panel
	style(xpBarBg, 8, nil)

	local xpFill = Instance.new("Frame")
	xpFill.Name = "Fill"
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.BackgroundColor3 = Brand.Color.HumanBlue
	xpFill.BorderSizePixel = 0
	xpFill.ZIndex = 3
	xpFill.Parent = xpBarBg
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = xpFill

	local xpText = Instance.new("TextLabel")
	xpText.BackgroundTransparency = 1
	xpText.Size = UDim2.fromScale(1, 1)
	xpText.Font = Brand.Font.Mono
	xpText.TextScaled = true
	xpText.TextColor3 = Brand.Color.TextLight
	xpText.Text = ""
	xpText.ZIndex = 4
	xpText.Parent = xpBarBg

	-- == Level-up toast =======================================================
	local levelUpToast = Instance.new("TextLabel")
	levelUpToast.Name = "LevelUpToast"
	levelUpToast.BackgroundTransparency = 1
	levelUpToast.Size = UDim2.fromScale(0.5, 0.1)
	levelUpToast.Position = UDim2.fromScale(0.5, 0.4)
	levelUpToast.AnchorPoint = Vector2.new(0.5, 0.5)
	levelUpToast.Font = Brand.Font.Display
	levelUpToast.TextScaled = true
	levelUpToast.TextColor3 = Brand.Color.SafeGreen
	levelUpToast.TextStrokeTransparency = 1
	levelUpToast.TextTransparency = 1
	levelUpToast.Text = ""
	levelUpToast.ZIndex = 5
	levelUpToast.Parent = gui

	-- == Daily reward popup ===================================================
	local dailyFrame = Instance.new("Frame")
	dailyFrame.Name = "DailyReward"
	dailyFrame.Size = UDim2.fromScale(0.32, 0.3)
	dailyFrame.Position = UDim2.fromScale(0.5, 0.5)
	dailyFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	dailyFrame.BackgroundColor3 = Brand.Color.Panel
	dailyFrame.BackgroundTransparency = 0.05
	dailyFrame.Visible = false
	dailyFrame.ZIndex = 6
	dailyFrame.Parent = gui
	style(dailyFrame, 16, Brand.Color.HazardYellow)

	local dailyTitle = Instance.new("TextLabel")
	dailyTitle.BackgroundTransparency = 1
	dailyTitle.Size = UDim2.fromScale(0.9, 0.2)
	dailyTitle.Position = UDim2.fromScale(0.5, 0.16)
	dailyTitle.AnchorPoint = Vector2.new(0.5, 0.5)
	dailyTitle.Font = Brand.Font.Display
	dailyTitle.TextScaled = true
	dailyTitle.TextColor3 = Brand.Color.TextLight
	dailyTitle.Text = "DAILY REWARD"
	dailyTitle.ZIndex = 6
	dailyTitle.Parent = dailyFrame

	local dailyDay = Instance.new("TextLabel")
	dailyDay.BackgroundTransparency = 1
	dailyDay.Size = UDim2.fromScale(0.9, 0.14)
	dailyDay.Position = UDim2.fromScale(0.5, 0.36)
	dailyDay.AnchorPoint = Vector2.new(0.5, 0.5)
	dailyDay.Font = Brand.Font.Body
	dailyDay.TextScaled = true
	dailyDay.TextColor3 = Brand.Color.TextDim
	dailyDay.Text = "Day 1"
	dailyDay.ZIndex = 6
	dailyDay.Parent = dailyFrame

	local dailyAmount = Instance.new("TextLabel")
	dailyAmount.BackgroundTransparency = 1
	dailyAmount.Size = UDim2.fromScale(0.9, 0.2)
	dailyAmount.Position = UDim2.fromScale(0.5, 0.54)
	dailyAmount.AnchorPoint = Vector2.new(0.5, 0.5)
	dailyAmount.Font = Brand.Font.Display
	dailyAmount.TextScaled = true
	dailyAmount.TextColor3 = Brand.Color.HazardYellow
	dailyAmount.Text = "+50 coins"
	dailyAmount.ZIndex = 6
	dailyAmount.Parent = dailyFrame

	local claimButton = Instance.new("TextButton")
	claimButton.Name = "Claim"
	claimButton.Size = UDim2.fromScale(0.6, 0.2)
	claimButton.Position = UDim2.fromScale(0.5, 0.82)
	claimButton.AnchorPoint = Vector2.new(0.5, 0.5)
	claimButton.BackgroundColor3 = Brand.Color.SafeGreen
	claimButton.Font = Brand.Font.Display
	claimButton.TextScaled = true
	claimButton.TextColor3 = Brand.Color.BgDeep
	claimButton.Text = "CLAIM"
	claimButton.AutoButtonColor = true
	claimButton.ZIndex = 6
	claimButton.Parent = dailyFrame
	style(claimButton, 10, nil)

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.Size = UDim2.fromScale(0.12, 0.12)
	closeButton.Position = UDim2.fromScale(0.97, 0.03)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.BackgroundTransparency = 1
	closeButton.Font = Brand.Font.Display
	closeButton.TextScaled = true
	closeButton.TextColor3 = Brand.Color.TextDim
	closeButton.Text = "\u{2715}"
	closeButton.ZIndex = 7
	closeButton.Parent = dailyFrame

	-- == Rendering ============================================================
	local function renderProgress()
		local level = player:GetAttribute("Level") or 1
		local xp = player:GetAttribute("Xp") or 0
		local forNext = player:GetAttribute("XpForNext") or 0
		local coins = player:GetAttribute("Coins") or 0

		coinsLabel.Text = string.format("%d coins", coins)
		levelLabel.Text = "Lv " .. tostring(level)
		if forNext and forNext > 0 then
			local ratio = math.clamp(xp / forNext, 0, 1)
			xpFill.Size = UDim2.fromScale(ratio, 1)
			xpText.Text = string.format("%d / %d", xp, forNext)
		else
			xpFill.Size = UDim2.fromScale(1, 1)
			xpText.Text = "MAX"
		end
	end

	local function showLevelUp(level: number)
		levelUpToast.Text = "LEVEL UP!  Lv " .. tostring(level)
		levelUpToast.TextTransparency = 0
		levelUpToast.TextStrokeTransparency = 0.4
		TweenService
			:Create(levelUpToast, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.6), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			})
			:Play()
	end

	-- Attribute-driven updates (no polling).
	local lastLevel = player:GetAttribute("Level") or 1
	player:GetAttributeChangedSignal("Level"):Connect(function()
		local level = player:GetAttribute("Level") or 1
		if level > lastLevel then
			showLevelUp(level)
		end
		lastLevel = level
		renderProgress()
	end)
	player:GetAttributeChangedSignal("Xp"):Connect(renderProgress)
	player:GetAttributeChangedSignal("XpForNext"):Connect(renderProgress)
	player:GetAttributeChangedSignal("Coins"):Connect(renderProgress)

	-- == Daily reward flow ====================================================
	local function hideDaily()
		TweenService:Create(dailyFrame, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		task.delay(0.25, function()
			dailyFrame.Visible = false
		end)
	end

	Net.DailyRewardState.OnClientEvent:Connect(function(canClaim, day, amount, _secondsLeft)
		if canClaim then
			dailyDay.Text = "Day " .. tostring(day)
			dailyAmount.Text = string.format("+%d coins", amount)
			claimButton.Text = "CLAIM"
			claimButton.Active = true
			claimButton.AutoButtonColor = true
			dailyFrame.BackgroundTransparency = 0.05
			dailyFrame.Visible = true
		else
			hideDaily()
		end
	end)

	claimButton.MouseButton1Click:Connect(function()
		if not claimButton.Active then
			return
		end
		claimButton.Active = false
		claimButton.AutoButtonColor = false
		claimButton.Text = "..."
		Net.ClaimDailyReward:FireServer()
	end)

	closeButton.MouseButton1Click:Connect(hideDaily)

	renderProgress()
	Net.RequestDailyState:FireServer() -- pull my daily state now that handlers are live
end

return ProgressionController
