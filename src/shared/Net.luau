--[[
	Net
	---
	RemoteEvent factory — the "phone lines" between server and clients.
	The empty "Remotes" folder is created by Rojo (see default.project.json).
	The SERVER creates the events on first require; each CLIENT waits for them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_NAMES = {
	"RoundStateChanged", -- server -> roster clients: match phase, timeLeft, survivors, infected
	"RoleAssigned", -- server -> one client: role string
	"Notify", -- server -> client(s): a short on-screen message
	"HubStateChanged", -- server -> all clients: queueCount, minPlayers, matchRunning, countdownLeft (nil = no countdown)
	"Spectacle", -- server -> all clients: a cinematic cue (e.g. "Outbreak")
	"RequestHubState", -- client -> server: "I loaded, send me the current hub state"
	"UseWeapon", -- client -> server: fire a weapon (kind, aim direction)
	"CombatFeedback", -- server -> shooter: hit confirmation (drives the hitmarker)
	"SelectClass", -- client -> server: choose a class for your faction (classId)
	"DailyRewardState", -- server -> client: daily reward state (canClaim, day, amount, secondsLeft)
	"ClaimDailyReward", -- client -> server: "claim my daily reward"
	"RequestDailyState", -- client -> server: "send me my current daily reward state"
	"UseAbility", -- client -> server: activate class signature ability (aim direction)
	"Ping", -- client -> server: drop a world ping (position); server -> teammates: position, name, color
	"MatchResults", -- server -> roster client: end-of-round results (infectedWin, awards, your stats)
	"RequestStore", -- client -> server: "send me the shop state"
	"StoreState", -- server -> client: catalog, owned-set, equipped trail
	"BuyItem", -- client -> server: buy a catalog item by id (coins)
	"EquipItem", -- client -> server: equip an owned trail by id
	"RevealInfected", -- server -> survivors: outline these infected for N seconds (Scout Motion Ping)
	"RevealSurvivors", -- server -> Patient Zero: outline all survivors for N seconds (Outbreak Pulse)
	"KillFeed", -- server -> all: a feed event (kind, nameA, nameB) — infect / rescue / stun / generator / outbreak
	"ToggleQueue", -- client -> server: join/leave the Outbreak queue (the mode-select PLAY button; mirrors the pad)
	"ContractsState", -- server -> client: daily-contract snapshot (list of {id,desc,target,reward,progress,claimed})
	"RequestContracts", -- client -> server: "send me my current daily contracts"
	"ClaimContract", -- client -> server: claim a completed contract's reward by id
	"PassState", -- server -> client: Outbreak Pass snapshot (xp, tier, premium, claimed maps)
	"RequestPass", -- client -> server: "send me my current pass state"
	"ClaimPassReward", -- client -> server: claim a tier reward (tier, isPremium)
	"UnlockPassPremium", -- client -> server: buy the premium track with gems
}

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local Net = {}

if RunService:IsServer() then
	for _, name in REMOTE_NAMES do
		local event = remotesFolder:FindFirstChild(name)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = remotesFolder
		end
		Net[name] = event
	end
else
	for _, name in REMOTE_NAMES do
		Net[name] = remotesFolder:WaitForChild(name)
	end
end

return Net
