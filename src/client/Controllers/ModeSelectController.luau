--[[
	ModeSelectController (client controller) — Increment 3
	------------------------------------------------------
	The design's "Mode Select / Queue" screen (02_UI_SCREENS): a raised hub PLAY button
	that opens a panel of game modes — OUTBREAK (the core mode, playable) plus Data Heist /
	Escort / Mutation Event as "Coming Soon" — with the live queue count and a QUEUE / LEAVE
	button. The button mirrors the in-world queue pad via Net.ToggleQueue, so mobile players
	get a thumb-friendly way to queue. Only shown in the hub (hidden during a match).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Brand = require(ReplicatedStorage:WaitForChild("Brand"))

local ModeSelectController = {}

local MODES = {
	{
		name = "OUTBREAK",
		desc = "Power the generators, then extract before you're all infected.",
		color = Brand.Color.HumanBlue,
		live = true,
	},
	{
		name = "DATA HEIST",
		desc = "Grab the data and run. Coming soon.",
		color = Brand.Color.HazardYellow,
		live = false,
	},
	{ name = "ESCORT", desc = "Move the payload together. Coming soon.", color = Brand.Color.SafeGreen, live = false },
	{
		name = "MUTATION EVENT",
		desc = "Weekly rotating modifier. Coming soon.",
		color = Brand.Color.InfectedPink,
		live = false,
	},
}

local function corner(inst: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
end

function ModeSelectController:Init()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "ModeSelect"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	-- The raised PLAY button (bottom-center).
	local playBtn = Instance.new("TextButton")
	playBtn.Name = "Play"
	playBtn.AnchorPoint = Vector2.new(0.5, 1)
	playBtn.Position = UDim2.fromScale(0.5, 0.97)
	playBtn.Size = UDim2.fromOffset(190, 56)
	playBtn.BackgroundColor3 = Brand.Color.SafeGreen
	playBtn.AutoButtonColor = true
	playBtn.Font = Brand.Font.Display
	playBtn.TextScaled = true
	playBtn.TextColor3 = Brand.Color.BgDeep
	playBtn.Text = "\u{25B6} PLAY"
	playBtn.Parent = gui
	corner(playBtn, 14)
	local playStroke = Instance.new("UIStroke")
	playStroke.Color = Brand.Color.TextLight
	playStroke.Thickness = 2
	playStroke.Transparency = 0.4
	playStroke.Parent = playBtn

	-- Modal panel (hidden until PLAY).
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(420, 460)
	panel.BackgroundColor3 = Brand.Color.BgDeep
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 18)
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Brand.Color.HumanBlue
	panelStroke.Thickness = 2
	panelStroke.Transparency = 0.3
	panelStroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 12)
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Font = Brand.Font.Display
	title.TextScaled = true
	title.TextColor3 = Brand.Color.TextLight
	title.Text = "SELECT MODE"
	title.Parent = panel

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

	-- Mode cards.
	local cards = Instance.new("Frame")
	cards.BackgroundTransparency = 1
	cards.Position = UDim2.fromOffset(16, 60)
	cards.Size = UDim2.new(1, -32, 0, 300)
	cards.Parent = panel
	local cardLayout = Instance.new("UIListLayout")
	cardLayout.FillDirection = Enum.FillDirection.Vertical
	cardLayout.Padding = UDim.new(0, 8)
	cardLayout.Parent = cards

	for i, mode in MODES do
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 66)
		card.BackgroundColor3 = Brand.Color.Panel
		card.BackgroundTransparency = if mode.live then 0 else 0.5
		card.LayoutOrder = i
		card.Parent = cards
		corner(card, 12)
		local cardStroke = Instance.new("UIStroke")
		cardStroke.Color = mode.color
		cardStroke.Thickness = 2
		cardStroke.Transparency = if mode.live then 0.1 else 0.7
		cardStroke.Parent = card

		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Position = UDim2.fromOffset(14, 8)
		name.Size = UDim2.new(1, -28, 0, 26)
		name.Font = Brand.Font.Display
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextScaled = true
		name.TextColor3 = if mode.live then mode.color else Brand.Color.TextDim
		name.Text = mode.name .. (if mode.live then "" else "   \u{1F512}")
		name.Parent = card

		local desc = Instance.new("TextLabel")
		desc.BackgroundTransparency = 1
		desc.Position = UDim2.fromOffset(14, 36)
		desc.Size = UDim2.new(1, -28, 0, 22)
		desc.Font = Brand.Font.Body
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextScaled = true
		desc.TextColor3 = Brand.Color.TextDim
		desc.Text = mode.desc
		desc.Parent = card
	end

	-- Status + QUEUE/LEAVE button.
	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.AnchorPoint = Vector2.new(0.5, 1)
	status.Position = UDim2.new(0.5, 0, 1, -70)
	status.Size = UDim2.new(1, -32, 0, 24)
	status.Font = Brand.Font.Body
	status.TextScaled = true
	status.TextColor3 = Brand.Color.TextDim
	status.Text = ""
	status.Parent = panel

	local queueBtn = Instance.new("TextButton")
	queueBtn.AnchorPoint = Vector2.new(0.5, 1)
	queueBtn.Position = UDim2.new(0.5, 0, 1, -16)
	queueBtn.Size = UDim2.new(1, -40, 0, 48)
	queueBtn.BackgroundColor3 = Brand.Color.SafeGreen
	queueBtn.Font = Brand.Font.Display
	queueBtn.TextScaled = true
	queueBtn.TextColor3 = Brand.Color.BgDeep
	queueBtn.Text = "QUEUE FOR OUTBREAK"
	queueBtn.Parent = panel
	corner(queueBtn, 12)

	-- == State + rendering ====================================================
	local hub = { count = 0, max = 12, matchRunning = false, countdown = nil :: number? }

	local function updateButton()
		local queued = player:GetAttribute("Queued") == true
		if hub.matchRunning then
			queueBtn.Text = "MATCH IN PROGRESS"
			queueBtn.BackgroundColor3 = Brand.Color.Panel
			status.Text = "A match is running — next one starts soon."
		elseif hub.countdown then
			queueBtn.Text = ("STARTING IN %d\u{2026}"):format(hub.countdown)
			queueBtn.BackgroundColor3 = Brand.Color.HazardYellow
			status.Text = ("%d / %d queued"):format(hub.count, hub.max)
		elseif queued then
			queueBtn.Text = "LEAVE QUEUE"
			queueBtn.BackgroundColor3 = Brand.Color.InfectedPink
			status.Text = ("\u{2713} In queue   %d / %d"):format(hub.count, hub.max)
		else
			queueBtn.Text = "QUEUE FOR OUTBREAK"
			queueBtn.BackgroundColor3 = Brand.Color.SafeGreen
			status.Text = ("%d / %d queued   \u{00B7}   finding match ~14s"):format(hub.count, hub.max)
		end
		-- The PLAY button reflects queue state too, at a glance.
		playBtn.Text = if queued then "\u{2713} QUEUED" else "\u{25B6} PLAY"
	end

	-- Hide the whole UI during a match (hub-only screen).
	local function updateVisibility()
		local inMatch = player:GetAttribute("InMatch") == true
		playBtn.Visible = not inMatch
		if inMatch then
			panel.Visible = false
		end
	end

	playBtn.Activated:Connect(function()
		panel.Visible = not panel.Visible
		updateButton()
	end)
	close.Activated:Connect(function()
		panel.Visible = false
	end)
	queueBtn.Activated:Connect(function()
		if not hub.matchRunning then
			Net.ToggleQueue:FireServer()
		end
	end)

	Net.HubStateChanged.OnClientEvent:Connect(function(count, max, matchRunning, countdownLeft)
		hub.count = count or 0
		hub.max = max or 12
		hub.matchRunning = matchRunning == true
		hub.countdown = countdownLeft
		updateButton()
	end)
	player:GetAttributeChangedSignal("Queued"):Connect(updateButton)
	player:GetAttributeChangedSignal("InMatch"):Connect(updateVisibility)

	updateVisibility()
	updateButton()
end

return ModeSelectController
