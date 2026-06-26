--[[
	StoreService (service)
	----------------------
	Phase 9 — the coin SHOP. Sells cosmetic trails + class unlocks (coins only; fair,
	no pay-to-win). Server-authoritative: it owns the catalog, validates affordability
	atomically (DataService:TrySpend), records ownership in DataService.unlocks, and
	applies the equipped trail to the character on spawn. The client only asks.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Config")
local CosmeticConfig = require(Config:WaitForChild("CosmeticConfig"))
local ClassConfig = require(Config:WaitForChild("ClassConfig"))

local StoreService = {}

local function getRootPart(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart? or nil
end

function StoreService:Initialize(services)
	self.data = services.DataService
	self.net = require(ReplicatedStorage:WaitForChild("Net"))
	self.playerConns = {} :: { [Player]: { RBXScriptConnection } }
	self._lastAction = {} :: { [Player]: number }
end

-- Light per-player throttle so a spammed Buy/Equip can't flood server work + Notifies.
function StoreService:_throttled(player: Player): boolean
	local now = os.clock()
	local last = self._lastAction[player]
	if last and now - last < 0.25 then
		return true
	end
	self._lastAction[player] = now
	return false
end

-- Buyable items: paid trails + lockable classes.
function StoreService:_catalog(): { any }
	local items = {}
	for _, t in CosmeticConfig.trails do
		if t.price > 0 then -- "none" (free) isn't a shop item
			table.insert(items, { id = t.id, name = t.name, price = t.price, kind = "trail" })
		end
	end
	for classId, def in ClassConfig.classes do
		if (def.unlockCost or 0) > 0 then
			table.insert(items, {
				id = classId,
				name = def.display .. " \u{2022} " .. def.faction,
				price = def.unlockCost,
				kind = "class",
			})
		end
	end
	return items
end

-- Returns (price, kind) for a buyable id, or nil if it isn't a real shop item.
function StoreService:_priceOf(itemId: string): (number?, string?)
	local trail = CosmeticConfig.byId[itemId]
	if trail and trail.price > 0 then
		return trail.price, "trail"
	end
	local class = ClassConfig.classes[itemId]
	if class and (class.unlockCost or 0) > 0 then
		return class.unlockCost, "class"
	end
	return nil, nil
end

function StoreService:_sendState(player: Player)
	local profile = self.data:GetProfile(player)
	local owned = {}
	if profile then
		for id in profile.unlocks do
			owned[id] = true
		end
	end
	local equipped = self.data:GetEquipped(player)
	self.net.StoreState:FireClient(player, self:_catalog(), owned, (equipped and equipped.trail) or "none")
end

function StoreService:_buy(player: Player, itemId: any)
	if typeof(itemId) ~= "string" or self:_throttled(player) then
		return
	end
	local price, kind = self:_priceOf(itemId)
	if not price then
		return -- not a real shop item
	end
	if self.data:IsUnlocked(player, itemId) then
		self.net.Notify:FireClient(player, "You already own that.")
		return
	end
	-- Atomic: check + spend with no yield, so spam can't double-charge or over-grant.
	if not self.data:TrySpend(player, price) then
		self.net.Notify:FireClient(player, "Not enough coins!")
		return
	end
	self.data:Unlock(player, itemId)
	if kind == "trail" then
		self.data:SetEquipped(player, "trail", itemId) -- auto-equip a freshly bought trail
		self:_applyTrail(player)
	end
	self.net.Notify:FireClient(player, "Purchased! \u{2728}")
	self:_sendState(player)
end

function StoreService:_equip(player: Player, trailId: any)
	if typeof(trailId) ~= "string" or not CosmeticConfig.byId[trailId] or self:_throttled(player) then
		return
	end
	-- Must be the free default or an owned trail.
	if trailId ~= CosmeticConfig.DEFAULT_TRAIL and not self.data:IsUnlocked(player, trailId) then
		return
	end
	self.data:SetEquipped(player, "trail", trailId)
	self:_applyTrail(player)
	self:_sendState(player)
end

-- == Trail application =======================================================

function StoreService:_applyTrail(player: Player)
	local hrp = getRootPart(player)
	if not hrp then
		return
	end
	local existing = hrp:FindFirstChild("CosmeticTrail")
	if existing then
		existing:Destroy()
	end

	local equipped = self.data:GetEquipped(player)
	local trailId = (equipped and equipped.trail) or CosmeticConfig.DEFAULT_TRAIL
	local def = CosmeticConfig.byId[trailId]
	if not def or not def.color then
		return -- "none"/unknown -> no trail
	end

	local a0 = hrp:FindFirstChild("TrailA0")
	if not a0 then
		a0 = Instance.new("Attachment")
		a0.Name = "TrailA0"
		a0.Position = Vector3.new(0, 1, 0)
		a0.Parent = hrp
	end
	local a1 = hrp:FindFirstChild("TrailA1")
	if not a1 then
		a1 = Instance.new("Attachment")
		a1.Name = "TrailA1"
		a1.Position = Vector3.new(0, -1, 0)
		a1.Parent = hrp
	end

	local trail = Instance.new("Trail")
	trail.Name = "CosmeticTrail"
	trail.Attachment0 = a0 :: Attachment
	trail.Attachment1 = a1 :: Attachment
	trail.Lifetime = 0.5
	trail.Color = ColorSequence.new(def.color)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = hrp
end

-- == Lifecycle ===============================================================

function StoreService:Start()
	self.net.RequestStore.OnServerEvent:Connect(function(player)
		if self:_throttled(player) then
			return -- light per-player debounce against request spam
		end
		task.spawn(function()
			self.data:WaitForProfile(player)
			self:_sendState(player)
		end)
	end)
	self.net.BuyItem.OnServerEvent:Connect(function(player, itemId)
		self:_buy(player, itemId)
	end)
	self.net.EquipItem.OnServerEvent:Connect(function(player, trailId)
		self:_equip(player, trailId)
	end)
end

function StoreService:OnPlayerAdded(player: Player)
	self.playerConns[player] = {}
	local conn = player.CharacterAdded:Connect(function()
		task.spawn(function()
			local char = player.Character
			if char then
				char:WaitForChild("HumanoidRootPart", 5)
			end
			self:_applyTrail(player)
		end)
	end)
	table.insert(self.playerConns[player], conn)

	-- Apply the saved trail once the profile finishes loading.
	task.spawn(function()
		self.data:WaitForProfile(player)
		self:_applyTrail(player)
	end)
end

function StoreService:OnPlayerRemoving(player: Player)
	local conns = self.playerConns[player]
	if conns then
		for _, c in conns do
			c:Disconnect()
		end
	end
	self.playerConns[player] = nil
	self._lastAction[player] = nil
end

return StoreService
