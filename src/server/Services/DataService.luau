--[[
	DataService (service)
	---------------------
	The single source of truth for persistent player data: coins, XP, level, and
	unlocks. Other services NEVER touch DataStores directly — they go through this
	API, and this service mirrors the bits the UI cares about to leaderstats (the
	Coins board) and to Player Attributes (Level / Xp / XpForNext), so the client
	HUD updates automatically with no polling — same pattern as the rest of the game.

	Durability is handled by the Persistence lib (retries + Studio in-memory
	fallback). We load on join, autosave on a loop, save on leave, and save all
	profiles on shutdown (BindToClose).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Config")
local ProgressionConfig = require(Config:WaitForChild("ProgressionConfig"))
local ContractsConfig = require(Config:WaitForChild("ContractsConfig"))
local PassConfig = require(Config:WaitForChild("PassConfig"))

local serverRoot = script.Parent.Parent
local Persistence = require(serverRoot:WaitForChild("Lib"):WaitForChild("Persistence"))

local STORE_NAME = "PlayerData_v1"
local AUTOSAVE_INTERVAL = 120 -- seconds between background saves
local MAX_COIN_AWARD = 1000000 -- defensive cap: a single AddCoins grant can never exceed this
local MAX_GEM_AWARD = 100000 -- defensive cap for a single AddGems grant
local GEM_PER_LEVEL = 5 -- premium currency drip: gems granted per level gained

-- Fresh-account data. `reconcile` fills any keys missing from older saves, so
-- this template can grow over time without wiping existing players.
local DEFAULT_PROFILE = {
	coins = 0,
	gems = 0, -- premium currency (◆) — earned via level-ups / gamepasses; cosmetic-only spend
	xp = 0,
	level = 1,
	unlocks = {}, -- map: id -> true (owned cosmetics + unlocked classes)
	equipped = { trail = "none" }, -- cosmetic loadout
	daily = { lastClaim = 0, streak = 0 }, -- lastClaim is an os.time() epoch
	stats = { rounds = 0, survivorWins = 0, infectedWins = 0 },
	-- Daily contracts: `day` is a UTC day-number stamp; progress/claimed reset when it rolls.
	contracts = { day = 0, progress = {}, claimed = {} },
	-- Outbreak Pass: `season` stamps the track; progress/claims/premium reset on a new season.
	pass = { season = "", xp = 0, premium = false, claimedFree = {}, claimedPremium = {} },
}

local DataService = {}

-- == small helpers ===========================================================

local function deepCopy(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local copy = {}
	for k, v in t do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- Recursively add any keys present in `template` but missing from `target`.
local function reconcile(target: { [any]: any }, template: { [any]: any })
	for key, value in template do
		if target[key] == nil then
			target[key] = deepCopy(value)
		elseif type(value) == "table" and type(target[key]) == "table" then
			reconcile(target[key], value)
		end
	end
end

function DataService:_key(player: Player): string
	return "Player_" .. player.UserId
end

-- XP required to advance FROM the given level to the next.
function DataService:_xpForLevel(level: number): number
	return math.floor(ProgressionConfig.BASE_XP * ProgressionConfig.GROWTH ^ (level - 1))
end

-- Push a profile's display values onto leaderstats + attributes. Pass an explicit
-- `profile` to show values before one is stored (e.g. defaults during the load
-- window); otherwise it uses the player's stored profile.
function DataService:_mirror(player: Player, profile: any?)
	profile = profile or self.profiles[player]
	if not profile then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end
	local coins = leaderstats:FindFirstChild("Coins")
	if not coins then
		coins = Instance.new("IntValue")
		coins.Name = "Coins"
		coins.Parent = leaderstats
	end
	(coins :: IntValue).Value = profile.coins

	local atMax = profile.level >= ProgressionConfig.MAX_LEVEL
	player:SetAttribute("Coins", profile.coins)
	player:SetAttribute("Gems", profile.gems)
	player:SetAttribute("Level", profile.level)
	player:SetAttribute("Xp", profile.xp)
	player:SetAttribute("XpForNext", if atMax then 0 else self:_xpForLevel(profile.level))
end

-- == lifecycle ===============================================================

function DataService:Initialize()
	self.persist = Persistence.new(STORE_NAME)
	self.net = require(ReplicatedStorage:WaitForChild("Net"))
	self.profiles = {} :: { [Player]: any }
	self._ready = {} :: { [Player]: boolean } -- true once the durable load finished
	self._failed = {} :: { [Player]: boolean } -- true if the durable load failed (read-only session)
	self._active = {} :: { [Player]: boolean } -- true between join and leave; guards late loads
	self._boundToClose = false
end

function DataService:Start()
	-- Background autosave so a crash loses at most AUTOSAVE_INTERVAL of progress.
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			-- Snapshot BEFORE saving: SaveAsync yields (retry backoff), and a
			-- PlayerRemoving during that yield would delete a key from self.profiles
			-- mid-iteration (undefined `next()` behavior in Luau). Collect first,
			-- then save sequentially off the snapshot (no shutdown deadline here, so
			-- sequential is gentler on DataStore throttle limits than a fan-out).
			local snapshot = {}
			for player, profile in self.profiles do
				if player.Parent then
					snapshot[#snapshot + 1] = { key = self:_key(player), profile = profile }
				end
			end
			for _, entry in snapshot do
				self.persist:SaveAsync(entry.key, entry.profile)
			end
		end
	end)

	-- Final save for everyone when the server shuts down. Fan the saves out so total
	-- time is bounded by ONE save's retries, not the sum across all players — Roblox
	-- force-closes the server after a ~30s budget, so a sequential loop with retry
	-- backoff would silently drop the players saved last.
	if not self._boundToClose then
		self._boundToClose = true
		game:BindToClose(function()
			local pending = 0
			for player, profile in self.profiles do
				pending += 1
				task.spawn(function()
					self.persist:SaveAsync(self:_key(player), profile)
					pending -= 1
				end)
			end
			while pending > 0 do
				task.wait()
			end
		end)
	end
end

function DataService:OnPlayerAdded(player: Player)
	-- Show defaults immediately so the HUD/leaderboard aren't blank while we load.
	-- IMPORTANT: we do NOT put this in self.profiles. Only a successfully LOADED profile
	-- is stored there, so no save path can ever persist a placeholder over real data, and
	-- writes (AddCoins/AddXp) safely no-op until the real profile is in.
	self:_mirror(player, DEFAULT_PROFILE)
	self._active[player] = true

	-- Load durable data without blocking the rest of the join chain.
	task.spawn(function()
		local ok, saved = self.persist:LoadAsync(self:_key(player))
		-- `_active` (not just .Parent) is the authoritative "still the current join"
		-- signal: if they left mid-load, OnPlayerRemoving cleared it, so we must NOT
		-- resurrect a stale profile under a removed key (would leak + never re-save).
		if not player.Parent or not self._active[player] then
			return -- left before the load finished
		end
		if not ok then
			-- A real read failure (throttle/outage). Run this player read-only — no
			-- stored profile, so nothing saves — rather than risk overwriting their
			-- existing cloud data with defaults. Tell the player so vanished rewards
			-- this session aren't mistaken for a bug.
			warn(("[DataService] could not load %s; running read-only this session (no save)."):format(player.Name))
			self._failed[player] = true -- terminal: WaitForProfile must stop waiting (no profile will arrive)
			self.net.Notify:FireClient(
				player,
				"⚠️ Couldn't load your save — progress won't be kept this session. Rejoin to try again."
			)
			return
		end
		local profile = deepCopy(DEFAULT_PROFILE)
		if type(saved) == "table" then
			-- Carry over saved values, then backfill any newer default keys.
			for key, value in saved do
				profile[key] = value
			end
			reconcile(profile, DEFAULT_PROFILE)
		end
		self.profiles[player] = profile
		self._ready[player] = true
		self:_mirror(player, profile)
	end)
end

function DataService:OnPlayerRemoving(player: Player)
	self._active[player] = nil -- first: a load coroutine resuming after this must not resurrect the profile
	local profile = self.profiles[player]
	if profile then
		self.persist:SaveAsync(self:_key(player), profile)
		self.profiles[player] = nil
	end
	self._ready[player] = nil
	self._failed[player] = nil
end

-- Yields until this player's durable data has loaded (or they leave). Returns
-- the loaded profile, or nil if they left first. Use this before reading values
-- that must reflect the SAVE (e.g. daily-reward timers), not the placeholder
-- defaults shown during the brief load window.
function DataService:WaitForProfile(player: Player): any?
	-- Returns the loaded profile, or nil if the player left OR the durable load failed
	-- (read-only session). The _failed guard stops this from spinning forever on an outage.
	while player.Parent and not self._ready[player] and not self._failed[player] do
		task.wait(0.1)
	end
	return self.profiles[player]
end

-- Best-effort immediate save (used after high-value actions like daily claims).
function DataService:SaveNow(player: Player)
	local profile = self.profiles[player]
	if profile then
		self.persist:SaveAsync(self:_key(player), profile)
	end
end

-- == data API ================================================================

function DataService:GetProfile(player: Player): any?
	return self.profiles[player]
end

function DataService:GetCoins(player: Player): number
	local profile = self.profiles[player]
	return profile and profile.coins or 0
end

function DataService:AddCoins(player: Player, amount: number)
	-- Defense-in-depth: AddCoins only ever GRANTS a sane positive amount (spending goes
	-- through TrySpend). Reject NaN / non-positive / absurd values so a config typo or
	-- overflow can't silently corrupt a balance.
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount > MAX_COIN_AWARD then
		warn(("[DataService] rejected AddCoins for %s: %s"):format(player.Name, tostring(amount)))
		return
	end
	local profile = self.profiles[player]
	if not profile then
		return
	end
	profile.coins = math.max(0, profile.coins + amount)
	self:_mirror(player)
end

-- Grants XP and applies any level-ups. Returns (leveledUp, newLevel).
function DataService:AddXp(player: Player, amount: number): (boolean, number)
	local profile = self.profiles[player]
	if not profile then
		return false, 1
	end
	profile.xp += amount
	local leveledUp = false
	while profile.level < ProgressionConfig.MAX_LEVEL do
		local need = self:_xpForLevel(profile.level)
		if profile.xp >= need then
			profile.xp -= need
			profile.level += 1
			profile.gems += GEM_PER_LEVEL -- premium-currency drip on each level gained
			leveledUp = true
		else
			break
		end
	end
	if profile.level >= ProgressionConfig.MAX_LEVEL then
		profile.xp = 0 -- capped: don't hoard overflow XP at max level
	end
	self:_mirror(player)
	return leveledUp, profile.level
end

function DataService:IsUnlocked(player: Player, id: string): boolean
	local profile = self.profiles[player]
	return profile ~= nil and profile.unlocks[id] == true
end

function DataService:Unlock(player: Player, id: string)
	local profile = self.profiles[player]
	if profile then
		profile.unlocks[id] = true
	end
end

-- Cosmetic loadout (e.g. equipped trail). Returns the equipped map, or nil if the
-- profile isn't loaded yet.
function DataService:GetEquipped(player: Player): any?
	local profile = self.profiles[player]
	return profile and profile.equipped or nil
end

function DataService:SetEquipped(player: Player, slot: string, id: string)
	local profile = self.profiles[player]
	if profile and profile.equipped then
		profile.equipped[slot] = id
	end
end

-- Spend coins if affordable; returns true on success. (AddCoins clamps at 0, so a
-- purchase must check affordability atomically here.)
function DataService:TrySpend(player: Player, amount: number): boolean
	local profile = self.profiles[player]
	if not profile or profile.coins < amount then
		return false
	end
	profile.coins -= amount
	self:_mirror(player)
	return true
end

-- == Gems (premium currency) =================================================

function DataService:GetGems(player: Player): number
	local profile = self.profiles[player]
	return profile and profile.gems or 0
end

function DataService:AddGems(player: Player, amount: number)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount > MAX_GEM_AWARD then
		warn(("[DataService] rejected AddGems for %s: %s"):format(player.Name, tostring(amount)))
		return
	end
	local profile = self.profiles[player]
	if not profile then
		return
	end
	profile.gems = math.max(0, profile.gems + amount)
	self:_mirror(player)
end

function DataService:TrySpendGems(player: Player, amount: number): boolean
	local profile = self.profiles[player]
	if not profile or profile.gems < amount then
		return false
	end
	profile.gems -= amount
	self:_mirror(player)
	return true
end

-- == Daily contracts =========================================================

local DAY_SECONDS = 86400

-- Reset the contract day if it rolled over (UTC midnight). Mutates the profile in place.
local function ensureContractDay(profile: any)
	local today = math.floor(os.time() / DAY_SECONDS)
	local c = profile.contracts
	if c.day ~= today then
		c.day = today
		c.progress = {}
		c.claimed = {}
	end
end

local function contractDef(id: string)
	for _, d in ContractsConfig.daily do
		if d.id == id then
			return d
		end
	end
	return nil
end

-- Snapshot of the player's contracts for the client (nil if no profile yet).
function DataService:GetContracts(player: Player): any?
	local profile = self.profiles[player]
	if not profile then
		return nil
	end
	ensureContractDay(profile)
	local out = {}
	for _, def in ContractsConfig.daily do
		table.insert(out, {
			id = def.id,
			desc = def.desc,
			target = def.target,
			reward = def.reward,
			progress = math.min(profile.contracts.progress[def.id] or 0, def.target),
			claimed = profile.contracts.claimed[def.id] == true,
		})
	end
	return out
end

-- Advance a contract's progress (capped at target). No-ops on unknown id / already
-- claimed / already complete / unloaded profile. Returns true if progress changed.
function DataService:AddContractProgress(player: Player, id: string, amount: number): boolean
	local profile = self.profiles[player]
	if not profile then
		return false
	end
	local def = contractDef(id)
	if not def then
		return false
	end
	ensureContractDay(profile)
	if profile.contracts.claimed[id] then
		return false
	end
	local current = profile.contracts.progress[id] or 0
	if current >= def.target then
		return false
	end
	profile.contracts.progress[id] = math.min(def.target, current + amount)
	return true
end

-- Claim a completed contract's reward (one-time). Yield-free until SaveNow, so the
-- claimed flag is set atomically before any await — a racing claim can't double-pay.
function DataService:ClaimContract(player: Player, id: string): boolean
	local profile = self.profiles[player]
	if not profile then
		return false
	end
	local def = contractDef(id)
	if not def then
		return false
	end
	ensureContractDay(profile)
	if profile.contracts.claimed[id] then
		return false
	end
	if (profile.contracts.progress[id] or 0) < def.target then
		return false
	end
	profile.contracts.claimed[id] = true
	self:AddCoins(player, def.reward)
	self:SaveNow(player)
	return true
end

-- == Outbreak Pass (season reward track) =====================================

-- Reset the pass if the season rolled over (or on first load: "" ~= SEASON_ID).
local function ensurePassSeason(profile: any)
	if profile.pass.season ~= PassConfig.SEASON_ID then
		profile.pass.season = PassConfig.SEASON_ID
		profile.pass.xp = 0
		profile.pass.premium = false
		profile.pass.claimedFree = {}
		profile.pass.claimedPremium = {}
	end
end

local function passTier(xp: number): number
	return math.min(#PassConfig.tiers, math.floor(xp / PassConfig.XP_PER_TIER))
end

function DataService:_grantPassReward(player: Player, reward: any)
	if reward.kind == "credits" then
		self:AddCoins(player, reward.amount)
	elseif reward.kind == "gems" then
		self:AddGems(player, reward.amount)
	elseif reward.kind == "trail" then
		self:Unlock(player, reward.id)
	end
end

-- Snapshot of the player's pass for the client (nil if no profile yet).
function DataService:GetPass(player: Player): any?
	local profile = self.profiles[player]
	if not profile then
		return nil
	end
	ensurePassSeason(profile)
	local p = profile.pass
	return {
		xp = p.xp,
		tier = passTier(p.xp),
		tierCount = #PassConfig.tiers,
		xpPerTier = PassConfig.XP_PER_TIER,
		premiumCost = PassConfig.PREMIUM_COST,
		premium = p.premium == true,
		claimedFree = p.claimedFree,
		claimedPremium = p.claimedPremium,
	}
end

function DataService:AddPassXp(player: Player, amount: number)
	local profile = self.profiles[player]
	if not profile or type(amount) ~= "number" or amount <= 0 then
		return
	end
	ensurePassSeason(profile)
	profile.pass.xp += amount
end

-- Claim a reached, unclaimed tier reward. `premium` claims the premium track (requires
-- pass ownership). Yield-free until SaveNow, so a racing claim can't double-grant.
function DataService:ClaimPassReward(player: Player, tier: number, premium: boolean): boolean
	local profile = self.profiles[player]
	if not profile or type(tier) ~= "number" then
		return false
	end
	local def = PassConfig.tiers[tier]
	if not def then
		return false
	end
	ensurePassSeason(profile)
	if tier > passTier(profile.pass.xp) then
		return false -- tier not reached yet
	end
	local claimed = if premium then profile.pass.claimedPremium else profile.pass.claimedFree
	local key = tostring(tier) -- string key: stable across DataStore (de)serialization
	if claimed[key] then
		return false -- already claimed
	end
	if premium and not profile.pass.premium then
		return false -- premium track locked (check BEFORE marking claimed)
	end
	-- Set claimed BEFORE granting (matches ClaimContract) so the no-double-grant property
	-- holds even if a grant path ever introduces a yield.
	claimed[key] = true
	self:_grantPassReward(player, if premium then def.premium else def.free)
	self:SaveNow(player)
	return true
end

-- Buy the premium track with gems (one-time per season).
function DataService:UnlockPassPremium(player: Player): boolean
	local profile = self.profiles[player]
	if not profile then
		return false
	end
	ensurePassSeason(profile)
	if profile.pass.premium then
		return false
	end
	if not self:TrySpendGems(player, PassConfig.PREMIUM_COST) then
		return false
	end
	profile.pass.premium = true
	self:SaveNow(player)
	return true
end

return DataService
