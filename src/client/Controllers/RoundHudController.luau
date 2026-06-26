--[[
	RoundHudController (client controller)
	--------------------------------------
	Outbreak Zero HUD. Shows the right view for where you are:
	  - HUB: queue panel + your queued status
	  - MATCH: phase/countdown/counts, role banner, INFECTION METER (green->pink %),
	    DOWNED overlay
	plus the queue-pop spectacle flash. Display only — the server decides everything.
	All colors/fonts come from the shared Brand module (the Claude Design handoff).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Brand = require(ReplicatedStorage:WaitForChild("Brand"))
local RoundState = require(ReplicatedStorage:WaitForChild("Round"):WaitForChild("RoundState"))

local RoundHudController = {}

local SURVIVOR = "Survivor"
local INFECTED = "Infected"

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- chunky rounded corner + a neon edge glow, the Brand component look
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

function RoundHudController:Init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "RoundHud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	-- Outbreak spectacle flash (behind everything), infected pink.
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Brand.Color.InfectedPink
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 0
	flash.Parent = gui

	-- Downed overlay (pink vignette + message).
	local downedOverlay = Instance.new("Frame")
	downedOverlay.Name = "DownedOverlay"
	downedOverlay.Size = UDim2.fromScale(1, 1)
	downedOverlay.BackgroundColor3 = Brand.Color.InfectedPink
	downedOverlay.BackgroundTransparency = 0.55
	downedOverlay.BorderSizePixel = 0
	downedOverlay.ZIndex = 1
	downedOverlay.Visible = false
	downedOverlay.Parent = gui

	local downedLabel = Instance.new("TextLabel")
	downedLabel.BackgroundTransparency = 1
	downedLabel.Size = UDim2.fromScale(0.8, 0.12)
	downedLabel.Position = UDim2.fromScale(0.5, 0.5)
	downedLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	downedLabel.Font = Brand.Font.Display
	downedLabel.TextScaled = true
	downedLabel.TextColor3 = Brand.Color.TextLight
	downedLabel.Text = "DOWNED — hold on for rescue!"
	downedLabel.ZIndex = 2
	downedLabel.Parent = downedOverlay

	-- Top status panel.
	local statusFrame = Instance.new("Frame")
	statusFrame.Size = UDim2.fromScale(0.44, 0.13)
	statusFrame.Position = UDim2.fromScale(0.5, 0.02)
	statusFrame.AnchorPoint = Vector2.new(0.5, 0)
	statusFrame.BackgroundColor3 = Brand.Color.Panel
	statusFrame.BackgroundTransparency = 0.1
	statusFrame.ZIndex = 3
	statusFrame.Parent = gui
	style(statusFrame, 14, Brand.Color.HumanBlue)

	local phaseLabel = Instance.new("TextLabel")
	phaseLabel.Name = "Phase"
	phaseLabel.BackgroundTransparency = 1
	phaseLabel.Size = UDim2.fromScale(0.96, 0.5)
	phaseLabel.Position = UDim2.fromScale(0.02, 0.06)
	phaseLabel.Font = Brand.Font.Display
	phaseLabel.TextScaled = true
	phaseLabel.TextColor3 = Brand.Color.TextLight
	phaseLabel.Text = "Connecting..."
	phaseLabel.ZIndex = 3
	phaseLabel.Parent = statusFrame

	local countsLabel = Instance.new("TextLabel")
	countsLabel.Name = "Counts"
	countsLabel.BackgroundTransparency = 1
	countsLabel.Size = UDim2.fromScale(0.96, 0.36)
	countsLabel.Position = UDim2.fromScale(0.02, 0.6)
	countsLabel.Font = Brand.Font.Body
	countsLabel.TextScaled = true
	countsLabel.TextColor3 = Brand.Color.TextDim
	countsLabel.Text = ""
	countsLabel.ZIndex = 3
	countsLabel.Parent = statusFrame

	-- Infection meter (survivors only).
	local infectionFrame = Instance.new("Frame")
	infectionFrame.Name = "InfectionMeter"
	infectionFrame.Size = UDim2.fromScale(0.3, 0.04)
	infectionFrame.Position = UDim2.fromScale(0.5, 0.8)
	infectionFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	infectionFrame.BackgroundColor3 = Brand.Color.BgDeep
	infectionFrame.BackgroundTransparency = 0.1
	infectionFrame.BorderSizePixel = 0
	infectionFrame.Visible = false
	infectionFrame.ZIndex = 3
	infectionFrame.Parent = gui
	style(infectionFrame, 10, Brand.Color.InfectedPink)

	local infectionFill = Instance.new("Frame")
	infectionFill.Name = "Fill"
	infectionFill.Size = UDim2.fromScale(0, 1)
	infectionFill.BackgroundColor3 = Brand.Color.SafeGreen
	infectionFill.BorderSizePixel = 0
	infectionFill.ZIndex = 3
	infectionFill.Parent = infectionFrame
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = infectionFill

	-- Animated "barber-pole" diagonal stripes over the fill (the signature meter look).
	infectionFill.ClipsDescendants = true
	local stripe = Instance.new("Frame")
	stripe.Name = "Stripe"
	stripe.Size = UDim2.fromScale(1, 1)
	stripe.BackgroundColor3 = Color3.new(1, 1, 1)
	stripe.BorderSizePixel = 0
	stripe.ZIndex = 3
	stripe.Parent = infectionFill
	local stripeGrad = Instance.new("UIGradient")
	stripeGrad.Rotation = 45
	stripeGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.49, 0.55),
		NumberSequenceKeypoint.new(0.5, 0.95),
		NumberSequenceKeypoint.new(1, 0.95),
	})
	stripeGrad.Parent = stripe
	RunService.Heartbeat:Connect(function(dt)
		if infectionFrame.Visible then
			stripeGrad.Offset = Vector2.new((stripeGrad.Offset.X + dt * 0.8) % 1, 0)
		end
	end)

	local infectionText = Instance.new("TextLabel")
	infectionText.BackgroundTransparency = 1
	infectionText.Size = UDim2.fromScale(1, 1)
	infectionText.Font = Brand.Font.Display
	infectionText.TextScaled = true
	infectionText.TextColor3 = Brand.Color.TextLight
	infectionText.Text = "INFECTION"
	infectionText.ZIndex = 4
	infectionText.Parent = infectionFrame

	-- Hint line under the meter (design HUD): how to purge.
	local infectionHint = Instance.new("TextLabel")
	infectionHint.Name = "Hint"
	infectionHint.BackgroundTransparency = 1
	infectionHint.AnchorPoint = Vector2.new(0.5, 0)
	infectionHint.Position = UDim2.fromScale(0.5, 1.25)
	infectionHint.Size = UDim2.fromScale(1.7, 0.7)
	infectionHint.Font = Brand.Font.Body
	infectionHint.TextScaled = true
	infectionHint.TextColor3 = Brand.Color.TextDim
	infectionHint.Text = "Power a generator's CLEANSE or find a Medic to purge"
	infectionHint.ZIndex = 3
	infectionHint.Parent = infectionFrame

	local banner = Instance.new("TextLabel")
	banner.Name = "RoleBanner"
	banner.BackgroundTransparency = 1
	banner.Size = UDim2.fromScale(0.7, 0.13)
	banner.Position = UDim2.fromScale(0.5, 0.32)
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Font = Brand.Font.Display
	banner.TextScaled = true
	banner.TextStrokeTransparency = 1
	banner.TextTransparency = 1
	banner.Text = ""
	banner.ZIndex = 3
	banner.Parent = gui

	local toast = Instance.new("TextLabel")
	toast.Name = "Toast"
	toast.BackgroundColor3 = Brand.Color.Panel
	toast.BackgroundTransparency = 1
	toast.Size = UDim2.fromScale(0.5, 0.06)
	toast.Position = UDim2.fromScale(0.5, 0.88)
	toast.AnchorPoint = Vector2.new(0.5, 0.5)
	toast.Font = Brand.Font.Body
	toast.TextScaled = true
	toast.TextColor3 = Brand.Color.TextLight
	toast.TextTransparency = 1
	toast.Text = ""
	toast.ZIndex = 3
	toast.Parent = gui
	style(toast, 8, nil)

	-- Phase 5 objective HUD: a row of generator pips that becomes a green EXTRACTION
	-- bar once armed. Driven by Attributes on Workspace.GameMap (set by ObjectiveService).
	local objectiveFrame = Instance.new("Frame")
	objectiveFrame.Name = "Objectives"
	objectiveFrame.Size = UDim2.fromScale(0.3, 0.05)
	objectiveFrame.Position = UDim2.fromScale(0.5, 0.17)
	objectiveFrame.AnchorPoint = Vector2.new(0.5, 0)
	objectiveFrame.BackgroundTransparency = 1
	objectiveFrame.ZIndex = 3
	objectiveFrame.Visible = false
	objectiveFrame.Parent = gui

	local pipHolder = Instance.new("Frame")
	pipHolder.Name = "Pips"
	pipHolder.Size = UDim2.fromScale(1, 1)
	pipHolder.BackgroundTransparency = 1
	pipHolder.ZIndex = 3
	pipHolder.Parent = objectiveFrame
	local pipLayout = Instance.new("UIListLayout")
	pipLayout.FillDirection = Enum.FillDirection.Horizontal
	pipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	pipLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	pipLayout.Padding = UDim.new(0, 8)
	pipLayout.Parent = pipHolder

	local extractBar = Instance.new("Frame")
	extractBar.Name = "ExtractBar"
	extractBar.Size = UDim2.fromScale(1, 0.7)
	extractBar.Position = UDim2.fromScale(0.5, 0.5)
	extractBar.AnchorPoint = Vector2.new(0.5, 0.5)
	extractBar.BackgroundColor3 = Brand.Color.BgDeep
	extractBar.BackgroundTransparency = 0.1
	extractBar.BorderSizePixel = 0
	extractBar.ZIndex = 3
	extractBar.Visible = false
	extractBar.Parent = objectiveFrame
	style(extractBar, 10, Brand.Color.SafeGreen)

	local extractFill = Instance.new("Frame")
	extractFill.Name = "Fill"
	extractFill.Size = UDim2.fromScale(0, 1)
	extractFill.BackgroundColor3 = Brand.Color.SafeGreen
	extractFill.BorderSizePixel = 0
	extractFill.ZIndex = 3
	extractFill.Parent = extractBar
	local efCorner = Instance.new("UICorner")
	efCorner.CornerRadius = UDim.new(1, 0)
	efCorner.Parent = extractFill

	local extractLabel = Instance.new("TextLabel")
	extractLabel.BackgroundTransparency = 1
	extractLabel.Size = UDim2.fromScale(1, 1)
	extractLabel.Font = Brand.Font.Display
	extractLabel.TextScaled = true
	extractLabel.TextColor3 = Brand.Color.TextLight
	extractLabel.Text = "ESCAPE"
	extractLabel.ZIndex = 4
	extractLabel.Parent = extractBar

	local pips: { Frame } = {}
	local mapFolder: Instance? = nil

	-- == Local state ==========================================================
	local state = {
		inMatch = false,
		queued = false,
		queueCount = 0,
		queueMax = 12,
		countdown = nil :: number?,
		mapName = "",
		matchRunning = false,
		phase = RoundState.Hub,
		timeLeft = 0,
		survivors = 0,
		infected = 0,
		role = SURVIVOR,
		infection = 0,
		downed = false,
	}

	local function updateInfection()
		local pct = math.clamp(state.infection / 100, 0, 1)
		infectionFill.Size = UDim2.fromScale(pct, 1)
		infectionFill.BackgroundColor3 = Brand.Color.SafeGreen:Lerp(Brand.Color.InfectedPink, pct)
		infectionText.Text = string.format("INFECTION %d%%", math.floor(state.infection))
		infectionFrame.Visible = state.inMatch and state.role == SURVIVOR and not state.downed
		downedOverlay.Visible = state.inMatch and state.downed
	end

	-- Generator pips during Action; swaps to the green EXTRACTION bar once armed.
	local function renderObjective()
		if not mapFolder then
			return
		end
		local gensTotal = mapFolder:GetAttribute("GensTotal") or 0
		local gensOn = mapFolder:GetAttribute("GensPowered") or 0
		local armed = mapFolder:GetAttribute("Extraction_Powered") == true
		local progress = mapFolder:GetAttribute("Extraction_Progress") or 0

		local show = state.inMatch and state.phase == RoundState.Action and gensTotal > 0
		objectiveFrame.Visible = show
		if not show then
			return
		end

		if armed then
			pipHolder.Visible = false
			extractBar.Visible = true
			extractFill.Size = UDim2.fromScale(math.clamp(progress / 100, 0, 1), 1)
			extractLabel.Text = string.format("ESCAPE  %d%%", math.floor(progress))
		else
			extractBar.Visible = false
			pipHolder.Visible = true
			if #pips ~= gensTotal then
				for _, pip in pips do
					pip:Destroy()
				end
				table.clear(pips)
				for i = 1, gensTotal do
					local pip = Instance.new("Frame")
					pip.Size = UDim2.fromOffset(52, 22)
					pip.BackgroundColor3 = Brand.Color.HazardYellow
					pip.BorderSizePixel = 0
					pip.LayoutOrder = i
					pip.ZIndex = 3
					pip.Parent = pipHolder
					local pc = Instance.new("UICorner")
					pc.CornerRadius = UDim.new(0, 6)
					pc.Parent = pip
					local pl = Instance.new("TextLabel")
					pl.Name = "L"
					pl.BackgroundTransparency = 1
					pl.Size = UDim2.fromScale(1, 1)
					pl.Font = Brand.Font.Display
					pl.TextScaled = true
					pl.TextColor3 = Brand.Color.BgDeep
					pl.Text = "GEN"
					pl.ZIndex = 4
					pl.Parent = pip
					pips[i] = pip
				end
			end
			for i, pip in pips do
				local done = i <= gensOn
				pip.BackgroundColor3 = if done then Brand.Color.SafeGreen else Brand.Color.HazardYellow
				local pl = pip:FindFirstChild("L")
				if pl and pl:IsA("TextLabel") then
					pl.Text = if done then "\u{2713}" else "GEN"
				end
			end
		end
	end

	local function render()
		local inMatch = state.inMatch or state.phase ~= RoundState.Hub
		if inMatch then
			countsLabel.TextColor3 = Brand.Color.TextDim
			if state.phase == RoundState.Prep then
				phaseLabel.Text = "Get ready! " .. formatTime(state.timeLeft)
				countsLabel.Text = if state.mapName ~= "" then "Map: " .. state.mapName else "Infection begins soon..."
			elseif state.phase == RoundState.Action then
				phaseLabel.Text = "Round ends in " .. formatTime(state.timeLeft)
				countsLabel.Text = string.format("Survivors: %d     Infected: %d", state.survivors, state.infected)
			elseif state.phase == RoundState.Results then
				phaseLabel.Text = "Round over!"
				countsLabel.Text = "Returning to the hub..."
			else
				phaseLabel.Text = "..."
				countsLabel.Text = ""
			end
		else
			if state.matchRunning then
				phaseLabel.Text = "Match in progress"
			elseif state.countdown then
				phaseLabel.Text = string.format("Match starts in %d...", state.countdown)
			else
				phaseLabel.Text = "Containment Hub"
			end
			if state.queued then
				countsLabel.Text = string.format("\u{2713} Queued   (%d / %d)", state.queueCount, state.queueMax)
				countsLabel.TextColor3 = Brand.Color.SafeGreen
			else
				countsLabel.Text =
					string.format("Step on the green pad to queue   (%d / %d)", state.queueCount, state.queueMax)
				countsLabel.TextColor3 = Brand.Color.TextDim
			end
		end
		updateInfection()
		renderObjective()
	end

	-- == Animations ===========================================================
	local bannerToken = 0
	local function showBanner(text: string, color: Color3)
		banner.Text = text
		banner.TextColor3 = color
		banner.TextTransparency = 0
		banner.TextStrokeTransparency = 0.4
		bannerToken += 1
		local myToken = bannerToken
		task.delay(2.5, function()
			if myToken ~= bannerToken then
				return
			end
			TweenService:Create(banner, TweenInfo.new(0.6), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}):Play()
		end)
	end

	local toastToken = 0
	local function showToast(text: string)
		toast.Text = text
		toast.TextTransparency = 0
		toast.BackgroundTransparency = 0.3
		toastToken += 1
		local myToken = toastToken
		task.delay(3, function()
			if myToken ~= toastToken then
				return
			end
			TweenService:Create(toast, TweenInfo.new(0.5), {
				TextTransparency = 1,
				BackgroundTransparency = 1,
			}):Play()
		end)
	end

	local function playFlash(color: Color3)
		flash.BackgroundColor3 = color
		flash.BackgroundTransparency = 0.35
		TweenService:Create(flash, TweenInfo.new(1.4), { BackgroundTransparency = 1 }):Play()
	end

	-- == Server -> client =====================================================
	local function refreshAttrs()
		state.inMatch = player:GetAttribute("InMatch") == true
		state.queued = player:GetAttribute("Queued") == true
		state.infection = player:GetAttribute("Infection") or 0
		state.downed = player:GetAttribute("Downed") == true
		render()
	end
	player:GetAttributeChangedSignal("InMatch"):Connect(refreshAttrs)
	player:GetAttributeChangedSignal("Queued"):Connect(refreshAttrs)
	player:GetAttributeChangedSignal("Infection"):Connect(refreshAttrs)
	player:GetAttributeChangedSignal("Downed"):Connect(refreshAttrs)

	Net.RoundStateChanged.OnClientEvent:Connect(function(phase, timeLeft, survivors, infected)
		state.phase = phase
		state.timeLeft = timeLeft
		state.survivors = survivors
		state.infected = infected
		render()
	end)

	Net.HubStateChanged.OnClientEvent:Connect(function(count, max, matchRunning, countdownLeft)
		state.queueCount = count
		state.queueMax = max
		state.matchRunning = matchRunning
		state.countdown = countdownLeft
		render()
	end)

	Net.RoleAssigned.OnClientEvent:Connect(function(role)
		state.role = role
		if role == INFECTED then
			showBanner("YOU ARE INFECTED", Brand.Color.InfectedPink)
		else
			showBanner("YOU ARE A SURVIVOR", Brand.Color.HumanBlue)
		end
		updateInfection()
	end)

	Net.Notify.OnClientEvent:Connect(function(message)
		showToast(message)
	end)

	Net.Spectacle.OnClientEvent:Connect(function(kind)
		if kind == "cleanse" then
			playFlash(Brand.Color.SafeGreen)
			showBanner("\u{2728} CLEANSE!", Brand.Color.SafeGreen)
		else
			playFlash(Brand.Color.InfectedPink)
			showBanner("\u{26A0} OUTBREAK", Brand.Color.InfectedPink)
		end
	end)

	-- Objective state lives on the GameMap folder. Wire it up off-thread so a slow
	-- map replication can't block client startup, then do an initial render.
	task.spawn(function()
		mapFolder = Workspace:WaitForChild("GameMap")
		for _, attr in { "GensTotal", "GensPowered", "Extraction_Powered", "Extraction_Progress" } do
			mapFolder:GetAttributeChangedSignal(attr):Connect(renderObjective)
		end
		state.mapName = mapFolder:GetAttribute("MapName") or ""
		mapFolder:GetAttributeChangedSignal("MapName"):Connect(function()
			state.mapName = (mapFolder and mapFolder:GetAttribute("MapName")) or ""
			render()
		end)
		renderObjective()
		render()
	end)

	refreshAttrs()
	render()
	Net.RequestHubState:FireServer() -- pull current hub state now that handlers are live
end

return RoundHudController
