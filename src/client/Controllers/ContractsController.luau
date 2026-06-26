--[[
	ContractsController (client controller) — Increment 4a
	------------------------------------------------------
	The hub "daily contracts" widget (design social-hub screen): a CONTRACTS button that
	opens a panel of the day's goals with progress bars + CLAIM buttons. Reads
	Net.ContractsState (pushed on progress/claim and on request) and claims via
	Net.ClaimContract. Rows are built from the shared ContractsConfig; the server is
	authoritative for progress + reward. Hub-only (hidden during a match).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Brand = require(ReplicatedStorage:WaitForChild("Brand"))
local ContractsConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("ContractsConfig"))

local ContractsController = {}

local function corner(inst: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
end

function ContractsController:Init()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "Contracts"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Open button (top-left, hub only).
	local openBtn = Instance.new("TextButton")
	openBtn.Name = "Open"
	openBtn.Position = UDim2.fromOffset(16, 16)
	openBtn.Size = UDim2.fromOffset(150, 40)
	openBtn.BackgroundColor3 = Brand.Color.Panel
	openBtn.Font = Brand.Font.Display
	openBtn.TextScaled = true
	openBtn.TextColor3 = Brand.Color.HazardYellow
	openBtn.Text = "\u{1F4CB} CONTRACTS"
	openBtn.Parent = gui
	corner(openBtn, 10)
	local openStroke = Instance.new("UIStroke")
	openStroke.Color = Brand.Color.HazardYellow
	openStroke.Thickness = 1.5
	openStroke.Transparency = 0.4
	openStroke.Parent = openBtn

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(440, 360)
	panel.BackgroundColor3 = Brand.Color.BgDeep
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 18)
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Brand.Color.HazardYellow
	panelStroke.Thickness = 2
	panelStroke.Transparency = 0.3
	panelStroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 12)
	title.Size = UDim2.new(1, 0, 0, 36)
	title.Font = Brand.Font.Display
	title.TextScaled = true
	title.TextColor3 = Brand.Color.TextLight
	title.Text = "DAILY CONTRACTS"
	title.Parent = panel

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromOffset(0, 46)
	subtitle.Size = UDim2.new(1, 0, 0, 18)
	subtitle.Font = Brand.Font.Body
	subtitle.TextScaled = true
	subtitle.TextColor3 = Brand.Color.TextDim
	subtitle.Text = "Resets daily \u{00B7} earn credits"
	subtitle.Parent = panel

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

	local listFrame = Instance.new("Frame")
	listFrame.BackgroundTransparency = 1
	listFrame.Position = UDim2.fromOffset(16, 74)
	listFrame.Size = UDim2.new(1, -32, 1, -86)
	listFrame.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 10)
	layout.Parent = listFrame

	-- Build a row per configured contract; updated from ContractsState by id.
	local rows: { [string]: any } = {}
	for i, def in ContractsConfig.daily do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 78)
		row.BackgroundColor3 = Brand.Color.Panel
		row.LayoutOrder = i
		row.Parent = listFrame
		corner(row, 12)

		local desc = Instance.new("TextLabel")
		desc.BackgroundTransparency = 1
		desc.Position = UDim2.fromOffset(12, 8)
		desc.Size = UDim2.new(1, -24, 0, 22)
		desc.Font = Brand.Font.Display
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextScaled = true
		desc.TextColor3 = Brand.Color.TextLight
		desc.Text = def.desc
		desc.Parent = row

		local barBg = Instance.new("Frame")
		barBg.Position = UDim2.fromOffset(12, 38)
		barBg.Size = UDim2.new(1, -150, 0, 16)
		barBg.BackgroundColor3 = Brand.Color.BgDeep
		barBg.BorderSizePixel = 0
		barBg.Parent = row
		corner(barBg, 8)
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = Brand.Color.HazardYellow
		fill.BorderSizePixel = 0
		fill.Parent = barBg
		corner(fill, 8)

		local progText = Instance.new("TextLabel")
		progText.BackgroundTransparency = 1
		progText.Position = UDim2.fromOffset(12, 56)
		progText.Size = UDim2.new(1, -150, 0, 16)
		progText.Font = Brand.Font.Body
		progText.TextXAlignment = Enum.TextXAlignment.Left
		progText.TextScaled = true
		progText.TextColor3 = Brand.Color.TextDim
		progText.Text = "0 / " .. def.target
		progText.Parent = row

		local claimBtn = Instance.new("TextButton")
		claimBtn.AnchorPoint = Vector2.new(1, 0.5)
		claimBtn.Position = UDim2.new(1, -12, 0.5, 0)
		claimBtn.Size = UDim2.fromOffset(116, 48)
		claimBtn.BackgroundColor3 = Brand.Color.Panel
		claimBtn.Font = Brand.Font.Display
		claimBtn.TextScaled = true
		claimBtn.TextColor3 = Brand.Color.TextDim
		claimBtn.Text = "\u{25C8} " .. def.reward
		claimBtn.Parent = row
		corner(claimBtn, 10)

		local id = def.id
		claimBtn.Activated:Connect(function()
			Net.ClaimContract:FireServer(id)
		end)

		rows[def.id] = { fill = fill, progText = progText, claimBtn = claimBtn, reward = def.reward }
	end

	local function render(state)
		if typeof(state) ~= "table" then
			return
		end
		for _, entry in state do
			local row = rows[entry.id]
			if row then
				local pct = math.clamp(entry.progress / math.max(1, entry.target), 0, 1)
				row.fill.Size = UDim2.fromScale(pct, 1)
				row.progText.Text = string.format("%d / %d", entry.progress, entry.target)
				if entry.claimed then
					row.claimBtn.Text = "\u{2713} CLAIMED"
					row.claimBtn.BackgroundColor3 = Brand.Color.Panel
					row.claimBtn.TextColor3 = Brand.Color.TextDim
					row.fill.BackgroundColor3 = Brand.Color.SafeGreen
				elseif entry.progress >= entry.target then
					row.claimBtn.Text = "CLAIM \u{25C8} " .. row.reward
					row.claimBtn.BackgroundColor3 = Brand.Color.SafeGreen
					row.claimBtn.TextColor3 = Brand.Color.BgDeep
					row.fill.BackgroundColor3 = Brand.Color.SafeGreen
				else
					row.claimBtn.Text = "\u{25C8} " .. row.reward
					row.claimBtn.BackgroundColor3 = Brand.Color.Panel
					row.claimBtn.TextColor3 = Brand.Color.TextDim
					row.fill.BackgroundColor3 = Brand.Color.HazardYellow
				end
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
			Net.RequestContracts:FireServer() -- refresh on open (profile is loaded by now)
		end
	end)
	close.Activated:Connect(function()
		panel.Visible = false
	end)
	Net.ContractsState.OnClientEvent:Connect(render)
	player:GetAttributeChangedSignal("InMatch"):Connect(updateVisibility)

	updateVisibility()
	Net.RequestContracts:FireServer()
end

return ContractsController
