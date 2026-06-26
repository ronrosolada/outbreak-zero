--!strict
--[[
	Persistence (server lib)
	------------------------
	A small, safe wrapper over DataStoreService. NOT a service — a plain library
	required by DataService. It exists so the rest of the game never has to think
	about DataStore quirks:

	  * Every call is pcall-guarded with exponential-backoff retries.
	  * If the DataStore API is unavailable (e.g. Studio without "Enable Studio
	    Access to API Services"), it transparently falls back to an in-memory
	    store so you can still playtest — your data just won't persist that session.
	  * Loads never error (return nil -> caller uses defaults); saves are
	    best-effort and report success so callers can retry on shutdown.

	This is a lightweight, in-repo stand-in for ProfileStore. It does NOT do
	cross-server session locking, so the production-hardening upgrade is to swap
	this module for the real ProfileStore later (the DataService API won't change).
]]

local DataStoreService = game:GetService("DataStoreService")

local MAX_ATTEMPTS = 4
local BACKOFF_BASE = 1 -- seconds; waits 1, 2, 4 ... between attempts

local Persistence = {}
Persistence.__index = Persistence

export type Store = typeof(setmetatable(
	{} :: {
		_store: DataStore?,
		_memory: { [string]: any },
		_useMemory: boolean,
		_name: string,
	},
	Persistence
))

-- An error worth giving up on immediately (no point retrying a permissions wall).
local function isAccessError(err: string): boolean
	local lower = string.lower(err)
	return string.find(lower, "access", 1, true) ~= nil
		or string.find(lower, "not allowed", 1, true) ~= nil
		or string.find(lower, "403", 1, true) ~= nil
end

-- Retry a throwing op a few times with backoff. Returns (ok, resultOrErr).
local function withRetry(fn: () -> any): (boolean, any)
	local attempt = 0
	while true do
		attempt += 1
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if isAccessError(tostring(result)) or attempt >= MAX_ATTEMPTS then
			return false, result
		end
		task.wait(BACKOFF_BASE * 2 ^ (attempt - 1))
	end
end

function Persistence.new(storeName: string): Store
	local self = setmetatable({
		_memory = {},
		_useMemory = false,
		_name = storeName,
	}, Persistence) :: Store

	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(storeName)
	end)
	if ok then
		self._store = store
	else
		warn(("[Persistence] '%s' unavailable, using in-memory store: %s"):format(storeName, tostring(store)))
		self._useMemory = true
	end
	return self
end

-- Load the value for a key. Never throws. Returns (ok, data):
--   ok=true,  data=value -> loaded (data is nil for a genuinely new key)
--   ok=true,  data=nil   -> in-memory mode (Studio w/o API access); safe to treat as new
--   ok=false, data=nil   -> a real read FAILURE (throttle/outage). The caller MUST NOT
--                           treat this as a new account and overwrite it, or it would
--                           clobber existing cloud data with defaults.
function Persistence.LoadAsync(self: Store, key: string): (boolean, any)
	if self._useMemory then
		return true, self._memory[key]
	end
	local store = self._store :: DataStore
	local ok, data = withRetry(function()
		return store:GetAsync(key)
	end)
	if ok then
		return true, data
	end
	if isAccessError(tostring(data)) then
		-- Permissions wall (typically Studio w/o API access): degrade to in-memory for
		-- the rest of the session. Memory is now authoritative, so this counts as ok.
		self._useMemory = true
		warn(("[Persistence] '%s' has no API access; running in-memory this session."):format(self._name))
		return true, self._memory[key]
	end
	-- Transient/hard failure against a real DataStore: report failure so the caller
	-- runs the player read-only rather than risking an overwrite of good data.
	warn(("[Persistence] load failed for key '%s': %s"):format(key, tostring(data)))
	return false, nil
end

-- Save a value for a key. Always caches the latest value in memory (so a later
-- shutdown save has the freshest data) and returns whether the durable write
-- succeeded.
function Persistence.SaveAsync(self: Store, key: string, value: any): boolean
	self._memory[key] = value
	if self._useMemory then
		return true
	end
	local store = self._store :: DataStore
	local ok, err = withRetry(function()
		store:SetAsync(key, value)
	end)
	if not ok then
		if isAccessError(tostring(err)) then
			self._useMemory = true
		end
		warn(("[Persistence] save failed for key '%s': %s"):format(key, tostring(err)))
		return false
	end
	return true
end

return Persistence
