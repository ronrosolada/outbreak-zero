--[[
	ShopController (client controller)
	----------------------------------
	Phase 9 — the SHOP UI (open from the hub). Spend coins on cosmetic trails and
	class unlocks; equip owned trails. Server-authoritative — this only displays the
	StoreState and fires Buy/Equip requests. Brand-styled.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Net"))
local Brand = require(ReplicatedStorage:WaitForChild("Brand"))

local ShopController = {}

local function corner(inst: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

function ShopController:Init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "Shop"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.Parent = playerGui

	-- Persistent open button (top-left; clear of the CLASS button at bottom-left).
	local shopButton = Instance.new("TextButton")
	shopButton.Name = "OpenShop"
	shopButton.Size = UDim2.fromScale(0.14, 0.06)
	shopButton.Position = UDim2.fromScale(0.02, 0.08)
	shopButton.Font = Brand.Font.Display
	shopButton.TextScaled = true
	shopButton.Text = "\u{1F6D2} SHOP"
	shopButton.TextColor3 = Brand.Color.TextLight
	shopButton.BackgroundColor3 = Brand.Color.HazardYellow
	shopButton.Parent = gui
	corner(shopButton, 10)

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Brand.Color.BgDeep
	backdrop.BackgroundTransparency = 0.3
	backdrop.BorderSizePixel = 0
	backdrop.Visible = false
	backdrop.Parent = gui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(0.56, 0.72)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Brand.Color.Panel
	panel.BorderSizePixel = 0
	panel.Parent = backdrop
	corner(panel, 16)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Brand.Color.HazardYellow
	stroke.Thickness = 1.5
	stroke.Transparency = 0.4
	stroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(0.6, 0.1)
	title.Position = UDim2.fromScale(0.05, 0.03)
	title.Font = Brand.Font.Display
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Brand.Color.TextLight
	title.Text = "SHOP"
	title.Parent = panel

	local coinLabel = Instance.new("TextLabel")
	coinLabel.BackgroundTransparency = 1
	coinLabel.Size = UDim2.fromScale(0.32, 0.08)
	coinLabel.Position = UDim2.fromScale(0.62, 0.04)
	coinLabel.Font = Brand.Font.Mono
	coinLabel.TextScaled = true
	coinLabel.TextXAlignment = Enum.TextXAlignment.Right
	coinLabel.TextColor3 = Brand.Color.HazardYellow
	coinLabel.Text = "Coins: 0"
	coinLabel.Parent = panel

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

	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.fromScale(0.9, 0.78)
	list.Position = UDim2.fromScale(0.5, 0.56)
	list.AnchorPoint = Vector2.new(0.5, 0.5)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local function refreshCoins()
		coinLabel.Text = "Coins: " .. tostring(player:GetAttribute("Coins") or 0)
	end
	player:GetAttributeChangedSignal("Coins"):Connect(refreshCoins)

	-- Build one shop row: a name + an action button.
	local order = 0
	local function addRow(name: string, btnText: string, btnColor: Color3, active: boolean, onClick: (() -> ())?)
		order += 1
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 48)
		row.BackgroundColor3 = Brand.Color.BgDeep
		row.BackgroundTransparency = 0.3
		row.BorderSizePixel = 0
		row.LayoutOrder = order
		row.Parent = list
		corner(row, 8)

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(0.6, 0.8)
		label.Position = UDim2.fromScale(0.03, 0.1)
		label.Font = Brand.Font.Body
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Brand.Color.TextLight
		label.Text = name
		label.Parent = row

		local btn = Instance.new("TextButton")
		btn.Size = UDim2.fromScale(0.32, 0.74)
		btn.Position = UDim2.fromScale(0.65, 0.13)
		btn.Font = Brand.Font.Display
		btn.TextScaled = true
		btn.Text = btnText
		btn.TextColor3 = Brand.Color.TextLight
		btn.BackgroundColor3 = btnColor
		btn.AutoButtonColor = active
		btn.Active = active
		btn.Parent = row
		corner(btn, 6)
		if active and onClick then
			btn.Activated:Connect(onClick)
		else
			btn.BackgroundTransparency = 0.4
		end
	end

	local function render(catalog, owned, equippedTrail)
		order = 0
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		-- Free "No Trail" equip option.
		local noneEquipped = equippedTrail == "none" or equippedTrail == nil
		addRow(
			"No Trail",
			if noneEquipped then "EQUIPPED" else "EQUIP",
			Brand.Color.HumanBlue,
			not noneEquipped,
			function()
				Net.EquipItem:FireServer("none")
			end
		)

		if typeof(catalog) ~= "table" then
			return
		end
		for _, item in catalog do
			local isOwned = owned and owned[item.id] == true
			if item.kind == "trail" then
				if not isOwned then
					addRow(item.name, "BUY " .. item.price, Brand.Color.SafeGreen, true, function()
						Net.BuyItem:FireServer(item.id)
					end)
				elseif equippedTrail == item.id then
					addRow(item.name, "EQUIPPED", Brand.Color.HumanBlue, false, nil)
				else
					addRow(item.name, "EQUIP", Brand.Color.HumanBlue, true, function()
						Net.EquipItem:FireServer(item.id)
					end)
				end
			else -- class unlock
				if not isOwned then
					addRow(item.name, "UNLOCK " .. item.price, Brand.Color.SafeGreen, true, function()
						Net.BuyItem:FireServer(item.id)
					end)
				else
					addRow(item.name, "OWNED", Brand.Color.HumanBlue, false, nil)
				end
			end
		end
	end

	Net.StoreState.OnClientEvent:Connect(function(catalog, owned, equippedTrail)
		render(catalog, owned, equippedTrail)
		refreshCoins()
	end)

	local function setOpen(open: boolean)
		backdrop.Visible = open
		shopButton.Visible = not open
		if open then
			Net.RequestStore:FireServer()
			refreshCoins()
		end
	end
	shopButton.Activated:Connect(function()
		setOpen(true)
	end)
	closeButton.Activated:Connect(function()
		setOpen(false)
	end)

	refreshCoins()
end

return ShopController
