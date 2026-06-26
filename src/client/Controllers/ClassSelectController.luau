--[[
	ClassSelectController (client controller)
	-----------------------------------------
	The Prep-phase class picker (design mockup 02). A faction toggle (Human / Infected)
	with a card per class — name, blurb, signature ability, and HP/SPD/PWR bars.
	Tapping a card sends SelectClass to the server, which stores it in that faction's
	slot; whichever role you're dealt that round uses your pick for that side.

	Shown while the match is in Prep, hidden otherwise. Brand-styled.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Brand = require(ReplicatedStorage:WaitForChild("Brand"))
local Config = ReplicatedStorage:WaitForChild("Config")
local ClassConfig = require(Config:WaitForChild("ClassConfig"))
local RoundState = require(ReplicatedStorage:WaitForChild("Round"):WaitForChild("RoundState"))

local ClassSelectController = {}

local STAT_COLORS = { hp = Brand.Color.SafeGreen, spd = Brand.Color.HumanBlue, pwr = Brand.Color.HazardYellow }
local STAT_ORDER = { "hp", "spd", "pwr" }
local STAT_LABEL = { hp = "HP", spd = "SPD", pwr = "PWR" }

local function corner(inst: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

function ClassSelectController:Init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "ClassSelect"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Enabled = true
	gui.Parent = playerGui

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Brand.Color.BgDeep
	backdrop.BackgroundTransparency = 0.35
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false -- opened via the CLASS button; auto-opens during Prep
	backdrop.Parent = gui

	-- Always-available "open the class picker" button (sits in a hub HUD corner).
	local openButton = Instance.new("TextButton")
	openButton.Name = "OpenClass"
	openButton.Size = UDim2.fromScale(0.16, 0.06)
	openButton.Position = UDim2.fromScale(0.02, 0.8)
	openButton.AnchorPoint = Vector2.new(0, 0.5)
	openButton.Font = Brand.Font.Display
	openButton.TextScaled = true
	openButton.Text = "\u{2605} CLASS"
	openButton.TextColor3 = Brand.Color.TextLight
	openButton.BackgroundColor3 = Brand.Color.HumanBlue
	openButton.Parent = gui
	corner(openButton, 10)

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(0.62, 0.74)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Brand.Color.Panel
	panel.BorderSizePixel = 0
	panel.Parent = backdrop
	corner(panel, 16)
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Brand.Color.HumanBlue
	panelStroke.Thickness = 1.5
	panelStroke.Transparency = 0.4
	panelStroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(0.9, 0.1)
	title.Position = UDim2.fromScale(0.05, 0.03)
	title.Font = Brand.Font.Display
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Brand.Color.TextLight
	title.Text = "CHOOSE YOUR CLASS"
	title.Parent = panel

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.fromScale(0.09, 0.07)
	closeButton.Position = UDim2.fromScale(0.985, 0.02)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Font = Brand.Font.Display
	closeButton.TextScaled = true
	closeButton.Text = "\u{2715}"
	closeButton.TextColor3 = Brand.Color.TextLight
	closeButton.BackgroundColor3 = Brand.Color.InfectedPink
	closeButton.Parent = panel
	corner(closeButton, 8)

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.Size = UDim2.fromScale(0.9, 0.05)
	hint.Position = UDim2.fromScale(0.05, 0.92)
	hint.Font = Brand.Font.Body
	hint.TextScaled = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = Brand.Color.TextDim
	hint.Text = "Pick a class for each faction — your role is revealed when the round starts."
	hint.Parent = panel

	-- Faction tabs
	local currentFaction = "Human"

	local humanTab = Instance.new("TextButton")
	humanTab.Size = UDim2.fromScale(0.44, 0.08)
	humanTab.Position = UDim2.fromScale(0.05, 0.15)
	humanTab.Font = Brand.Font.Display
	humanTab.TextScaled = true
	humanTab.Text = "HUMAN"
	humanTab.TextColor3 = Brand.Color.TextLight
	humanTab.BackgroundColor3 = Brand.Color.HumanBlue
	humanTab.AutoButtonColor = true
	humanTab.Parent = panel
	corner(humanTab, 10)

	local infectedTab = Instance.new("TextButton")
	infectedTab.Size = UDim2.fromScale(0.44, 0.08)
	infectedTab.Position = UDim2.fromScale(0.51, 0.15)
	infectedTab.Font = Brand.Font.Display
	infectedTab.TextScaled = true
	infectedTab.Text = "INFECTED"
	infectedTab.TextColor3 = Brand.Color.TextLight
	infectedTab.BackgroundColor3 = Brand.Color.InfectedPink
	infectedTab.AutoButtonColor = true
	infectedTab.Parent = panel
	corner(infectedTab, 10)

	-- Card list
	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Size = UDim2.fromScale(0.9, 0.62)
	list.Position = UDim2.fromScale(0.05, 0.26)
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local cards: { [string]: { card: TextButton, stroke: UIStroke } } = {}

	local function highlight()
		local chosen = player:GetAttribute(currentFaction == "Human" and "HumanClass" or "InfectedClass")
		local accent = currentFaction == "Human" and Brand.Color.HumanBlue or Brand.Color.InfectedPink
		for classId, entry in cards do
			local selected = classId == chosen
			entry.stroke.Color = accent
			entry.stroke.Transparency = selected and 0 or 0.7
			entry.stroke.Thickness = selected and 3 or 1
		end
	end

	local function makeStatBar(parent: Instance, key: string, value: number, y: number)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(0.12, 0.16)
		label.Position = UDim2.fromScale(0.02, y)
		label.Font = Brand.Font.Mono
		label.TextScaled = true
		label.TextColor3 = Brand.Color.TextDim
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = STAT_LABEL[key]
		label.Parent = parent

		local track = Instance.new("Frame")
		track.Size = UDim2.fromScale(0.82, 0.1)
		track.Position = UDim2.fromScale(0.16, y + 0.03)
		track.BackgroundColor3 = Brand.Color.BgDeep
		track.BorderSizePixel = 0
		track.Parent = parent
		corner(track, 6)

		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(math.clamp(value, 0, 1), 1)
		fill.BackgroundColor3 = STAT_COLORS[key]
		fill.BorderSizePixel = 0
		fill.Parent = track
		corner(fill, 6)
	end

	local function buildCards(faction: string)
		for _, child in list:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		table.clear(cards)

		local order = faction == "Human" and ClassConfig.humanOrder or ClassConfig.infectedOrder
		for index, classId in order do
			local def = ClassConfig.classes[classId]
			local card = Instance.new("TextButton")
			card.Size = UDim2.fromScale(1, 0.46)
			card.AutoButtonColor = false
			card.BackgroundColor3 = Brand.Color.BgDeep
			card.Text = ""
			card.LayoutOrder = index
			card.Parent = list
			corner(card, 12)
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 1
			stroke.Transparency = 0.7
			stroke.Parent = card

			local name = Instance.new("TextLabel")
			name.BackgroundTransparency = 1
			name.Size = UDim2.fromScale(0.6, 0.22)
			name.Position = UDim2.fromScale(0.03, 0.06)
			name.Font = Brand.Font.Display
			name.TextScaled = true
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextColor3 = Brand.Color.TextLight
			name.Text = def.display
			name.Parent = card

			local ability = Instance.new("TextLabel")
			ability.BackgroundTransparency = 1
			ability.Size = UDim2.fromScale(0.6, 0.16)
			ability.Position = UDim2.fromScale(0.03, 0.3)
			ability.Font = Brand.Font.Mono
			ability.TextScaled = true
			ability.TextXAlignment = Enum.TextXAlignment.Left
			ability.TextColor3 = Brand.Color.HazardYellow
			ability.Text = "\u{2605} " .. def.ability.name
			ability.Parent = card

			local blurb = Instance.new("TextLabel")
			blurb.BackgroundTransparency = 1
			blurb.Size = UDim2.fromScale(0.94, 0.2)
			blurb.Position = UDim2.fromScale(0.03, 0.5)
			blurb.Font = Brand.Font.Body
			blurb.TextScaled = true
			blurb.TextWrapped = true
			blurb.TextXAlignment = Enum.TextXAlignment.Left
			blurb.TextColor3 = Brand.Color.TextDim
			blurb.Text = def.blurb
			blurb.Parent = card

			-- stat bars on the right
			local stats = Instance.new("Frame")
			stats.BackgroundTransparency = 1
			stats.Size = UDim2.fromScale(0.34, 0.86)
			stats.Position = UDim2.fromScale(0.64, 0.08)
			stats.Parent = card
			for i, key in STAT_ORDER do
				makeStatBar(stats, key, def.stats[key], (i - 1) * 0.34)
			end

			card.Activated:Connect(function()
				Net.SelectClass:FireServer(classId)
				highlight()
			end)

			cards[classId] = { card = card, stroke = stroke }
		end
		highlight()
	end

	local function setFaction(faction: string)
		currentFaction = faction
		panelStroke.Color = faction == "Human" and Brand.Color.HumanBlue or Brand.Color.InfectedPink
		humanTab.BackgroundTransparency = faction == "Human" and 0 or 0.55
		infectedTab.BackgroundTransparency = faction == "Infected" and 0 or 0.55
		buildCards(faction)
	end

	humanTab.Activated:Connect(function()
		setFaction("Human")
	end)
	infectedTab.Activated:Connect(function()
		setFaction("Infected")
	end)

	-- Reflect server-side selection changes (e.g. another device, or confirmation).
	player:GetAttributeChangedSignal("HumanClass"):Connect(highlight)
	player:GetAttributeChangedSignal("InfectedClass"):Connect(highlight)

	-- Open/close the picker. Set your loadout anytime in the hub via the CLASS
	-- button; it auto-opens during Prep, and locks away once Action begins.
	local function setOpen(open: boolean)
		backdrop.Visible = open
		openButton.Visible = not open
	end
	openButton.Activated:Connect(function()
		setOpen(true)
	end)
	closeButton.Activated:Connect(function()
		setOpen(false)
	end)

	local currentPhase = RoundState.Hub
	local function applyAvailability()
		local inMatch = player:GetAttribute("InMatch") == true
		if inMatch and currentPhase == RoundState.Prep then
			setOpen(true) -- nudge the roster to lock in their class before the round
		elseif inMatch then
			-- Any other in-match phase (Action/Results): no fiddling with your loadout.
			backdrop.Visible = false
			openButton.Visible = false
		elseif not backdrop.Visible then
			-- Back in the hub: the CLASS button is available, picker closed until opened.
			openButton.Visible = true
		end
	end

	Net.RoundStateChanged.OnClientEvent:Connect(function(phase)
		currentPhase = phase
		applyAvailability()
	end)
	player:GetAttributeChangedSignal("InMatch"):Connect(applyAvailability)

	setFaction("Human")
	applyAvailability()
end

return ClassSelectController
