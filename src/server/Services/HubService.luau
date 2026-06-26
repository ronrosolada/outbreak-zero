--[[
	HubService (service)
	--------------------
	Owns the social hub experience and matchmaking:
	  - a queue pad (ProximityPrompt) players toggle to join/leave the Outbreak queue
	  - when the queue reaches MIN_PLAYERS, pulls that roster, plays the
	    queue-pop spectacle (alarm + airlock), then hands the roster to RoundService
	  - everyone NOT in the match keeps living in the hub

	Per-player state uses Attributes (Queued, and RoundService's InMatch) so the
	client HUD reacts via GetAttributeChangedSignal.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = ReplicatedStorage:WaitForChild("Config")
local RoundConfig = require(Config:WaitForChild("RoundConfig"))
local HubConfig = require(Config:WaitForChild("HubConfig"))

local HubService = {}

function HubService:Initialize(services)
	self.map = services.MapService
	self.round = services.RoundService
	self.net = require(ReplicatedStorage:WaitForChild("Net"))
	self.queue = {} :: { [Player]: boolean } -- membership set (fast dedupe + removal test)
	self._queueOrder = {} :: { Player } -- insertion order, so overflow selection is FIFO-fair
	self.matchRunning = false
	self._countdown = nil :: number? -- seconds left in the queue-fill countdown (nil when idle)
	self._lastReq = {} :: { [Player]: number } -- per-player RequestHubState debounce

	-- Attach the queue-pad prompt.
	local pad = self.map.queuePad
	if pad then
		self._padHome = pad.CFrame
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = HubConfig.QUEUE_PROMPT
		prompt.ObjectText = HubConfig.QUEUE_OBJECT_TEXT
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 16
		prompt.RequiresLineOfSight = false
		prompt.Parent = pad
		prompt.Triggered:Connect(function(player)
			self:_toggleQueue(player)
		end)
	end

	-- Late joiners ask for the current hub state once their client is ready
	-- (avoids the FireAllClients-vs-client-setup race on join).
	self.net.RequestHubState.OnServerEvent:Connect(function(player)
		local now = os.clock()
		if self._lastReq[player] and now - self._lastReq[player] < 0.5 then
			return -- light per-player debounce against request spam
		end
		self._lastReq[player] = now
		self.net.HubStateChanged:FireClient(
			player,
			self:_queueCount(),
			RoundConfig.MAX_PLAYERS,
			self.matchRunning,
			self._countdown
		)
	end)
end

function HubService:_queueCount(): number
	local n = 0
	for _ in self.queue do
		n += 1
	end
	return n
end

function HubService:_broadcast()
	self.net.HubStateChanged:FireAllClients(
		self:_queueCount(),
		RoundConfig.MAX_PLAYERS,
		self.matchRunning,
		self._countdown
	)
end

-- Remove a player from the queue (both the membership set and the order list).
function HubService:_unqueue(player: Player)
	self.queue[player] = nil
	local i = table.find(self._queueOrder, player)
	if i then
		table.remove(self._queueOrder, i)
	end
end

-- Everyone currently queued who is still in the server, in JOIN ORDER.
function HubService:_liveRoster(): { Player }
	local roster = {}
	for _, player in self._queueOrder do
		if self.queue[player] and player.Parent then
			table.insert(roster, player)
		end
	end
	return roster
end

function HubService:_toggleQueue(player: Player)
	if player:GetAttribute("InMatch") then
		return -- can't queue while already in a match
	end
	if self.queue[player] then
		self:_unqueue(player)
		player:SetAttribute("Queued", false)
	else
		self.queue[player] = true
		table.insert(self._queueOrder, player)
		player:SetAttribute("Queued", true)
	end
	self:_broadcast()
end

function HubService:OnPlayerAdded(player: Player)
	player:SetAttribute("Queued", false)
	self:_broadcast()
end

function HubService:OnPlayerRemoving(player: Player)
	self:_unqueue(player)
	self._lastReq[player] = nil
	self:_broadcast()
end

-- Alarm + airlock drama in the hub before the roster is whisked to the arena.
function HubService:_spectacle()
	local light = self.map.alarmLight
	local pad = self.map.queuePad

	if light then
		light.Enabled = true
	end
	self.net.Spectacle:FireAllClients("Outbreak")

	if pad and self._padHome then
		TweenService:Create(
			pad,
			TweenInfo.new(HubConfig.SPECTACLE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ CFrame = self._padHome * CFrame.new(0, -10, 0) } -- airlock descends
		):Play()
	end

	task.wait(HubConfig.SPECTACLE_SECONDS)

	if light then
		light.Enabled = false
	end
	if pad and self._padHome then
		TweenService:Create(pad, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = self._padHome,
		}):Play()
	end
end

-- One iteration of the matchmaker: wait for a full queue, run the fill countdown,
-- then commit + run a match. Returns early (next tick) when there's nothing to do.
function HubService:_matchmakeTick()
	task.wait(1)
	if self.matchRunning then
		return
	end

	-- Wait until enough players are queued to begin the start countdown.
	if #self:_liveRoster() < RoundConfig.MIN_PLAYERS then
		return
	end

	-- Fill window: MIN_PLAYERS reached. Run a visible countdown during which MORE
	-- players can still join the queue (up to MAX_PLAYERS). Pop early if we hit the
	-- cap; abort if players leave and we drop back below MIN.
	local aborted = false
	for t = RoundConfig.QUEUE_COUNTDOWN_SECONDS, 1, -1 do
		local count = #self:_liveRoster()
		if count >= RoundConfig.MAX_PLAYERS then
			break -- full house: start now
		end
		if count < RoundConfig.MIN_PLAYERS then
			aborted = true
			break
		end
		self._countdown = t
		self:_broadcast()
		task.wait(1)
	end
	self._countdown = nil

	if aborted then
		self:_broadcast() -- clear the countdown on the HUD, wait for more players
		return
	end

	-- Final roster: everyone still queued (incl. those who joined during the
	-- countdown), capped at MAX_PLAYERS. Extras stay queued for the next match.
	local roster = self:_liveRoster()
	while #roster > RoundConfig.MAX_PLAYERS do
		table.remove(roster)
	end
	if #roster < RoundConfig.MIN_PLAYERS then
		self:_broadcast()
		return
	end

	-- Commit: pull them from the queue and LOCK them in (InMatch set BEFORE the
	-- spectacle so they can't re-queue during its yield).
	for _, player in roster do
		self:_unqueue(player)
		player:SetAttribute("Queued", false)
		player:SetAttribute("InMatch", true)
	end
	self.matchRunning = true
	self:_broadcast()

	-- The roster is now LOCKED. Run the spectacle + match inside a pcall so a failure
	-- (e.g. a destroyed queue pad in _spectacle, or a match error) can NEVER leave the
	-- roster stuck InMatch or wedge the matchmaker — the cleanup below always runs.
	local ok, err = pcall(function()
		self:_spectacle()

		-- Re-validate after the spectacle's yield: players may have left.
		local present = {}
		for _, player in roster do
			if player.Parent then
				table.insert(present, player)
			end
		end
		if #present >= RoundConfig.MIN_PLAYERS then
			self.round:RunMatch(present) -- blocks until the match ends
		end
	end)
	if not ok then
		warn("[HubService] match aborted: " .. tostring(err))
	end

	-- Always release the locks and reset, however the match ended.
	for _, player in roster do
		player:SetAttribute("InMatch", false)
	end
	self.matchRunning = false
	self:_broadcast()
end

function HubService:Start()
	self:_broadcast()
	task.spawn(function()
		while true do
			-- Guard the whole tick: a thrown error must never kill the one and only
			-- matchmaking thread (which would stop all future matches).
			local ok, err = pcall(function()
				self:_matchmakeTick()
			end)
			if not ok then
				warn("[HubService] matchmaker error: " .. tostring(err))
				self.matchRunning = false
				self._countdown = nil
				task.wait(1) -- avoid a tight error loop
			end
		end
	end)
end

return HubService
